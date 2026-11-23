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

public enum RequestPriority: Int, Sendable {
    case background = 0
    case interactive = 1
}

public actor LocalEngine {
    private struct Waiter {
        let id: UUID
        let priority: RequestPriority
        let continuation: CheckedContinuation<Void, Error>
    }
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
    private var waiters: [Waiter] = []
    private var pendingWaiterIDs = Set<UUID>()
    private var cancelledWaiters = Set<UUID>()
    private var abandonedResponses = 0
    private let maxAbandonedResponses = 4
    public let idleSeconds: TimeInterval

    public init(installation: LocalModelInstallation, script: URL, logDirectory: URL, idleSeconds: TimeInterval = 300) {
        self.installation = installation; self.script = script; self.logDirectory = logDirectory
        self.idleSeconds = idleSeconds
    }
    deinit {
        idleTask?.cancel()
        if process?.isRunning == true { process?.terminate() }
    }
    public func configure(_ value: LocalModelInstallation) {
        stop(); installation = value
    }
    private func terminateProcess() {
        abandonedResponses = 0
        if process?.isRunning == true { process?.terminate() }
        try? input?.close(); try? output?.close()
        process = nil; input = nil; output = nil; pending.removeAll()
    }
    public func stop() {
        idleTask?.cancel(); idleTask = nil
        requestOwner = nil
        terminateProcess()
        wakeNextWaiter()
    }
    public func purge() async {
        guard process?.isRunning == true else { return }
        _ = try? await request(["op": "purge"], timeout: 10, priority: .background, terminateOnCancel: false)
    }
    private func acquireSlot(priority: RequestPriority) async throws -> UUID {
        try Task.checkCancellation()
        if requestOwner == nil {
            let owner = UUID()
            requestOwner = owner
            return owner
        }
        let waiterID = UUID()
        pendingWaiterIDs.insert(waiterID)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pendingWaiterIDs.remove(waiterID)
                if Task.isCancelled || cancelledWaiters.remove(waiterID) != nil {
                    continuation.resume(throwing: CancellationError())
                } else if requestOwner == nil {
                    requestOwner = waiterID
                    continuation.resume()
                } else {
                    waiters.append(Waiter(id: waiterID, priority: priority, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: waiterID) }
        }
        cancelledWaiters.remove(waiterID)
        if Task.isCancelled {
            if requestOwner == waiterID { releaseSlot(owner: waiterID) }
            throw CancellationError()
        }
        return waiterID
    }
    private func cancelWaiter(id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(throwing: CancellationError())
        } else if pendingWaiterIDs.contains(id) {
            cancelledWaiters.insert(id)
        }
    }
    private func releaseSlot(owner: UUID) {
        guard requestOwner == owner else { return }
        requestOwner = nil
        wakeNextWaiter()
    }
    private func wakeNextWaiter() {
        guard requestOwner == nil else { return }
        guard !waiters.isEmpty else {
            if process?.isRunning == true { resetIdleTimer() }
            return
        }
        var bestIndex = 0
        for index in 1..<waiters.count {
            if waiters[index].priority.rawValue > waiters[bestIndex].priority.rawValue {
                bestIndex = index
            }
        }
        let next = waiters.remove(at: bestIndex)
        requestOwner = next.id
        next.continuation.resume()
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
        let response = try await request(["op": "verify"], timeout: timeout, priority: .interactive, terminateOnCancel: false)
        return response["backend"] as? String ?? "MLX"
    }
    public func embed(query: String, mode: SearchMode) async throws -> [Float] {
        try vector(await request(["op": "text", "text": mode.queryText(query)], priority: .interactive, terminateOnCancel: false))
    }
    public func embed(frames: [URL]) async throws -> [Float] {
        try vector(await request(["op": "images", "paths": frames.map(\.path)], priority: .background, terminateOnCancel: true))
    }
    public func embed(audio: URL, offset: Double? = nil, duration: Double? = nil) async throws -> [Float] {
        var payload: [String: Any] = ["op": "audio", "path": audio.path]
        if let offset { payload["offset"] = offset }
        if let duration { payload["duration"] = duration }
        return try vector(await request(payload, priority: .background, terminateOnCancel: true))
    }
    /// Embeds transcript lines as retrieval documents, in batches to keep pipe responses small.
    public func embed(documents: [String]) async throws -> [[Float]] {
        var output: [[Float]] = []
        for start in stride(from: 0, to: documents.count, by: 16) {
            try Task.checkCancellation()
            let batch = Array(documents[start..<min(documents.count, start + 16)]).map { "title: none | text: \($0)" }
            let response = try await request(["op": "texts", "texts": batch], priority: .background, terminateOnCancel: true)
            guard let rows = response["embeddings"] as? [[NSNumber]], rows.count == batch.count else { throw EngineError.invalidResponse }
            output += try rows.map { try vector(["embedding": $0]) }
        }
        return output
    }
    /// Transcribes a 16 kHz mono WAV with Whisper and returns sentence-level cues in seconds.
    /// Long audio is chunked into units (default 60s) to allow prompt cancellation.
    public func transcribe(audio: URL, duration: Double, chunkSize: Double = 60, language: String? = nil) async throws -> [TranscriptCue] {
        guard installation.whisperDirectory != nil else { throw EngineError.transcriberUnavailable }
        if duration <= chunkSize {
            var payload: [String: Any] = ["op": "transcribe", "path": audio.path]
            if let language { payload["language"] = language }
            let response = try await request(payload, timeout: max(300, duration * 3), priority: .background, terminateOnCancel: true)
            return try parseCues(response)
        }
        var allCues: [TranscriptCue] = []
        var offset: Double = 0
        while offset < duration {
            try Task.checkCancellation()
            let chunkDuration = min(chunkSize, duration - offset)
            var payload: [String: Any] = [
                "op": "transcribe",
                "path": audio.path,
                "offset": offset,
                "duration": chunkDuration
            ]
            if let language { payload["language"] = language }
            let response = try await request(payload, timeout: max(60, chunkDuration * 3), priority: .background, terminateOnCancel: true)
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
        terminateProcess()
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
        abandonedResponses = 0
    }
    public func request(
        _ payload: [String: Any],
        timeout: TimeInterval = 180,
        priority: RequestPriority = .interactive,
        terminateOnCancel: Bool = false
    ) async throws -> sending [String: Any] {
        try Task.checkCancellation()
        idleTask?.cancel(); idleTask = nil

        let owner = try await acquireSlot(priority: priority)
        defer {
            releaseSlot(owner: owner)
        }
        idleTask?.cancel(); idleTask = nil

        try Task.checkCancellation()
        if abandonedResponses >= maxAbandonedResponses {
            terminateProcess()
        }
        try start()
        guard let input, output != nil else { throw EngineError.stopped }

        let reqId = nextRequestId
        nextRequestId += 1
        var payloadWithId = payload
        payloadWithId["id"] = reqId

        var bytes = try JSONSerialization.data(withJSONObject: payloadWithId)
        bytes.append(10)
        do {
            try input.write(contentsOf: bytes)
        } catch {
            terminateProcess()
            throw EngineError.stopped
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard requestOwner == owner else { throw EngineError.stopped }
            if Task.isCancelled {
                if terminateOnCancel { terminateProcess() }
                else { abandonedResponses += 1 }
                throw CancellationError()
            }

            if let newline = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: newline)
                pending.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    terminateProcess()
                    throw EngineError.invalidResponse
                }
                if let resId = (object["id"] as? NSNumber)?.uint64Value ?? (object["id"] as? UInt64) {
                    if resId != reqId {
                        // Stale response from a cancelled or previous request; discard and continue
                        if abandonedResponses > 0 { abandonedResponses -= 1 }
                        continue
                    }
                } else if abandonedResponses > 0 {
                    // Untagged response belonging to an abandoned request; discard and continue
                    abandonedResponses -= 1
                    continue
                }
                if object["ok"] as? Bool == false {
                    throw EngineError.inference(object["error"] as? String ?? "Model tidak dapat memproses media ini.")
                }
                return object
            }

            guard let currentOutput = self.output, let currentProcess = self.process, currentProcess.isRunning else {
                terminateProcess()
                throw EngineError.stopped
            }

            var descriptor = pollfd(fd: currentOutput.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, 0)
            if ready > 0 {
                var chunk = [UInt8](repeating: 0, count: 65536)
                let count = chunk.withUnsafeMutableBytes { Darwin.read(currentOutput.fileDescriptor, $0.baseAddress!, $0.count) }
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { terminateProcess(); throw EngineError.stopped }
                pending.append(contentsOf: chunk.prefix(count))
                if pending.count > 2_000_000 { terminateProcess(); throw EngineError.invalidResponse }
            } else if ready < 0 && errno != EINTR {
                terminateProcess(); throw EngineError.stopped
            } else {
                if currentProcess.isRunning != true {
                    terminateProcess()
                    throw EngineError.stopped
                }
                // Yield the actor cooperatively
                do { try await Task.sleep(for: .milliseconds(15)) }
                catch {
                    if requestOwner == owner {
                        if terminateOnCancel { terminateProcess() }
                        else { abandonedResponses += 1 }
                    }
                    throw error
                }
            }
        }
        terminateProcess()
        throw EngineError.timedOut
    }
}
