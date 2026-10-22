import AppKit
import AVKit
import CarfoCore
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let carfoFocusSearch = Notification.Name("CarfoFocusSearch")
    static let footageFocusSearch = carfoFocusSearch
}

struct SearchView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var thumbnails = ThumbnailCache.shared
    var resize: (Bool) -> Void
    @State private var searchFocused = true
    @Environment(\.colorScheme) private var scheme
    private var expanded: Bool { model.hasQuery }
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 13) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16.5, weight: .light))
                    .foregroundStyle(scheme == .dark ? Color(red: 0.60, green: 0.65, blue: 0.73) : Color(red: 0.49, green: 0.53, blue: 0.60))
                SearchTextField(model: model, focused: $searchFocused)
                    .frame(height: 28)
                Button {
                    if !model.query.isEmpty {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            model.query = ""
                        }
                    } else {
                        model.hideSearch?()
                    }
                } label: { SearchEscBadge() }
                    .buttonStyle(.plain)
                    .help("Tutup pencarian (Escape)")
                    .accessibilityLabel("Tutup pencarian")
            }
            .padding(.horizontal, 20)
            .frame(height: 54)
            .background(WindowDragBackground())
            .modifier(SearchBarSurface())

            if expanded {
                VStack(spacing: 0) {
                    toolbar
                    Divider().opacity(0.55)
                    if !model.results.isEmpty { resultsView.frame(height: 354) }
                    else if model.isSearching { loadingView.frame(height: 354) }
                    else { emptyView.frame(height: 354) }
                    Divider().opacity(0.55)
                    footer
                }
                .modifier(GlassSurface())
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .offset(y: -18))
                            .combined(with: .scale(scale: 0.96, anchor: .top)),
                        removal: .opacity
                            .combined(with: .offset(y: -18))
                            .combined(with: .scale(scale: 0.96, anchor: .top))
                    )
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .font(CarfoDesign.font(12))
        .tint(CarfoDesign.action)
        .preferredColorScheme(model.appearance.colorScheme)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: expanded)
        .onChange(of: expanded) { _, value in resize(value) }
        .onAppear { model.recordStartupStage("searchViewAppearedMS") }
        .onExitCommand {
            if !model.query.isEmpty {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    model.query = ""
                }
            } else {
                model.hideSearch?()
            }
        }
    }
    private var toolbar: some View {
        HStack(spacing: 14) {
            ForEach(SearchMode.allCases) { mode in
                Button { model.mode = mode } label: {
                    Label(mode.title, systemImage: mode.symbol)
                        .font(CarfoDesign.font(11, weight: model.mode == mode ? .medium : .regular))
                        .foregroundStyle(model.mode == mode ? CarfoDesign.action : CarfoDesign.secondary)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(
                            model.mode == mode
                                ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.02))
                                : nil
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(model.mode == mode ? CarfoDesign.action : Color.clear, lineWidth: 1.2)
                        )
                }
                .buttonStyle(.plain).accessibilityAddTraits(model.mode == mode ? .isSelected : [])
                .help(modeHelp(mode))
            }
            Spacer(minLength: 2)
            Menu {
                Button("Semua folder") { model.folderFilter = nil }
                ForEach(model.library.folders) { folder in Button(folder.name) { model.folderFilter = folder.id } }
                Divider()
                Button("Tambah folder...") { model.pickFolder() }.disabled(model.isWorking)
            } label: {
                Label(model.library.folders.first { $0.id == model.folderFilter }?.name ?? "Semua folder", systemImage: "folder")
                    .font(CarfoDesign.font(10)).foregroundStyle(CarfoDesign.secondary).lineLimit(1)
            }.menuStyle(.borderlessButton).tint(CarfoDesign.accent).fixedSize().frame(maxWidth: 160)
        }.padding(.horizontal, 15).frame(height: 44)
    }
    private func modeHelp(_ mode: SearchMode) -> String {
        switch mode {
        case .video: return "Cari video secara keseluruhan di Mac ini"
        case .visual: return "Cari adegan, objek, dan suasana dari gambar"
        case .dialogue: return "Cari isi percakapan dari audio lokal"
        case .sound: return "Cari bunyi dan suasana dari audio lokal"
        }
    }
    private var startingDescription: String {
        switch model.mode {
        case .video: return "Deskripsikan video, aksi, adegan, atau peristiwa yang kamu cari."
        case .visual: return "Deskripsikan objek, latar visual, atau gambar yang kamu cari."
        case .dialogue: return "Ketik kalimat atau topik percakapan yang diucapkan dalam video."
        case .sound: return "Deskripsikan bunyi, musik, atau suasana audio yang kamu cari."
        }
    }
    private var emptyDetail: String {
        switch model.mode {
        case .video:
            return "Coba kata kunci yang lebih umum atau periksa cakupan folder footage."
        case .visual:
            return "Coba deskripsi objek atau gambar visual lain, atau pastikan folder berisi file gambar (.png, .jpg, .svg, dll)."
        case .dialogue:
            return "Kata atau kalimat yang diucapkan belum ditemukan. Pastikan video memiliki trek suara percakapan."
        case .sound:
            return "Suara atau suasana audio belum ditemukan. Coba kata kunci suara lain seperti hujan atau burung."
        }
    }
    private var startingView: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let error = model.folderAccessError {
                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark").font(.system(size: 23, weight: .light))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Folder tidak bisa dibuka").font(CarfoDesign.font(13, weight: .medium))
                        Text(error).font(CarfoDesign.font(11)).foregroundStyle(CarfoDesign.secondary)
                    }
                    Spacer()
                    Button("Pilih folder") { model.pickFolder() }.buttonStyle(.borderedProminent).controlSize(.small)
                }
            } else if model.library.folders.isEmpty || model.library.clips.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "folder.badge.plus").font(.system(size: 23, weight: .light)).foregroundStyle(CarfoDesign.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.library.folders.isEmpty ? "Mulai dari folder footage Anda" : "Belum ada file media di koleksi ini").font(CarfoDesign.font(13, weight: .medium))
                        Text("Pilih folder. File asli tetap di tempatnya.").font(CarfoDesign.font(11)).foregroundStyle(CarfoDesign.secondary)
                    }
                    Spacer()
                    Button("Pilih folder") { model.pickFolder() }.buttonStyle(.borderedProminent).controlSize(.small)
                }
            } else {
                Text(startingDescription)
                    .font(CarfoDesign.font(12)).foregroundStyle(CarfoDesign.secondary)
                HStack(spacing: 7) {
                    Text(model.recentQueries.isEmpty ? "Contoh:" : "Terakhir:").font(CarfoDesign.font(10)).foregroundStyle(CarfoDesign.secondary)
                    ForEach(Array((model.recentQueries.isEmpty ? suggestions : model.recentQueries).prefix(2)), id: \.self) { query in
                        Button { model.query = query } label: {
                            Label(query, systemImage: model.recentQueries.isEmpty ? "magnifyingglass" : "clock")
                                .font(CarfoDesign.font(10)).lineLimit(1)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain)
                    }
                }
            }

            if let work = model.work {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini)
                    Text(work.detail).lineLimit(1)
                    Spacer()
                    Button("Hentikan") { model.cancelWork() }.buttonStyle(.link).tint(CarfoDesign.accent)
                }.font(CarfoDesign.font(10)).foregroundStyle(CarfoDesign.secondary)
            } else if !model.installation.isAvailable {
                Label("Model AI lokal belum terdeteksi", systemImage: "exclamationmark.triangle")
                    .font(CarfoDesign.font(10)).foregroundStyle(CarfoDesign.secondary)
            }
        }.padding(.horizontal, 24).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var suggestions: [String] {
        switch model.mode {
        case .video: return ["jalan santai", "pemandangan alam"]
        case .visual: return ["jalan berkabut", "ombak pantai"]
        case .dialogue: return ["kabutnya mulai turun", "kita jalan dulu"]
        case .sound: return ["suara hujan", "burung berkicau"]
        }
    }
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Mencari footage...").font(CarfoDesign.font(13, weight: .medium))
            Text("Memproses pencarian di Mac ini.").font(CarfoDesign.font(11)).foregroundStyle(CarfoDesign.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var emptyView: some View {
        Group {
            if let error = model.folderAccessError {
                StateMessage(symbol: "folder.badge.questionmark", title: "Folder tidak bisa dibuka", detail: error, actionTitle: "Pilih folder") { model.pickFolder() }
            } else if let error = model.searchError {
                StateMessage(symbol: "exclamationmark.triangle", title: "Pencarian lokal perlu diperiksa", detail: error, actionTitle: "Buka pengaturan") { model.showSettings?() }
            } else if model.library.folders.isEmpty {
                StateMessage(symbol: "folder.badge.plus", title: "Folder footage belum dipilih", detail: "Tambahkan folder agar Carfo dapat mencari video di Mac ini.", actionTitle: "Pilih folder") { model.pickFolder() }
            } else if model.indexedCount == 0 && model.isWorking {
                StateMessage(symbol: "internaldrive", title: "Sedang mengindeks koleksi...", detail: "Nama file sudah bisa dicari langsung. Indexing isi berjalan otomatis di latar belakang.", actionTitle: nil)
            } else if model.mode == .dialogue && model.transcribedCount == 0 && model.isWorking {
                StateMessage(
                    symbol: "quote.bubble",
                    title: "Dialog sedang ditranskrip...",
                    detail: "Transkripsi audio lokal sedang berjalan otomatis di latar belakang.",
                    actionTitle: nil
                )
            } else if model.mode == .visual && !model.library.clips.contains(where: \.isImage) {
                StateMessage(symbol: "photo.badge.plus", title: "Belum ada gambar", detail: "Folder yang dipilih belum memiliki file gambar (.png, .jpg, .svg, dll).", actionTitle: "Pilih folder") { model.pickFolder() }
            } else if model.mode == .sound && !model.library.clips.contains(where: { $0.isAudio || ($0.isVideo && $0.hasAudio) }) {
                StateMessage(symbol: "waveform.badge.plus", title: "Belum ada audio", detail: "Folder yang dipilih belum memiliki file audio (.mp3, .wav, dll) atau video bersuara.", actionTitle: "Pilih folder") { model.pickFolder() }
            } else {
                let notFoundTitle: String = {
                    switch model.mode {
                    case .video: return "Video belum ditemukan"
                    case .visual: return "Gambar belum ditemukan"
                    case .dialogue: return "Dialog belum ditemukan"
                    case .sound: return "Suara belum ditemukan"
                    }
                }()
                StateMessage(symbol: "magnifyingglass", title: notFoundTitle, detail: emptyDetail, actionTitle: "Ubah pencarian") { NotificationCenter.default.post(name: .carfoFocusSearch, object: nil) }
            }
        }
    }
    private var resultsView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if model.mode == .dialogue {
                    HStack {
                        Text("Kecocokan dialog").font(CarfoDesign.font(12, weight: .semibold)).foregroundStyle(Color.primary)
                        Spacer()
                        if model.isSearching {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text("Mencari semantik...")
                            }
                            .font(CarfoDesign.font(11)).foregroundStyle(CarfoDesign.secondary)
                        } else {
                            Text(model.results.first?.isSampleData == true ? "Data contoh" : "\(model.results.count) dialog")
                                .font(CarfoDesign.font(11)).foregroundStyle(CarfoDesign.secondary)
                        }
                    }.padding(.horizontal, 8)
                } else {
                    HStack {
                        Text("Carfo")
                        Spacer()
                        if model.isSearching {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text(model.semanticSearch ? "\(model.results.count) hasil" : "Nama file · mencari semantik...")
                            }
                            .font(CarfoDesign.font(10)).foregroundStyle(CarfoDesign.secondary)
                        } else {
                            Text(model.semanticSearch ? "\(model.results.count) hasil terdekat" : "Nama file")
                                .font(CarfoDesign.font(10)).foregroundStyle(CarfoDesign.secondary)
                        }
                    }.padding(.horizontal, 8)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(model.results) { result in
                                if model.mode == .dialogue {
                                    DialogResultRow(model: model, result: result).id(result.id)
                                } else {
                                    ResultRow(model: model, result: result).id(result.id)
                                }
                            }
                        }
                    }.onChange(of: model.selectedID) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
                }
                if model.mode == .dialogue {
                    Text("Waktu = posisi ucapan di video (mm:ss), bukan durasi footage.")
                        .font(CarfoDesign.font(10))
                        .foregroundStyle(CarfoDesign.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
                if let searchError = model.searchError {
                    Text(searchError).font(CarfoDesign.font(10)).foregroundStyle(CarfoDesign.secondary).lineLimit(1)
                }
            }.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10).frame(width: model.mode == .dialogue ? 332 : 302)
            Divider().opacity(0.55)
            if let selected = model.selected {
                if model.mode == .dialogue {
                    dialoguePreview(selected)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    preview(selected)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
        .onKeyPress(.space) { model.togglePreview(); return .handled }
    }
    private func thumbnailImage(for clip: FootageClip) -> NSImage? {
        clipThumbnailImage(for: clip, thumbnailDirectory: model.store.thumbnailDirectory)
    }
    private func dialoguePreview(_ selected: SearchResult) -> some View {
        let thumbImage = thumbnailImage(for: selected.clip)
        return VStack(alignment: .leading, spacing: 12) {
            MoviePreview(player: model.player, fileURL: selected.clip.url, thumbnail: thumbImage)
                .frame(maxWidth: .infinity)
                .frame(height: 184)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .accessibilityLabel("Pratinjau \(selected.clip.name)")

            VStack(alignment: .leading, spacing: 3) {
                Text(selected.clip.name)
                    .font(CarfoDesign.font(14, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: "folder").font(.system(size: 11))
                    Text(selected.clip.relativePath.isEmpty ? "Lokal" : selected.clip.relativePath)
                        .font(CarfoDesign.font(11))
                        .lineLimit(1)
                }.foregroundStyle(CarfoDesign.secondary)
            }
            .contentShape(Rectangle())
            .onDrag({
                makeDragItemProvider(for: selected.clip.url, thumbnail: thumbImage)
            }, preview: {
                DragItemPreview(name: selected.clip.name, iconName: "film", thumbnail: thumbImage)
            })

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(selected.isSampleData ? "Transkrip · contoh" : "Transkrip")
                        .font(CarfoDesign.font(11.5, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    let cueStart = selected.matchedCue?.start ?? selected.segment?.start ?? 0
                    let cueEnd = selected.matchedCue?.end ?? selected.segment?.end ?? cueStart + 4
                    Text("\(timecode(cueStart))–\(timecode(cueEnd))")
                        .font(CarfoDesign.font(11.5, weight: .semibold))
                        .foregroundStyle(CarfoDesign.action)
                }

                if selected.contextCues.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 24))
                            .foregroundStyle(CarfoDesign.secondary)
                        Text("Belum ada transkrip ucapan")
                            .font(CarfoDesign.font(12, weight: .medium))
                        Text("Video ini belum ditranskrip atau tidak memiliki ucapan.")
                            .font(CarfoDesign.font(10.5))
                            .foregroundStyle(CarfoDesign.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    VStack(spacing: 4) {
                        ForEach(selected.contextCues) { cue in
                            let isMatch = cue.id == selected.matchedCue?.id
                            HStack(alignment: .top, spacing: 10) {
                                Text(timecode(cue.start))
                                    .font(CarfoDesign.font(11, weight: isMatch ? .bold : .regular))
                                    .foregroundStyle(isMatch ? CarfoDesign.action : CarfoDesign.secondary)
                                    .frame(width: 42, alignment: .leading)
                                Text(isMatch ? "“\(cue.text)”" : cue.text)
                                    .font(CarfoDesign.font(11.5, weight: isMatch ? .medium : .regular))
                                    .foregroundStyle(isMatch ? Color.primary : CarfoDesign.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, isMatch ? 8 : 4)
                            .padding(.vertical, isMatch ? 6 : 3)
                            .background(
                                isMatch
                                    ? RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.blue.opacity(scheme == .dark ? 0.24 : 0.10))
                                    : nil
                            )
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Button { model.togglePreview() } label: { Label(model.isPlaying ? "Jeda preview" : "Putar preview", systemImage: model.isPlaying ? "pause.fill" : "play.fill").font(CarfoDesign.font(10)) }.buttonStyle(.link).tint(CarfoDesign.accent)
                Spacer()
                Button { model.openSelected() } label: { HStack(spacing: 9) { Text("Buka footage"); Text("↵").opacity(0.85) }.font(CarfoDesign.font(11, weight: .medium)) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
    }
    @ViewBuilder
    private func imagePreviewView(_ selected: SearchResult, thumbImage: NSImage?) -> some View {
        let previewImage = ThumbnailCache.shared.image(for: selected.clip.url, targetSize: CGSize(width: 640, height: 480), version: selected.clip.modifiedAt.timeIntervalSinceReferenceDate) ?? thumbImage
        if let previewImage {
            Image(nsImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity).frame(height: 174)
                .background(.black, in: RoundedRectangle(cornerRadius: 6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Pratinjau \(selected.clip.name)")
        } else {
            Image(systemName: "photo")
                .font(.system(size: 40))
                .foregroundStyle(CarfoDesign.secondary)
                .frame(maxWidth: .infinity).frame(height: 174)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func preview(_ selected: SearchResult) -> some View {
        let thumbImage = thumbnailImage(for: selected.clip)
        let mediaIcon: String = selected.clip.isImage ? "photo" : selected.clip.isAudio ? "waveform" : "film"

        return VStack(alignment: .leading, spacing: 10) {
            if selected.clip.isImage {
                // Image preview: show the actual image and make it draggable
                imagePreviewView(selected, thumbImage: thumbImage)
                    .contentShape(Rectangle())
                    .onDrag({
                        makeDragItemProvider(for: selected.clip.url, thumbnail: thumbImage)
                    }, preview: {
                        DragItemPreview(name: selected.clip.name, iconName: mediaIcon, thumbnail: thumbImage)
                    })
                    .help("Klik & tarik gambar ini ke mana saja")
            } else if selected.clip.isAudio {
                // Audio preview: waveform icon with draggable surface
                VStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(CarfoDesign.accent)
                    Text(selected.clip.name)
                        .font(CarfoDesign.font(11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(CarfoDesign.secondary)
                }
                .frame(maxWidth: .infinity).frame(height: 174)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .accessibilityLabel("Pratinjau audio \(selected.clip.name)")
                .onDrag({
                    makeDragItemProvider(for: selected.clip.url, thumbnail: nil)
                }, preview: {
                    DragItemPreview(name: selected.clip.name, iconName: mediaIcon, thumbnail: nil)
                })
                .help("Klik & tarik audio ini ke mana saja")
            } else {
                // Video preview: clean and directly draggable
                MoviePreview(player: model.player, fileURL: selected.clip.url, thumbnail: thumbImage)
                    .frame(maxWidth: .infinity).frame(height: 174)
                    .background(.black, in: RoundedRectangle(cornerRadius: 6)).clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Pratinjau \(selected.clip.name)")
            }

            // File info
            VStack(alignment: .leading, spacing: 3) {
                Text(selected.clip.name).font(CarfoDesign.font(13, weight: .semibold)).lineLimit(1).help(selected.clip.name)
                Text(selected.clip.relativePath).font(CarfoDesign.font(10)).foregroundStyle(CarfoDesign.secondary).lineLimit(1).help(selected.clip.path)
            }
            .contentShape(Rectangle())
            .onDrag({
                makeDragItemProvider(for: selected.clip.url, thumbnail: thumbImage)
            }, preview: {
                DragItemPreview(name: selected.clip.name, iconName: mediaIcon, thumbnail: thumbImage)
            })

            HStack(spacing: 10) {
                if selected.clip.isImage {
                    Text("\(selected.clip.width) × \(selected.clip.height)")
                    Text(selected.clip.url.pathExtension.uppercased())
                } else if selected.clip.isAudio {
                    Text(timecode(selected.clip.duration))
                    Text(selected.clip.url.pathExtension.uppercased())
                } else {
                    Text("\(selected.clip.width) × \(selected.clip.height)")
                    Text("\(Int(selected.clip.frameRate.rounded())) fps")
                    Text(selected.segment.map { "\(timecode($0.start))–\(timecode($0.end))" } ?? timecode(selected.clip.duration))
                }
            }.font(CarfoDesign.font(10)).foregroundStyle(CarfoDesign.secondary).lineLimit(1).minimumScaleFactor(0.85)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if !selected.clip.isImage {
                    Button { model.togglePreview() } label: { Label(model.isPlaying ? "Jeda preview" : "Putar preview", systemImage: model.isPlaying ? "pause.fill" : "play.fill").font(CarfoDesign.font(10)) }.buttonStyle(.link).tint(CarfoDesign.accent)
                }
                Spacer()
                Button { model.openSelected() } label: { HStack(spacing: 9) { Text(selected.clip.isImage ? "Buka gambar" : selected.clip.isAudio ? "Buka audio" : "Buka footage"); Text("↵").opacity(0.85) }.font(CarfoDesign.font(11, weight: .medium)) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
    }
    private var footer: some View {
        HStack(spacing: 12) {
            if expanded {
                if model.mode == .dialogue {
                    HStack(spacing: 5) { Keycap(text: "↑ ↓"); Text("Pilih dialog") }
                    HStack(spacing: 5) { Keycap(text: "spasi"); Text("Putar dari waktu") }
                    HStack(spacing: 5) { Keycap(text: "↵"); Text("Buka di waktu") }
                } else {
                    HStack(spacing: 5) { Keycap(text: "↑ ↓"); Text("Pilih") }
                    HStack(spacing: 5) { Keycap(text: "spasi"); Text("Preview") }.help("Tekan Tab untuk berpindah ke hasil, lalu Spasi. ⌃P juga memutar preview.")
                    HStack(spacing: 5) { Keycap(text: "↵"); Text("Buka") }
                }
            } else {
                HStack(spacing: 6) { Keycap(text: model.shortcut.label); Text("Buka dari mana saja") }
            }
            Spacer(minLength: 8)
            Button { model.showSettings?() } label: {
                Text(model.statusText).lineLimit(1)
            }.buttonStyle(.plain).help("Buka pengaturan Carfo")
        }.font(CarfoDesign.font(9.5)).foregroundStyle(CarfoDesign.secondary).padding(.horizontal, 20).frame(height: 42)
            .background(.primary.opacity(0.025))
    }
}

final class DraggablePlayerView: AVPlayerView, NSDraggingSource {
    var fileURL: URL?
    var thumbnail: NSImage?
    private var mouseDownPoint: NSPoint?
    private var isDragging = false

    override var mouseDownCanMoveWindow: Bool { false }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }

        // If clicking on the inline controls bar (bottom ~38pt), let controls receive click
        if localPoint.y <= 38 {
            if let controlSubview = super.hitTest(point), controlSubview !== self {
                return controlSubview
            }
        }
        // In the main video area, return self so DraggablePlayerView controls dragging
        return self
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let start = mouseDownPoint, let url = fileURL else {
            super.mouseDragged(with: event)
            return
        }

        let current = event.locationInWindow
        let distance = hypot(current.x - start.x, current.y - start.y)
        if distance > 4 {
            isDragging = true
            mouseDownPoint = nil

            let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
            let dragSize = NSSize(width: 80, height: 50)
            let dragImage = thumbnail ?? snapshot()
            let mouseLocation = convert(event.locationInWindow, from: nil)
            let dragFrame = NSRect(
                x: mouseLocation.x - dragSize.width / 2,
                y: mouseLocation.y - dragSize.height / 2,
                width: dragSize.width,
                height: dragSize.height
            )
            draggingItem.setDraggingFrame(dragFrame, contents: dragImage)
            beginDraggingSession(with: [draggingItem], event: event, source: self)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !isDragging && mouseDownPoint != nil {
            mouseDownPoint = nil
            // Single click toggles play/pause on the video
            if let player = player {
                if player.timeControlStatus == .playing {
                    player.pause()
                } else {
                    player.play()
                }
            }
        }
        isDragging = false
        super.mouseUp(with: event)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
    }

    private func snapshot() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        draw(bounds)
        image.unlockFocus()
        return image
    }
}

private struct MoviePreview: NSViewRepresentable {
    let player: AVPlayer
    var fileURL: URL? = nil
    var thumbnail: NSImage? = nil

    func makeNSView(context: Context) -> DraggablePlayerView {
        let view = DraggablePlayerView()
        view.player = player
        view.fileURL = fileURL
        view.thumbnail = thumbnail
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ view: DraggablePlayerView, context: Context) {
        view.player = player
        view.fileURL = fileURL
        view.thumbnail = thumbnail
    }
}

private struct DialogResultRow: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var thumbnails = ThumbnailCache.shared
    let result: SearchResult
    private var selected: Bool { model.selectedID == result.id }

    var body: some View {
        let thumbImage = clipThumbnailImage(for: result.clip, thumbnailDirectory: model.store.thumbnailDirectory)

        HStack(alignment: .top, spacing: 14) {
            Text(timecode(result.matchedCue?.start ?? result.segment?.start ?? 0))
                .font(CarfoDesign.font(13.5, weight: .bold))
                .foregroundStyle(selected ? Color.white : CarfoDesign.action)
                .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                if let cue = result.matchedCue {
                    Text("“\(cue.text)”")
                        .font(CarfoDesign.font(12.5, weight: .regular))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(result.clip.name)
                        .font(CarfoDesign.font(12, weight: .medium))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .lineLimit(1)
                        .onDrag({
                            makeDragItemProvider(for: result.clip.url, thumbnail: thumbImage)
                        }, preview: {
                            DragItemPreview(name: result.clip.name, iconName: "film", thumbnail: thumbImage)
                        })
                    Text("Belum ditranskrip")
                        .font(CarfoDesign.font(10))
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : CarfoDesign.secondary)
                }

                if result.matchedCue != nil {
                    Text(result.clip.name)
                        .font(CarfoDesign.font(11))
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : CarfoDesign.secondary)
                        .lineLimit(1)
                        .onDrag({
                            makeDragItemProvider(for: result.clip.url, thumbnail: thumbImage)
                        }, preview: {
                            DragItemPreview(name: result.clip.name, iconName: "film", thumbnail: thumbImage)
                        })
                }
            }

            Spacer(minLength: 4)

            if selected {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? CarfoDesign.action : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            model.select(result.id)
        }
        .onDrag({
            makeDragItemProvider(for: result.clip.url, thumbnail: thumbImage)
        }, preview: {
            DragItemPreview(name: result.clip.name, iconName: "film", thumbnail: thumbImage)
        })
        .contextMenu {
            Button("Buka footage") { model.select(result.id); model.openSelected() }
            Button("Tampilkan di Finder") { model.select(result.id); model.revealSelected() }
            Button("Salin kutipan") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.matchedCue?.text ?? result.clip.name, forType: .string)
            }
        }
    }
}

private struct ResultRow: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var thumbnails = ThumbnailCache.shared
    let result: SearchResult
    private var selected: Bool { model.selectedID == result.id }
    private var mediaIcon: String {
        switch result.clip.mediaType {
        case .image: return "photo"
        case .audio: return "waveform"
        case .video: return "film"
        }
    }
    var body: some View {
        let thumbImage = clipThumbnailImage(for: result.clip, thumbnailDirectory: model.store.thumbnailDirectory)

        HStack(spacing: 9) {
            if result.clip.isImage {
                if let thumbImage {
                    Image(nsImage: thumbImage).resizable().aspectRatio(contentMode: .fill).frame(width: 48, height: 32).clipped().clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "photo").frame(width: 48, height: 32).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                }
            } else if result.clip.isAudio {
                Image(systemName: "waveform")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Color.white : CarfoDesign.accent)
                    .frame(width: 48, height: 32)
                    .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
            } else {
                if let thumbImage {
                    Image(nsImage: thumbImage).resizable().aspectRatio(contentMode: .fill).frame(width: 48, height: 32).clipped().clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "film").frame(width: 48, height: 32).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(result.clip.name)
                    .font(CarfoDesign.font(11, weight: .medium))
                    .lineLimit(1)
                    .onDrag({
                        makeDragItemProvider(for: result.clip.url, thumbnail: thumbImage)
                    }, preview: {
                        DragItemPreview(name: result.clip.name, iconName: mediaIcon, thumbnail: thumbImage)
                    })
                HStack(spacing: 4) {
                    if result.clip.isImage {
                        Text("\(result.clip.width)×\(result.clip.height) · \(model.library.folders.first { $0.id == result.clip.folderID }?.name ?? "Lokal")")
                    } else if result.clip.isAudio {
                        Text("\(timecode(result.segment?.start ?? 0))–\(timecode(result.segment?.end ?? result.clip.duration)) · \(model.library.folders.first { $0.id == result.clip.folderID }?.name ?? "Lokal")")
                    } else {
                        Text("\(timecode(result.segment?.start ?? 0))–\(timecode(result.segment?.end ?? result.clip.duration)) · \(model.library.folders.first { $0.id == result.clip.folderID }?.name ?? "Lokal")")
                    }
                }
                .font(CarfoDesign.font(9)).lineLimit(1).opacity(selected ? 0.9 : 0.75)
            }
            Spacer(minLength: 0)
            if selected { Image(systemName: "return").font(.system(size: 10)) }
        }
        .padding(.horizontal, 7).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? CarfoDesign.action : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            model.select(result.id)
        }
        .onDrag({
            makeDragItemProvider(for: result.clip.url, thumbnail: thumbImage)
        }, preview: {
            DragItemPreview(name: result.clip.name, iconName: mediaIcon, thumbnail: thumbImage)
        })
        .contextMenu {
            Button(result.clip.isImage ? "Buka gambar" : result.clip.isAudio ? "Buka audio" : "Buka footage") { model.select(result.id); model.openSelected() }
            Button("Tampilkan di Finder") { model.select(result.id); model.revealSelected() }
            Button("Salin lokasi file") { model.select(result.id); model.copySelectedPath() }
        }
    }
}

struct SearchBarSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background {
                if scheme == .dark {
                    ZStack {
                        VisualEffect(material: .popover)
                        Color(red: 0.12, green: 0.13, blue: 0.16).opacity(0.98)
                    }
                } else {
                    Color.white
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        scheme == .dark
                            ? Color.white.opacity(0.14)
                            : Color(red: 0.87, green: 0.89, blue: 0.92),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(scheme == .dark ? 0.35 : 0.08),
                radius: 16,
                x: 0,
                y: 5
            )
            .shadow(
                color: Color.black.opacity(scheme == .dark ? 0.15 : 0.03),
                radius: 2,
                x: 0,
                y: 1
            )
    }
}

struct SearchEscBadge: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text("esc")
            .font(CarfoDesign.font(11.5, weight: .regular))
            .foregroundStyle(scheme == .dark ? Color(red: 0.65, green: 0.70, blue: 0.78) : Color(red: 0.38, green: 0.42, blue: 0.48))
            .padding(.horizontal, 8.5)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.015))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        scheme == .dark
                            ? Color.white.opacity(0.20)
                            : Color(red: 0.76, green: 0.79, blue: 0.84),
                        lineWidth: 1
                    )
            )
    }
}

final class CarfoSearchField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        updateCursorColor()
        return ok
    }

    override func selectText(_ sender: Any?) {
        super.selectText(sender)
        updateCursorColor()
    }

    private func updateCursorColor() {
        if let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = NSColor.systemBlue
        }
    }
}

private struct SearchTextField: NSViewRepresentable {
    @ObservedObject var model: AppModel
    @Binding var focused: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> CarfoSearchField {
        let field = CarfoSearchField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none

        let font = NSFont(name: "Inter", size: 16) ?? .systemFont(ofSize: 16, weight: .regular)
        field.font = font
        field.textColor = .labelColor

        applyPlaceholder(field)

        field.delegate = context.coordinator
        field.setAccessibilityLabel("Cari footage di Carfo")
        field.setAccessibilityIdentifier("search-field")

        context.coordinator.field = field
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .carfoFocusSearch,
            object: nil,
            queue: .main
        ) { [weak field] _ in
            Task { @MainActor in
                field?.window?.makeFirstResponder(field)
                field?.selectText(nil)
            }
        }

        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: CarfoSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != model.query {
            field.stringValue = model.query
        }
        applyPlaceholder(field)
    }

    private func applyPlaceholder(_ field: NSTextField) {
        let font = NSFont(name: "Inter", size: 16) ?? .systemFont(ofSize: 16, weight: .regular)
        let placeholderColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 180/255, green: 188/255, blue: 200/255, alpha: 1)
                : NSColor(red: 92/255, green: 101/255, blue: 117/255, alpha: 1)
        }
        let text = model.library.folders.isEmpty
            ? "Pilih folder footage di menu bar untuk mulai..."
            : model.mode.placeholder
        field.placeholderAttributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: placeholderColor
            ]
        )
    }

    static func dismantleNSView(_ field: CarfoSearchField, coordinator: Coordinator) {
        if let observer = coordinator.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchTextField
        weak var field: NSTextField?
        var observer: NSObjectProtocol?

        init(_ parent: SearchTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            if let field {
                let hadQuery = parent.model.hasQuery
                let newQuery = field.stringValue
                let willHaveQuery = !newQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if hadQuery != willHaveQuery {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        parent.model.query = newQuery
                    }
                } else {
                    parent.model.query = newQuery
                }
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.focused = true
            if let textView = notification.userInfo?["NSFieldEditor"] as? NSTextView {
                textView.insertionPointColor = NSColor.systemBlue
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.focused = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                parent.model.moveSelection(1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.model.moveSelection(-1)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                    parent.model.revealSelected()
                } else {
                    parent.model.openSelected()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                if !parent.model.query.isEmpty {
                    DispatchQueue.main.async {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            self.parent.model.query = ""
                        }
                    }
                } else {
                    parent.model.hideSearch?()
                }
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Thumbnail Cache & Image Helpers

@MainActor
final class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    @Published private(set) var revision = 0
    private var resolvedKeys: [String: String] = [:]
    private var pending = Set<String>()

    init() {
        cache.countLimit = 300
        cache.totalCostLimit = 64 * 1024 * 1024 // 64 MB
    }

    func image(for url: URL, targetSize: CGSize? = nil, version: Double = 0) -> NSImage? {
        let size = targetSize ?? CGSize(width: 480, height: 480)
        let request = "\(url.path)|\(size.width)x\(size.height)|\(version)"
        let previousKey = resolvedKeys[request]
        let previous = previousKey.flatMap { cache.object(forKey: $0 as NSString) }
        let wasCached = previous != nil
        if pending.insert(request).inserted {
            Task { [weak self] in
                let loaded = await Task.detached(priority: .utility) {
                    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                    let modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
                    let key = request + "|\(modified)|\(attrs?[.size] as? NSNumber ?? 0)"
                    return DecodedThumbnail(key: key, image: key == previousKey && wasCached ? nil : Self.loadDownsampled(url: url, maxPixelSize: max(size.width, size.height) * 2))
                }.value
                guard let self else { return }
                self.pending.remove(request)
                if let image = loaded.image {
                    self.cache.setObject(image, forKey: loaded.key as NSString, cost: Int(image.size.width * image.size.height * 4))
                    self.resolvedKeys[request] = loaded.key
                    if self.resolvedKeys.count > 600 { self.resolvedKeys = [request: loaded.key] }
                    self.revision &+= 1
                } else if loaded.key != previousKey {
                    self.resolvedKeys.removeValue(forKey: request)
                    if wasCached { self.revision &+= 1 }
                }
            }
        }
        return previous
    }

    nonisolated private static func loadDownsampled(url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        return NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width, height: cgThumb.height))
    }
}

private struct DecodedThumbnail: @unchecked Sendable {
    let key: String
    let image: NSImage?
}

@MainActor
func clipThumbnailImage(for clip: FootageClip, thumbnailDirectory: URL, targetSize: CGSize = CGSize(width: 96, height: 64)) -> NSImage? {
    if let thumbnail = clip.thumbnail {
        let thumbURL = thumbnailDirectory.appendingPathComponent(thumbnail)
        return ThumbnailCache.shared.image(for: thumbURL, targetSize: targetSize, version: clip.modifiedAt.timeIntervalSinceReferenceDate)
    }
    if clip.isImage {
        return ThumbnailCache.shared.image(for: clip.url, targetSize: targetSize, version: clip.modifiedAt.timeIntervalSinceReferenceDate)
    }
    return nil
}

// MARK: - Drag & Drop Helpers & Components

func makeDragItemProvider(for url: URL, thumbnail: NSImage? = nil) -> NSItemProvider {
    let provider = NSItemProvider(object: url as NSURL)
    provider.suggestedName = url.deletingPathExtension().lastPathComponent
    let type = UTType(filenameExtension: url.pathExtension) ?? .item
    provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
        completion(url, false, nil)
        return nil
    }
    if let data = thumbnail?.tiffRepresentation {
        provider.previewImageHandler = { (completion, _, _) in
            completion?(NSImage(data: data), nil)
        }
    }
    return provider
}

struct DragItemPreview: View {
    let name: String
    let iconName: String
    let thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 9) {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 32)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 16))
                    .frame(width: 44, height: 32)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
            Text(name)
                .font(CarfoDesign.font(12, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

struct WindowDragBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragView {
        WindowDragView()
    }
    func updateNSView(_ nsView: WindowDragView, context: Context) {}
}
