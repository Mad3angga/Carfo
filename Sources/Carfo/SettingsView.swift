import AppKit
import CarfoCore
import SwiftUI

struct CarfoAppLogo: View {
    var size: CGFloat = 36
    private var image: NSImage? {
        if let url = Bundle.module.url(forResource: "CarfoIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        let fallback = URL(fileURLWithPath: "Assets/Carfo-icon-transparent.png")
        if let img = NSImage(contentsOf: fallback) {
            return img
        }
        return NSApp.applicationIconImage
    }
    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "film.stack")
                .font(.system(size: size * 0.6, weight: .light))
                .foregroundStyle(CarfoDesign.accent)
                .frame(width: size, height: size)
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var systemScheme

    private var isDark: Bool {
        switch model.appearance {
        case .dark: return true
        case .light: return false
        case .system: return systemScheme == .dark
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Button { model.showSearch?() } label: {
                HStack(spacing: 12) {
                    CarfoAppLogo(size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Carfo")
                            .font(CarfoDesign.font(16, weight: .semibold))
                            .foregroundStyle(Color.primary)
                        Text("Pencarian footage di Mac")
                            .font(CarfoDesign.font(11.5))
                            .foregroundStyle(CarfoDesign.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Buka pencarian Carfo")

            // Tampilan section
            VStack(alignment: .leading, spacing: 8) {
                Text("Tampilan")
                    .font(CarfoDesign.font(13, weight: .semibold))
                    .foregroundStyle(Color.primary)
                CustomThemePicker(model: model, showsBlueBorder: false)
            }

            // Shortcut pencarian row
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 14))
                    .foregroundStyle(CarfoDesign.secondary)
                Text("Shortcut pencarian")
                    .font(CarfoDesign.font(13, weight: .regular))
                    .foregroundStyle(Color.primary)
                Spacer()
                KeycapBadge(text: model.shortcut.label)
                Menu {
                    ForEach(SearchShortcut.allCases) { shortcut in
                        Button {
                            model.shortcut = shortcut
                        } label: {
                            HStack {
                                Text(shortcut.label)
                                if model.shortcut == shortcut {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text("Ubah")
                        .font(CarfoDesign.font(13, weight: .medium))
                        .foregroundStyle(CarfoDesign.action)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            // Buka saat login row
            HStack {
                Text("Buka saat login")
                    .font(CarfoDesign.font(13, weight: .regular))
                    .foregroundStyle(Color.primary)
                Spacer()
                Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Divider()
                .overlay(isDark ? Color.white.opacity(0.10) : Color(red: 0.88, green: 0.90, blue: 0.93))

            // Folder footage row
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(CarfoDesign.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Folder footage")
                        .font(CarfoDesign.font(13, weight: .medium))
                        .foregroundStyle(Color.primary)
                    Text(model.library.folders.isEmpty ? "Belum ada folder" : "\(model.library.folders.count) folder · \(model.library.clips.count) file")
                        .font(CarfoDesign.font(11.5))
                        .foregroundStyle(CarfoDesign.secondary)
                }
                Spacer()
                Button {
                    model.pickFolder()
                } label: {
                    Text("Tambah")
                        .font(CarfoDesign.font(13, weight: .medium))
                        .foregroundStyle(CarfoDesign.action)
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking)
            }

            if let work = model.work {
                VStack(alignment: .leading, spacing: 4) {
                    if let fraction = work.fraction {
                        ProgressView(value: fraction).controlSize(.mini)
                    } else {
                        ProgressView().controlSize(.mini)
                    }
                    HStack {
                        Text(work.detail).lineLimit(1)
                        Spacer()
                        Button("Hentikan") { model.cancelWork() }
                            .buttonStyle(.link)
                            .tint(CarfoDesign.accent)
                    }
                    .font(CarfoDesign.font(10))
                    .foregroundStyle(CarfoDesign.secondary)
                }
                .padding(.top, 2)
            }

            Divider()
                .overlay(isDark ? Color.white.opacity(0.10) : Color(red: 0.88, green: 0.90, blue: 0.93))

            // Action rows
            VStack(spacing: 4) {
                menuAction("Pengaturan...", symbol: "switch.2", key: "⌘ ,") {
                    model.showSettings?()
                }
                menuAction("Keluar dari Carfo", symbol: "power", key: "⌘ Q") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(isDark ? Color(red: 0.12, green: 0.13, blue: 0.16) : Color(red: 0.965, green: 0.968, blue: 0.973))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .font(CarfoDesign.font(12))
        .tint(CarfoDesign.action)
        .preferredColorScheme(model.appearance.colorScheme)
    }

    private func menuAction(_ text: String, symbol: String, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .frame(width: 20)
                    .foregroundStyle(CarfoDesign.secondary)
                Text(text)
                    .font(CarfoDesign.font(13))
                    .foregroundStyle(Color.primary)
                Spacer()
                Text(key)
                    .font(CarfoDesign.font(12))
                    .foregroundStyle(CarfoDesign.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var removing: CarfoFolder?
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool {
        switch model.appearance {
        case .dark: return true
        case .light: return false
        case .system: return scheme == .dark
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                // Header Bar
                HStack(alignment: .center, spacing: 14) {
                    CarfoAppLogo(size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Carfo")
                            .font(CarfoDesign.font(22, weight: .semibold))
                            .foregroundStyle(Color.primary)
                        Text("Temukan bagian yang tepat di koleksi footage Anda.")
                            .font(CarfoDesign.font(12))
                            .foregroundStyle(CarfoDesign.secondary)
                    }
                    Spacer()
                    Button {
                        model.showSearch?()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .medium))
                            Text("Buka pencarian")
                                .font(CarfoDesign.font(12, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isDark ? Color.white.opacity(0.10) : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isDark ? Color.white.opacity(0.15) : Color(red: 0.82, green: 0.85, blue: 0.89), lineWidth: 1)
                        )
                        .foregroundStyle(isDark ? Color.white : Color(red: 0.15, green: 0.17, blue: 0.20))
                    }
                    .buttonStyle(.plain)
                }

                // Section 1: Koleksi footage
                VStack(alignment: .leading, spacing: 12) {
                    // Header text
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Koleksi footage")
                                .font(CarfoDesign.font(13.5, weight: .semibold))
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if !model.library.folders.isEmpty {
                                Text("\(model.library.clips.count.formatted()) file dalam \(model.library.folders.count) folder")
                                    .font(CarfoDesign.font(11.5))
                                    .foregroundStyle(CarfoDesign.secondary)
                            }
                        }
                        Text("File asli tetap di folder Anda. Indeks dan thumbnail disimpan di Mac ini.")
                            .font(CarfoDesign.font(11.5))
                            .foregroundStyle(CarfoDesign.secondary)
                    }

                    // White Card for Folders
                    VStack(spacing: 0) {
                        if model.library.folders.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "folder")
                                    .font(.system(size: 20))
                                    .foregroundStyle(CarfoDesign.action)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Belum ada folder")
                                        .font(CarfoDesign.font(13, weight: .medium))
                                    Text("Klik '+ Tambah folder' di bawah untuk menambahkan koleksi footage Anda.")
                                        .font(CarfoDesign.font(11))
                                        .foregroundStyle(CarfoDesign.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        } else {
                            ForEach(Array(model.library.folders.enumerated()), id: \.element.id) { index, folder in
                                if index > 0 {
                                    Divider()
                                        .overlay(isDark ? Color.white.opacity(0.08) : Color(red: 0.90, green: 0.92, blue: 0.94))
                                }
                                HStack(spacing: 14) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 20, weight: .regular))
                                        .foregroundStyle(CarfoDesign.action)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(folder.name)
                                            .font(CarfoDesign.font(13, weight: .medium))
                                            .foregroundStyle(Color.primary)
                                        Text(folder.path)
                                            .font(CarfoDesign.font(11))
                                            .foregroundStyle(CarfoDesign.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .help(folder.path)
                                    }
                                    Spacer()
                                    let clipCount = model.stats.folderCounts[folder.id, default: 0]
                                    Text("\(clipCount.formatted()) file")
                                        .font(CarfoDesign.font(12))
                                        .foregroundStyle(CarfoDesign.secondary)

                                    Button {
                                        NSWorkspace.shared.open(URL(fileURLWithPath: folder.path))
                                    } label: {
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.system(size: 15))
                                            .foregroundStyle(CarfoDesign.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Buka folder di Finder")

                                    Menu {
                                        Button {
                                            NSWorkspace.shared.open(URL(fileURLWithPath: folder.path))
                                        } label: {
                                            Label("Buka di Finder", systemImage: "arrow.up.right.square")
                                        }
                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(folder.path, forType: .string)
                                        } label: {
                                            Label("Salin lokasi folder", systemImage: "doc.on.doc")
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            removing = folder
                                        } label: {
                                            Label("Keluarkan folder", systemImage: "minus.circle")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(CarfoDesign.secondary)
                                            .frame(width: 20, height: 20)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .menuIndicator(.hidden)
                                    .fixedSize()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isDark ? Color(red: 0.14, green: 0.155, blue: 0.18) : Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isDark ? Color.white.opacity(0.10) : Color(red: 0.88, green: 0.90, blue: 0.93), lineWidth: 1)
                    )

                    // Action buttons below folder card
                    HStack {
                        Button {
                            model.pickFolder()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Tambah folder")
                                    .font(CarfoDesign.font(12.5, weight: .semibold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(CarfoDesign.action)
                            )
                            .foregroundStyle(Color.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isWorking)

                        Spacer()

                        Button {
                            model.scanFolders(autoIndex: true, force: true)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Pindai ulang")
                                    .font(CarfoDesign.font(12.5, weight: .medium))
                            }
                            .foregroundStyle(CarfoDesign.action)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isWorking)
                        .help("Jika ada file baru dalam folder, silakan pindai ulang")
                    }
                    .padding(.top, 2)

                    if let work = model.work {
                        VStack(alignment: .leading, spacing: 6) {
                            if let fraction = work.fraction {
                                ProgressView(value: fraction)
                            } else {
                                ProgressView().controlSize(.small)
                            }
                            HStack {
                                Text(work.detail).lineLimit(1)
                                Spacer()
                                Button("Hentikan") { model.cancelWork() }
                                    .buttonStyle(.link)
                                    .tint(CarfoDesign.accent)
                            }
                            .font(CarfoDesign.font(10))
                            .foregroundStyle(CarfoDesign.secondary)
                        }
                        .padding(.top, 4)
                    }

                }

                // Section 2: Tampilan & pintasan
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tampilan & pintasan")
                        .font(CarfoDesign.font(13.5, weight: .semibold))
                        .foregroundStyle(Color.primary)

                    VStack(spacing: 0) {
                        // Row 1: Tampilan
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Tampilan")
                                    .font(CarfoDesign.font(13, weight: .medium))
                                    .foregroundStyle(Color.primary)
                                Text("Pilih tema untuk jendela Carfo.")
                                    .font(CarfoDesign.font(11))
                                    .foregroundStyle(CarfoDesign.secondary)
                            }
                            Spacer()
                            CustomThemePicker(model: model, showsBlueBorder: true)
                                .frame(width: 290)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider()
                            .overlay(isDark ? Color.white.opacity(0.08) : Color(red: 0.90, green: 0.92, blue: 0.94))

                        // Row 2: Buka pencarian
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Buka pencarian")
                                    .font(CarfoDesign.font(13, weight: .medium))
                                    .foregroundStyle(Color.primary)
                                Text("Akses cepat dari aplikasi apa pun.")
                                    .font(CarfoDesign.font(11))
                                    .foregroundStyle(CarfoDesign.secondary)
                            }
                            Spacer()
                            HStack(spacing: 12) {
                                KeycapBadge(text: model.shortcut.label)
                                Menu {
                                    ForEach(SearchShortcut.allCases) { shortcut in
                                        Button {
                                            model.shortcut = shortcut
                                        } label: {
                                            HStack {
                                                Text(shortcut.label)
                                                if model.shortcut == shortcut {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Text("Ubah")
                                        .font(CarfoDesign.font(13, weight: .medium))
                                        .foregroundStyle(CarfoDesign.action)
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .fixedSize()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider()
                            .overlay(isDark ? Color.white.opacity(0.08) : Color(red: 0.90, green: 0.92, blue: 0.94))

                        // Row 3: Buka saat login
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Buka saat login")
                                    .font(CarfoDesign.font(13, weight: .medium))
                                    .foregroundStyle(Color.primary)
                                Text("Jalankan Carfo saat Anda masuk ke Mac.")
                                    .font(CarfoDesign.font(11))
                                    .foregroundStyle(CarfoDesign.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isDark ? Color(red: 0.14, green: 0.155, blue: 0.18) : Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isDark ? Color.white.opacity(0.10) : Color(red: 0.88, green: 0.90, blue: 0.93), lineWidth: 1)
                    )
                }

                // Section 3: FAQ
                SettingsFAQView(isDark: isDark)

                if let notice = model.notice {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "info.circle")
                        Text(notice).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).help("Tutup pesan")
                    }.font(CarfoDesign.font(11)).padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }

                // Footer
                HStack {
                    Spacer()
                    Text("Carfo \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0")")
                }
                .font(CarfoDesign.font(10.5))
                .foregroundStyle(CarfoDesign.secondary)
                .padding(.top, 4)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .font(CarfoDesign.font(12)).tint(CarfoDesign.action)
        .background(isDark ? Color(red: 0.09, green: 0.10, blue: 0.12) : Color(red: 0.965, green: 0.968, blue: 0.973))
        .preferredColorScheme(model.appearance.colorScheme)
        .confirmationDialog("Keluarkan \(removing?.name ?? "folder") dari koleksi?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Keluarkan folder", role: .destructive) { if let removing { model.removeFolder(removing) }; removing = nil }
            Button("Batal", role: .cancel) { removing = nil }
        } message: { Text("File video asli tetap disimpan. Indeks folder ini akan dikeluarkan dari Carfo.") }
    }
}

struct SettingsFAQView: View {
    let isDark: Bool
    @State private var expandedItems: Set<Int> = []

    private struct FAQItem: Identifiable {
        let id: Int
        let question: String
        let answer: String
    }

    private let items: [FAQItem] = [
        FAQItem(
            id: 0,
            question: "Apakah file asli ikut terhapus saat folder dihapus dari koleksi?",
            answer: "Tidak. File asli tetap berada di folder Anda."
        ),
        FAQItem(
            id: 1,
            question: "Bagaimana memperbarui koleksi saat ada file baru?",
            answer: "Klik tombol 'Pindai ulang' untuk mendeteksi dan mengindeks file baru yang ditambahkan ke folder Anda."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FAQ")
                .font(CarfoDesign.font(13.5, weight: .semibold))
                .foregroundStyle(Color.primary)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                            .overlay(isDark ? Color.white.opacity(0.08) : Color(red: 0.90, green: 0.92, blue: 0.94))
                    }

                    let isExpanded = expandedItems.contains(item.id)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded {
                                expandedItems.remove(item.id)
                            } else {
                                expandedItems.insert(item.id)
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 12) {
                                Text(item.question)
                                    .font(CarfoDesign.font(13, weight: .medium))
                                    .foregroundStyle(Color.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CarfoDesign.secondary)
                            }

                            if isExpanded {
                                Text(item.answer)
                                    .font(CarfoDesign.font(12))
                                    .foregroundStyle(CarfoDesign.secondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDark ? Color(red: 0.14, green: 0.155, blue: 0.18) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isDark ? Color.white.opacity(0.10) : Color(red: 0.88, green: 0.90, blue: 0.93), lineWidth: 1)
            )
        }
    }
}

