import Foundation

public enum MediaType: String, Codable, Sendable {
    case video, image, audio

    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif", "svg", "avif", "ico"]
    public static let audioExtensions: Set<String> = ["mp3", "wav", "aac", "m4a", "ogg", "flac", "wma", "aiff", "aif", "opus"]
    public static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "mkv", "avi", "webm"]

    public static func from(extension ext: String) -> MediaType {
        let lower = ext.lowercased()
        if imageExtensions.contains(lower) { return .image }
        if audioExtensions.contains(lower) { return .audio }
        return .video
    }
}

public enum SearchMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case video, visual, dialogue, sound
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .video: return "Video"
        case .visual: return "Gambar"
        case .dialogue: return "Dialog"
        case .sound: return "Suara"
        }
    }
    public var symbol: String {
        switch self {
        case .video: return "film"
        case .visual: return "photo"
        case .dialogue: return "quote.bubble"
        case .sound: return "waveform"
        }
    }
    public var placeholder: String {
        switch self {
        case .video: return "Cari footage di Mac ini..."
        case .visual: return "Cari adegan atau objek gambar..."
        case .dialogue: return "Cari topik yang dibicarakan..."
        case .sound: return "Cari suara atau suasana..."
        }
    }
    public func queryText(_ text: String) -> String {
        switch self {
        case .video: return "task: search result | query: \(text)"
        case .visual: return "task: search result | query: image of \(text)"
        case .dialogue: return "task: search result | query: spoken dialogue about \(text)"
        case .sound: return "task: search result | query: sound of \(text)"
        }
    }
}

public struct FootageFolder: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var path: String
    public var bookmark: Data?
    /// Last time a full scan of this folder finished. Lets an interrupted rescan skip folders it already completed.
    public var scannedAt: Date?
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public init(id: UUID = UUID(), path: String, bookmark: Data? = nil, scannedAt: Date? = nil) {
        self.id = id; self.path = path; self.bookmark = bookmark; self.scannedAt = scannedAt
    }
}

public struct TranscriptCue: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var text: String
    public var speaker: String?
    /// EmbeddingGemma vector of `text`, used for meaning-based dialogue search.
    public var embedding: [Float]?
    public init(id: UUID = UUID(), start: Double, end: Double, text: String, speaker: String? = nil, embedding: [Float]? = nil) {
        self.id = id; self.start = start; self.end = end; self.text = text; self.speaker = speaker; self.embedding = embedding
    }
}

public struct VideoSegment: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var visualEmbedding: [Float]?
    public var audioEmbedding: [Float]?
    public var transcript: String?
    public var cues: [TranscriptCue]
    public init(id: UUID = UUID(), start: Double, end: Double, visualEmbedding: [Float]? = nil, audioEmbedding: [Float]? = nil, transcript: String? = nil, cues: [TranscriptCue] = []) {
        self.id = id; self.start = start; self.end = end
        self.visualEmbedding = visualEmbedding; self.audioEmbedding = audioEmbedding
        self.transcript = transcript; self.cues = cues
    }
    enum CodingKeys: String, CodingKey {
        case id, start, end, visualEmbedding, audioEmbedding, transcript, cues
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        start = try container.decode(Double.self, forKey: .start)
        end = try container.decode(Double.self, forKey: .end)
        visualEmbedding = try container.decodeIfPresent([Float].self, forKey: .visualEmbedding)
        audioEmbedding = try container.decodeIfPresent([Float].self, forKey: .audioEmbedding)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        cues = try container.decodeIfPresent([TranscriptCue].self, forKey: .cues) ?? []
    }
}

public struct FootageClip: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var folderID: UUID
    public var path: String
    public var relativePath: String
    public var fileSize: Int64
    public var modifiedAt: Date
    public var duration: Double
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var hasAudio: Bool
    public var thumbnail: String?
    public var segments: [VideoSegment]
    public var transcripts: [TranscriptCue]
    /// Set once speech-to-text (or a sidecar subtitle) has produced `transcripts`, even if the clip has no speech.
    public var transcribedAt: Date?
    public var transcriptError: String?
    public var indexedAt: Date?
    public var indexError: String?
    public var mediaType: MediaType
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var url: URL { URL(fileURLWithPath: path) }
    public var isImage: Bool { mediaType == .image }
    public var isAudio: Bool { mediaType == .audio }
    public var isVideo: Bool { mediaType == .video }
    public var isIndexed: Bool {
        switch mediaType {
        case .image: return !segments.isEmpty && segments.allSatisfy { $0.visualEmbedding != nil }
        case .audio: return !segments.isEmpty && segments.allSatisfy { $0.audioEmbedding != nil }
        case .video: return !segments.isEmpty && segments.allSatisfy { $0.visualEmbedding != nil && (!hasAudio || $0.audioEmbedding != nil) }
        }
    }
    public var needsTranscript: Bool { hasAudio && (transcribedAt == nil || transcripts.contains { $0.embedding == nil }) }
    public init(id: UUID = UUID(), folderID: UUID, path: String, relativePath: String = "", fileSize: Int64 = 0, modifiedAt: Date = Date(), duration: Double, width: Int = 0, height: Int = 0, frameRate: Double = 0, hasAudio: Bool = false, thumbnail: String? = nil, segments: [VideoSegment] = [], indexedAt: Date? = nil, indexError: String? = nil, transcripts: [TranscriptCue] = [], transcribedAt: Date? = nil, transcriptError: String? = nil, mediaType: MediaType = .video) {
        self.id = id; self.folderID = folderID; self.path = path; self.relativePath = relativePath
        self.fileSize = fileSize; self.modifiedAt = modifiedAt; self.duration = duration
        self.width = width; self.height = height; self.frameRate = frameRate; self.hasAudio = hasAudio
        self.thumbnail = thumbnail; self.segments = segments; self.indexedAt = indexedAt; self.indexError = indexError
        self.transcripts = transcripts; self.transcribedAt = transcribedAt; self.transcriptError = transcriptError; self.mediaType = mediaType
    }
    enum CodingKeys: String, CodingKey {
        case id, folderID, path, relativePath, fileSize, modifiedAt, duration, width, height, frameRate, hasAudio, thumbnail, segments, indexedAt, indexError, transcripts, transcribedAt, transcriptError, mediaType
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        folderID = try container.decode(UUID.self, forKey: .folderID)
        path = try container.decode(String.self, forKey: .path)
        relativePath = try container.decodeIfPresent(String.self, forKey: .relativePath) ?? ""
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
        duration = try container.decode(Double.self, forKey: .duration)
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 0
        frameRate = try container.decodeIfPresent(Double.self, forKey: .frameRate) ?? 0
        hasAudio = try container.decodeIfPresent(Bool.self, forKey: .hasAudio) ?? false
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        segments = try container.decodeIfPresent([VideoSegment].self, forKey: .segments) ?? []
        indexedAt = try container.decodeIfPresent(Date.self, forKey: .indexedAt)
        indexError = try container.decodeIfPresent(String.self, forKey: .indexError)
        transcripts = try container.decodeIfPresent([TranscriptCue].self, forKey: .transcripts) ?? []
        transcribedAt = try container.decodeIfPresent(Date.self, forKey: .transcribedAt)
        transcriptError = try container.decodeIfPresent(String.self, forKey: .transcriptError)
        mediaType = try container.decodeIfPresent(MediaType.self, forKey: .mediaType)
            ?? MediaType.from(extension: URL(fileURLWithPath: path).pathExtension)
    }
}

public enum SampleDialogue {
    public static let sampleClips: [FootageClip] = [
        FootageClip(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            folderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            path: "/Volumes/Footage/Travel/Morning walk/Jalan berkabut.mov",
            relativePath: "Travel / Morning walk",
            duration: 420,
            hasAudio: true,
            transcripts: [
                TranscriptCue(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, start: 129, end: 133, text: "Kabutnya makin tebal, ya."),
                TranscriptCue(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, start: 134, end: 138, text: "Kita jalan dulu, kabutnya mulai turun."),
                TranscriptCue(id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, start: 139, end: 143, text: "Iya, lewat sebelah kiri."),
                TranscriptCue(id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!, start: 338, end: 342, text: "Kita jalan dulu sebelum gelap.")
            ]
        ),
        FootageClip(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            folderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            path: "/Volumes/Footage/Travel/Hutan/Jalan hutan.mov",
            relativePath: "Travel / Hutan",
            duration: 360,
            hasAudio: true,
            transcripts: [
                TranscriptCue(id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, start: 66, end: 70, text: "Kita jalan dulu ke arah sana."),
                TranscriptCue(id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!, start: 261, end: 265, text: "Kita jalan dulu, nanti istirahat.")
            ]
        ),
        FootageClip(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            folderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            path: "/Volumes/Footage/Travel/Gunung/Jalan pegunungan.mov",
            relativePath: "Travel / Gunung",
            duration: 300,
            hasAudio: true,
            transcripts: [
                TranscriptCue(id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!, start: 222, end: 226, text: "Kalau sudah siap, kita jalan dulu.")
            ]
        )
    ]
    public static var sampleResults: [SearchResult] {
        let clips = sampleClips
        let c1 = clips[0]
        let c2 = clips[1]
        let c3 = clips[2]
        
        let cue1 = c1.transcripts[1] // 02:14 "Kita jalan dulu, kabutnya mulai turun."
        let context1 = [c1.transcripts[0], c1.transcripts[1], c1.transcripts[2]]
        
        let cue2 = c1.transcripts[3] // 05:38 "Kita jalan dulu sebelum gelap."
        let cue3 = c2.transcripts[0] // 01:06 "Kita jalan dulu ke arah sana."
        let cue4 = c3.transcripts[0] // 03:42 "Kalau sudah siap, kita jalan dulu."
        let cue5 = c2.transcripts[1] // 04:21 "Kita jalan dulu, nanti istirahat."
        
        return [
            SearchResult(clip: c1, segment: VideoSegment(start: cue1.start, end: cue1.end), score: 10, matchedCue: cue1, contextCues: context1, isSampleData: true),
            SearchResult(clip: c1, segment: VideoSegment(start: cue2.start, end: cue2.end), score: 9, matchedCue: cue2, contextCues: [cue2], isSampleData: true),
            SearchResult(clip: c2, segment: VideoSegment(start: cue3.start, end: cue3.end), score: 8, matchedCue: cue3, contextCues: [cue3], isSampleData: true),
            SearchResult(clip: c3, segment: VideoSegment(start: cue4.start, end: cue4.end), score: 7, matchedCue: cue4, contextCues: [cue4], isSampleData: true),
            SearchResult(clip: c2, segment: VideoSegment(start: cue5.start, end: cue5.end), score: 6, matchedCue: cue5, contextCues: [cue5], isSampleData: true)
        ]
    }
}

public typealias CarfoFolder = FootageFolder
public typealias CarfoClip = FootageClip

public struct LibraryManifest: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var model: String = "mlx-community/embeddinggemma-2-bf16"
    public var modelRevision: String?
    public var folders: [FootageFolder] = []
    public var clips: [FootageClip] = []
    public init() {}
}

public struct LibraryStore: Sendable {
    public let directory: URL
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
    }
    public var thumbnailDirectory: URL { directory.appendingPathComponent("Thumbnails", isDirectory: true) }
    public var workingDirectory: URL { directory.appendingPathComponent("Working", isDirectory: true) }
    public var databaseURL: URL { directory.appendingPathComponent("library.sqlite3") }
    public var databaseBackupURL: URL { directory.appendingPathComponent("library.sqlite3.backup") }
    public var manifestURL: URL { directory.appendingPathComponent("library.json") }
    public var backupURL: URL { directory.appendingPathComponent("library.json.backup") }

    public func database() throws -> LibraryDatabase {
        try LibraryDatabase(url: databaseURL)
    }

    public func load() throws -> LibraryManifest {
        // If manifestURL exists and is non-empty, ensure it's valid JSON (protect against corrupt files)
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            if !data.isEmpty {
                let manifest = try JSONDecoder().decode(LibraryManifest.self, from: data)
                guard manifest.version == 1 else { throw LibraryError.unsupportedVersion }
            }
        }

        // 1. If SQLite database exists, load from SQLite
        if FileManager.default.fileExists(atPath: databaseURL.path) {
            let db = try LibraryDatabase(url: databaseURL)
            guard db.checkIntegrity() else {
                db.close()
                throw LibraryError.corrupted
            }
            return try db.loadManifest()
        }

        // 2. If SQLite database does not exist, but library.json exists: migrate from JSON to SQLite
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            guard !data.isEmpty else { return LibraryManifest() }
            let manifest = try JSONDecoder().decode(LibraryManifest.self, from: data)
            guard manifest.version == 1 else { throw LibraryError.unsupportedVersion }

            // Create initial JSON backup prior to migration
            try? data.write(to: backupURL, options: .atomic)

            // Safe migration via temp database
            let tempURL = directory.appendingPathComponent("library.sqlite3.migration")
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }
            do {
                let tempDb = try LibraryDatabase(url: tempURL)
                try tempDb.saveManifest(manifest)
                guard tempDb.checkIntegrity() else {
                    tempDb.close()
                    try? FileManager.default.removeItem(at: tempURL)
                    throw LibraryError.corrupted
                }
                tempDb.close()
                try FileManager.default.moveItem(at: tempURL, to: databaseURL)
                let db = try LibraryDatabase(url: databaseURL)
                try? db.createBackup(to: databaseBackupURL)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                throw error
            }
            return manifest
        }

        return LibraryManifest()
    }

    public func save(_ manifest: LibraryManifest) throws {
        // 1. Persist to SQLite database
        let db = try LibraryDatabase(url: databaseURL)
        try db.saveManifest(manifest)
        try? db.createBackup(to: databaseBackupURL)

        // 2. Export / sync JSON and backup for backward compatibility & safety
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
        try? data.write(to: backupURL, options: .atomic)
    }

    /// Incremental save of a single clip and its segments/cues without rewriting the entire database.
    public func saveClip(_ clip: FootageClip) throws {
        let db = try LibraryDatabase(url: databaseURL)
        try db.saveClip(clip)
    }

    /// Incremental save of multiple dirty clips without rewriting the entire database.
    public func saveClips(_ clips: [FootageClip]) throws {
        guard !clips.isEmpty else { return }
        let db = try LibraryDatabase(url: databaseURL)
        try db.saveClips(clips)
    }

    /// Incremental save of a single segment and its cues.
    public func saveSegment(clipID: UUID, segment: VideoSegment) throws {
        let db = try LibraryDatabase(url: databaseURL)
        try db.saveSegment(clipID: clipID, segment: segment)
    }

    /// Incremental save of a folder.
    public func saveFolder(_ folder: FootageFolder) throws {
        let db = try LibraryDatabase(url: databaseURL)
        try db.saveFolder(folder)
    }

    /// Incremental removal of a folder and its clips.
    public func removeFolder(id: UUID) throws {
        let db = try LibraryDatabase(url: databaseURL)
        try db.removeFolder(id: id)
    }

    /// Incremental removal of a clip.
    public func removeClip(id: UUID) throws {
        let db = try LibraryDatabase(url: databaseURL)
        try db.removeClip(id: id)
    }

    public func restoreBackup() throws -> LibraryManifest {
        // 1. Attempt restore from SQLite backup if available and intact
        if FileManager.default.fileExists(atPath: databaseBackupURL.path) {
            if let testDb = try? LibraryDatabase(url: databaseBackupURL), testDb.checkIntegrity() {
                testDb.close()
                if FileManager.default.fileExists(atPath: databaseURL.path) {
                    try? FileManager.default.removeItem(at: databaseURL)
                }
                try FileManager.default.copyItem(at: databaseBackupURL, to: databaseURL)
                let db = try LibraryDatabase(url: databaseURL)
                let manifest = try db.loadManifest()
                // Synchronize JSON
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                if let data = try? encoder.encode(manifest) {
                    try? data.write(to: manifestURL, options: .atomic)
                }
                return manifest
            }
        }

        // 2. Fall back to JSON backup
        guard FileManager.default.fileExists(atPath: backupURL.path) else { throw LibraryError.noBackup }
        let data = try Data(contentsOf: backupURL)
        let manifest = try JSONDecoder().decode(LibraryManifest.self, from: data)
        guard manifest.version == 1 else { throw LibraryError.unsupportedVersion }
        try save(manifest)
        return manifest
    }

    public func cleanWorkingDirectories() {
        if FileManager.default.fileExists(atPath: workingDirectory.path) {
            try? FileManager.default.removeItem(at: workingDirectory)
        }
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    }

    public func pruneThumbnails(keeping activeNames: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: thumbnailDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            if !activeNames.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    public enum LibraryError: LocalizedError {
        case unsupportedVersion
        case noBackup
        case corrupted
        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion:
                return "Versi indeks ini belum didukung. Gunakan versi Carfo yang membuat indeks tersebut."
            case .noBackup:
                return "Tidak ada berkas backup indeks yang tersedia."
            case .corrupted:
                return "Berkas indeks rusak atau gagal dalam pemeriksaan integritas."
            }
        }
    }
}

public enum SegmentPlanner {
    public static func segments(duration: Double, length: Double = 12) -> [VideoSegment] {
        guard duration.isFinite, duration > 0, length.isFinite, length > 0 else { return [] }
        return stride(from: 0.0, to: duration, by: length).map { VideoSegment(start: $0, end: min(duration, $0 + length)) }
    }
    public static func sampleTimes(in segment: VideoSegment, count: Int = 3) -> [Double] {
        guard count > 0, segment.end > segment.start else { return [] }
        let step = (segment.end - segment.start) / Double(count)
        return (0..<count).map { segment.start + (Double($0) + 0.5) * step }
    }
}

public func timecode(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "00:00" }
    let total = max(0, Int(seconds))
    if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) }
    return String(format: "%02d:%02d", total / 60, total % 60)
}
