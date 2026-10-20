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
    @Published var library: LibraryManifest
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
    private var accessURLs: [URL] = []
    private var queryCache: [String: [Float]] = [:]
    private var endObserver: NSObjectProtocol?
    private var playbackObserver: NSKeyValueObservation?
    var isWorking: Bool { work != nil }
    var selected: SearchResult? { results.first { $0.id == selectedID } }
    var indexMatchesModel: Bool { library.modelRevision == nil || library.modelRevision == installation.modelDirectory?.lastPathComponent }
    var indexedCount: Int { indexMatchesModel ? library.clips.filter(\.isIndexed).count : 0 }
    var transcribedCount: Int { library.clips.filter { $0.transcribedAt != nil || !$0.transcripts.isEmpty }.count }
    var clipsNeedingTranscriptCount: Int { installation.canTranscribe ? library.clips.filter(\.needsTranscript).count : 0 }
    var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var statusText: String {
        if let work { return work.title }
        if library.clips.isEmpty { return "Cari di file lokal" }
        let videoCount = library.clips.filter(\.isVideo).count
        let imageCount = library.clips.filter(\.isImage).count
        let audioCount = library.clips.filter(\.isAudio).count
        var parts: [String] = []
        if videoCount > 0 { parts.append("\(videoCount) video") }
        if imageCount > 0 { parts.append("\(imageCount) gambar") }
        if audioCount > 0 { parts.append("\(audioCount) audio") }
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
                if url.startAccessingSecurityScopedResource() { accessURLs.append(url) }
                library.folders[index].path = url.path
                if stale { library.folders[index].bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
            }
        }
        if library.folders.contains(where: { !FileManager.default.isReadableFile(atPath: $0.path) }) {
            folderAccessError = "Salah satu folder tidak dapat dibuka. Pilih ulang folder untuk memperbarui aksesnya."
        }
    }
    func persist() {
        do { try store.save(library) }
        catch { notice = "Indeks belum tersimpan: \(error.localizedDescription)" }
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
            if url.startAccessingSecurityScopedResource() { accessURLs.append(url) }
            let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            if let index = library.folders.firstIndex(where: { standardized.path == URL(fileURLWithPath: $0.path).standardizedFileURL.path }) {
                library.folders[index].bookmark = bookmark
                continue
            }
            library.folders.append(CarfoFolder(path: standardized.path, bookmark: bookmark))
        }
        persist(); scanFolders(autoIndex: true)
    }
    func removeFolder(_ folder: CarfoFolder) {
        guard !isWorking else { return }
        library.folders.removeAll { $0.id == folder.id }
        library.clips.removeAll { $0.folderID == folder.id }
        if folderFilter == folder.id { folderFilter = nil }
        persist(); scheduleSearch()
    }
    func scanFolders(autoIndex: Bool = false) {
        guard !isWorking else { return }
        let folders = library.folders
        guard !folders.isEmpty else { pickFolder(); return }
        folderAccessError = nil
        work = WorkProgress(title: "Membaca koleksi...", detail: "Mencari file media dan menyiapkan thumbnail")
        workTask = Task {
            defer { work = nil; workTask = nil; scheduleSearch() }
            var issues: [String] = []
            for folder in folders {
                do {
                    try Task.checkCancellation()
                    work?.detail = folder.name
                    let report = try await LibraryScanner.scan(folder: folder, previous: library.clips, thumbnails: store.thumbnailDirectory)
                    library.clips.removeAll { $0.folderID == folder.id }
                    library.clips += report.clips
                    issues += report.errors
                    persist()
                } catch is CancellationError { return }
                catch {
                    issues.append("\(folder.name): \(error.localizedDescription)")
                    if !FileManager.default.isReadableFile(atPath: folder.path) { folderAccessError = "Folder \(folder.name) tidak dapat dibuka. Pilih ulang folder untuk memperbarui aksesnya." }
                }
            }
            if !issues.isEmpty { notice = issues.prefix(3).joined(separator: "\n") }
            // Auto-index after scan if requested and there are un-indexed or un-transcribed clips
            if autoIndex && installation.isAvailable {
                let hasUnindexed = library.clips.contains { !$0.isIndexed || (installation.canTranscribe && $0.needsTranscript) }
                if hasUnindexed {
                    // Must schedule on main actor since we're already on it
                    Task { @MainActor in self.startIndexing() }
                }
            }
        }
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
        guard !candidates.isEmpty else { notice = "Semua file sudah diindeks. Pindai ulang folder untuk menemukan file baru."; return }
        let total = candidates.reduce(0) { count, clip in
            switch clip.mediaType {
            case .image:
                return count + clip.segments.filter { $0.visualEmbedding == nil }.count
            case .audio:
                return count + clip.segments.filter { $0.audioEmbedding == nil }.count
                    + (canTranscribe && clip.hasAudio && clip.needsTranscript ? 1 : 0)
            case .video:
                return count + clip.segments.filter { $0.visualEmbedding == nil || (clip.hasAudio && $0.audioEmbedding == nil) }.count
                    + (canTranscribe && clip.hasAudio && clip.needsTranscript ? 1 : 0)
            }
        }
        work = WorkProgress(title: "Mengindeks koleksi", detail: "Menyiapkan indeks...", total: total)
        workTask = Task(priority: .utility) {
            defer {
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
                            persist()
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            library.clips[clipIndex].transcribedAt = Date()
                            library.clips[clipIndex].indexError = error.localizedDescription
                            persist()
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
                            persist()
                        }
                        library.clips[clipIndex].indexedAt = Date(); library.clips[clipIndex].indexError = nil
                        persist()
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
                            persist()
                        }
                        library.clips[clipIndex].indexedAt = Date(); library.clips[clipIndex].indexError = nil
                        persist()
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
                            persist()
                        }
                        if candidate.hasAudio && segment.audioEmbedding == nil {
                            let wav = temporary.appendingPathComponent("audio.wav")
                            try await MediaProcessor.audio(url: candidate.url, segment: segment, destination: wav)
                            segment.audioEmbedding = try await engine.embed(audio: wav)
                        }
                        library.clips[clipIndex].segments[segmentIndex] = segment
                        work?.completed += 1
                        persist()
                    }
                    library.clips[clipIndex].indexedAt = Date(); library.clips[clipIndex].indexError = nil
                    persist()
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
        for url in accessURLs { url.stopAccessingSecurityScopedResource() }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        Task { await engine.stop() }
    }
}
