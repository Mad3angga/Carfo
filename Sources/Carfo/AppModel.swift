import AppKit
import AVKit
import Combine
import CarfoCore
import ServiceManagement
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var title: String { switch self { case .light: return "Terang"; case .dark: return "Gelap"; case .system: return "Sistem" } }
    var symbol: String { switch self { case .light: return "sun.max"; case .dark: return "moon"; case .system: return "display" } }
    var colorScheme: ColorScheme? { switch self { case .light: return .light; case .dark: return .dark; case .system: return nil } }
    var nsAppearance: NSAppearance? { switch self { case .light: return NSAppearance(named: .aqua); case .dark: return NSAppearance(named: .darkAqua); case .system: return nil } }
}

enum SearchShortcut: String, CaseIterable, Identifiable {
    case optionSpace, controlOptionSpace, controlSpace
    var id: String { rawValue }
    var label: String { switch self { case .optionSpace: return "⌥ Spasi"; case .controlOptionSpace: return "⌃ ⌥ Spasi"; case .controlSpace: return "⌃ Spasi" } }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case indonesian = "id"
    case englishUS = "en"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .indonesian: return "Bahasa Indonesia"
        case .englishUS: return "English (US)"
        }
    }
    var symbol: String {
        switch self {
        case .indonesian: return "globe.asia.australia.fill"
        case .englishUS: return "globe.americas.fill"
        }
    }
}

struct WorkProgress {
    var title: String
    var detail: String
    var completed: Int = 0
    var total: Int = 0
    var fraction: Double? { total > 0 ? Double(completed) / Double(total) : nil }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var library: LibraryManifest {
        didSet {
            if mergingClips {
                // Scan batches update their ID map and counts together before publishing.
            } else if let index = mutatingClipIndex {
                stats.replace(oldValue.clips[index], with: library.clips[index])
            } else {
                stats = LibraryStats(library.clips)
                clipPositions = Dictionary(library.clips.indices.map { (library.clips[$0].id, $0) }, uniquingKeysWith: { first, _ in first })
            }
        }
    }
    private(set) var stats = LibraryStats()
    private var mutatingClipIndex: Int?
    private var mergingClips = false
    private var clipPositions: [UUID: Int] = [:]
    @Published private(set) var isLoading = true
    private var startupTask: Task<Void, Never>?
    private let startupBegan = ContinuousClock.now
    private(set) var startupTimings: [String: Double] = [:]
    func recordStartupStage(_ stage: String) {
        guard startupTimings[stage] == nil else { return }
        let duration = startupBegan.duration(to: .now).components
        startupTimings[stage] = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
        let values = startupTimings, destination = store.directory.appendingPathComponent("startup-timings.json")
        saveQueue.async {
            if let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) {
                try? data.write(to: destination, options: .atomic)
            }
        }
    }
    @Published var query = "" { didSet { scheduleSearch() } }
    @Published var mode: SearchMode = .video { didSet { scheduleSearch() } }
    @Published var folderFilter: UUID? { didSet { scheduleSearch() } }
    @Published var results: [SearchResult] = []
    @Published var selectedID: String?
    @Published var isSearching = false
    @Published var semanticSearch = false
    @Published var searchError: String?
    @Published var notice: String?
    @Published var folderAccessError: String?
    @Published var work: WorkProgress?
    @Published var installation: LocalModelInstallation
    @Published var modelVerified = false
    @Published var modelChecking = false
    @Published var modelError: String?
    @Published var recentQueries: [String]
    @Published var isPlaying = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance"); appearanceChanged?() } }
    @Published var shortcut: SearchShortcut { didSet { defaults.set(shortcut.rawValue, forKey: "shortcut"); shortcutChanged?() } }
    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }
    let store: LibraryStore
    let engine: LocalEngine
    let player = AVPlayer()
    let defaults: UserDefaults
    var showSettings: (() -> Void)?
    var showSearch: (() -> Void)?
    var hideSearch: (() -> Void)?
    var appearanceChanged: (() -> Void)?
    var shortcutChanged: (() -> Void)?
    private var searchTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    /// Serial, so snapshots reach disk in order without blocking the UI.
    private let saveQueue = DispatchQueue(label: "id.carfo.library-save", qos: .utility)
    private var accessURLs: [UUID: URL] = [:]
    private var queryCacheOrder: [String] = []
    private var queryCache: [String: [Float]] = [:]
    private var endObserver: NSObjectProtocol?
    private var playbackObserver: NSKeyValueObservation?
    public private(set) var loadFailed: Bool = false
    var isWorking: Bool { isLoading || work != nil }
    var selected: SearchResult? { results.first { $0.id == selectedID } }
    var indexMatchesModel: Bool {
        guard let currentModel = installation.modelIdentifier else { return true }
        guard let savedModel = library.modelRevision else {
            return library.clips.isEmpty || !library.clips.contains { $0.isIndexed }
        }
        return savedModel == currentModel
    }
    var indexedCount: Int { indexMatchesModel ? stats.indexed : 0 }
    var transcribedCount: Int { stats.transcribed }
    var clipsNeedingTranscriptCount: Int { installation.canTranscribe ? stats.needsTranscript : 0 }
    var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Start of an unfinished "Pindai ulang" run. Survives stops and relaunches so pressing the button again resumes the run.
    private var rescanSessionStart: Date? {
        get { defaults.object(forKey: "rescanSessionStart") as? Date }
        set { defaults.set(newValue, forKey: "rescanSessionStart") }
    }
    var hasPendingRescan: Bool { rescanSessionStart != nil }
    var statusText: String {
        if isLoading { return library.clips.isEmpty ? "Membaca metadata koleksi..." : "Menyiapkan indeks pencarian..." }
        if let work { return work.title }
        if library.clips.isEmpty { return "Cari di file lokal" }
        var parts: [String] = []
        if stats.video > 0 { parts.append("\(stats.video) video") }
        if stats.image > 0 { parts.append("\(stats.image) gambar") }
        if stats.audio > 0 { parts.append("\(stats.audio) audio") }
        return parts.isEmpty ? "\(library.clips.count) file di Mac ini" : "\(parts.joined(separator: ", ")) di Mac ini"
    }
    var modelStatus: String {
        if modelChecking { return "Memeriksa Google Embedding..." }
        if modelError != nil { return "Model memerlukan perbaikan" }
        if modelVerified { return "Google Embedding siap (terverifikasi)" }
        return installation.isAvailable ? "Google Embedding ditemukan" : "Google Embedding belum ditemukan"
    }

    init(directory: URL? = nil, installationOverride: LocalModelInstallation? = nil, workerScript: URL? = nil, defaultsOverride: UserDefaults? = nil) throws {
        let environment = ProcessInfo.processInfo.environment
        defaults = defaultsOverride ?? environment["CARFO_DEFAULTS_SUITE"].flatMap(UserDefaults.init(suiteName:))
            ?? environment["FOOTAGE_DEFAULTS_SUITE"].flatMap(UserDefaults.init(suiteName:))
            ?? .standard
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let carfoDir = appSupport.appendingPathComponent("Carfo", isDirectory: true)
        let footageDir = appSupport.appendingPathComponent("Footage", isDirectory: true)
        if directory == nil && !FileManager.default.fileExists(atPath: carfoDir.path) && FileManager.default.fileExists(atPath: footageDir.path) {
            try? FileManager.default.copyItem(at: footageDir, to: carfoDir)
        }
        let root = directory ?? environment["CARFO_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? environment["FOOTAGE_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? carfoDir
        store = try LibraryStore(directory: root)
        library = LibraryManifest()
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "system") ?? .system
        shortcut = SearchShortcut(rawValue: defaults.string(forKey: "shortcut") ?? "optionSpace") ?? .optionSpace
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "id") ?? .indonesian
        recentQueries = defaults.stringArray(forKey: "recentQueries") ?? []
        defaults.removeObject(forKey: "modelPath")
        let detected = installationOverride ?? LocalModelInstallation.discover(pythonOverride: defaults.string(forKey: "pythonPath"))
        installation = detected
        guard let script = workerScript ?? AppResources.bundle.url(forResource: "worker", withExtension: "py", subdirectory: "Engine") else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError,
                          userInfo: [NSLocalizedDescriptionKey: "Komponen pemrosesan Carfo tidak ditemukan. Instal ulang aplikasi Carfo."])
        }
        engine = LocalEngine(installation: detected, script: script, logDirectory: root)
        startupTask = Task { [weak self, store] in
            guard let self else { return }
            defer { self.isLoading = false; self.startupTask = nil }
            do {
                let metadata = try await Task.detached(priority: .userInitiated) {
                    guard FileManager.default.fileExists(atPath: store.databaseURL.path) else { return LibraryManifest() }
                    return try store.database().loadManifest(metadataOnly: true)
                }.value
                try Task.checkCancellation()
                self.library = metadata
                self.scheduleSearch()
                self.recordStartupStage("metadataReadyMS")
                let loaded = try await Task.detached(priority: .userInitiated) { try store.load() }.value
                try Task.checkCancellation()
                self.library = loaded
                self.restoreFolderAccess()
                self.scheduleSearch()
                let active = Set(loaded.clips.compactMap(\.thumbnail))
                await Task.detached(priority: .utility) {
                    store.pruneThumbnails(keeping: active)
                    store.cleanWorkingDirectories()
                }.value
                self.recordStartupStage("indexReadyMS")
            } catch is CancellationError { return }
            catch {
                self.loadFailed = true
                self.notice = "Indeks tidak dapat dibaca: \(error.localizedDescription). Indeks asli tetap disimpan."
            }
        }
        player.actionAtItemEnd = .pause
        playbackObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor in self?.isPlaying = playing }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isPlaying = false }
        }
    }

    private func restoreFolderAccess() {
        for index in library.folders.indices {
            let folder = library.folders[index]
            guard let bookmark = folder.bookmark else { continue }
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                if url.startAccessingSecurityScopedResource() {
                    accessURLs[folder.id]?.stopAccessingSecurityScopedResource()
                    accessURLs[folder.id] = url
                }
                library.folders[index].path = url.path
                if stale { library.folders[index].bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
            }
        }
        if library.folders.contains(where: { !FileManager.default.isReadableFile(atPath: $0.path) }) {
            folderAccessError = "Salah satu folder tidak dapat dibuka. Pilih ulang folder untuk memperbarui aksesnya."
        }
    }
    private var dirtyClipIDs = Set<UUID>()
    private func updateClip(at index: Int, _ edit: (inout FootageClip) -> Void) {
        mutatingClipIndex = index
        defer { mutatingClipIndex = nil }
        edit(&library.clips[index])
    }

    /// Saves now. If dirtyClipIDs are tracked and fewer than all clips, writes only those clips incrementally.
    func persist() {
        guard !loadFailed, !isLoading else { return }
        saveTask?.cancel(); saveTask = nil
        let snapshot = library, store = store
        let positions = clipPositions
        let dirty = dirtyClipIDs
        dirtyClipIDs.removeAll()
        saveQueue.async { [weak self] in
            do {
                if !dirty.isEmpty && dirty.count < snapshot.clips.count {
                    let dirtyClips = dirty.compactMap { id in positions[id].map { snapshot.clips[$0] } }
                    try store.saveClips(dirtyClips)
                } else {
                    try store.save(snapshot)
                }
            }
            catch {
                let message = error.localizedDescription
                Task { @MainActor in self?.notice = "Indeks belum tersimpan: \(message)" }
            }
        }
    }
    /// Coalesces the frequent saves made while scanning and indexing into one write every few seconds.
    func persistSoon(for clipID: UUID? = nil) {
        guard !loadFailed, !isLoading else { return }
        if let clipID { dirtyClipIDs.insert(clipID) }
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }
    /// Writes any pending changes and waits until they are on disk. Used when quitting.
    func flushSaves() {
        guard !loadFailed, !isLoading else { return }
        persist()
        saveQueue.sync {}
    }
    func recoverFromBackup() {
        do {
            library = try store.restoreBackup()
            loadFailed = false
            stats = LibraryStats(library.clips)
            notice = "Indeks berhasil dipulihkan dari backup."
        } catch {
            notice = "Gagal memulihkan backup: \(error.localizedDescription)"
        }
    }
    func resetCorruptedIndex() {
        loadFailed = false
        library = LibraryManifest()
        stats = LibraryStats(library.clips)
        persist()
        notice = "Indeks telah disetel ulang."
    }
    func pickFolder() {
        guard !isWorking else { notice = "Tunggu proses selesai sebelum menambah folder."; return }
        let picker = NSOpenPanel()
        picker.title = "Tambah folder footage"
        picker.prompt = "Tambah folder"
        picker.canChooseDirectories = true; picker.canChooseFiles = false; picker.allowsMultipleSelection = true
        picker.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        picker.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.addFolders(picker.urls) }
        }
    }
    func addFolders(_ urls: [URL]) {
        guard !isWorking else { notice = "Tunggu proses selesai sebelum menambah folder."; return }
        folderAccessError = nil
        for url in urls {
            let standardized = url.standardizedFileURL
            let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            if let index = library.folders.firstIndex(where: { standardized.path == URL(fileURLWithPath: $0.path).standardizedFileURL.path }) {
                library.folders[index].bookmark = bookmark
                if url.startAccessingSecurityScopedResource() {
                    let folderID = library.folders[index].id
                    accessURLs[folderID]?.stopAccessingSecurityScopedResource()
                    accessURLs[folderID] = url
                }
                continue
            }
            let newFolder = CarfoFolder(path: standardized.path, bookmark: bookmark)
            if url.startAccessingSecurityScopedResource() {
                accessURLs[newFolder.id] = url
            }
            library.folders.append(newFolder)
        }
        persist(); scanFolders(autoIndex: true)
    }
    func removeFolder(_ folder: CarfoFolder) {
        guard !isWorking else { return }
        if let access = accessURLs.removeValue(forKey: folder.id) {
            access.stopAccessingSecurityScopedResource()
        }
        library.folders.removeAll { $0.id == folder.id }
        library.clips.removeAll { $0.folderID == folder.id }
        if folderFilter == folder.id { folderFilter = nil }
        persist(); scheduleSearch()
        let activeThumbnails = Set(library.clips.compactMap(\.thumbnail))
        store.pruneThumbnails(keeping: activeThumbnails)
    }
    /// - Parameter force: "Pindai ulang". Starts a rescan run over every folder, or resumes the unfinished one.
    ///   Folders the run already finished are skipped. Without `force`, only folders never scanned are read.
    func scanFolders(autoIndex: Bool = false, force: Bool = false) {
        guard !isWorking else { return }
        guard !library.folders.isEmpty else { pickFolder(); return }
        let session: Date? = force ? (rescanSessionStart ?? Date()) : nil
        if let session { rescanSessionStart = session }
        let foldersWithClips = Set(library.clips.map(\.folderID))
        func needsScan(_ folder: CarfoFolder) -> Bool {
            if let session { return (folder.scannedAt ?? .distantPast) < session }
            return folder.scannedAt == nil && !foldersWithClips.contains(folder.id)
        }
        // A rescan run counts every folder, so a resumed run shows the folders it already finished as done.
        let scope = session == nil ? library.folders.filter(needsScan) : library.folders
        let pending = scope.filter(needsScan)
        guard !pending.isEmpty else {
            if autoIndex && installation.isAvailable {
                if library.clips.contains(where: needsIndexing) { startIndexing(); return }
                notice = "Semua folder sudah dipindai dan diindeks."
            } else {
                notice = "Semua folder sudah dipindai."
            }
            if session != nil { rescanSessionStart = nil }
            return
        }
        folderAccessError = nil
        let alreadyDone = scope.count - pending.count
        // Progress units: 100 per folder, so the bar also moves file by file inside a folder.
        work = WorkProgress(title: "Membaca koleksi...", detail: "Mencari file media dan menyiapkan thumbnail", completed: alreadyDone * 100, total: scope.count * 100)
        workTask = Task {
            defer { persist(); work = nil; workTask = nil; scheduleSearch() }
            var issues: [String] = []
            for (offset, folder) in pending.enumerated() {
                let position = alreadyDone + offset
                do {
                    try Task.checkCancellation()
                    work?.detail = folder.name
                    work?.completed = position * 100
                    let report = try await LibraryScanner.scan(folder: folder, previous: library.clips, thumbnails: store.thumbnailDirectory) { [weak self] progress in
                        await self?.applyScanProgress(progress, folder: folder, position: position)
                    }
                    // The full report also drops clips whose files were deleted.
                    var clips = library.clips
                    clips.removeAll { $0.folderID == folder.id }
                    clips += report.clips
                    library.clips = clips
                    if let index = library.folders.firstIndex(where: { $0.id == folder.id }) { library.folders[index].scannedAt = Date() }
                    issues += report.errors
                    persistSoon()
                } catch is CancellationError { return }
                catch {
                    issues.append("\(folder.name): \(error.localizedDescription)")
                    if !FileManager.default.isReadableFile(atPath: folder.path) { folderAccessError = "Folder \(folder.name) tidak dapat dibuka. Pilih ulang folder untuk memperbarui aksesnya." }
                }
            }
            work?.completed = scope.count * 100
            if !issues.isEmpty { notice = issues.prefix(3).joined(separator: "\n") }
            // Auto-index after scan if requested and there are un-indexed or un-transcribed clips.
            // The rescan run stays open until indexing also finishes, so stopping during indexing does not rescan again.
            if autoIndex && installation.isAvailable && library.clips.contains(where: needsIndexing) {
                // Must schedule on main actor since we're already on it
                Task { @MainActor in self.startIndexing() }
            } else if session != nil {
                rescanSessionStart = nil
            }
        }
    }
    private func needsIndexing(_ clip: FootageClip) -> Bool {
        !clip.isIndexed || ((installation.canTranscribe || !clip.transcripts.isEmpty) && clip.needsTranscript)
    }
    private func applyScanProgress(_ progress: LibraryScanner.ScanProgress, folder: CarfoFolder, position: Int) {
        mergeScannedClips(progress.clips)
        let share = progress.total > 0 ? progress.processed * 100 / progress.total : 0
        work?.completed = position * 100 + share
        work?.detail = "\(folder.name) · \(progress.processed)/\(progress.total) file"
        if !progress.clips.isEmpty { persistSoon() }
    }
    /// Adds or updates clips from a scan in progress. Clips the scan has not reached yet are kept,
    /// so stopping mid-folder loses nothing and the next scan reuses these as cache hits.
    private func mergeScannedClips(_ scanned: [FootageClip]) {
        guard !scanned.isEmpty else { return }
        var clips = library.clips
        for clip in scanned {
            if let index = clipPositions[clip.id] {
                stats.replace(clips[index], with: clip)
                clips[index] = clip
            } else {
                clipPositions[clip.id] = clips.count
                stats.replace(nil, with: clip)
                clips.append(clip)
            }
        }
        mergingClips = true
        library.clips = clips
        mergingClips = false
    }
    /// Work units for one clip: one per segment, plus one for its transcript when transcription is available.
    private static func indexUnits(_ clip: FootageClip, canTranscribe: Bool) -> (done: Int, total: Int) {
        let finished: (VideoSegment) -> Bool
        switch clip.mediaType {
        case .image: finished = { $0.visualEmbedding != nil }
        case .audio: finished = { $0.audioEmbedding != nil }
        case .video: finished = { $0.visualEmbedding != nil && (!clip.hasAudio || $0.audioEmbedding != nil) }
        }
        var total = clip.segments.count
        var done = clip.segments.filter(finished).count
        if (canTranscribe || !clip.transcripts.isEmpty) && clip.hasAudio {
            total += 1
            if !clip.needsTranscript { done += 1 }
        }
        return (done, total)
    }
    func startIndexing() {
        guard !isWorking else { return }
        guard installation.isAvailable else { modelError = EngineError.unavailable.localizedDescription; showSettings?(); return }
        guard !library.clips.isEmpty else { pickFolder(); return }
        if !indexMatchesModel {
            for index in library.clips.indices {
                switch library.clips[index].mediaType {
                case .image:
                    library.clips[index].segments = [VideoSegment(start: 0, end: 0)]
                case .audio:
                    library.clips[index].segments = SegmentPlanner.segments(duration: library.clips[index].duration)
                case .video:
                    library.clips[index].segments = SegmentPlanner.segments(duration: library.clips[index].duration)
                }
                library.clips[index].indexedAt = nil
                // Invalidate transcript cue embeddings while preserving transcript text (CF-06)
                for cueIndex in library.clips[index].transcripts.indices {
                    library.clips[index].transcripts[cueIndex].embedding = nil
                }
            }
            library.modelRevision = installation.modelIdentifier
            queryCache.removeAll(); queryCacheOrder.removeAll()
            persist()
        }
        let canTranscribe = installation.canTranscribe
        let candidates = library.clips.filter(needsIndexing)
        guard !candidates.isEmpty else {
            rescanSessionStart = nil
            notice = "Semua file sudah diindeks. Pindai ulang folder untuk menemukan file baru."
            return
        }
        // Count finished work too, so a resumed run continues the bar instead of restarting at 0%.
        var total = 0, done = 0
        for clip in library.clips {
            let units = Self.indexUnits(clip, canTranscribe: canTranscribe)
            total += units.total; done += units.done
        }
        work = WorkProgress(title: "Mengindeks koleksi", detail: "Menyiapkan indeks...", completed: done, total: total)
        workTask = Task(priority: .utility) {
            defer {
                persist()
                work = nil
                workTask = nil
                scheduleSearch()
                Task { await engine.purge() }
            }
            do {
                _ = try await engine.verify(); modelVerified = true; modelError = nil
                library.modelRevision = installation.modelIdentifier
                for (candidateIndex, candidate) in candidates.enumerated() {
                    guard let clipIndex = clipPositions[candidate.id] else { continue }
                    let frameDecoder = candidate.isVideo ? FrameDecoder(url: candidate.url) : nil

                    // Transcription for audio-bearing clips
                    if (canTranscribe || !candidate.transcripts.isEmpty) && candidate.hasAudio && library.clips[clipIndex].needsTranscript {
                        try Task.checkCancellation()
                        work?.detail = "Transkrip dialog: \(candidate.name)"
                        do {
                            let temporary = store.directory.appendingPathComponent("Working/\(UUID().uuidString)", isDirectory: true)
                            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                            defer { try? FileManager.default.removeItem(at: temporary) }
                            if library.clips[clipIndex].transcriptSource == nil && !library.clips[clipIndex].transcripts.isEmpty {
                                updateClip(at: clipIndex) { $0.transcriptSource = "legacy"; $0.transcribedAt = Date() }
                            }
                            // Existing subtitle or completed speech text only needs missing vectors.
                            if library.clips[clipIndex].transcribedAt == nil && library.clips[clipIndex].transcriptSource != "subtitle" {
                                let chunks = try TranscriptionPlan.chunks(duration: candidate.duration, resumeAt: library.clips[clipIndex].transcriptOffset)
                                for chunk in chunks {
                                    try Task.checkCancellation()
                                    work?.detail = "Transkrip \(candidate.name) · \(timecode(chunk.start))"
                                    let wav = temporary.appendingPathComponent("chunk.wav")
                                    try await MediaProcessor.audio(url: candidate.url, segment: chunk.extraction, destination: wav)
                                    let local = try await engine.transcribe(audio: wav, duration: chunk.extraction.end - chunk.extraction.start, chunkSize: 90)
                                    let cues = TranscriptionPlan.cues(local, in: chunk)
                                    updateClip(at: clipIndex) {
                                        $0.transcripts += cues
                                        $0.transcriptOffset = chunk.end
                                        $0.transcriptSource = "whisper"
                                    }
                                    persistSoon(for: candidate.id)
                                    try Task.checkCancellation()
                                }
                                updateClip(at: clipIndex) { $0.transcribedAt = Date() }
                            }
                            let missing = library.clips[clipIndex].transcripts.indices.filter { library.clips[clipIndex].transcripts[$0].embedding == nil }
                            for batchStart in stride(from: 0, to: missing.count, by: 16) {
                                let batch = Array(missing[batchStart..<min(missing.count, batchStart + 16)])
                                let embeddings = try await engine.embed(documents: batch.map { library.clips[clipIndex].transcripts[$0].text })
                                updateClip(at: clipIndex) { clip in
                                    for (offset, index) in batch.enumerated() { clip.transcripts[index].embedding = embeddings[offset] }
                                }
                                persistSoon(for: candidate.id)
                            }
                            updateClip(at: clipIndex) { $0.transcriptError = nil }
                            persistSoon(for: candidate.id)
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            // CF-03: Separate error, do not set transcribedAt so needsTranscript stays true for retry
                            updateClip(at: clipIndex) { $0.transcriptError = error.localizedDescription }
                            notice = "Transkripsi \(candidate.name) belum selesai: \(error.localizedDescription). Pindai ulang untuk melanjutkan progres tersimpan."
                            persistSoon(for: candidate.id)
                        }
                        work?.completed += 1
                    }

                    // Image indexing: embed the image file directly (or its rendered raster thumbnail for SVG)
                    if candidate.isImage {
                        for segmentIndex in library.clips[clipIndex].segments.indices {
                            try Task.checkCancellation()
                            var segment = library.clips[clipIndex].segments[segmentIndex]
                            if segment.visualEmbedding != nil { continue }
                            work?.detail = "\(candidate.name)"
                            let frameURL: URL
                            if candidate.url.pathExtension.lowercased() == "svg" {
                                let thumbName = candidate.thumbnail ?? "\(candidate.id.uuidString).jpg"
                                let thumbURL = store.thumbnailDirectory.appendingPathComponent(thumbName)
                                if !FileManager.default.fileExists(atPath: thumbURL.path) {
                                    try? LibraryScanner.imageThumbnail(url: candidate.url, destination: thumbURL)
                                }
                                frameURL = FileManager.default.fileExists(atPath: thumbURL.path) ? thumbURL : candidate.url
                            } else {
                                frameURL = candidate.url
                            }
                            segment.visualEmbedding = try await engine.embed(frames: [frameURL])
                            updateClip(at: clipIndex) { $0.segments[segmentIndex] = segment }
                            work?.completed += 1
                            persistSoon(for: candidate.id)
                        }
                        updateClip(at: clipIndex) { $0.indexedAt = Date(); $0.indexError = nil }
                        persistSoon(for: candidate.id)
                        if (candidateIndex + 1) % 25 == 0 { await engine.purge() }
                        await Task.yield()
                        continue
                    }

                    // Audio-only indexing: embed audio segments only
                    if candidate.isAudio {
                        let temporary = store.directory.appendingPathComponent("Working/\(candidate.id.uuidString)", isDirectory: true)
                        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                        defer { try? FileManager.default.removeItem(at: temporary) }
                        let fullWav = temporary.appendingPathComponent("full_audio.wav")
                        var fullWavExtracted = false

                        for segmentIndex in library.clips[clipIndex].segments.indices {
                            try Task.checkCancellation()
                            var segment = library.clips[clipIndex].segments[segmentIndex]
                            if segment.audioEmbedding != nil { continue }
                            work?.detail = "\(candidate.name) · \(timecode(segment.start))–\(timecode(segment.end))"
                            if !fullWavExtracted {
                                try await MediaProcessor.audio(url: candidate.url, segment: VideoSegment(start: 0, end: candidate.duration), destination: fullWav)
                                fullWavExtracted = true
                            }
                            segment.audioEmbedding = try await engine.embed(audio: fullWav, offset: segment.start, duration: segment.end - segment.start)
                            updateClip(at: clipIndex) { $0.segments[segmentIndex] = segment }
                            work?.completed += 1
                            persistSoon(for: candidate.id)
                        }
                        updateClip(at: clipIndex) { $0.indexedAt = Date(); $0.indexError = nil }
                        persistSoon(for: candidate.id)
                        if (candidateIndex + 1) % 25 == 0 { await engine.purge() }
                        await Task.yield()
                        continue
                    }

                    // Video indexing: embed frames + audio
                    let temporary = store.directory.appendingPathComponent("Working/\(candidate.id.uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    let fullWav = temporary.appendingPathComponent("full_audio.wav")
                    var fullWavExtracted = false

                    for segmentIndex in library.clips[clipIndex].segments.indices {
                        try Task.checkCancellation()
                        var segment = library.clips[clipIndex].segments[segmentIndex]
                        if segment.visualEmbedding != nil && (!candidate.hasAudio || segment.audioEmbedding != nil) { continue }
                        work?.detail = "\(candidate.name) · \(timecode(segment.start))–\(timecode(segment.end))"
                        if segment.visualEmbedding == nil {
                            let frames = try await MediaProcessor.frames(url: candidate.url, segment: segment, directory: temporary, decoder: frameDecoder)
                            segment.visualEmbedding = try await engine.embed(frames: frames)
                            updateClip(at: clipIndex) { $0.segments[segmentIndex] = segment }
                            persistSoon(for: candidate.id)
                            for frame in frames { try? FileManager.default.removeItem(at: frame) }
                        }
                        if candidate.hasAudio && segment.audioEmbedding == nil {
                            if !fullWavExtracted {
                                do {
                                    try await MediaProcessor.audio(url: candidate.url, segment: VideoSegment(start: 0, end: candidate.duration), destination: fullWav)
                                    fullWavExtracted = true
                                } catch {
                                    fullWavExtracted = false
                                }
                            }
                            if fullWavExtracted {
                                segment.audioEmbedding = try await engine.embed(audio: fullWav, offset: segment.start, duration: segment.end - segment.start)
                            }
                        }
                        updateClip(at: clipIndex) { $0.segments[segmentIndex] = segment }
                        work?.completed += 1
                        persistSoon(for: candidate.id)
                    }
                    updateClip(at: clipIndex) { $0.indexedAt = Date(); $0.indexError = nil }
                    persistSoon(for: candidate.id)
                    if (candidateIndex + 1) % 25 == 0 { await engine.purge() }
                    await Task.yield()
                }
            } catch is CancellationError { notice = "Pengindeksan dihentikan. Segmen yang sudah selesai tetap tersimpan." }
            catch {
                modelError = error.localizedDescription
                notice = "Pengindeksan berhenti: \(error.localizedDescription). Proses dapat dilanjutkan tanpa mengulang segmen yang tersimpan."
            }
        }
    }
    func cancelWork() {
        workTask?.cancel()
        Task { await engine.stop() }
    }
    func verifyModel() {
        guard !modelChecking, !isWorking else { return }
        modelChecking = true; modelError = nil
        Task {
            defer { modelChecking = false }
            do { _ = try await engine.verify(); modelVerified = true }
            catch { modelVerified = false; modelError = error.localizedDescription }
        }
    }
    func pickPython() {
        let picker = NSOpenPanel()
        picker.title = "Pilih Python dengan MLX dan mlx-vlm"; picker.prompt = "Pakai runtime ini"
        picker.canChooseDirectories = false; picker.canChooseFiles = true; picker.showsHiddenFiles = true
        picker.begin { [weak self] response in
            guard response == .OK, let url = picker.url else { return }
            Task { @MainActor in self?.updateInstallation(pythonPath: url.path) }
        }
    }
    private func cacheQueryEmbedding(_ embedding: [Float], for key: String) {
        if queryCache[key] == nil {
            if queryCacheOrder.count >= 100 {
                let oldest = queryCacheOrder.removeFirst()
                queryCache.removeValue(forKey: oldest)
            }
            queryCacheOrder.append(key)
        }
        queryCache[key] = embedding
    }
    private func updateInstallation(pythonPath: String? = nil) {
        guard !isWorking else { return }
        if let pythonPath { defaults.set(pythonPath, forKey: "pythonPath") }
        installation = .discover(pythonOverride: defaults.string(forKey: "pythonPath"))
        modelVerified = false; modelError = nil; queryCache.removeAll(); queryCacheOrder.removeAll()
        let value = installation
        Task { await engine.configure(value) }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { notice = "Izinkan Carfo di Pengaturan Sistem → Umum → Item Masuk." }
        } catch { launchAtLogin = SMAppService.mainApp.status == .enabled; notice = error.localizedDescription }
    }
    func scheduleSearch() {
        searchTask?.cancel(); searchError = nil
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && mode != .dialogue {
            isSearching = false; results = []; selectedID = nil; stopPreview(); return
        }
        let selectedMode = mode, filter = folderFilter, clips = library.clips

        // Phase 1 (Instant): Immediate filename and lexical text search without waiting for model
        let instantMatches = SearchEngine.search(clips: clips, query: text, mode: selectedMode, folderID: filter)
        results = instantMatches
        semanticSearch = false
        if selectedID == nil || !instantMatches.contains(where: { $0.id == selectedID }) {
            select(instantMatches.first?.id)
        }

        let hasVectors = clips.contains { clip in
            if selectedMode == .dialogue {
                return clip.hasAudio && (clip.segments.contains { $0.audioEmbedding != nil } || clip.transcripts.contains { $0.embedding != nil })
            }
            return clip.segments.contains { seg in
                switch selectedMode {
                case .video: return clip.mediaType == .video && (seg.visualEmbedding != nil || seg.audioEmbedding != nil)
                case .visual: return clip.mediaType == .image && seg.visualEmbedding != nil
                case .sound: return (clip.mediaType == .audio || (clip.mediaType == .video && clip.hasAudio)) && seg.audioEmbedding != nil
                case .dialogue: return clip.hasAudio && (seg.audioEmbedding != nil || clip.transcripts.contains { $0.embedding != nil })
                }
            }
        }
        let canDoSemantic = !text.isEmpty && installation.isAvailable && indexMatchesModel && hasVectors
        guard canDoSemantic else {
            isSearching = false
            return
        }

        isSearching = true

        // Phase 2 (Asynchronous): Semantic model embedding and vector reranking
        searchTask = Task(priority: .userInitiated) {
            do {
                try await Task.sleep(for: .milliseconds(200))
                try Task.checkCancellation()

                var embedding: [Float]?
                var textEmbedding: [Float]?
                let key = selectedMode.rawValue + ":" + text
                if selectedMode == .dialogue {
                    if let cached = queryCache[key] { textEmbedding = cached }
                    else {
                        textEmbedding = try await engine.embed(query: text, mode: .dialogue)
                        if let textEmbedding {
                            cacheQueryEmbedding(textEmbedding, for: key)
                        }
                    }
                } else {
                    if let cached = queryCache[key] { embedding = cached }
                    else {
                        embedding = try await engine.embed(query: text, mode: selectedMode)
                        if let embedding {
                            cacheQueryEmbedding(embedding, for: key)
                        }
                    }
                }
                try Task.checkCancellation()

                let matches = await Task.detached(priority: .userInitiated) {
                    SearchEngine.search(clips: clips, query: text, mode: selectedMode, folderID: filter, embedding: embedding, textEmbedding: textEmbedding)
                }.value
                try Task.checkCancellation()

                // Guard against stale search results from an older query (CF-07)
                guard self.query.trimmingCharacters(in: .whitespacesAndNewlines) == text && self.mode == selectedMode else { return }

                semanticSearch = embedding != nil || textEmbedding != nil
                results = matches
                isSearching = false
                if selectedID == nil || !matches.contains(where: { $0.id == selectedID }) {
                    select(matches.first?.id)
                }
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                guard self.query.trimmingCharacters(in: .whitespacesAndNewlines) == text && self.mode == selectedMode else { return }
                isSearching = false
                semanticSearch = false
                searchError = error.localizedDescription
                if results.isEmpty {
                    results = instantMatches
                    select(results.first?.id)
                }
            }
        }
    }
    func select(_ id: String?) {
        if selectedID == id { return }
        stopPreview(); selectedID = id
        guard let result = selected else { player.replaceCurrentItem(with: nil); return }
        if result.clip.isImage {
            player.replaceCurrentItem(with: nil)
            return
        }
        if FileManager.default.fileExists(atPath: result.clip.path) {
            let item = AVPlayerItem(url: result.clip.url)
            let rawEnd = result.matchedCue != nil ? (result.contextCues.last?.end ?? (result.matchedCue!.end + 1.0)) : (result.segment?.end ?? result.clip.duration)
            let playbackEnd = min(result.clip.duration, rawEnd)
            item.forwardPlaybackEndTime = CMTime(seconds: playbackEnd, preferredTimescale: 600)
            player.replaceCurrentItem(with: item)
            let seekTime = result.matchedCue?.start ?? result.segment?.start ?? 0
            player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.replaceCurrentItem(with: nil)
        }
    }
    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? 0
        select(results[max(0, min(results.count - 1, current + delta))].id)
    }
    func togglePreview() {
        guard let result = selected, !result.clip.isImage else { return }
        if isPlaying { stopPreview() }
        else {
            let start = result.matchedCue?.start ?? result.segment?.start ?? 0
            let rawEnd = result.matchedCue != nil ? (result.contextCues.last?.end ?? (result.matchedCue!.end + 1.0)) : (result.segment?.end ?? result.clip.duration)
            let end = min(result.clip.duration, rawEnd)
            if player.currentTime().seconds >= end - 0.1 || player.currentTime().seconds < start - 0.5 {
                player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            player.play(); isPlaying = true
        }
    }
    func stopPreview() { player.pause(); isPlaying = false }
    func recordQuery() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        recentQueries.removeAll { $0 == text }; recentQueries.insert(text, at: 0)
        recentQueries = Array(recentQueries.prefix(5)); defaults.set(recentQueries, forKey: "recentQueries")
    }
    func openSelected() {
        guard let result = selected else { return }
        guard FileManager.default.isReadableFile(atPath: result.clip.path) else { searchError = "File tidak ditemukan atau izin folder berubah. Pilih ulang folder footage."; return }
        recordQuery(); stopPreview()
        if NSWorkspace.shared.open(result.clip.url) { hideSearch?() }
        else { searchError = "macOS belum memiliki aplikasi yang dapat membuka video ini." }
    }
    func revealSelected() {
        guard let result = selected else { return }
        recordQuery(); NSWorkspace.shared.activateFileViewerSelecting([result.clip.url]); hideSearch?()
    }
    func copySelectedPath() {
        guard let selected else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(selected.clip.path, forType: .string)
    }
    func shutdown() {
        startupTask?.cancel()
        searchTask?.cancel(); workTask?.cancel(); stopPreview()
        for (_, url) in accessURLs { url.stopAccessingSecurityScopedResource() }
        accessURLs.removeAll()
        flushSaves()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        Task { await engine.stop() }
    }
}
