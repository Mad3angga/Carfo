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
    public init(installation: LocalModelInstallation, script: URL, logDirectory: URL) {
        self.installation = installation; self.script = script; self.logDirectory = logDirectory
    }
    public func configure(_ value: LocalModelInstallation) {
        stop(); installation = value
    }
    public func stop() {
        idleTask?.cancel(); idleTask = nil
        if process?.isRunning == true { process?.terminate() }
        try? input?.close(); try? output?.close()
        process = nil; input = nil; output = nil; pending.removeAll()
    }
    public func purge() {
        guard process?.isRunning == true else { return }
        _ = try? request(["op": "purge"], timeout: 10)
    }
    private func resetIdleTimer(seconds: TimeInterval = 45) {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }
    public func verify() throws -> String {
        let response = try request(["op": "verify"])
        return response["backend"] as? String ?? "MLX"
    }
    public func embed(query: String, mode: SearchMode) throws -> [Float] {
        try vector(request(["op": "text", "text": mode.queryText(query)]))
    }
    public func embed(frames: [URL]) throws -> [Float] {
        try vector(request(["op": "images", "paths": frames.map(\.path)]))
    }
    public func embed(audio: URL) throws -> [Float] {
        try vector(request(["op": "audio", "path": audio.path]))
    }
    /// Embeds transcript lines as retrieval documents, in batches to keep pipe responses small.
    public func embed(documents: [String]) throws -> [[Float]] {
        var output: [[Float]] = []
        for start in stride(from: 0, to: documents.count, by: 16) {
            let batch = Array(documents[start..<min(documents.count, start + 16)]).map { "title: none | text: \($0)" }
            let response = try request(["op": "texts", "texts": batch])
            guard let rows = response["embeddings"] as? [[NSNumber]], rows.count == batch.count else { throw EngineError.invalidResponse }
            output += try rows.map { try vector(["embedding": $0]) }
        }
        return output
    }
    /// Transcribes a 16 kHz mono WAV with Whisper and returns sentence-level cues in seconds.
    public func transcribe(audio: URL, duration: Double) throws -> [TranscriptCue] {
        guard installation.whisperDirectory != nil else { throw EngineError.transcriberUnavailable }
        let response = try request(["op": "transcribe", "path": audio.path], timeout: max(300, duration * 3))
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
        guard let python = installation.pythonExecutable, let model = installation.modelDirectory else { throw EngineError.unavailable }
        let worker = Process()
        worker.executableURL = python
        worker.arguments = ["-B", "-u", script.path, "--model", model.path] + (installation.whisperDirectory.map { ["--whisper", $0.path] } ?? [])
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_OFFLINE"] = "1"; environment["TRANSFORMERS_OFFLINE"] = "1"
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"; environment["DO_NOT_TRACK"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"; environment["PYTHONDONTWRITEBYTECODE"] = "1"
        worker.environment = environment
        let incoming = Pipe(), outgoing = Pipe()
        worker.standardInput = incoming; worker.standardOutput = outgoing
        let log = logDirectory.appendingPathComponent("engine.log")
        _ = FileManager.default.createFile(atPath: log.path, contents: nil)
        worker.standardError = try FileHandle(forWritingTo: log)
        try worker.run()
        process = worker; input = incoming.fileHandleForWriting; output = outgoing.fileHandleForReading
        pending.removeAll()
    }
    private func request(_ payload: [String: Any], timeout: TimeInterval = 180) throws -> [String: Any] {
        try Task.checkCancellation()
        idleTask?.cancel(); idleTask = nil
        try start()
        guard let input, let output else { throw EngineError.stopped }
        var bytes = try JSONSerialization.data(withJSONObject: payload)
        bytes.append(10)
        try input.write(contentsOf: bytes)
        let deadline = Date().addingTimeInterval(timeout)
        var wasCancelled = false
        while Date() < deadline {
            if Task.isCancelled { wasCancelled = true }
            if let newline = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: newline)
                pending.removeSubrange(...newline)
                if wasCancelled {
                    resetIdleTimer()
                    throw CancellationError()
                }
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw EngineError.invalidResponse }
                if object["ok"] as? Bool == false { throw EngineError.inference(object["error"] as? String ?? "Model tidak dapat memproses media ini.") }
                resetIdleTimer()
                return object
            }
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, 200)
            if ready > 0 {
                var chunk = [UInt8](repeating: 0, count: 65536)
                let count = chunk.withUnsafeMutableBytes { Darwin.read(output.fileDescriptor, $0.baseAddress!, $0.count) }
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { stop(); throw EngineError.stopped }
                pending.append(contentsOf: chunk.prefix(count))
                if pending.count > 2_000_000 { stop(); throw EngineError.invalidResponse }
            } else if process?.isRunning != true { stop(); throw EngineError.stopped }
        }
        stop(); throw EngineError.timedOut
    }
}
