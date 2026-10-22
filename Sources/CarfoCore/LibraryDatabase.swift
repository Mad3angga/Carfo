import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum DatabaseError: LocalizedError {
    case connectionFailed(String)
    case executionFailed(String)
    case corrupted
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Gagal membuka database SQLite: \(msg)"
        case .executionFailed(let msg): return "Operasi SQLite gagal: \(msg)"
        case .corrupted: return "Database SQLite mengalami kerusakan integritas."
        case .unsupportedVersion(let v): return "Versi skema database \(v) tidak didukung."
        }
    }
}

public final class LibraryDatabase: @unchecked Sendable {
    public let url: URL
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private var transactionDepth = 0

    public init(url: URL) throws {
        self.url = url
        try openDatabase()
        try createTables()
    }

    deinit {
        close()
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    private func openDatabase() throws {
        let path = url.path
        var dbPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        if sqlite3_open_v2(path, &dbPointer, flags, nil) != SQLITE_OK {
            let msg = dbPointer != nil ? String(cString: sqlite3_errmsg(dbPointer)) : "Unknown"
            if let dbPointer { sqlite3_close(dbPointer) }
            throw DatabaseError.connectionFailed(msg)
        }
        self.db = dbPointer

        // Configure WAL mode and normal sync for concurrency and speed
        _ = execute("PRAGMA journal_mode = WAL;")
        _ = execute("PRAGMA synchronous = NORMAL;")
        _ = execute("PRAGMA foreign_keys = ON;")
    }

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        guard let db else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func createTables() throws {
        let schema = """
        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS folders (
            id TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            bookmark BLOB,
            scanned_at REAL
        );

        CREATE TABLE IF NOT EXISTS clips (
            id TEXT PRIMARY KEY,
            folder_id TEXT NOT NULL,
            path TEXT NOT NULL,
            relative_path TEXT,
            file_size INTEGER NOT NULL,
            modified_at REAL NOT NULL,
            duration REAL NOT NULL,
            width INTEGER NOT NULL,
            height INTEGER NOT NULL,
            frame_rate REAL NOT NULL,
            has_audio INTEGER NOT NULL,
            thumbnail TEXT,
            indexed_at REAL,
            index_error TEXT,
            transcribed_at REAL,
            transcript_error TEXT,
            media_type TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS segments (
            id TEXT PRIMARY KEY,
            clip_id TEXT NOT NULL,
            start_time REAL NOT NULL,
            end_time REAL NOT NULL,
            visual_embedding BLOB,
            audio_embedding BLOB,
            transcript TEXT
        );

        CREATE TABLE IF NOT EXISTS segment_cues (
            id TEXT PRIMARY KEY,
            segment_id TEXT NOT NULL,
            start_time REAL NOT NULL,
            end_time REAL NOT NULL,
            text TEXT NOT NULL,
            speaker TEXT,
            embedding BLOB
        );

        CREATE TABLE IF NOT EXISTS clip_transcripts (
            id TEXT PRIMARY KEY,
            clip_id TEXT NOT NULL,
            start_time REAL NOT NULL,
            end_time REAL NOT NULL,
            text TEXT NOT NULL,
            speaker TEXT,
            embedding BLOB
        );

        CREATE INDEX IF NOT EXISTS idx_segments_clip ON segments(clip_id);
        CREATE INDEX IF NOT EXISTS idx_segment_cues_seg ON segment_cues(segment_id);
        CREATE INDEX IF NOT EXISTS idx_clip_transcripts_clip ON clip_transcripts(clip_id);
        """

        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw DatabaseError.connectionFailed("Database tidak terbuka") }
        if sqlite3_exec(db, schema, nil, nil, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("Gagal membuat skema: \(msg)")
        }
    }

    public func checkIntegrity() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return false }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA integrity_check;", -1, &stmt, nil) != SQLITE_OK {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            if let textPtr = sqlite3_column_text(stmt, 0) {
                let text = String(cString: textPtr)
                return text == "ok"
            }
        }
        return false
    }

    public func transaction<T>(_ block: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw DatabaseError.connectionFailed("Database tidak terbuka") }

        let isOuter = (transactionDepth == 0)
        let savepointName = "sp_\(transactionDepth)"
        transactionDepth += 1

        if isOuter {
            if sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) != SQLITE_OK {
                transactionDepth -= 1
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.executionFailed("Gagal memulai transaksi: \(msg)")
            }
        } else {
            if sqlite3_exec(db, "SAVEPOINT \(savepointName);", nil, nil, nil) != SQLITE_OK {
                transactionDepth -= 1
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.executionFailed("Gagal membuat savepoint: \(msg)")
            }
        }

        do {
            let result = try block()
            transactionDepth -= 1
            if isOuter {
                if sqlite3_exec(db, "COMMIT;", nil, nil, nil) != SQLITE_OK {
                    let msg = String(cString: sqlite3_errmsg(db))
                    throw DatabaseError.executionFailed("Gagal commit transaksi: \(msg)")
                }
            } else {
                _ = sqlite3_exec(db, "RELEASE SAVEPOINT \(savepointName);", nil, nil, nil)
            }
            return result
        } catch {
            transactionDepth -= 1
            if isOuter {
                _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            } else {
                _ = sqlite3_exec(db, "ROLLBACK TO SAVEPOINT \(savepointName);", nil, nil, nil)
            }
            throw error
        }
    }

    // MARK: - Embedding Binary Serialization

    public static func serializeEmbedding(_ floats: [Float]?) -> Data? {
        guard let floats, !floats.isEmpty else { return nil }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func deserializeEmbedding(_ data: Data?) -> [Float]? {
        guard let data, data.count >= MemoryLayout<Float>.size, data.count % MemoryLayout<Float>.size == 0 else { return nil }
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }

    // MARK: - Incremental Save Methods

    public func saveClip(_ clip: FootageClip) throws {
        try transaction {
            try internalSaveClip(clip)
        }
    }

    public func saveClips(_ clips: [FootageClip]) throws {
        try transaction {
            for clip in clips {
                try internalSaveClip(clip)
            }
        }
    }

    public func saveSegment(clipID: UUID, segment: VideoSegment) throws {
        try transaction {
            guard let db else { throw DatabaseError.connectionFailed("Database tidak terbuka") }

            // Delete old segment_cues for this segment
            var delStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM segment_cues WHERE segment_id = ?;", -1, &delStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(delStmt, 1, segment.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(delStmt)
                sqlite3_finalize(delStmt)
            }

            // Insert or replace segment
            var segStmt: OpaquePointer?
            let segSql = """
            INSERT OR REPLACE INTO segments (id, clip_id, start_time, end_time, visual_embedding, audio_embedding, transcript)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            if sqlite3_prepare_v2(db, segSql, -1, &segStmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(segStmt) }
                sqlite3_bind_text(segStmt, 1, segment.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(segStmt, 2, clipID.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(segStmt, 3, segment.start)
                sqlite3_bind_double(segStmt, 4, segment.end)

                if let vData = Self.serializeEmbedding(segment.visualEmbedding) {
                    vData.withUnsafeBytes { buf in
                        sqlite3_bind_blob(segStmt, 5, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
                    }
                } else {
                    sqlite3_bind_null(segStmt, 5)
                }

                if let aData = Self.serializeEmbedding(segment.audioEmbedding) {
                    aData.withUnsafeBytes { buf in
                        sqlite3_bind_blob(segStmt, 6, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
                    }
                } else {
                    sqlite3_bind_null(segStmt, 6)
                }

                if let tr = segment.transcript {
                    sqlite3_bind_text(segStmt, 7, tr, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(segStmt, 7)
                }

                if sqlite3_step(segStmt) != SQLITE_DONE {
                    let msg = String(cString: sqlite3_errmsg(db))
                    throw DatabaseError.executionFailed("Gagal menyimpan segmen: \(msg)")
                }
            }

            // Insert segment cues
            try insertSegmentCues(segment.cues, segmentID: segment.id)
        }
    }

    public func removeClip(id: UUID) throws {
        try transaction {
            guard let db else { throw DatabaseError.connectionFailed("Database tidak terbuka") }

            // Delete cues and transcripts
            _ = executeWithID("DELETE FROM clip_transcripts WHERE clip_id = ?;", id: id)

            // Delete cues belonging to segments of this clip
            let subSql = "DELETE FROM segment_cues WHERE segment_id IN (SELECT id FROM segments WHERE clip_id = ?);"
            _ = executeWithID(subSql, id: id)

            // Delete segments
            _ = executeWithID("DELETE FROM segments WHERE clip_id = ?;", id: id)

            // Delete clip
            _ = executeWithID("DELETE FROM clips WHERE id = ?;", id: id)
        }
    }

    public func saveFolder(_ folder: FootageFolder) throws {
        try transaction {
            guard let db else { throw DatabaseError.connectionFailed("Database tidak terbuka") }
            var stmt: OpaquePointer?
            let sql = "INSERT OR REPLACE INTO folders (id, path, bookmark, scanned_at) VALUES (?, ?, ?, ?);"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, folder.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, folder.path, -1, SQLITE_TRANSIENT)
                if let bm = folder.bookmark {
                    bm.withUnsafeBytes { buf in
                        sqlite3_bind_blob(stmt, 3, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
                    }
                } else {
                    sqlite3_bind_null(stmt, 3)
                }
                if let scan = folder.scannedAt {
                    sqlite3_bind_double(stmt, 4, scan.timeIntervalSinceReferenceDate)
                } else {
                    sqlite3_bind_null(stmt, 4)
                }
                if sqlite3_step(stmt) != SQLITE_DONE {
                    let msg = String(cString: sqlite3_errmsg(db))
                    throw DatabaseError.executionFailed("Gagal menyimpan folder: \(msg)")
                }
            }
        }
    }

    public func removeFolder(id: UUID) throws {
        try transaction {
            guard let db else { throw DatabaseError.connectionFailed("Database tidak terbuka") }
            var stmt: OpaquePointer?
            var clipIDs: [UUID] = []
            if sqlite3_prepare_v2(db, "SELECT id FROM clips WHERE folder_id = ?;", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let ptr = sqlite3_column_text(stmt, 0), let u = UUID(uuidString: String(cString: ptr)) {
                        clipIDs.append(u)
                    }
                }
                sqlite3_finalize(stmt)
            }
            for cid in clipIDs {
                _ = executeWithID("DELETE FROM clip_transcripts WHERE clip_id = ?;", id: cid)
                _ = executeWithID("DELETE FROM segment_cues WHERE segment_id IN (SELECT id FROM segments WHERE clip_id = ?);", id: cid)
                _ = executeWithID("DELETE FROM segments WHERE clip_id = ?;", id: cid)
                _ = executeWithID("DELETE FROM clips WHERE id = ?;", id: cid)
            }
            _ = executeWithID("DELETE FROM folders WHERE id = ?;", id: id)
        }
    }

    // MARK: - Full Manifest Save & Load

    public func saveManifest(_ manifest: LibraryManifest) throws {
        try transaction {
            guard let db else { throw DatabaseError.connectionFailed("Database tidak terbuka") }

            // 1. Metadata
            var metaStmt: OpaquePointer?
            let metaSql = "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?);"
            if sqlite3_prepare_v2(db, metaSql, -1, &metaStmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(metaStmt) }

                func bindMeta(_ key: String, _ value: String) {
                    sqlite3_reset(metaStmt)
                    sqlite3_bind_text(metaStmt, 1, key, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(metaStmt, 2, value, -1, SQLITE_TRANSIENT)
                    sqlite3_step(metaStmt)
                }

                bindMeta("version", String(manifest.version))
                bindMeta("model", manifest.model)
                if let rev = manifest.modelRevision { bindMeta("modelRevision", rev) }
            }

            // 2. Folders
            let currentFolderIDs = Set(manifest.folders.map(\.id.uuidString))
            var existingFolderIDs: [String] = []
            var folderListStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT id FROM folders;", -1, &folderListStmt, nil) == SQLITE_OK {
                while sqlite3_step(folderListStmt) == SQLITE_ROW {
                    if let ptr = sqlite3_column_text(folderListStmt, 0) { existingFolderIDs.append(String(cString: ptr)) }
                }
                sqlite3_finalize(folderListStmt)
            }
            for fid in existingFolderIDs where !currentFolderIDs.contains(fid) {
                if let u = UUID(uuidString: fid) { try? removeFolder(id: u) }
            }
            for folder in manifest.folders {
                var fStmt: OpaquePointer?
                let fSql = "INSERT OR REPLACE INTO folders (id, path, bookmark, scanned_at) VALUES (?, ?, ?, ?);"
                if sqlite3_prepare_v2(db, fSql, -1, &fStmt, nil) == SQLITE_OK {
                    defer { sqlite3_finalize(fStmt) }
                    sqlite3_bind_text(fStmt, 1, folder.id.uuidString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(fStmt, 2, folder.path, -1, SQLITE_TRANSIENT)
                    if let bm = folder.bookmark {
                        bm.withUnsafeBytes { buf in
                            sqlite3_bind_blob(fStmt, 3, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
                        }
                    } else { sqlite3_bind_null(fStmt, 3) }
                    if let sc = folder.scannedAt {
                        sqlite3_bind_double(fStmt, 4, sc.timeIntervalSinceReferenceDate)
                    } else { sqlite3_bind_null(fStmt, 4) }
                    sqlite3_step(fStmt)
                }
            }

            // 3. Clips
            let currentClipIDs = Set(manifest.clips.map(\.id.uuidString))
            var existingClipIDs: [String] = []
            var clipListStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT id FROM clips;", -1, &clipListStmt, nil) == SQLITE_OK {
                while sqlite3_step(clipListStmt) == SQLITE_ROW {
                    if let ptr = sqlite3_column_text(clipListStmt, 0) { existingClipIDs.append(String(cString: ptr)) }
                }
                sqlite3_finalize(clipListStmt)
            }
            for cid in existingClipIDs where !currentClipIDs.contains(cid) {
                if let u = UUID(uuidString: cid) { try? removeClip(id: u) }
            }

            for clip in manifest.clips {
                try internalSaveClip(clip)
            }
        }
    }

    public func loadManifest() throws -> LibraryManifest {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw DatabaseError.connectionFailed("Database tidak terbuka") }

        var manifest = LibraryManifest()

        // 1. Metadata
        var metaStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT key, value FROM metadata;", -1, &metaStmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(metaStmt) }
            while sqlite3_step(metaStmt) == SQLITE_ROW {
                guard let kPtr = sqlite3_column_text(metaStmt, 0), let vPtr = sqlite3_column_text(metaStmt, 1) else { continue }
                let key = String(cString: kPtr)
                let val = String(cString: vPtr)
                switch key {
                case "version":
                    let v = Int(val) ?? 1
                    guard v == 1 else { throw DatabaseError.unsupportedVersion(v) }
                    manifest.version = v
                case "model":
                    manifest.model = val
                case "modelRevision":
                    manifest.modelRevision = val
                default: break
                }
            }
        }

        // 2. Folders
        var folderStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id, path, bookmark, scanned_at FROM folders;", -1, &folderStmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(folderStmt) }
            while sqlite3_step(folderStmt) == SQLITE_ROW {
                guard let idPtr = sqlite3_column_text(folderStmt, 0), let u = UUID(uuidString: String(cString: idPtr)),
                      let pPtr = sqlite3_column_text(folderStmt, 1) else { continue }
                let path = String(cString: pPtr)
                var bookmark: Data?
                if sqlite3_column_type(folderStmt, 2) != SQLITE_NULL, let bPtr = sqlite3_column_blob(folderStmt, 2) {
                    let len = sqlite3_column_bytes(folderStmt, 2)
                    bookmark = Data(bytes: bPtr, count: Int(len))
                }
                var scannedAt: Date?
                if sqlite3_column_type(folderStmt, 3) != SQLITE_NULL {
                    scannedAt = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(folderStmt, 3))
                }
                manifest.folders.append(FootageFolder(id: u, path: path, bookmark: bookmark, scannedAt: scannedAt))
            }
        }

        // 3. Segment Cues (grouped by segment_id)
        var segmentCuesMap: [UUID: [TranscriptCue]] = [:]
        var segCueStmt: OpaquePointer?
        let segCueSql = "SELECT id, segment_id, start_time, end_time, text, speaker, embedding FROM segment_cues ORDER BY start_time ASC;"
        if sqlite3_prepare_v2(db, segCueSql, -1, &segCueStmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(segCueStmt) }
            while sqlite3_step(segCueStmt) == SQLITE_ROW {
                guard let idPtr = sqlite3_column_text(segCueStmt, 0), let id = UUID(uuidString: String(cString: idPtr)),
                      let segIdPtr = sqlite3_column_text(segCueStmt, 1), let segId = UUID(uuidString: String(cString: segIdPtr)),
                      let textPtr = sqlite3_column_text(segCueStmt, 4) else { continue }
                let start = sqlite3_column_double(segCueStmt, 2)
                let end = sqlite3_column_double(segCueStmt, 3)
                let text = String(cString: textPtr)
                var speaker: String?
                if sqlite3_column_type(segCueStmt, 5) != SQLITE_NULL, let spkPtr = sqlite3_column_text(segCueStmt, 5) {
                    speaker = String(cString: spkPtr)
                }
                var emb: [Float]?
                if sqlite3_column_type(segCueStmt, 6) != SQLITE_NULL, let embPtr = sqlite3_column_blob(segCueStmt, 6) {
                    let len = sqlite3_column_bytes(segCueStmt, 6)
                    emb = Self.deserializeEmbedding(Data(bytes: embPtr, count: Int(len)))
                }
                let cue = TranscriptCue(id: id, start: start, end: end, text: text, speaker: speaker, embedding: emb)
                segmentCuesMap[segId, default: []].append(cue)
            }
        }

        // 4. Segments (grouped by clip_id)
        var clipSegmentsMap: [UUID: [VideoSegment]] = [:]
        var segStmt: OpaquePointer?
        let segSql = "SELECT id, clip_id, start_time, end_time, visual_embedding, audio_embedding, transcript FROM segments ORDER BY start_time ASC;"
        if sqlite3_prepare_v2(db, segSql, -1, &segStmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(segStmt) }
            while sqlite3_step(segStmt) == SQLITE_ROW {
                guard let idPtr = sqlite3_column_text(segStmt, 0), let segID = UUID(uuidString: String(cString: idPtr)),
                      let clipIdPtr = sqlite3_column_text(segStmt, 1), let clipID = UUID(uuidString: String(cString: clipIdPtr)) else { continue }
                let start = sqlite3_column_double(segStmt, 2)
                let end = sqlite3_column_double(segStmt, 3)

                var visual: [Float]?
                if sqlite3_column_type(segStmt, 4) != SQLITE_NULL, let vPtr = sqlite3_column_blob(segStmt, 4) {
                    let len = sqlite3_column_bytes(segStmt, 4)
                    visual = Self.deserializeEmbedding(Data(bytes: vPtr, count: Int(len)))
                }

                var audio: [Float]?
                if sqlite3_column_type(segStmt, 5) != SQLITE_NULL, let aPtr = sqlite3_column_blob(segStmt, 5) {
                    let len = sqlite3_column_bytes(segStmt, 5)
                    audio = Self.deserializeEmbedding(Data(bytes: aPtr, count: Int(len)))
                }

                var transcript: String?
                if sqlite3_column_type(segStmt, 6) != SQLITE_NULL, let trPtr = sqlite3_column_text(segStmt, 6) {
                    transcript = String(cString: trPtr)
                }

                let cues = segmentCuesMap[segID] ?? []
                let segment = VideoSegment(id: segID, start: start, end: end, visualEmbedding: visual, audioEmbedding: audio, transcript: transcript, cues: cues)
                clipSegmentsMap[clipID, default: []].append(segment)
            }
        }

        // 5. Clip Transcripts (grouped by clip_id)
        var clipTranscriptsMap: [UUID: [TranscriptCue]] = [:]
        var trStmt: OpaquePointer?
        let trSql = "SELECT id, clip_id, start_time, end_time, text, speaker, embedding FROM clip_transcripts ORDER BY start_time ASC;"
        if sqlite3_prepare_v2(db, trSql, -1, &trStmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(trStmt) }
            while sqlite3_step(trStmt) == SQLITE_ROW {
                guard let idPtr = sqlite3_column_text(trStmt, 0), let id = UUID(uuidString: String(cString: idPtr)),
                      let clipIdPtr = sqlite3_column_text(trStmt, 1), let clipID = UUID(uuidString: String(cString: clipIdPtr)),
                      let textPtr = sqlite3_column_text(trStmt, 4) else { continue }
                let start = sqlite3_column_double(trStmt, 2)
                let end = sqlite3_column_double(trStmt, 3)
                let text = String(cString: textPtr)
                var speaker: String?
                if sqlite3_column_type(trStmt, 5) != SQLITE_NULL, let spkPtr = sqlite3_column_text(trStmt, 5) {
                    speaker = String(cString: spkPtr)
                }
                var emb: [Float]?
                if sqlite3_column_type(trStmt, 6) != SQLITE_NULL, let embPtr = sqlite3_column_blob(trStmt, 6) {
                    let len = sqlite3_column_bytes(trStmt, 6)
                    emb = Self.deserializeEmbedding(Data(bytes: embPtr, count: Int(len)))
                }
                let cue = TranscriptCue(id: id, start: start, end: end, text: text, speaker: speaker, embedding: emb)
                clipTranscriptsMap[clipID, default: []].append(cue)
            }
        }

        // 6. Clips
        var clipStmt: OpaquePointer?
        let clipSql = """
        SELECT id, folder_id, path, relative_path, file_size, modified_at, duration, width, height, frame_rate,
               has_audio, thumbnail, indexed_at, index_error, transcribed_at, transcript_error, media_type
        FROM clips ORDER BY path ASC;
        """
        if sqlite3_prepare_v2(db, clipSql, -1, &clipStmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(clipStmt) }
            while sqlite3_step(clipStmt) == SQLITE_ROW {
                guard let idPtr = sqlite3_column_text(clipStmt, 0), let id = UUID(uuidString: String(cString: idPtr)),
                      let fIdPtr = sqlite3_column_text(clipStmt, 1), let folderID = UUID(uuidString: String(cString: fIdPtr)),
                      let pathPtr = sqlite3_column_text(clipStmt, 2) else { continue }
                let path = String(cString: pathPtr)
                var relPath = ""
                if sqlite3_column_type(clipStmt, 3) != SQLITE_NULL, let rPtr = sqlite3_column_text(clipStmt, 3) {
                    relPath = String(cString: rPtr)
                }
                let fileSize = sqlite3_column_int64(clipStmt, 4)
                let modifiedAt = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(clipStmt, 5))
                let duration = sqlite3_column_double(clipStmt, 6)
                let width = Int(sqlite3_column_int64(clipStmt, 7))
                let height = Int(sqlite3_column_int64(clipStmt, 8))
                let frameRate = sqlite3_column_double(clipStmt, 9)
                let hasAudio = sqlite3_column_int64(clipStmt, 10) != 0

                var thumb: String?
                if sqlite3_column_type(clipStmt, 11) != SQLITE_NULL, let tPtr = sqlite3_column_text(clipStmt, 11) {
                    thumb = String(cString: tPtr)
                }

                var indexedAt: Date?
                if sqlite3_column_type(clipStmt, 12) != SQLITE_NULL {
                    indexedAt = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(clipStmt, 12))
                }

                var indexError: String?
                if sqlite3_column_type(clipStmt, 13) != SQLITE_NULL, let ePtr = sqlite3_column_text(clipStmt, 13) {
                    indexError = String(cString: ePtr)
                }

                var transcribedAt: Date?
                if sqlite3_column_type(clipStmt, 14) != SQLITE_NULL {
                    transcribedAt = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(clipStmt, 14))
                }

                var transcriptError: String?
                if sqlite3_column_type(clipStmt, 15) != SQLITE_NULL, let tePtr = sqlite3_column_text(clipStmt, 15) {
                    transcriptError = String(cString: tePtr)
                }

                var mediaType: MediaType = .video
                if sqlite3_column_type(clipStmt, 16) != SQLITE_NULL, let mPtr = sqlite3_column_text(clipStmt, 16) {
                    mediaType = MediaType(rawValue: String(cString: mPtr)) ?? .video
                }

                let segments = clipSegmentsMap[id] ?? []
                let transcripts = clipTranscriptsMap[id] ?? []

                let clip = FootageClip(
                    id: id,
                    folderID: folderID,
                    path: path,
                    relativePath: relPath,
                    fileSize: fileSize,
                    modifiedAt: modifiedAt,
                    duration: duration,
                    width: width,
                    height: height,
                    frameRate: frameRate,
                    hasAudio: hasAudio,
                    thumbnail: thumb,
                    segments: segments,
                    indexedAt: indexedAt,
                    indexError: indexError,
                    transcripts: transcripts,
                    transcribedAt: transcribedAt,
                    transcriptError: transcriptError,
                    mediaType: mediaType
                )
                manifest.clips.append(clip)
            }
        }

        return manifest
    }

    public func createBackup(to destination: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw DatabaseError.connectionFailed("Database tidak terbuka") }

        sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_FULL, nil, nil)

        var destDb: OpaquePointer?
        if sqlite3_open_v2(destination.path, &destDb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) != SQLITE_OK {
            let msg = destDb != nil ? String(cString: sqlite3_errmsg(destDb)) : "Unknown"
            if let destDb { sqlite3_close(destDb) }
            throw DatabaseError.executionFailed("Gagal membuka destination backup: \(msg)")
        }
        defer { sqlite3_close(destDb) }

        guard let backup = sqlite3_backup_init(destDb, "main", db, "main") else {
            let msg = String(cString: sqlite3_errmsg(destDb))
            throw DatabaseError.executionFailed("Gagal inisialisasi backup SQLite: \(msg)")
        }

        let step = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        if step != SQLITE_DONE {
            throw DatabaseError.executionFailed("Backup SQLite belum selesai sempurna.")
        }
    }

    // MARK: - Internal Helpers

    private func internalSaveClip(_ clip: FootageClip) throws {
        guard let db else { throw DatabaseError.connectionFailed("Database tidak terbuka") }

        var clipStmt: OpaquePointer?
        let clipSql = """
        INSERT OR REPLACE INTO clips (id, folder_id, path, relative_path, file_size, modified_at, duration, width, height, frame_rate,
                                     has_audio, thumbnail, indexed_at, index_error, transcribed_at, transcript_error, media_type)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        if sqlite3_prepare_v2(db, clipSql, -1, &clipStmt, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("Prepare clips statement failed: \(msg)")
        }
        defer { sqlite3_finalize(clipStmt) }

        sqlite3_bind_text(clipStmt, 1, clip.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(clipStmt, 2, clip.folderID.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(clipStmt, 3, clip.path, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(clipStmt, 4, clip.relativePath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(clipStmt, 5, clip.fileSize)
        sqlite3_bind_double(clipStmt, 6, clip.modifiedAt.timeIntervalSinceReferenceDate)
        sqlite3_bind_double(clipStmt, 7, clip.duration)
        sqlite3_bind_int64(clipStmt, 8, Int64(clip.width))
        sqlite3_bind_int64(clipStmt, 9, Int64(clip.height))
        sqlite3_bind_double(clipStmt, 10, clip.frameRate)
        sqlite3_bind_int64(clipStmt, 11, clip.hasAudio ? 1 : 0)

        if let thumb = clip.thumbnail {
            sqlite3_bind_text(clipStmt, 12, thumb, -1, SQLITE_TRANSIENT)
        } else { sqlite3_bind_null(clipStmt, 12) }

        if let idx = clip.indexedAt {
            sqlite3_bind_double(clipStmt, 13, idx.timeIntervalSinceReferenceDate)
        } else { sqlite3_bind_null(clipStmt, 13) }

        if let err = clip.indexError {
            sqlite3_bind_text(clipStmt, 14, err, -1, SQLITE_TRANSIENT)
        } else { sqlite3_bind_null(clipStmt, 14) }

        if let trAt = clip.transcribedAt {
            sqlite3_bind_double(clipStmt, 15, trAt.timeIntervalSinceReferenceDate)
        } else { sqlite3_bind_null(clipStmt, 15) }

        if let trErr = clip.transcriptError {
            sqlite3_bind_text(clipStmt, 16, trErr, -1, SQLITE_TRANSIENT)
        } else { sqlite3_bind_null(clipStmt, 16) }

        sqlite3_bind_text(clipStmt, 17, clip.mediaType.rawValue, -1, SQLITE_TRANSIENT)

        if sqlite3_step(clipStmt) != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("Gagal menyimpan clip: \(msg)")
        }

        // Delete previous segments and segment_cues for this clip
        _ = executeWithID("DELETE FROM segment_cues WHERE segment_id IN (SELECT id FROM segments WHERE clip_id = ?);", id: clip.id)
        _ = executeWithID("DELETE FROM segments WHERE clip_id = ?;", id: clip.id)

        // Insert segments
        var segStmt: OpaquePointer?
        let segSql = "INSERT INTO segments (id, clip_id, start_time, end_time, visual_embedding, audio_embedding, transcript) VALUES (?, ?, ?, ?, ?, ?, ?);"
        if sqlite3_prepare_v2(db, segSql, -1, &segStmt, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("Prepare segments statement failed: \(msg)")
        }
        defer { sqlite3_finalize(segStmt) }

        for seg in clip.segments {
            sqlite3_reset(segStmt)
            sqlite3_bind_text(segStmt, 1, seg.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(segStmt, 2, clip.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(segStmt, 3, seg.start)
            sqlite3_bind_double(segStmt, 4, seg.end)

            if let vData = Self.serializeEmbedding(seg.visualEmbedding) {
                vData.withUnsafeBytes { buf in
                    sqlite3_bind_blob(segStmt, 5, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
                }
            } else { sqlite3_bind_null(segStmt, 5) }

            if let aData = Self.serializeEmbedding(seg.audioEmbedding) {
                aData.withUnsafeBytes { buf in
                    sqlite3_bind_blob(segStmt, 6, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
                }
            } else { sqlite3_bind_null(segStmt, 6) }

            if let tr = seg.transcript {
                sqlite3_bind_text(segStmt, 7, tr, -1, SQLITE_TRANSIENT)
            } else { sqlite3_bind_null(segStmt, 7) }

            if sqlite3_step(segStmt) != SQLITE_DONE {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.executionFailed("Gagal menyimpan segmen: \(msg)")
            }

            try insertSegmentCues(seg.cues, segmentID: seg.id)
        }

        // Delete previous transcripts for this clip
        _ = executeWithID("DELETE FROM clip_transcripts WHERE clip_id = ?;", id: clip.id)

        // Insert clip transcripts
        var trStmt: OpaquePointer?
        let trSql = "INSERT INTO clip_transcripts (id, clip_id, start_time, end_time, text, speaker, embedding) VALUES (?, ?, ?, ?, ?, ?, ?);"
        if sqlite3_prepare_v2(db, trSql, -1, &trStmt, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("Prepare transcripts statement failed: \(msg)")
        }
        defer { sqlite3_finalize(trStmt) }

        for cue in clip.transcripts {
            sqlite3_reset(trStmt)
            sqlite3_bind_text(trStmt, 1, cue.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(trStmt, 2, clip.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(trStmt, 3, cue.start)
            sqlite3_bind_double(trStmt, 4, cue.end)
            sqlite3_bind_text(trStmt, 5, cue.text, -1, SQLITE_TRANSIENT)
            if let spk = cue.speaker {
                sqlite3_bind_text(trStmt, 6, spk, -1, SQLITE_TRANSIENT)
            } else { sqlite3_bind_null(trStmt, 6) }

            if let embData = Self.serializeEmbedding(cue.embedding) {
                embData.withUnsafeBytes { buf in
                    sqlite3_bind_blob(trStmt, 7, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
                }
            } else { sqlite3_bind_null(trStmt, 7) }

            if sqlite3_step(trStmt) != SQLITE_DONE {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.executionFailed("Gagal menyimpan transcript: \(msg)")
            }
        }
    }

    private func insertSegmentCues(_ cues: [TranscriptCue], segmentID: UUID) throws {
        guard !cues.isEmpty, let db else { return }
        var cueStmt: OpaquePointer?
        let cueSql = "INSERT INTO segment_cues (id, segment_id, start_time, end_time, text, speaker, embedding) VALUES (?, ?, ?, ?, ?, ?, ?);"
        if sqlite3_prepare_v2(db, cueSql, -1, &cueStmt, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("Prepare segment cues statement failed: \(msg)")
        }
        defer { sqlite3_finalize(cueStmt) }

        for cue in cues {
            sqlite3_reset(cueStmt)
            sqlite3_bind_text(cueStmt, 1, cue.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(cueStmt, 2, segmentID.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(cueStmt, 3, cue.start)
            sqlite3_bind_double(cueStmt, 4, cue.end)
            sqlite3_bind_text(cueStmt, 5, cue.text, -1, SQLITE_TRANSIENT)
            if let spk = cue.speaker {
                sqlite3_bind_text(cueStmt, 6, spk, -1, SQLITE_TRANSIENT)
            } else { sqlite3_bind_null(cueStmt, 6) }

            if let embData = Self.serializeEmbedding(cue.embedding) {
                embData.withUnsafeBytes { buf in
                    sqlite3_bind_blob(cueStmt, 7, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
                }
            } else { sqlite3_bind_null(cueStmt, 7) }

            if sqlite3_step(cueStmt) != SQLITE_DONE {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.executionFailed("Gagal menyimpan segment cue: \(msg)")
            }
        }
    }

    private func executeWithID(_ sql: String, id: UUID) -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            return sqlite3_step(stmt) == SQLITE_DONE
        }
        return false
    }
}
