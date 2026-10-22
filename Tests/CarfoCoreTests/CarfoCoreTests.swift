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
    func testAccelerateVectorMathAccuracyAndSimilarity() {
        let u1 = VectorMath.normalized([1, 2, 3, 4])!
        let u2 = VectorMath.normalized([2, 3, 4, 5])!
        let sim = VectorMath.similarity(normalizedQuery: u1, candidate: u2)!
        let cos = VectorMath.cosine(u1, u2)!
        XCTAssertEqual(sim, cos, accuracy: 0.00001)
        XCTAssertEqual(VectorMath.dot(u1, u2)!, cos, accuracy: 0.00001)
        // Candidate not pre-normalized
        let simUnnorm = VectorMath.similarity(normalizedQuery: u1, candidate: [2, 3, 4, 5])!
        XCTAssertEqual(simUnnorm, cos, accuracy: 0.00001)
        // Mismatched dimensions
        XCTAssertNil(VectorMath.similarity(normalizedQuery: [1, 0], candidate: [1, 0, 0]))
        XCTAssertNil(VectorMath.dot([1, 0], [1, 0, 0]))
    }
    func testMultiModalScoreBoostRanksDualMatchingClipsHigher() {
        let folder = UUID()
        // a matches both visual and audio
        let a = FootageClip(folderID: folder, path: "/dual.mov", duration: 10, hasAudio: true, segments: [
            VideoSegment(start: 0, end: 10, visualEmbedding: [1, 0], audioEmbedding: [0.9, 0.1])
        ], mediaType: .video)
        // b matches only visual
        let b = FootageClip(folderID: folder, path: "/visual_only.mov", duration: 10, hasAudio: true, segments: [
            VideoSegment(start: 0, end: 10, visualEmbedding: [1, 0], audioEmbedding: [0.1, 0.9])
        ], mediaType: .video)
        let results = SearchEngine.search(clips: [b, a], query: "scene", mode: .video, embedding: [1, 0])
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].clip.id, a.id, "Clip matching both visual and audio must rank first")
        XCTAssertGreaterThan(results[0].score, results[1].score)
    }
    func testDialogueModeFallsBackToAudioEmbeddingForUntranscribedClips() {
        let folder = UUID()
        // a is transcribed with dialogue
        let a = FootageClip(folderID: folder, path: "/transcribed.mov", duration: 10, hasAudio: true, transcripts: [
            TranscriptCue(start: 2, end: 4, text: "Halo apa kabar")
        ], transcribedAt: Date())
        // b has no transcript, but has audio embedding matching the query
        let b = FootageClip(folderID: folder, path: "/untranscribed.mov", duration: 10, hasAudio: true, segments: [
            VideoSegment(start: 0, end: 10, audioEmbedding: [0.95, 0.05])
        ])
        let results = SearchEngine.search(clips: [a, b], query: "kabar", mode: .dialogue, textEmbedding: [0.95, 0.05])
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains { $0.clip.id == a.id })
        XCTAssertTrue(results.contains { $0.clip.id == b.id })
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
    func testFixtureAudioExtractionIfPresent() async throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".runtime/Fixtures/Videos/Test red.mp4").path
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("Generate the repository media fixtures first") }
        let dest = try temporaryDirectory().appendingPathComponent("real.wav")
        try await MediaProcessor.audio(url: URL(fileURLWithPath: path), segment: VideoSegment(start: 0, end: 1), destination: dest)
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
    func testSVGMetadataAndThumbnailGeneration() throws {
        let dir = try temporaryDirectory()
        let svgURL = dir.appendingPathComponent("test-graphic.svg")
        let svgContent = """
        <svg width="400" height="200" viewBox="0 0 400 200" xmlns="http://www.w3.org/2000/svg">
            <rect width="400" height="200" fill="#0866D8"/>
            <circle cx="200" cy="100" r="50" fill="#ffffff"/>
        </svg>
        """
        try svgContent.write(to: svgURL, atomically: true, encoding: .utf8)

        let dims = try LibraryScanner.imageMetadata(url: svgURL)
        XCTAssertEqual(dims.width, 400)
        XCTAssertEqual(dims.height, 200)

        let thumbURL = dir.appendingPathComponent("thumb.jpg")
        try LibraryScanner.imageThumbnail(url: svgURL, destination: thumbURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbURL.path))
        let thumbData = try Data(contentsOf: thumbURL)
        XCTAssertEqual(thumbData.prefix(2), Data([0xff, 0xd8]))
    }
    func testSVGScanningProducesImageClip() async throws {
        let dir = try temporaryDirectory()
        let imagesDir = dir.appendingPathComponent("Graphics")
        let thumbsDir = dir.appendingPathComponent("Thumbs")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbsDir, withIntermediateDirectories: true)

        let svgURL = imagesDir.appendingPathComponent("vector_logo.svg")
        let svgContent = """
        <svg viewBox="0 0 300 150" xmlns="http://www.w3.org/2000/svg">
            <path d="M 10 10 L 290 10 L 150 140 Z" fill="purple"/>
        </svg>
        """
        try svgContent.write(to: svgURL, atomically: true, encoding: .utf8)

        let folder = FootageFolder(path: imagesDir.path)
        let report = try await LibraryScanner.scan(folder: folder, previous: [], thumbnails: thumbsDir)
        XCTAssertTrue(report.errors.isEmpty, "Scan errors: \(report.errors)")
        XCTAssertEqual(report.clips.count, 1)

        let clip = try XCTUnwrap(report.clips.first)
        XCTAssertEqual(clip.mediaType, .image)
        XCTAssertEqual(clip.name, "vector_logo.svg")
        XCTAssertEqual(clip.width, 300)
        XCTAssertEqual(clip.height, 150)
        XCTAssertNotNil(clip.thumbnail)
        if let thumb = clip.thumbnail {
            XCTAssertTrue(FileManager.default.fileExists(atPath: thumbsDir.appendingPathComponent(thumb).path))
        }
    }

    func testCF01_LibraryStoreBackupAndRestore() throws {
        let dir = try temporaryDirectory()
        let store = try LibraryStore(directory: dir)
        var manifest = LibraryManifest()
        let folder = FootageFolder(path: "/TestFolder")
        manifest.folders = [folder]
        manifest.clips = [FootageClip(folderID: folder.id, path: "/TestFolder/clip.mov", duration: 10)]
        try store.save(manifest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.manifestURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backupURL.path))

        // Corrupt manifest file
        try Data("corrupted data".utf8).write(to: store.manifestURL)
        XCTAssertThrowsError(try store.load())

        // Restore from backup
        let restored = try store.restoreBackup()
        XCTAssertEqual(restored.clips.count, 1)
        XCTAssertEqual(restored.clips[0].path, "/TestFolder/clip.mov")
        XCTAssertEqual(try store.load(), manifest)
    }

    func testCF02_PartialAudioIndexingIsNotComplete() {
        let folder = UUID()
        let segments = [
            VideoSegment(start: 0, end: 12, audioEmbedding: [1, 0]),
            VideoSegment(start: 12, end: 24, audioEmbedding: nil),
            VideoSegment(start: 24, end: 36, audioEmbedding: nil)
        ]
        var audioClip = FootageClip(folderID: folder, path: "/audio.mp3", duration: 36, hasAudio: true, segments: segments, mediaType: .audio)
        XCTAssertFalse(audioClip.isIndexed, "Audio with only 1 of 3 segments indexed should not be considered isIndexed")

        // Once all segments have audioEmbedding:
        audioClip.segments[1].audioEmbedding = [0.8, 0.2]
        audioClip.segments[2].audioEmbedding = [0.5, 0.5]
        XCTAssertTrue(audioClip.isIndexed, "Audio with all segments indexed should be isIndexed")
    }

    func testCF03_TranscriptionErrorDoesNotMarkCompleted() {
        let folder = UUID()
        let clip = FootageClip(
            folderID: folder,
            path: "/dialogue.mov",
            duration: 20,
            hasAudio: true,
            transcripts: [],
            transcribedAt: nil,
            transcriptError: "Transcriber failed: model out of memory",
            mediaType: .video
        )
        XCTAssertTrue(clip.needsTranscript, "Clip with transcript error must retain needsTranscript = true for retry")
        XCTAssertNil(clip.transcribedAt)
        XCTAssertEqual(clip.transcriptError, "Transcriber failed: model out of memory")
    }

    func testCF04_ParallelSearchWithManyCandidatesIsConsistent() {
        let folder = UUID()
        var clips: [FootageClip] = []
        for i in 0..<40 {
            let angle = Float(i) / 40.0 * Float.pi * 2.0
            let embed = [cos(angle), sin(angle)]
            let clip = FootageClip(
                folderID: folder,
                path: "/clip_\(i).mov",
                duration: 12,
                segments: [VideoSegment(start: 0, end: 12, visualEmbedding: embed)],
                mediaType: .video
            )
            clips.append(clip)
        }
        let queryVector: [Float] = [1, 0]
        let results = SearchEngine.search(clips: clips, query: "clip", mode: .video, embedding: queryVector, limit: 10)
        XCTAssertEqual(results.count, 10)
        // Top match should be clip_0 (angle 0 => [1, 0])
        XCTAssertEqual(results.first?.clip.name, "clip_0.mov")
        XCTAssertEqual(results.first?.score ?? 0, 1.35, accuracy: 0.001)
        // Verify scores are strictly descending
        for i in 0..<(results.count - 1) {
            XCTAssertGreaterThanOrEqual(results[i].score, results[i + 1].score)
        }
    }

    func testCF05_DialogueSearchFallbackUsesTextEmbeddingWhenUntranscribed() {
        let folder = UUID()
        let clip = FootageClip(
            folderID: folder,
            path: "/podcast_untranscribed.mov",
            duration: 12,
            hasAudio: true,
            segments: [VideoSegment(start: 0, end: 12, audioEmbedding: [0.99, 0.01])],
            mediaType: .video
        )
        // Dialogue search when no transcripts exist, passing textEmbedding (as AppModel does)
        let results = SearchEngine.search(clips: [clip], query: "obrolan", mode: .dialogue, textEmbedding: [1, 0])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.clip.id, clip.id)
        XCTAssertGreaterThan(results.first?.score ?? 0, 0.78)
    }

    func testCF06_ModelIdentifierDiffersAcrossRevisionsInSameDirectoryName() throws {
        let temp = try temporaryDirectory()
        let dirA = temp.appendingPathComponent("RevA/Model")
        let dirB = temp.appendingPathComponent("RevB/Model")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)

        try Data("{\"model_type\":\"embedding_gemma2\",\"hidden_size\":768}".utf8).write(to: dirA.appendingPathComponent("config.json"))
        try Data([UInt8](repeating: 1, count: 1024)).write(to: dirA.appendingPathComponent("model.safetensors"))

        try Data("{\"model_type\":\"embedding_gemma2\",\"hidden_size\":1024}".utf8).write(to: dirB.appendingPathComponent("config.json"))
        try Data([UInt8](repeating: 2, count: 2048)).write(to: dirB.appendingPathComponent("model.safetensors"))

        let idA = LocalModelInstallation.computeModelIdentifier(for: dirA)
        let idB = LocalModelInstallation.computeModelIdentifier(for: dirB)
        XCTAssertNotEqual(idA, idB, "Models in folder named 'Model' with different configs/weights must produce different identifiers")
    }

    func testCF07_InstantTextSearchReturnsImmediatelyWithoutEmbedding() {
        let folder = UUID()
        let a = FootageClip(folderID: folder, path: "/Volumes/Footage/Travel/jalan_pagi.mov", duration: 10, segments: [
            VideoSegment(start: 0, end: 10, visualEmbedding: [0, 1])
        ], mediaType: .video)
        let b = FootageClip(folderID: folder, path: "/Volumes/Footage/Travel/ombak_laut.mov", duration: 10, segments: [
            VideoSegment(start: 0, end: 10, visualEmbedding: [1, 0])
        ], mediaType: .video)

        // Phase 1: Instant search without embedding
        let instant = SearchEngine.search(clips: [a, b], query: "jalan", mode: .video, embedding: nil)
        XCTAssertEqual(instant.count, 1)
        XCTAssertEqual(instant.first?.clip.id, a.id)
        XCTAssertEqual(instant.first?.score, 0.35)

        // Phase 2: Semantic search with embedding (querying for [1, 0])
        let semantic = SearchEngine.search(clips: [a, b], query: "jalan", mode: .video, embedding: [1, 0])
        XCTAssertEqual(semantic.count, 2)
        XCTAssertEqual(semantic.first?.clip.id, b.id)
        XCTAssertEqual(semantic.first?.score ?? 0, 1.0, accuracy: 0.001)
    }

    func testCF08_WorkerCancellationRespondsQuickly() async throws {
        let directory = try temporaryDirectory()
        let script = directory.appendingPathComponent("slow_worker.py")
        let source = """
        import sys, json, time
        for line in sys.stdin:
            req = json.loads(line)
            req_id = req.get('id')
            time.sleep(1.5)
            res = {'ok': True, 'backend': 'slow_result'}
            if req_id is not None:
                res['id'] = req_id
            print(json.dumps(res), flush=True)
        """
        try Data(source.utf8).write(to: script)
        let installation = LocalModelInstallation(modelDirectory: directory, pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"))
        let engine = LocalEngine(installation: installation, script: script, logDirectory: directory)

        let start = Date()
        let task = Task {
            try await engine.verify()
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        var caughtCancellation = false
        do {
            _ = try await task.value
        } catch is CancellationError {
            caughtCancellation = true
        } catch {
            // Cancellation caught
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertTrue(caughtCancellation, "Cancelled task should throw CancellationError")
        XCTAssertLessThan(elapsed, 0.5, "Cancellation must respond rapidly (<0.5s) without waiting for 1.5s worker delay")
        await engine.stop()
    }

    func testCF08_StopButtonResponseTimeRecorded() async throws {
        let directory = try temporaryDirectory()
        let script = directory.appendingPathComponent("slow_stop_worker.py")
        let source = """
        import sys, json, time
        for line in sys.stdin:
            req = json.loads(line)
            time.sleep(1.5)
            print(json.dumps({'ok': True, 'backend': 'done'}), flush=True)
        """
        try Data(source.utf8).write(to: script)
        let installation = LocalModelInstallation(modelDirectory: directory, pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"))
        let engine = LocalEngine(installation: installation, script: script, logDirectory: directory)

        let bgTask = Task {
            try? await engine.verify()
        }
        try await Task.sleep(for: .milliseconds(50))

        let stopStart = Date()
        await engine.stop()
        let stopElapsed = Date().timeIntervalSince(stopStart)

        print("[CF-08 Benchmark] engine.stop() response time: \(String(format: "%.3f", stopElapsed * 1000)) ms")
        XCTAssertLessThan(stopElapsed, 0.2, "Stop button response time must be under 200ms even when worker is in a 1.5s delay")
        _ = await bgTask.result
    }

    func testCF08_StaleResponseIgnoredOnNewSearchAfterCancellation() async throws {
        let directory = try temporaryDirectory()
        let script = directory.appendingPathComponent("id_worker.py")
        let source = """
        import sys, json, time
        for line in sys.stdin:
            req = json.loads(line)
            req_id = req.get('id')
            if req.get('op') == 'slow':
                time.sleep(0.2)
                res = {'ok': True, 'val': 'old_stale_response'}
            else:
                res = {'ok': True, 'val': 'new_fresh_response'}
            if req_id is not None:
                res['id'] = req_id
            print(json.dumps(res), flush=True)
        """
        try Data(source.utf8).write(to: script)
        let installation = LocalModelInstallation(modelDirectory: directory, pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"))
        let engine = LocalEngine(installation: installation, script: script, logDirectory: directory)

        let task1 = Task {
            _ = try await engine.request(["op": "slow"])
        }
        try await Task.sleep(for: .milliseconds(30))
        task1.cancel()
        _ = try? await task1.value

        let res2 = try await engine.request(["op": "fast"])
        XCTAssertEqual(res2["val"] as? String, "new_fresh_response", "New request must not receive stale response from cancelled request")
        await engine.stop()
    }

    func testCF08_WorkerSuddenExitOrCrashDetectedAndRecovers() async throws {
        let directory = try temporaryDirectory()
        let script = directory.appendingPathComponent("crash_worker.py")
        let source = """
        import sys, json
        for line in sys.stdin:
            req = json.loads(line)
            req_id = req.get('id')
            if req.get('op') == 'crash':
                sys.exit(42)
            res = {'ok': True, 'backend': 'recovered'}
            if req_id is not None:
                res['id'] = req_id
            print(json.dumps(res), flush=True)
        """
        try Data(source.utf8).write(to: script)
        let installation = LocalModelInstallation(modelDirectory: directory, pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"))
        let engine = LocalEngine(installation: installation, script: script, logDirectory: directory)

        var caughtStopped = false
        do {
            _ = try await engine.request(["op": "crash"])
        } catch EngineError.stopped {
            caughtStopped = true
        }
        XCTAssertTrue(caughtStopped, "Abrupt worker termination must throw EngineError.stopped")

        let response = try await engine.verify()
        XCTAssertEqual(response, "recovered", "Next request after worker exit must restart worker cleanly")
        await engine.stop()
    }

    func testCF08_WorkerTimeoutHandled() async throws {
        let directory = try temporaryDirectory()
        let script = directory.appendingPathComponent("hang_worker.py")
        let source = """
        import sys, json, time
        for line in sys.stdin:
            time.sleep(10)
        """
        try Data(source.utf8).write(to: script)
        let installation = LocalModelInstallation(modelDirectory: directory, pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"))
        let engine = LocalEngine(installation: installation, script: script, logDirectory: directory)

        var caughtTimeout = false
        do {
            _ = try await engine.verify(timeout: 0.15)
        } catch EngineError.timedOut {
            caughtTimeout = true
        }
        XCTAssertTrue(caughtTimeout, "Requests exceeding timeout must throw EngineError.timedOut")
        await engine.stop()
    }

    func testCF09_SingleSegmentIncrementalUpdateDoesNotRewriteWholeCollection() throws {
        let dir = try temporaryDirectory()
        let store = try LibraryStore(directory: dir)
        var manifest = LibraryManifest()
        let folder = FootageFolder(path: "/Media")
        manifest.folders = [folder]

        for i in 0..<20 {
            let clip = FootageClip(
                folderID: folder.id,
                path: "/Media/clip_\(i).mov",
                duration: 36,
                segments: [
                    VideoSegment(start: 0, end: 12, visualEmbedding: [Float(i), 0.1]),
                    VideoSegment(start: 12, end: 24, visualEmbedding: [Float(i), 0.2]),
                    VideoSegment(start: 24, end: 36, visualEmbedding: [Float(i), 0.3])
                ]
            )
            manifest.clips.append(clip)
        }
        try store.save(manifest)

        let targetClipID = manifest.clips[5].id
        var updatedSegment = manifest.clips[5].segments[1]
        updatedSegment.audioEmbedding = [0.99, 0.88]
        updatedSegment.transcript = "suara burung di hutan"

        let start = Date()
        try store.saveSegment(clipID: targetClipID, segment: updatedSegment)
        let elapsed = Date().timeIntervalSince(start)

        print("[CF-09 Benchmark] saveSegment duration: \(String(format: "%.3f", elapsed * 1000)) ms")
        XCTAssertLessThan(elapsed, 0.05, "Incremental update of a single segment must be faster than 50ms")

        let reloaded = try store.load()
        let reloadedTarget = reloaded.clips.first { $0.id == targetClipID }
        XCTAssertEqual(reloadedTarget?.segments[1].audioEmbedding, [0.99, 0.88])
        XCTAssertEqual(reloadedTarget?.segments[1].transcript, "suara burung di hutan")

        let clip0 = reloaded.clips.first { $0.path == "/Media/clip_0.mov" }
        XCTAssertEqual(clip0?.segments[0].visualEmbedding, [0.0, 0.1])
        XCTAssertNil(clip0?.segments[1].audioEmbedding)
    }

    func testCF09_MigrationFromJSONPreservesAllData() throws {
        let dir = try temporaryDirectory()
        let store = try LibraryStore(directory: dir)

        var jsonManifest = LibraryManifest()
        let folderID = UUID()
        let folder = FootageFolder(id: folderID, path: "/Volumes/Ext", bookmark: Data([9, 8, 7]), scannedAt: Date(timeIntervalSince1970: 1700000000))
        jsonManifest.folders = [folder]

        let clipID = UUID()
        let cueID = UUID()
        let clip = FootageClip(
            id: clipID,
            folderID: folderID,
            path: "/Volumes/Ext/sample.mp4",
            relativePath: "Sub/sample.mp4",
            fileSize: 1048576,
            modifiedAt: Date(timeIntervalSince1970: 1700001000),
            duration: 120,
            width: 1920,
            height: 1080,
            frameRate: 29.97,
            hasAudio: true,
            thumbnail: "sample.jpg",
            segments: [
                VideoSegment(start: 0, end: 12, visualEmbedding: [0.123, 0.456], audioEmbedding: [0.789, 0.012], transcript: "pembuka", cues: [
                    TranscriptCue(id: cueID, start: 1, end: 5, text: "Halo pemirsa", speaker: "Host", embedding: [0.55, 0.66])
                ])
            ],
            indexedAt: Date(timeIntervalSince1970: 1700003000),
            indexError: nil,
            transcripts: [
                TranscriptCue(start: 10, end: 15, text: "Penutup acara", speaker: "Host", embedding: [0.77, 0.88])
            ],
            transcribedAt: Date(timeIntervalSince1970: 1700002000),
            transcriptError: nil,
            mediaType: .video
        )
        jsonManifest.clips = [clip]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(jsonManifest).write(to: store.manifestURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.databaseURL.path))

        let migrated = try store.load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.databaseURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backupURL.path))
        let db = try store.database()
        XCTAssertTrue(db.checkIntegrity(), "Migrated SQLite database must pass integrity check")

        XCTAssertEqual(migrated.folders.count, 1)
        XCTAssertEqual(migrated.folders[0].id, folderID)
        XCTAssertEqual(migrated.folders[0].path, "/Volumes/Ext")
        XCTAssertEqual(migrated.folders[0].bookmark, Data([9, 8, 7]))
        XCTAssertEqual(migrated.folders[0].scannedAt?.timeIntervalSince1970, 1700000000)

        XCTAssertEqual(migrated.clips.count, 1)
        let c = migrated.clips[0]
        XCTAssertEqual(c.id, clipID)
        XCTAssertEqual(c.folderID, folderID)
        XCTAssertEqual(c.path, "/Volumes/Ext/sample.mp4")
        XCTAssertEqual(c.fileSize, 1048576)
        XCTAssertEqual(c.duration, 120)
        XCTAssertEqual(c.width, 1920)
        XCTAssertEqual(c.height, 1080)
        XCTAssertEqual(c.frameRate, 29.97, accuracy: 0.001)
        XCTAssertEqual(c.hasAudio, true)
        XCTAssertEqual(c.thumbnail, "sample.jpg")

        XCTAssertEqual(c.segments.count, 1)
        XCTAssertEqual(c.segments[0].visualEmbedding, [0.123, 0.456])
        XCTAssertEqual(c.segments[0].audioEmbedding, [0.789, 0.012])
        XCTAssertEqual(c.segments[0].transcript, "pembuka")
        XCTAssertEqual(c.segments[0].cues.count, 1)
        XCTAssertEqual(c.segments[0].cues[0].id, cueID)
        XCTAssertEqual(c.segments[0].cues[0].text, "Halo pemirsa")
        XCTAssertEqual(c.segments[0].cues[0].embedding, [0.55, 0.66])

        XCTAssertEqual(c.transcripts.count, 1)
        XCTAssertEqual(c.transcripts[0].text, "Penutup acara")
        XCTAssertEqual(c.transcripts[0].embedding, [0.77, 0.88])
    }

    func testCF09_WriteFailureRollsBackAtomically() throws {
        let dir = try temporaryDirectory()
        let store = try LibraryStore(directory: dir)
        var manifest = LibraryManifest()
        manifest.folders = [FootageFolder(path: "/A")]
        manifest.clips = [FootageClip(folderID: manifest.folders[0].id, path: "/A/1.mov", duration: 10)]
        try store.save(manifest)

        let db = try store.database()
        XCTAssertThrowsError(try db.transaction {
            try db.saveClip(FootageClip(folderID: UUID(), path: "/A/2.mov", duration: 10))
            throw DatabaseError.executionFailed("Simulated error")
        })

        let reloaded = try store.load()
        XCTAssertEqual(reloaded.clips.count, 1)
        XCTAssertEqual(reloaded.clips[0].path, "/A/1.mov")
    }

    func testCF09_BackupCreationAndRestoration() throws {
        let dir = try temporaryDirectory()
        let store = try LibraryStore(directory: dir)
        var manifest = LibraryManifest()
        manifest.folders = [FootageFolder(path: "/BackupTest")]
        manifest.clips = [
            FootageClip(folderID: manifest.folders[0].id, path: "/BackupTest/video.mov", duration: 45, segments: [
                VideoSegment(start: 0, end: 12, visualEmbedding: [0.42, 0.84])
            ])
        ]
        try store.save(manifest)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.databaseBackupURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backupURL.path))

        try Data("garbage sqlite".utf8).write(to: store.databaseURL)

        let restored = try store.restoreBackup()
        XCTAssertEqual(restored.clips.count, 1)
        XCTAssertEqual(restored.clips[0].path, "/BackupTest/video.mov")
        XCTAssertEqual(restored.clips[0].segments[0].visualEmbedding, [0.42, 0.84])

        let reloaded = try store.load()
        XCTAssertEqual(reloaded.clips.count, 1)
    }
}


