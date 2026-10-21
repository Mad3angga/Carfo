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

/// Clip counts computed once per library change instead of on every view render.
struct LibraryStats {
    var video = 0, image = 0, audio = 0, indexed = 0, transcribed = 0, needsTranscript = 0
    init() {}
    init(_ clips: [FootageClip]) {
        for clip in clips {
            switch clip.mediaType {
            case .video: video += 1
            case .image: image += 1
            case .audio: audio += 1
            }
            if clip.isIndexed { indexed += 1 }
            if clip.transcribedAt != nil || !clip.transcripts.isEmpty { transcribed += 1 }
            if clip.needsTranscript { needsTranscript += 1 }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var library: LibraryManifest { didSet { stats = LibraryStats(library.clips) } }
    private(set) var stats = LibraryStats()
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
    private var queryCache: [String: [Float]] = [:]
    private var endObserver: NSObjectProtocol?
    private var playbackObserver: NSKeyValueObservation?
    var isWorking: Bool { work != nil }
    var selected: SearchResult? { results.first { $0.id == selectedID } }
    var indexMatchesModel: Bool { library.modelRevision == nil || library.modelRevision == installation.modelDirectory?.lastPathComponent }
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

    init(directory: URL? = nil) throws {
        let environment = ProcessInfo.processInfo.environment
        defaults = environment["CARFO_DEFAULTS_SUITE"].flatMap(UserDefaults.init(suiteName:))
            ?? environment["FOOTAGE_DEFAULTS_SUITE"].flatMap(UserDefaults.init(suiteName:))
            ?? .standard
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let carfoDir = appSupport.appendingPathComponent("Carfo", isDirectory: true)
        let footageDir = appSupport.appendingPathComponent("Footage", isDirectory: true)
        if !FileManager.default.fileExists(atPath: carfoDir.path) && FileManager.default.fileExists(atPath: footageDir.path) {
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
        let detected = LocalModelInstallation.discover(pythonOverride: defaults.string(forKey: "pythonPath"))
        installation = detected
        let script = Bundle.main.url(forResource: "worker", withExtension: "py", subdirectory: "Engine")
            ?? Bundle.module.url(forResource: "Engine", withExtension: nil)!.appendingPathComponent("worker.py")
        engine = LocalEngine(installation: detected, script: script, logDirectory: root)
        do { library = try store.load() }
        catch { notice = "Indeks tidak dapat dibaca: \(error.localizedDescription). File indeks tetap disimpan di \(store.manifestURL.path)." }
        stats = LibraryStats(library.clips) // didSet does not run inside init
        store.cleanWorkingDirectories()
        let activeThumbnails = Set(library.clips.compactMap(\.thumbnail))
        store.pruneThumbnails(keeping: activeThumbnails)
        restoreFolderAccess()
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
    /// Saves now. Encoding the whole library takes hundreds of ms, so it runs on `saveQueue`, not the main thread.
    func persist() {
        saveTask?.cancel(); saveTask = nil
        let snapshot = library, store = store
        saveQueue.async { [weak self] in
            do { try store.save(snapshot) }
            catch {
                let message = error.localizedDescription
                Task { @MainActor in self?.notice = "Indeks belum tersimpan: \(message)" }
            }
        }
    }
    /// Coalesces the frequent saves made while scanning and indexing into one write every few seconds.
    func persistSoon() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }
    /// Writes any pending changes and waits until they are on disk. Used when quitting.
    func flushSaves() {
        persist()
        saveQueue.sync {}
    }
    func pickFolder() {
        guard !isWorking else { notice = "Tunggu proses selesai sebelum menambah folder."; return }
        let picker = NSOpenPanel()
        picker.title = "Tambah folder footage"
        picker.prompt = "Tambah folder"
        picker.canChooseDirectories = true; picker.canChooseFiles = false; picker.allowsMultipleSelection = true
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
        !clip.isIndexed || (installation.canTranscribe && clip.needsTranscript)
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
        var positions = Dictionary(clips.indices.map { (clips[$0].folderID.uuidString + clips[$0].path, $0) }, uniquingKeysWith: { first, _ in first })
        for clip in scanned {
            let key = clip.folderID.uuidString + clip.path
            if let index = positions[key] { clips[index] = clip }
            else { positions[key] = clips.count; clips.append(clip) }
        }
        library.clips = clips
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
        if canTranscribe && clip.hasAudio {
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
            }
            library.modelRevision = installation.modelDirectory?.lastPathComponent
            persist()
        }
        let canTranscribe = installation.canTranscribe
        let candidates = library.clips.filter { !$0.isIndexed || (canTranscribe && $0.needsTranscript) }
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
                Task { await engine.stop() }
            }
            do {
                _ = try await engine.verify(); modelVerified = true; modelError = nil
                library.modelRevision = installation.modelDirectory?.lastPathComponent
                for candidate in candidates {
                    guard let clipIndex = library.clips.firstIndex(where: { $0.id == candidate.id }) else { continue }

                    // Transcription for audio-bearing clips
                    if canTranscribe && candidate.hasAudio && library.clips[clipIndex].needsTranscript {
                        try Task.checkCancellation()
                        work?.detail = "Transkrip dialog: \(candidate.name)"
                        do {
                            let temporary = store.directory.appendingPathComponent("Working/\(UUID().uuidString)", isDirectory: true)
                            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                            defer { try? FileManager.default.removeItem(at: temporary) }
                            let wav = temporary.appendingPathComponent("full_audio.wav")
                            try await MediaProcessor.audio(url: candidate.url, segment: VideoSegment(start: 0, end: candidate.duration), destination: wav)
                            var cues = try await engine.transcribe(audio: wav, duration: candidate.duration)
                            if !cues.isEmpty {
                                let embeddings = try await engine.embed(documents: cues.map(\.text))
                                for i in cues.indices {
                                    if i < embeddings.count { cues[i].embedding = embeddings[i] }
                                }
                            }
                            library.clips[clipIndex].transcripts = cues
                            library.clips[clipIndex].transcribedAt = Date()
                            persistSoon()
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            library.clips[clipIndex].transcribedAt = Date()
                            library.clips[clipIndex].indexError = error.localizedDescription
                            persistSoon()
                        }
                        work?.completed += 1
                    }

                    // Image indexing: embed the image file directly
                    if candidate.isImage {
                        for segmentIndex in library.clips[clipIndex].segments.indices {
                            try Task.checkCancellation()
                            var segment = library.clips[clipIndex].segments[segmentIndex]
                            if segment.visualEmbedding != nil { continue }
                            work?.detail = "\(candidate.name)"
                            segment.visualEmbedding = try await engine.embed(frames: [candidate.url])
                            library.clips[clipIndex].segments[segmentIndex] = segment
                            work?.completed += 1
                            persistSoon()
                        }
                        library.clips[clipIndex].indexedAt = Date(); library.clips[clipIndex].indexError = nil
                        persistSoon()
                        await engine.purge()
                        try await Task.sleep(for: .milliseconds(50))
                        continue
                    }

                    // Audio-only indexing: embed audio segments only
                    if candidate.isAudio {
                        for segmentIndex in library.clips[clipIndex].segments.indices {
                            try Task.checkCancellation()
                            var segment = library.clips[clipIndex].segments[segmentIndex]
                            if segment.audioEmbedding != nil { continue }
                            work?.detail = "\(candidate.name) · \(timecode(segment.start))–\(timecode(segment.end))"
                            let temporary = store.directory.appendingPathComponent("Working/\(UUID().uuidString)", isDirectory: true)
                            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                            defer { try? FileManager.default.removeItem(at: temporary) }
                            let wav = temporary.appendingPathComponent("audio.wav")
                            try await MediaProcessor.audio(url: candidate.url, segment: segment, destination: wav)
                            segment.audioEmbedding = try await engine.embed(audio: wav)
                            library.clips[clipIndex].segments[segmentIndex] = segment
                            work?.completed += 1
                            persistSoon()
                        }
                        library.clips[clipIndex].indexedAt = Date(); library.clips[clipIndex].indexError = nil
                        persistSoon()
                        await engine.purge()
                        try await Task.sleep(for: .milliseconds(50))
                        continue
                    }

                    // Video indexing: embed frames + audio
                    for segmentIndex in library.clips[clipIndex].segments.indices {
                        try Task.checkCancellation()
                        var segment = library.clips[clipIndex].segments[segmentIndex]
                        if segment.visualEmbedding != nil && (!candidate.hasAudio || segment.audioEmbedding != nil) { continue }
                        work?.detail = "\(candidate.name) · \(timecode(segment.start))–\(timecode(segment.end))"
                        let temporary = store.directory.appendingPathComponent("Working/\(UUID().uuidString)", isDirectory: true)
                        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                        defer { try? FileManager.default.removeItem(at: temporary) }
                        if segment.visualEmbedding == nil {
                            let frames = try await MediaProcessor.frames(url: candidate.url, segment: segment, directory: temporary)
                            segment.visualEmbedding = try await engine.embed(frames: frames)
                            library.clips[clipIndex].segments[segmentIndex] = segment
                            persistSoon()
                        }
                        if candidate.hasAudio && segment.audioEmbedding == nil {
                            let wav = temporary.appendingPathComponent("audio.wav")
                            try await MediaProcessor.audio(url: candidate.url, segment: segment, destination: wav)
                            segment.audioEmbedding = try await engine.embed(audio: wav)
                        }
                        library.clips[clipIndex].segments[segmentIndex] = segment
                        work?.completed += 1
                        persistSoon()
                    }
                    library.clips[clipIndex].indexedAt = Date(); library.clips[clipIndex].indexError = nil
                    persistSoon()
                    await engine.purge()
                    try await Task.sleep(for: .milliseconds(60))
                }
            } catch is CancellationError { notice = "Pengindeksan dihentikan. Segmen yang sudah selesai tetap tersimpan." }
            catch {
                modelError = error.localizedDescription
                notice = "Pengindeksan berhenti: \(error.localizedDescription). Proses dapat dilanjutkan tanpa mengulang segmen yang tersimpan."
            }
        }
    }
    func cancelWork() { workTask?.cancel() }
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
    private func updateInstallation(pythonPath: String? = nil) {
        guard !isWorking else { return }
        if let pythonPath { defaults.set(pythonPath, forKey: "pythonPath") }
        installation = .discover(pythonOverride: defaults.string(forKey: "pythonPath"))
        modelVerified = false; modelError = nil; queryCache.removeAll()
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
        isSearching = true
        let selectedMode = mode, filter = folderFilter, clips = library.clips
        searchTask = Task {
            do {
                if !text.isEmpty { try await Task.sleep(for: .milliseconds(250)) }
                let hasVectors = clips.contains { clip in
                    clip.segments.contains { seg in
                        switch selectedMode {
                        case .video: return clip.mediaType == .video && (seg.visualEmbedding != nil || seg.audioEmbedding != nil)
                        case .visual: return clip.mediaType == .image && seg.visualEmbedding != nil
                        case .sound: return (clip.mediaType == .audio || (clip.mediaType == .video && clip.hasAudio)) && seg.audioEmbedding != nil
                        case .dialogue: return clip.hasAudio && seg.audioEmbedding != nil
                        }
                    }
                }
                var embedding: [Float]?
                var textEmbedding: [Float]?
                if !text.isEmpty && installation.isAvailable && indexMatchesModel {
                    let key = selectedMode.rawValue + ":" + text
                    if selectedMode == .dialogue {
                        if let cached = queryCache[key] { textEmbedding = cached }
                        else {
                            textEmbedding = try await engine.embed(query: text, mode: .dialogue)
                            if let textEmbedding {
                                if queryCache.count >= 50 { queryCache.removeAll() }
                                queryCache[key] = textEmbedding
                            }
                        }
                    } else if hasVectors {
                        if let cached = queryCache[key] { embedding = cached }
                        else {
                            embedding = try await engine.embed(query: text, mode: selectedMode)
                            if let embedding {
                                if queryCache.count >= 50 { queryCache.removeAll() }
                                queryCache[key] = embedding
                            }
                        }
                    }
                }
                try Task.checkCancellation()
                let matches = await Task.detached(priority: .userInitiated) {
                    SearchEngine.search(clips: clips, query: text, mode: selectedMode, folderID: filter, embedding: embedding, textEmbedding: textEmbedding)
                }.value
                try Task.checkCancellation()
                semanticSearch = embedding != nil || textEmbedding != nil; results = matches; isSearching = false
                select(matches.first?.id)
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                isSearching = false; semanticSearch = false; searchError = error.localizedDescription
                results = SearchEngine.search(clips: clips, query: text, mode: selectedMode, folderID: filter)
                select(results.first?.id)
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
            if let segment = result.segment { item.forwardPlaybackEndTime = CMTime(seconds: segment.end, preferredTimescale: 600) }
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
            let end = result.matchedCue?.end ?? result.segment?.end ?? result.clip.duration
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
        searchTask?.cancel(); workTask?.cancel(); stopPreview()
        for (_, url) in accessURLs { url.stopAccessingSecurityScopedResource() }
        accessURLs.removeAll()
        flushSaves()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        Task { await engine.stop() }
    }
}
