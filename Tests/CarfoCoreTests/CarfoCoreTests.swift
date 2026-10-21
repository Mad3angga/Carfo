import XCTest
@testable import CarfoCore

final class CarfoCoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("CarfoTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: path) }
        return path
    }
    func testSegmentsCoverTheEntireVideoWithoutCrossingItsEnd() {
        let segments = SegmentPlanner.segments(duration: 25.3)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.first?.start, 0)
        XCTAssertEqual(segments.last?.end, 25.3)
        for pair in zip(segments, segments.dropFirst()) { XCTAssertEqual(pair.0.end, pair.1.start) }
        XCTAssertTrue(SegmentPlanner.segments(duration: .infinity).isEmpty)
        XCTAssertTrue(SegmentPlanner.segments(duration: -1).isEmpty)
        XCTAssertTrue(SegmentPlanner.segments(duration: 30, length: 0).isEmpty)
    }
    func testFrameSamplesRemainInsideShortSegments() {
        let times = SegmentPlanner.sampleTimes(in: VideoSegment(start: 24, end: 24.1))
        XCTAssertEqual(times.count, 3)
        XCTAssertTrue(times.allSatisfy { $0 > 24 && $0 < 24.1 })
    }
    func testInvalidVectorsCannotProducePlausibleScores() {
        XCTAssertNil(VectorMath.cosine([1, 0], [1]))
        XCTAssertNil(VectorMath.cosine([0, 0], [1, 0]))
        XCTAssertNil(VectorMath.normalized([.nan, 1]))
        XCTAssertNil(VectorMath.normalized([.infinity, 0]))
        XCTAssertNil(VectorMath.normalized([]))
        XCTAssertEqual(VectorMath.cosine([3, 4], [6, 8])!, 1, accuracy: 0.00001)
        XCTAssertEqual(VectorMath.cosine([1, 0], [0, 1])!, 0, accuracy: 0.00001)
    }
    func testSemanticSearchReturnsBestTimestampAndOneResultPerFile() {
        let folder = UUID()
        let a = FootageClip(folderID: folder, path: "/video/a.mov", duration: 24, segments: [
            VideoSegment(start: 0, end: 12, visualEmbedding: [0, 1]),
            VideoSegment(start: 12, end: 24, visualEmbedding: [1, 0])
        ])
        let b = FootageClip(folderID: folder, path: "/video/b.mov", duration: 12, segments: [VideoSegment(start: 0, end: 12, visualEmbedding: [0.5, 0.5])])
        let results = SearchEngine.search(clips: [b, a], query: "hutan", embedding: [1, 0])
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first?.clip.id, a.id)
        XCTAssertEqual(results.first?.segment?.start, 12)
    }
    func testSoundModeUsesAudioRatherThanVisualVectors() {
        let folder = UUID()
        let a = FootageClip(folderID: folder, path: "/a.jpg", duration: 0, segments: [VideoSegment(start: 0, end: 0, visualEmbedding: [1, 0])], mediaType: .image)
        let b = FootageClip(folderID: folder, path: "/b.mov", duration: 12, hasAudio: true, segments: [VideoSegment(start: 0, end: 12, visualEmbedding: [0, 1], audioEmbedding: [1, 0])], mediaType: .video)
        XCTAssertEqual(SearchEngine.search(clips: [a, b], query: "hujan", mode: .visual, embedding: [1, 0]).first?.clip.id, a.id)
        XCTAssertEqual(SearchEngine.search(clips: [a, b], query: "hujan", mode: .sound, embedding: [1, 0]).first?.clip.id, b.id)
        XCTAssertEqual(SearchEngine.search(clips: [a, b], query: "hujan", mode: .dialogue, embedding: [1, 0]).first?.clip.id, b.id)
    }
    func testSearchModeSeparatesVideoAndImageClips() {
        let folder = UUID()
        let vid = FootageClip(folderID: folder, path: "/clip.mp4", duration: 10, segments: [VideoSegment(start: 0, end: 10, visualEmbedding: [1, 0])], mediaType: .video)
        let img = FootageClip(folderID: folder, path: "/photo.png", duration: 0, segments: [VideoSegment(start: 0, end: 0, visualEmbedding: [1, 0])], mediaType: .image)
        let aud = FootageClip(folderID: folder, path: "/sound.mp3", duration: 5, hasAudio: true, segments: [VideoSegment(start: 0, end: 5, audioEmbedding: [1, 0])], mediaType: .audio)
        let visualResults = SearchEngine.search(clips: [vid, img, aud], query: "test", mode: .visual, embedding: [1, 0])
        XCTAssertEqual(visualResults.count, 1)
        XCTAssertEqual(visualResults.first?.clip.id, img.id)
        let videoResults = SearchEngine.search(clips: [vid, img, aud], query: "test", mode: .video, embedding: [1, 0])
        XCTAssertEqual(videoResults.count, 1)
        XCTAssertEqual(videoResults.first?.clip.id, vid.id)
    }
    func testFilenameSearchSupportsIndonesianAndDiacriticsAndFolderScope() {
        let first = UUID(), second = UUID()
        let a = FootageClip(folderID: first, path: "/koleksi/JALAN_berkábút.mov", duration: 12)
        let b = FootageClip(folderID: second, path: "/koleksi/Jalan_berkabut_2.mov", duration: 12)
        let results = SearchEngine.search(clips: [a, b], query: "jalan berkabut", folderID: first)
        XCTAssertEqual(results.map(\.clip.id), [a.id])
        XCTAssertTrue(SearchEngine.search(clips: [a, b], query: "jalan laut").isEmpty)
    }
    func testModelDimensionsDoNotGetMixedAndMissingVectorsFallBackOnlyToRealFilenames() {
        let clip = FootageClip(folderID: UUID(), path: "/jalan.mov", duration: 12, segments: [VideoSegment(start: 0, end: 12, visualEmbedding: [1, 0])])
        XCTAssertTrue(SearchEngine.search(clips: [clip], query: "hutan", embedding: [1, 0, 0]).isEmpty)
        XCTAssertEqual(SearchEngine.search(clips: [clip], query: "jalan", embedding: [1, 0, 0]).count, 1)
        XCTAssertTrue(SearchEngine.search(clips: [clip], query: "", limit: 0).isEmpty)
    }
    func testLibraryRoundTripPreservesEmbeddingsAndPartialProgress() throws {
        let store = try LibraryStore(directory: temporaryDirectory())
        var library = LibraryManifest()
        let folder = FootageFolder(path: "/Videos", bookmark: Data([1, 2, 3]))
        library.folders = [folder]
        library.clips = [FootageClip(folderID: folder.id, path: "/Videos/a.mov", duration: 24, segments: [VideoSegment(start: 0, end: 12, visualEmbedding: [0.6, 0.8]), VideoSegment(start: 12, end: 24)])]
        try store.save(library)
        XCTAssertEqual(try store.load(), library)
        XCTAssertFalse(try store.load().clips[0].isIndexed)
        XCTAssertEqual(try store.load().clips[0].segments[0].visualEmbedding, [0.6, 0.8])
    }
    func testCorruptedIndexIsNotSilentlyReplaced() throws {
        let store = try LibraryStore(directory: temporaryDirectory())
        let corrupt = Data("not valid JSON".utf8)
        try corrupt.write(to: store.manifestURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.manifestURL), corrupt)
    }
    func testDiscoveryUsesOnlyTheMatchingCachedArchitecture() throws {
        let home = try temporaryDirectory()
        let model = home.appendingPathComponent(".cache/huggingface/hub/models--mlx-community--embeddinggemma-2-bf16/snapshots/test-revision")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data("{\"model_type\":\"embedding_gemma2\"}".utf8).write(to: model.appendingPathComponent("config.json"))
        try Data([1]).write(to: model.appendingPathComponent("model.safetensors"))
        let python = home.appendingPathComponent(".unsloth/studio/unsloth_studio/bin/python")
        try FileManager.default.createDirectory(at: python.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: python)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        let result = LocalModelInstallation.discover(home: home)
        XCTAssertTrue(result.isAvailable)
        XCTAssertEqual(result.modelDirectory?.resolvingSymlinksInPath().path, model.resolvingSymlinksInPath().path)
        XCTAssertEqual(result.pythonExecutable?.resolvingSymlinksInPath().path, python.resolvingSymlinksInPath().path)
        try Data("{\"model_type\":\"gemma\"}".utf8).write(to: model.appendingPathComponent("config.json"))
        XCTAssertNil(LocalModelInstallation.discover(home: home).modelDirectory)
    }
    func testDiscoverFindsMLXCommunityModel() {
        let result = LocalModelInstallation.discover()
        XCTAssertTrue(result.isAvailable)
        XCTAssertTrue(result.modelDirectory?.path.contains("models--mlx-community--embeddinggemma-2-bf16") == true)
    }
    func testTimecodeNeverOverflowsAtAnHour() {
        XCTAssertEqual(timecode(3661), "1:01:01")
        XCTAssertEqual(timecode(125), "02:05")
        XCTAssertEqual(timecode(-10), "00:00")
        XCTAssertEqual(timecode(.nan), "00:00")
    }
    func testWorkerPipeReturnsShortResponsesWithoutWaitingForEOF() async throws {
        let directory = try temporaryDirectory()
        let script = directory.appendingPathComponent("test_worker.py")
        let source = """
        import sys, json
        for line in sys.stdin:
            request=json.loads(line)
            if request['op']=='verify':
                print(json.dumps({'ok':True,'backend':'isolated test worker'}),flush=True)
            else:
                print(json.dumps({'ok':True,'embedding':[1.0]+[0.0]*767}),flush=True)
        """
        try Data(source.utf8).write(to: script)
        let installation = LocalModelInstallation(modelDirectory: directory, pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"))
        let engine = LocalEngine(installation: installation, script: script, logDirectory: directory)
        let backend = try await engine.verify()
        XCTAssertEqual(backend, "isolated test worker")
        let vector = try await engine.embed(query: "hutan", mode: .visual)
        XCTAssertEqual(vector.count, 768)
        XCTAssertEqual(vector.first, 1)
        await engine.stop()
    }
    func testDialogueSearchMatchesExactSpokenCueAndContext() {
        let folder = UUID()
        let clip = FootageClip(
            folderID: folder,
            path: "/Volumes/Footage/Travel/Morning walk/Jalan berkabut.mov",
            relativePath: "Travel / Morning walk",
            duration: 420,
            hasAudio: true,
            transcripts: [
                TranscriptCue(start: 129, end: 133, text: "Kabutnya makin tebal, ya."),
                TranscriptCue(start: 134, end: 138, text: "Kita jalan dulu, kabutnya mulai turun."),
                TranscriptCue(start: 139, end: 143, text: "Iya, lewat sebelah kiri.")
            ]
        )
        let results = SearchEngine.search(clips: [clip], query: "kabutnya mulai turun", mode: .dialogue)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.matchedCue?.text, "Kita jalan dulu, kabutnya mulai turun.")
        XCTAssertEqual(results.first?.matchedCue?.start, 134)
        XCTAssertEqual(results.first?.contextCues.count, 3)
        XCTAssertEqual(results.first?.contextCues[0].text, "Kabutnya makin tebal, ya.")
        XCTAssertEqual(results.first?.contextCues[2].text, "Iya, lewat sebelah kiri.")
    }
    func testDialogueSemanticSearchMatchesMeaningEvenWithDifferentWords() {
        let folder = UUID()
        let clip = FootageClip(
            folderID: folder,
            path: "/Volumes/Footage/Travel/Morning walk/Jalan berkabut.mov",
            relativePath: "Travel / Morning walk",
            duration: 420,
            hasAudio: true,
            transcripts: [
                TranscriptCue(start: 129, end: 133, text: "Kabutnya makin tebal, ya.", embedding: [0, 1]),
                TranscriptCue(start: 134, end: 138, text: "Kita istirahat dan berteduh.", embedding: [0.99, 0.01]),
                TranscriptCue(start: 139, end: 143, text: "Iya, lewat sebelah kiri.", embedding: [0, 1])
            ]
        )
        let results = SearchEngine.search(clips: [clip], query: "berhenti santai", mode: .dialogue, textEmbedding: [1, 0])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.matchedCue?.text, "Kita istirahat dan berteduh.")
    }
    func testSubtitleParserParsesSRT() {
        let srt = """
        1
        00:02:09,000 --> 00:02:13,000
        Kabutnya makin tebal, ya.

        2
        00:02:14,000 --> 00:02:18,000
        Kita jalan dulu, kabutnya mulai turun.
        """
        let cues = SubtitleParser.parse(text: srt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].start, 129)
        XCTAssertEqual(cues[0].text, "Kabutnya makin tebal, ya.")
        XCTAssertEqual(cues[1].start, 134)
        XCTAssertEqual(cues[1].text, "Kita jalan dulu, kabutnya mulai turun.")
    }
    func testRealAudioExtractionIfPresent() async throws {
        let path = "/Users/apple/Documents/KERJAAN/PLAYGROUND/David laid podcast/Final render.mp4"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let dest = try temporaryDirectory().appendingPathComponent("real.wav")
        try await MediaProcessor.audio(url: URL(fileURLWithPath: path), segment: VideoSegment(start: 0, end: 10), destination: dest)
        let data = try Data(contentsOf: dest)
        XCTAssertGreaterThan(data.count, 44)
    }
    func testDialogueSearchIncludesInstantFilenameMatches() {
        let folder = UUID()
        let untranscribed = FootageClip(
            folderID: folder,
            path: "/Volumes/Footage/Podcasts/Wawancara Direktur.mp4",
            duration: 120,
            hasAudio: true,
            transcripts: []
        )
        let transcribed = FootageClip(
            folderID: folder,
            path: "/Volumes/Footage/Podcasts/Episode 1.mp4",
            duration: 120,
            hasAudio: true,
            transcripts: [
                TranscriptCue(start: 10, end: 15, text: "Selamat pagi semua pemirsa.")
            ],
            transcribedAt: Date()
        )
        // Matching by filename in untranscribed clip works instantly
        let results1 = SearchEngine.search(clips: [untranscribed, transcribed], query: "direktur", mode: .dialogue)
        XCTAssertEqual(results1.count, 1)
        XCTAssertEqual(results1.first?.clip.name, "Wawancara Direktur.mp4")

        // Matching spoken cue in transcribed clip works
        let results2 = SearchEngine.search(clips: [untranscribed, transcribed], query: "pemirsa", mode: .dialogue)
        XCTAssertEqual(results2.count, 1)
        XCTAssertEqual(results2.first?.matchedCue?.text, "Selamat pagi semua pemirsa.")
    }
}
