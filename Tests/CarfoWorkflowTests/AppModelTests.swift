import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
import CarfoCore
@testable import Carfo

@MainActor
final class AppModelTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CarfoWorkflow-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func model(_ root: URL, installation: LocalModelInstallation = .init(), script: URL? = nil) throws -> AppModel {
        let suite = "CarfoWorkflow.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return try AppModel(directory: root, installationOverride: installation, workerScript: script, defaultsOverride: defaults)
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { XCTFail("Workflow timed out"); throw EngineError.timedOut }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private func worker(in root: URL) throws -> URL {
        let url = root.appendingPathComponent("worker.py")
        try """
        import sys,json,time
        for line in sys.stdin:
            r=json.loads(line)
            op=r['op']
            time.sleep(0.02)
            if op=='texts': result={'embeddings':[[1.0]+[0.0]*767 for _ in r['texts']]}
            elif op=='transcribe': result={'cues':[{'start':0,'end':1,'text':'hello'}]}
            elif op=='text': result={'embedding':[1.0]+[0.0]*767}
            else: result={'backend':'test'}
            print(json.dumps(dict(result,ok=True,id=r['id'])),flush=True)
        """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    func testCorruptStartupCannotSavePruneOrOverwriteAtShutdown() async throws {
        let root = try directory(), store = try LibraryStore(directory: root)
        let original = Data("{bad json".utf8)
        try original.write(to: store.manifestURL)
        let thumbnail = store.thumbnailDirectory.appendingPathComponent("keep.jpg")
        try Data([1, 2]).write(to: thumbnail)
        let app = try model(root)
        XCTAssertTrue(app.isLoading)
        app.persist()
        try await waitUntil { !app.isLoading }
        XCTAssertTrue(app.loadFailed)
        app.persist(); app.shutdown()
        XCTAssertEqual(try Data(contentsOf: store.manifestURL), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnail.path))
    }
    func testStartupThenImmediateFilenameSearchAndFolderRemovalKeepCountsCorrect() async throws {
        let root = try directory(), store = try LibraryStore(directory: root)
        var library = LibraryManifest()
        let folder = FootageFolder(path: root.path)
        library.folders = [folder]
        library.clips = [FootageClip(folderID: folder.id, path: "/pantai.mov", duration: 12)]
        try store.save(library)
        let app = try model(root)
        try await waitUntil { !app.isLoading }
        XCTAssertFalse(app.loadFailed)
        app.query = "pantai"
        XCTAssertEqual(app.results.count, 1)
        XCTAssertEqual(app.stats.folderCounts[folder.id], 1)
        app.removeFolder(folder)
        XCTAssertEqual(app.stats.video, 0)
        XCTAssertTrue(app.results.isEmpty)
        app.shutdown()
        XCTAssertTrue(try store.load().clips.isEmpty)
    }
    func testExistingSubtitlesGetVectorsWithoutInvokingWhisperOrReplacingText() async throws {
        let root = try directory(), store = try LibraryStore(directory: root)
        var library = LibraryManifest()
        let installation = LocalModelInstallation(modelDirectory: root, pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"))
        library.modelRevision = installation.modelIdentifier
        var clip = FootageClip(folderID: UUID(), path: "/nonexistent.wav", duration: 12, hasAudio: true,
            segments: [VideoSegment(start: 0, end: 12, audioEmbedding: [1, 0])],
            transcripts: [TranscriptCue(start: 2, end: 4, text: "Subtitle asli")], transcribedAt: Date(), mediaType: .audio)
        clip.transcriptSource = "subtitle"; clip.subtitleFingerprint = "fixture"
        library.clips = [clip]
        try store.save(library)
        let app = try model(root, installation: installation, script: worker(in: root))
        try await waitUntil { !app.isLoading }
        app.startIndexing()
        try await waitUntil { !app.isWorking }
        XCTAssertEqual(app.library.clips[0].transcripts[0].text, "Subtitle asli")
        XCTAssertEqual(app.library.clips[0].transcripts[0].embedding?.count, 768)
        XCTAssertNil(app.library.clips[0].transcriptError)
        app.shutdown()
        XCTAssertEqual(try store.load().clips[0].transcriptSource, "subtitle")
    }
    func testNewestQueryAndFolderRemainSelectedWhenModelResponseArrives() async throws {
        let root = try directory(), store = try LibraryStore(directory: root)
        let installation = LocalModelInstallation(modelDirectory: root, pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"))
        var library = LibraryManifest()
        library.modelRevision = installation.modelIdentifier
        let first = UUID(), second = UUID()
        let vector: [Float] = [1] + Array(repeating: 0, count: 767)
        library.clips = [FootageClip(folderID: first, path: "/lama.mov", duration: 12, segments: [VideoSegment(start: 0, end: 12, visualEmbedding: vector)]),
                         FootageClip(folderID: second, path: "/baru.mov", duration: 12, segments: [VideoSegment(start: 0, end: 12, visualEmbedding: vector)])]
        try store.save(library)
        let app = try model(root, installation: installation, script: worker(in: root))
        try await waitUntil { !app.isLoading }
        app.query = "lama"
        app.folderFilter = second
        app.query = "baru"
        XCTAssertEqual(app.results.first?.clip.name, "baru.mov")
        try await waitUntil { !app.isSearching }
        XCTAssertEqual(app.results.map(\.clip.folderID), [second])
        app.shutdown()
    }
    func testDialogueWithoutVectorsShowsTextWithoutLoadingModel() async throws {
        let root = try directory(), store = try LibraryStore(directory: root)
        var library = LibraryManifest()
        library.clips = [FootageClip(folderID: UUID(), path: "/a.wav", duration: 12, hasAudio: true,
            transcripts: [TranscriptCue(start: 1, end: 2, text: "Halo dunia")], mediaType: .audio)]
        try store.save(library)
        let installation = LocalModelInstallation(modelDirectory: root, pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"))
        let app = try model(root, installation: installation, script: worker(in: root))
        try await waitUntil { !app.isLoading }
        app.mode = .dialogue; app.query = "Halo"
        XCTAssertFalse(app.isSearching)
        XCTAssertEqual(app.results.first?.matchedCue?.text, "Halo dunia")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("engine.log").path))
        app.shutdown()
    }
    func testModelChangeReembedsSubtitleAndPreservesTextWhenMediaIsUnavailable() async throws {
        let root = try directory(), store = try LibraryStore(directory: root)
        var library = LibraryManifest()
        library.modelRevision = "previous-model"
        let oldVector: [Float] = [0, 1] + Array(repeating: 0, count: 766)
        var clip = FootageClip(folderID: UUID(), path: root.appendingPathComponent("missing.wav").path, duration: 12, hasAudio: true,
            segments: [VideoSegment(start: 0, end: 12, audioEmbedding: oldVector)],
            transcripts: [TranscriptCue(start: 1, end: 2, text: "Teks dipertahankan", embedding: oldVector)], transcribedAt: Date(), mediaType: .audio)
        clip.transcriptSource = "subtitle"
        library.clips = [clip]
        try store.save(library)
        let installation = LocalModelInstallation(modelDirectory: root, pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"))
        let app = try model(root, installation: installation, script: worker(in: root))
        try await waitUntil { !app.isLoading }
        XCTAssertFalse(app.indexMatchesModel)
        app.startIndexing()
        try await waitUntil { !app.isWorking }
        XCTAssertEqual(app.library.modelRevision, installation.modelIdentifier)
        XCTAssertEqual(app.library.clips[0].transcripts[0].text, "Teks dipertahankan")
        XCTAssertEqual(app.library.clips[0].transcripts[0].embedding?.first, 1)
        XCTAssertNil(app.library.clips[0].segments[0].audioEmbedding)
        XCTAssertEqual(app.indexedCount, 0)
        app.shutdown()
    }
    func testFailedSecondTranscriptionChunkResumesFromSavedOffset() async throws {
        let root = try directory(), store = try LibraryStore(directory: root)
        let audio = root.appendingPathComponent("long.wav")
        var wav = Data()
        func string(_ value: String) { wav.append(contentsOf: value.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) } }
        let count = 125 * 32000
        string("RIFF"); integer(UInt32(36 + count)); string("WAVEfmt "); integer(UInt32(16))
        integer(UInt16(1)); integer(UInt16(1)); integer(UInt32(16000)); integer(UInt32(32000))
        integer(UInt16(2)); integer(UInt16(16)); string("data"); integer(UInt32(count))
        wav.append(Data(repeating: 0, count: count)); try wav.write(to: audio)
        let script = root.appendingPathComponent("retry.py")
        try """
        import sys,json,pathlib
        log=pathlib.Path(__file__).with_suffix('.log')
        for line in sys.stdin:
            r=json.loads(line); op=r['op']
            if op=='transcribe':
                calls=int(log.read_text())+1 if log.exists() else 1
                log.write_text(str(calls))
                if calls==2:
                    print(json.dumps({'ok':False,'id':r['id'],'error':'temporary Whisper error'}),flush=True)
                    continue
                result={'cues':[{'start':3,'end':4,'text':'chunk'}]}
            elif op=='texts': result={'embeddings':[[1.0]+[0.0]*767 for _ in r['texts']]}
            else: result={'backend':'test'}
            print(json.dumps(dict(result,ok=True,id=r['id'])),flush=True)
        """.write(to: script, atomically: true, encoding: .utf8)
        let installation = LocalModelInstallation(modelDirectory: root, pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"), whisperDirectory: root)
        var library = LibraryManifest()
        library.modelRevision = installation.modelIdentifier
        library.clips = [FootageClip(folderID: UUID(), path: audio.path, duration: 125, hasAudio: true,
            segments: [VideoSegment(start: 0, end: 125, audioEmbedding: [1, 0])], mediaType: .audio)]
        try store.save(library)
        let app = try model(root, installation: installation, script: script)
        try await waitUntil { !app.isLoading }
        app.startIndexing()
        try await waitUntil { !app.isWorking }
        XCTAssertEqual(app.library.clips[0].transcriptOffset, 60)
        XCTAssertNil(app.library.clips[0].transcribedAt)
        XCTAssertNotNil(app.library.clips[0].transcriptError)
        XCTAssertEqual(app.stats.transcribed, 0)
        app.flushSaves()
        XCTAssertEqual(try store.load().clips[0].transcriptOffset, 60)
        app.startIndexing()
        try await waitUntil { !app.isWorking }
        XCTAssertEqual(app.library.clips[0].transcriptOffset, 125)
        XCTAssertEqual(app.library.clips[0].transcripts.count, 3)
        XCTAssertEqual(app.stats.transcribed, 1)
        XCTAssertNil(app.library.clips[0].transcriptError)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("retry.log"), encoding: .utf8), "4")
        app.shutdown()
    }
    func testThumbnailCacheLoadsAsynchronouslyUsesRequestedSizeAndRefreshesChangedFile() async throws {
        let url = try directory().appendingPathComponent("thumbnail.png")
        func write(_ red: CGFloat, _ blue: CGFloat) throws {
            let context = CGContext(data: nil, width: 1600, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: red, green: 0, blue: blue, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1000))
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
        }
        try write(1, 0)
        let cache = ThumbnailCache()
        let small = CGSize(width: 64, height: 64), large = CGSize(width: 640, height: 480)
        XCTAssertNil(cache.image(for: url, targetSize: small))
        try await waitUntil { cache.image(for: url, targetSize: small) != nil }
        XCTAssertLessThanOrEqual(cache.image(for: url, targetSize: small)!.size.width, 128)
        XCTAssertNil(cache.image(for: url, targetSize: large))
        try await waitUntil { cache.image(for: url, targetSize: large) != nil }
        XCTAssertGreaterThan(cache.image(for: url, targetSize: large)!.size.width, 1000)
        let revision = cache.revision
        try write(0, 1)
        _ = cache.image(for: url, targetSize: small)
        try await waitUntil { cache.revision > revision }
        let image = cache.image(for: url, targetSize: small)!
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        let color = bitmap.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
        XCTAssertGreaterThan(color.blueComponent, 0.9)
        XCTAssertLessThan(color.redComponent, 0.1)
    }
}
