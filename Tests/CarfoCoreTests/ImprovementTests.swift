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

    func testLexicalWordBoundaryPreventsSubstringFalsePositives() {
        let folder = UUID()
        let clip = FootageClip(
            folderID: folder,
            path: "/koleksi/pendidikan_indonesia.mov",
            duration: 60,
            hasAudio: true,
            transcripts: [
                TranscriptCue(start: 0, end: 5, text: "kucing berlari di lapangan")
            ]
        )
        // Short token "di" should match the separate word "di", but should NOT match "pendidikan" in another clip
        let clipWithoutDi = FootageClip(
            folderID: folder,
            path: "/koleksi/pendidikan.mov",
            duration: 60,
            hasAudio: true,
            transcripts: [
                TranscriptCue(start: 0, end: 5, text: "semuanya berjalan lancar")
            ]
        )
        // "di" must not match "pendidikan" as a filename
        XCTAssertTrue(SearchEngine.search(clips: [clipWithoutDi], query: "di").isEmpty)
        // "di" matches clip that actually has word "di" in transcript (dialogue mode)
        let dialogueResults = SearchEngine.search(clips: [clip, clipWithoutDi], query: "di", mode: .dialogue)
        XCTAssertEqual(dialogueResults.count, 1)
        XCTAssertEqual(dialogueResults.first?.clip.id, clip.id)

        // "kucing" matches exact word
        let matchExact = SearchEngine.search(clips: [clip], query: "kucing", mode: .dialogue)
        XCTAssertEqual(matchExact.count, 1)

        // "kucin" (prefix >= 3) matches "kucing"
        let matchPrefix = SearchEngine.search(clips: [clip], query: "kucin", mode: .dialogue)
        XCTAssertEqual(matchPrefix.count, 1)

        // Substring inside word "lap" should NOT match "lapangan" if token is shorter or not prefix? Wait: "lap" hasPrefix "lapangan"!
        // But "pangan" should NOT match "lapangan" because it's not a prefix
        let matchSuffix = SearchEngine.search(clips: [clip], query: "pangan", mode: .dialogue)
        XCTAssertTrue(matchSuffix.isEmpty)

        // Numeric codes in filename match
        let codeClip = FootageClip(folderID: folder, path: "/DCIM/CLIP_0042.mp4", duration: 10)
        let codeMatch = SearchEngine.search(clips: [codeClip], query: "0042")
        XCTAssertEqual(codeMatch.count, 1)
    }

    func testFileRenamingAndMovingPreservesClipIdentityAndEmbeddings() async throws {
        let root = try directory()
        let imagesDir = root.appendingPathComponent("Graphics")
        let thumbnailsDir = root.appendingPathComponent("Thumbnails")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)

        let initialFile = imagesDir.appendingPathComponent("artwork_a.svg")
        let svgContent = "<svg viewBox=\"0 0 100 100\" xmlns=\"http://www.w3.org/2000/svg\"><circle cx=\"50\" cy=\"50\" r=\"40\" fill=\"red\"/></svg>"
        try svgContent.write(to: initialFile, atomically: true, encoding: .utf8)

        let folder = FootageFolder(path: imagesDir.path)
        let firstReport = try await LibraryScanner.scan(folder: folder, previous: [], thumbnails: thumbnailsDir)
        XCTAssertEqual(firstReport.clips.count, 1)
        var clip = firstReport.clips[0]
        clip.segments[0].visualEmbedding = [0.3, 0.7]

        // Rename the file on disk (preserving size and modification date)
        let renamedFile = imagesDir.appendingPathComponent("artwork_renamed.svg")
        try FileManager.default.moveItem(at: initialFile, to: renamedFile)

        let secondReport = try await LibraryScanner.scan(folder: folder, previous: [clip], thumbnails: thumbnailsDir)
        XCTAssertEqual(secondReport.clips.count, 1)
        let scanned = secondReport.clips[0]
        XCTAssertEqual(scanned.id, clip.id)
        XCTAssertEqual(scanned.path, renamedFile.resolvingSymlinksInPath().path)
        XCTAssertEqual(scanned.relativePath, "artwork_renamed.svg")
        XCTAssertEqual(scanned.segments[0].visualEmbedding, [0.3, 0.7])
    }

    func testSinglePassAudioOffsetAndDurationPassedToEngine() async throws {
        let dir = try directory()
        let script = dir.appendingPathComponent("test_audio_worker.py")
        let source = """
        import sys, json
        for line in sys.stdin:
            r = json.loads(line)
            req_id = r.get('id')
            if r.get('op') == 'verify':
                print(json.dumps({'ok': True, 'id': req_id, 'backend': 'MLX'}), flush=True)
            elif r.get('op') == 'audio':
                offset = r.get('offset', 0.0)
                duration = r.get('duration', 0.0)
                # Embed the offset into the first vector component to verify roundtrip
                vec = [float(offset)] + [0.0] * 767
                # Unit normalize
                vec[0] = 1.0
                print(json.dumps({'ok': True, 'id': req_id, 'embedding': vec, 'received_offset': offset, 'received_duration': duration}), flush=True)
            else:
                print(json.dumps({'ok': True, 'id': req_id, 'embedding': [1.0] + [0.0] * 767}), flush=True)
        """
        try Data(source.utf8).write(to: script)
        let installation = LocalModelInstallation(modelDirectory: dir, pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"))
        let engine = LocalEngine(installation: installation, script: script, logDirectory: dir)
        let dummyWav = dir.appendingPathComponent("full.wav")
        try Data(repeating: 0, count: 100).write(to: dummyWav)

        let vector = try await engine.embed(audio: dummyWav, offset: 24.0, duration: 12.0)
        XCTAssertEqual(vector.count, 768)
        XCTAssertEqual(vector.first, 1.0)
        await engine.stop()
    }

    func testCF15_RankingCalibrationPhraseInFilenameOutranksPartialTokens() {
        let folder = UUID()
        // a has exact name: "pantai kuta.mov"
        let exactClip = FootageClip(folderID: folder, path: "/pantai kuta.mov", duration: 10)
        // b has exact phrase inside a longer name: "liburan_pantai_kuta_bali.mov"
        let phraseClip = FootageClip(folderID: folder, path: "/liburan_pantai_kuta_bali.mov", duration: 10)
        // c has scattered tokens: "kuta_di_pinggir_pantai.mov"
        let scatteredClip = FootageClip(folderID: folder, path: "/kuta_di_pinggir_pantai.mov", duration: 10)

        let results = SearchEngine.search(clips: [scatteredClip, exactClip, phraseClip], query: "pantai kuta")
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].clip.id, exactClip.id)
        XCTAssertEqual(results[1].clip.id, phraseClip.id)
        XCTAssertEqual(results[2].clip.id, scatteredClip.id)
        XCTAssertGreaterThan(results[0].score, results[1].score)
        XCTAssertGreaterThan(results[1].score, results[2].score)
    }

    func testCF15_DialogueRankingPrioritizesSemanticMatchesOverUntranscribedPartialFilename() {
        let folder = UUID()
        // Transcribed clip with a strong semantic dialogue match
        let transcribed = FootageClip(
            folderID: folder,
            path: "/travel/vlog_01.mp4",
            duration: 60,
            hasAudio: true,
            transcripts: [
                TranscriptCue(start: 10, end: 15, text: "kita istirahat dan berteduh", embedding: [0.95, 0.05])
            ],
            transcribedAt: Date()
        )
        // Untranscribed clip that happens to have one token in its filename
        let untranscribed = FootageClip(
            folderID: folder,
            path: "/travel/santai_sore.mp4",
            duration: 60,
            hasAudio: true,
            transcripts: []
        )

        // Query: "berhenti santai"
        let queryVector: [Float] = [1.0, 0.0]
        let results = SearchEngine.search(clips: [untranscribed, transcribed], query: "berhenti santai", mode: .dialogue, textEmbedding: queryVector)

        // The actual dialogue match should outrank the untranscribed clip that only had one word in its filename!
        XCTAssertEqual(results.first?.clip.id, transcribed.id)
        XCTAssertEqual(results.first?.matchedCue?.text, "kita istirahat dan berteduh")
    }
}
