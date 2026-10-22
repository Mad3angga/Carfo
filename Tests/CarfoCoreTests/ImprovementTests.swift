import XCTest
@testable import CarfoCore

final class ImprovementTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testMetadataLoadExcludesVectorsAndPreservesTextSearch() throws {
        let store = try LibraryStore(directory: directory())
        var manifest = LibraryManifest()
        manifest.clips = [FootageClip(folderID: UUID(), path: "/pantai.mov", duration: 12,
            segments: [VideoSegment(start: 0, end: 12, visualEmbedding: [1, 0])])]
        try store.save(manifest)
        let metadata = try store.database().loadManifest(metadataOnly: true)
        XCTAssertTrue(metadata.clips[0].segments.isEmpty)
        XCTAssertEqual(SearchEngine.search(clips: metadata.clips, query: "pantai").count, 1)
        XCTAssertEqual(try store.load(), manifest)
    }
    func testStatsDeltasMatchFullRecountAcrossIndexingRemovalAndCancellation() {
        let folder = UUID()
        var clip = FootageClip(folderID: folder, path: "/a.wav", duration: 120, hasAudio: true,
            segments: SegmentPlanner.segments(duration: 120), mediaType: .audio)
        var stats = LibraryStats([clip])
        for index in clip.segments.indices {
            let old = clip
            clip.segments[index].audioEmbedding = [1, 0]
            stats.replace(old, with: clip)
            XCTAssertEqual(stats, LibraryStats([clip]))
        }
        let old = clip
        clip.transcribedAt = Date()
        stats.replace(old, with: clip)
        XCTAssertEqual(stats.indexed, 1)
        XCTAssertEqual(stats.transcribed, 1)
        stats.replace(clip, with: nil)
        XCTAssertEqual(stats.folderCounts[folder], 0)
        XCTAssertEqual(stats.audio, 0)
    }
    func testChunkResumeOverlapOwnershipAndDurationGuard() throws {
        let chunks = try TranscriptionPlan.chunks(duration: 125)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[1].extraction.start, 58)
        XCTAssertEqual(chunks[1].extraction.end, 122)
        let boundary = TranscriptCue(start: 59, end: 61, text: "batas")
        let fromLeft = TranscriptionPlan.cues([boundary], in: chunks[0])
        let fromRight = TranscriptionPlan.cues([TranscriptCue(start: 1, end: 3, text: "batas")], in: chunks[1])
        XCTAssertEqual((fromLeft + fromRight).count, 1)
        XCTAssertEqual(fromRight.first?.start, 59)
        XCTAssertEqual(try TranscriptionPlan.chunks(duration: 125, resumeAt: 60).first?.start, 60)
        XCTAssertThrowsError(try TranscriptionPlan.chunks(duration: 14401))
        XCTAssertThrowsError(try TranscriptionPlan.chunks(duration: .nan))
    }
    func testTranscriptProvenanceAndPartialOffsetSurviveBothStores() throws {
        let store = try LibraryStore(directory: directory())
        var manifest = LibraryManifest()
        var clip = FootageClip(folderID: UUID(), path: "/a.wav", duration: 125, hasAudio: true, mediaType: .audio)
        clip.transcriptSource = "whisper"; clip.transcriptOffset = 60
        clip.transcripts = [TranscriptCue(start: 2, end: 3, text: "Halo")]
        manifest.clips = [clip]
        try store.save(manifest)
        XCTAssertEqual(try store.load(), manifest)
        XCTAssertEqual(try JSONDecoder().decode(FootageClip.self, from: JSONEncoder().encode(clip)), clip)
        XCTAssertTrue(try store.load().clips[0].needsTranscript)
    }
    func testVTTSettingsIdentifiersNumericTextAndInvalidTimestamps() {
        let cues = SubtitleParser.parse(text: "WEBVTT\n\nintro\n00:01.000 --> 00:02.500 align:start position:20%\n123\n\ninvalid\nx --> 00:03.000\nNo\n")
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "123")
        XCTAssertEqual(cues[0].start, 1)
        XCTAssertEqual(cues[0].end, 2.5)
    }
    func testSubtitleChangesInvalidateOnlyTranscriptVectorsWithoutVideoChanges() throws {
        let root = try directory()
        let subtitle = root.appendingPathComponent("a.vtt")
        var clip = FootageClip(folderID: UUID(), path: root.appendingPathComponent("a.mov").path, duration: 12,
            hasAudio: true, segments: [VideoSegment(start: 0, end: 12, visualEmbedding: [1, 0])])
        try "WEBVTT\n\ncue-id\n00:01.000 --> 00:02.000 align:start\nHalo".write(to: subtitle, atomically: true, encoding: .utf8)
        LibraryScanner.refreshSubtitles(for: &clip)
        XCTAssertEqual(clip.transcriptSource, "subtitle")
        XCTAssertNotNil(clip.transcribedAt)
        let original = clip.subtitleFingerprint
        clip.transcripts[0].embedding = [1, 0]
        LibraryScanner.refreshSubtitles(for: &clip)
        XCTAssertEqual(clip.transcripts[0].embedding, [1, 0])
        try "WEBVTT\n\n00:01.000 --> 00:02.000\nBaru".write(to: subtitle, atomically: true, encoding: .utf8)
        LibraryScanner.refreshSubtitles(for: &clip)
        XCTAssertNotEqual(clip.subtitleFingerprint, original)
        XCTAssertEqual(clip.transcripts[0].text, "Baru")
        XCTAssertNil(clip.transcripts[0].embedding)
        XCTAssertEqual(clip.segments[0].visualEmbedding, [1, 0])
        try "invalid".write(to: subtitle, atomically: true, encoding: .utf8)
        LibraryScanner.refreshSubtitles(for: &clip)
        XCTAssertEqual(clip.transcripts[0].text, "Baru")
        XCTAssertNotNil(clip.transcriptError)
    }
    func testExactFilenameOutranksSemanticOnlyMatchAndNegativeResultsAreRejected() {
        let folder = UUID()
        let exact = FootageClip(folderID: folder, path: "/mobil merah.mov", duration: 12,
            segments: [VideoSegment(start: 0, end: 12, visualEmbedding: [-1, 0])])
        let related = FootageClip(folderID: folder, path: "/other.mov", duration: 12,
            segments: [VideoSegment(start: 0, end: 12, visualEmbedding: [1, 0])])
        XCTAssertEqual(SearchEngine.search(clips: [exact, related], query: "mobil merah", embedding: [1, 0]).first?.clip.id, exact.id)
        XCTAssertTrue(SearchEngine.search(clips: [exact], query: "no match", embedding: [1, 0]).isEmpty)
    }
}
