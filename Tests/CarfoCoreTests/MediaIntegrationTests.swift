import XCTest
@testable import CarfoCore

final class MediaIntegrationTests: XCTestCase {
    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".runtime/Fixtures/Videos/Test red.mp4")
    }
    private func directory() throws -> URL {
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("Prepare local media fixtures before running AVFoundation integration tests.") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CarfoMedia-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func requireVideoDecoding(in output: URL) async throws {
        do { try await MediaProcessor.frame(url: fixture, at: 0.5, destination: output.appendingPathComponent("probe.jpg")) }
        catch {
            let error = error as NSError
            let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
            if underlying?.code == -12911 {
                throw XCTSkip("The build sandbox cannot access the macOS media decoder. Run the native validation app for this integration test.")
            }
            throw error
        }
    }
    func testNativeMediaExtractionProducesUsableFramesAndPCM16Audio() async throws {
        let output = try directory()
        try await requireVideoDecoding(in: output)
        let metadata = try await MediaProcessor.metadata(url: fixture)
        XCTAssertEqual(metadata.width, 640)
        XCTAssertEqual(metadata.height, 360)
        XCTAssertEqual(metadata.duration, 2, accuracy: 0.1)
        XCTAssertTrue(metadata.hasAudio)
        let segment = VideoSegment(start: 0, end: 1)
        let frames = try await MediaProcessor.frames(url: fixture, segment: segment, directory: output)
        XCTAssertEqual(frames.count, 3)
        for frame in frames { XCTAssertEqual(try Data(contentsOf: frame).prefix(2), Data([0xff, 0xd8])) }
        let wav = output.appendingPathComponent("audio.wav")
        try await MediaProcessor.audio(url: fixture, segment: segment, destination: wav)
        let bytes = try Data(contentsOf: wav)
        XCTAssertEqual(String(data: bytes.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: bytes[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(bytes[22], 1)
        XCTAssertEqual(bytes[34], 16)
        XCTAssertGreaterThan(bytes.count, 30000)
        XCTAssertLessThan(bytes.count, 40000)
    }
    func testRescanningKeepsCachedEmbeddingsAndRemovesDeletedVideoEntries() async throws {
        let output = try directory()
        try await requireVideoDecoding(in: output)
        let videos = output.appendingPathComponent("Videos")
        let thumbnails = output.appendingPathComponent("Thumbnails")
        try FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        let video = videos.appendingPathComponent("original.mp4")
        try FileManager.default.copyItem(at: fixture, to: video)
        let folder = FootageFolder(path: videos.path)
        let first = try await LibraryScanner.scan(folder: folder, previous: [], thumbnails: thumbnails)
        _ = try XCTUnwrap(first.clips.first, first.errors.joined(separator: "; "))
        XCTAssertEqual(first.clips.count, 1)
        var cached = first.clips
        cached[0].segments[0].visualEmbedding = [0.6, 0.8]
        let second = try await LibraryScanner.scan(folder: folder, previous: cached, thumbnails: thumbnails)
        XCTAssertEqual(second.clips[0].id, first.clips[0].id)
        XCTAssertEqual(second.clips[0].segments[0].visualEmbedding, [0.6, 0.8])
        try FileManager.default.removeItem(at: video)
        let third = try await LibraryScanner.scan(folder: folder, previous: second.clips, thumbnails: thumbnails)
        XCTAssertTrue(third.clips.isEmpty)
    }
}
