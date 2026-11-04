import Foundation
import Darwin

public enum EngineError: LocalizedError {
    case unavailable, stopped, timedOut, invalidResponse, transcriberUnavailable, inference(String)
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Model atau mesin lokal belum ditemukan. Pilih lokasinya di Pengaturan."
        case .stopped: return "Mesin lokal berhenti. Coba muat ulang model melalui Pengaturan."
        case .timedOut: return "Model membutuhkan waktu terlalu lama. Coba lagi dengan menutup aplikasi berat lainnya."
        case .invalidResponse: return "Mesin lokal menghasilkan embedding yang tidak valid."
        case .transcriberUnavailable: return "Model transkripsi Whisper belum ditemukan di Mac ini."
        case .inference(let message): return message
        }
    }
}

public actor LocalEngine {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var pending = Data()
    private var idleTask: Task<Void, Never>?
    private var installation: LocalModelInstallation
    private let script: URL
    private let logDirectory: URL
    private var nextRequestId: UInt64 = 1
    private var requestOwner: UUID?
    public let idleSeconds: TimeInterval

    public init(installation: LocalModelInstallation, script: URL, logDirectory: URL, idleSeconds: TimeInterval = 300) {
        self.installation = installation; self.script = script; self.logDirectory = logDirectory
        self.idleSeconds = idleSeconds
    }
    public func configure(_ value: LocalModelInstallation) {
        stop(); installation = value
    }
    public func stop() {
        idleTask?.cancel(); idleTask = nil
        requestOwner = nil
        if process?.isRunning == true { process?.terminate() }
        try? input?.close(); try? output?.close()
        process = nil; input = nil; output = nil; pending.removeAll()
    }
    public func purge() async {
        guard process?.isRunning == true else { return }
        _ = try? await request(["op": "purge"], timeout: 10)
    }
    private func resetIdleTimer() {
        idleTask?.cancel()
        let seconds = idleSeconds
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }
    public func verify(timeout: TimeInterval = 180) async throws -> String {
        let response = try await request(["op": "verify"], timeout: timeout)
        return response["backend"] as? String ?? "MLX"
    }
    public func embed(query: String, mode: SearchMode) async throws -> [Float] {
        try vector(await request(["op": "text", "text": mode.queryText(query)]))
    }
    public func embed(frames: [URL]) async throws -> [Float] {
        try vector(await request(["op": "images", "paths": frames.map(\.path)]))
    }
    public func embed(audio: URL, offset: Double? = nil, duration: Double? = nil) async throws -> [Float] {
        var payload: [String: Any] = ["op": "audio", "path": audio.path]
        if let offset { payload["offset"] = offset }
        if let duration { payload["duration"] = duration }
        return try vector(await request(payload))
    }
    /// Embeds transcript lines as retrieval documents, in batches to keep pipe responses small.
    public func embed(documents: [String]) async throws -> [[Float]] {
        var output: [[Float]] = []
        for start in stride(from: 0, to: documents.count, by: 16) {
            try Task.checkCancellation()
            let batch = Array(documents[start..<min(documents.count, start + 16)]).map { "title: none | text: \($0)" }
            let response = try await request(["op": "texts", "texts": batch])
            guard let rows = response["embeddings"] as? [[NSNumber]], rows.count == batch.count else { throw EngineError.invalidResponse }
            output += try rows.map { try vector(["embedding": $0]) }
        }
        return output
    }
    /// Transcribes a 16 kHz mono WAV with Whisper and returns sentence-level cues in seconds.
    /// Long audio is chunked into units (default 60s) to allow prompt cancellation.
    public func transcribe(audio: URL, duration: Double, chunkSize: Double = 60) async throws -> [TranscriptCue] {
        guard installation.whisperDirectory != nil else { throw EngineError.transcriberUnavailable }
        if duration <= chunkSize {
            let response = try await request(["op": "transcribe", "path": audio.path], timeout: max(300, duration * 3))
            return try parseCues(response)
        }
        var allCues: [TranscriptCue] = []
        var offset: Double = 0
        while offset < duration {
            try Task.checkCancellation()
            let chunkDuration = min(chunkSize, duration - offset)
            let response = try await request([
                "op": "transcribe",
                "path": audio.path,
                "offset": offset,
                "duration": chunkDuration
            ], timeout: max(60, chunkDuration * 3))
            allCues += try parseCues(response)
            offset += chunkSize
        }
        return allCues
    }
    private func parseCues(_ response: [String: Any]) throws -> [TranscriptCue] {
        guard let rows = response["cues"] as? [[String: Any]] else { throw EngineError.invalidResponse }
        return rows.compactMap { row in
            guard let start = (row["start"] as? NSNumber)?.doubleValue, let end = (row["end"] as? NSNumber)?.doubleValue,
                  let text = row["text"] as? String, start.isFinite, end > start else { return nil }
            return TranscriptCue(start: start, end: end, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    private func vector(_ response: [String: Any]) throws -> [Float] {
        guard let values = response["embedding"] as? [NSNumber], values.count == 768,
              let normalized = VectorMath.normalized(values.map(\.floatValue)) else { throw EngineError.invalidResponse }
        return normalized
    }
    private func start() throws {
        if process?.isRunning == true { return }
        stop()
        guard let python = installation.pythonExecutable, let model = installation.modelDirectory else { throw EngineError.unavailable }
        let worker = Process()
        worker.executableURL = python
        worker.arguments = ["-I", "-B", "-u", script.path, "--model", model.path] + (installation.whisperDirectory.map { ["--whisper", $0.path] } ?? [])
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_OFFLINE"] = "1"; environment["TRANSFORMERS_OFFLINE"] = "1"
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"; environment["DO_NOT_TRACK"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"; environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment.removeValue(forKey: "PYTHONPATH"); environment.removeValue(forKey: "PYTHONHOME")
        environment["PYTHONNOUSERSITE"] = "1"
        worker.environment = environment
        let incoming = Pipe(), outgoing = Pipe()
        worker.standardInput = incoming; worker.standardOutput = outgoing
        let log = logDirectory.appendingPathComponent("engine.log")
        _ = FileManager.default.createFile(atPath: log.path, contents: nil)
        let errorLog = try FileHandle(forWritingTo: log)
        defer { try? errorLog.close() }
        worker.standardError = errorLog
        try worker.run()
        process = worker; input = incoming.fileHandleForWriting; output = outgoing.fileHandleForReading
        pending.removeAll()
    }
    public func request(_ payload: [String: Any], timeout: TimeInterval = 180) async throws -> sending [String: Any] {
        try Task.checkCancellation()
        idleTask?.cancel(); idleTask = nil

        while requestOwner != nil {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(10))
        }
        try Task.checkCancellation()
        try start()
        let owner = UUID()
        requestOwner = owner
        defer {
            if requestOwner == owner { requestOwner = nil; resetIdleTimer() }
        }
        guard let input, output != nil else { throw EngineError.stopped }

        let reqId = nextRequestId
        nextRequestId += 1
        var payloadWithId = payload
        payloadWithId["id"] = reqId

        var bytes = try JSONSerialization.data(withJSONObject: payloadWithId)
        bytes.append(10)
        try input.write(contentsOf: bytes)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard requestOwner == owner else { throw EngineError.stopped }
            if Task.isCancelled {
                stop()
                throw CancellationError()
            }

            if let newline = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: newline)
                pending.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw EngineError.invalidResponse
                }
                if let resId = (object["id"] as? NSNumber)?.uint64Value ?? (object["id"] as? UInt64) {
                    if resId != reqId {
                        // Stale response from a cancelled or previous request; discard and continue
                        continue
                    }
                }
                if object["ok"] as? Bool == false {
                    throw EngineError.inference(object["error"] as? String ?? "Model tidak dapat memproses media ini.")
                }
                resetIdleTimer()
                return object
            }

            guard let currentOutput = self.output, let currentProcess = self.process, currentProcess.isRunning else {
                stop()
                throw EngineError.stopped
            }

            var descriptor = pollfd(fd: currentOutput.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, 0)
            if ready > 0 {
                var chunk = [UInt8](repeating: 0, count: 65536)
                let count = chunk.withUnsafeMutableBytes { Darwin.read(currentOutput.fileDescriptor, $0.baseAddress!, $0.count) }
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { stop(); throw EngineError.stopped }
                pending.append(contentsOf: chunk.prefix(count))
                if pending.count > 2_000_000 { stop(); throw EngineError.invalidResponse }
            } else if ready < 0 && errno != EINTR {
                stop(); throw EngineError.stopped
            } else {
                if currentProcess.isRunning != true {
                    stop(); throw EngineError.stopped
                }
                // Yield the actor cooperatively
                do { try await Task.sleep(for: .milliseconds(15)) }
                catch {
                    if requestOwner == owner { stop() }
                    throw error
                }
            }
        }
        stop()
        throw EngineError.timedOut
    }
}
