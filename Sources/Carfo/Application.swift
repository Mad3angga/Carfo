import AppKit
import Carbon
import CarfoCore
import SwiftUI

@main
enum CarfoApplication {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

typealias FootageApplication = CarfoApplication

final class SpotlightPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var searchPanel: SpotlightPanel!
    private var settingsWindow: NSWindow?
    private var hotkey: EventHotKeyRef?
    private var hotkeyHandler: EventHandlerRef?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let arguments = ProcessInfo.processInfo.arguments
            let testDirectory = arguments.firstIndex(of: "--self-test-directory").flatMap { arguments.indices.contains($0 + 1) ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
                ?? (Bundle.main.object(forInfoDictionaryKey: "CarfoSelfTestDirectory") as? String).map { URL(fileURLWithPath: $0) }
                ?? (Bundle.main.object(forInfoDictionaryKey: "FootageSelfTestDirectory") as? String).map { URL(fileURLWithPath: $0) }
            if testDirectory != nil { setenv("CARFO_DEFAULTS_SUITE", "id.carfo.selftest", 1) }
            model = try AppModel(directory: testDirectory?.appendingPathComponent("Library"))
            model.showSearch = { [weak self] in self?.showSearch() }
            model.hideSearch = { [weak self] in self?.hideSearch() }
            model.showSettings = { [weak self] in self?.showSettings() }
            model.appearanceChanged = { [weak self] in self?.applyAppearance() }
            model.shortcutChanged = { [weak self] in self?.registerHotkey() }
            if let testDirectory {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 180), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.title = "Validasi Carfo"
                window.contentView = NSHostingView(rootView: VStack(spacing: 15) {
                    ProgressView()
                    Text("Menguji model lokal dan pemrosesan media").font(.headline)
                    Text("Menggunakan dua video sintetis. Koleksi pengguna tidak diubah.").font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity))
                window.center(); window.makeKeyAndOrderFront(nil); settingsWindow = window
                runSelfTest(directory: testDirectory)
                return
            }
            makeMainMenu(); makeStatusItem(); makeSearchPanel(); installKeyboardMonitor(); registerHotkey(); applyAppearance()
            showSearch()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Carfo belum dapat dibuka"
            alert.informativeText = error.localizedDescription
            alert.runModal(); NSApp.terminate(nil)
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSearch(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let hotkeyHandler { RemoveEventHandler(hotkeyHandler) }
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
    private func makeMainMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Cari di Carfo", action: #selector(searchAction), keyEquivalent: "f").target = self
        appMenu.addItem(withTitle: "Pengaturan...", action: #selector(settingsAction), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Keluar dari Carfo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Urungkan", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Potong", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Salin", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Tempel", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Pilih semua", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = editMenu; menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "film.stack", accessibilityDescription: "Carfo")
            button.image?.isTemplate = true
            button.toolTip = "Carfo · \(model.shortcut.label)"
            button.target = self; button.action = #selector(statusAction)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView(model: model))
    }
    private func makeSearchPanel() {
        let isExpanded = model.hasQuery
        let width: CGFloat = 760
        let height: CGFloat = isExpanded ? 547 : 94
        let panel = SpotlightPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true; panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.isMovableByWindowBackground = false
        panel.title = "Pencarian Carfo"; panel.delegate = self
        panel.contentView = NSHostingView(rootView: SearchView(model: model) { [weak self] expanded in self?.resizeSearch(expanded: expanded) })
        searchPanel = panel
    }
    private func resizeSearch(expanded: Bool) {
        let width: CGFloat = 760
        let height: CGFloat = expanded ? 547 : 94
        let old = searchPanel.frame
        let origin = NSPoint(x: old.midX - width / 2, y: old.maxY - height)
        let newFrame = NSRect(origin: origin, size: NSSize(width: width, height: height))
        guard old != newFrame else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.90, 0.25, 1.0)
            context.allowsImplicitAnimation = true
            searchPanel.animator().setFrame(newFrame, display: true)
        }
    }
    func showSearch() {
        guard searchPanel != nil else { return }
        popover?.performClose(nil)
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let isExpanded = model.hasQuery
        let width: CGFloat = 760, height: CGFloat = isExpanded ? 547 : 94
        let visible = screen.visibleFrame
        let top = visible.maxY - max(70, visible.height * 0.18)
        searchPanel.setFrame(NSRect(x: visible.midX - width / 2, y: max(visible.minY + 16, top - height), width: width, height: height), display: true)
        searchPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .carfoFocusSearch, object: nil)
    }
    func hideSearch() { model.stopPreview(); searchPanel?.orderOut(nil) }
    func showSettings() {
        popover?.performClose(nil); hideSearch()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Pengaturan Carfo"; window.minSize = NSSize(width: 700, height: 540)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center(); settingsWindow = window
        }
        settingsWindow?.appearance = model.appearance.nsAppearance
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func applyAppearance() {
        NSApp.appearance = model.appearance.nsAppearance
        searchPanel?.appearance = model.appearance.nsAppearance
        settingsWindow?.appearance = model.appearance.nsAppearance
        popover?.appearance = model.appearance.nsAppearance
    }
    @objc private func statusAction() {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true { showSearch(); return }
        hideSearch()
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button {
            popover.appearance = model.appearance.nsAppearance
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                window.appearance = model.appearance.nsAppearance
                window.makeKey()
            }
        }
    }
    @objc private func settingsAction() { showSettings() }
    @objc private func searchAction() { showSearch() }
    private func installKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.contains(.command), event.charactersIgnoringModifiers == "," { self.showSettings(); return nil }
            if modifiers.contains(.command), event.charactersIgnoringModifiers == "q" { NSApp.terminate(nil); return nil }
            if self.searchPanel.isKeyWindow && modifiers.contains(.control) && event.charactersIgnoringModifiers == "p" { self.model.togglePreview(); return nil }
            return event
        }
    }
    private func registerHotkey() {
        if let hotkey { UnregisterEventHotKey(hotkey); self.hotkey = nil }
        if hotkeyHandler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), { _, _, data -> OSStatus in
                guard let data else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(data).takeUnretainedValue()
                MainActor.assumeIsolated {
                    if delegate.searchPanel.isVisible { delegate.hideSearch() } else { delegate.showSearch() }
                }
                return noErr
            }, 1, &event, pointer, &hotkeyHandler)
        }
        let modifiers: UInt32
        switch model.shortcut {
        case .optionSpace: modifiers = UInt32(optionKey)
        case .controlOptionSpace: modifiers = UInt32(controlKey | optionKey)
        case .controlSpace: modifiers = UInt32(controlKey)
        }
        let status = RegisterEventHotKey(UInt32(kVK_Space), modifiers, EventHotKeyID(signature: 0x4352464F, id: 1), GetApplicationEventTarget(), 0, &hotkey)
        if status != noErr { model.notice = "Pintasan \(model.shortcut.label) sudah digunakan aplikasi lain. Pilih pintasan lain di Pengaturan." }
        statusItem?.button?.toolTip = "Carfo · \(model.shortcut.label)"
    }
    private func runSelfTest(directory: URL) {
        Task {
            let output = directory.appendingPathComponent("self-test.json")
            var report: [String: Any] = ["model": model.installation.modelDirectory?.path ?? "missing", "python": model.installation.pythonExecutable?.path ?? "missing"]
            do {
                report["backend"] = try await model.engine.verify()
                let query = try await model.engine.embed(query: "a red scene", mode: .visual)
                report["textDimensions"] = query.count
                let red = try await model.engine.embed(frames: [directory.appendingPathComponent("red.jpg")])
                let blue = try await model.engine.embed(frames: [directory.appendingPathComponent("blue.jpg")])
                report["imageDimensions"] = red.count
                report["redScore"] = VectorMath.cosine(query, red)
                report["blueScore"] = VectorMath.cosine(query, blue)
                let audio = try await model.engine.embed(audio: directory.appendingPathComponent("tone.wav"))
                report["audioDimensions"] = audio.count
                model.modelVerified = true
                model.addFolders([directory.appendingPathComponent("Videos")])
                while model.isWorking { try await Task.sleep(for: .milliseconds(100)) }
                model.startIndexing()
                while model.isWorking { try await Task.sleep(for: .milliseconds(100)) }
                report["clips"] = model.library.clips.count
                report["indexedClips"] = model.indexedCount
                report["indexError"] = model.modelError
                report["ok"] = model.indexedCount == model.library.clips.count && model.indexedCount > 0
                model.query = "a red scene"
            } catch { report["ok"] = false; report["error"] = error.localizedDescription }
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic) }
            catch { NSLog("Carfo self-test: %@", error.localizedDescription) }
            let passed = report["ok"] as? Bool == true
            settingsWindow?.contentView = NSHostingView(rootView: VStack(spacing: 12) {
                Image(systemName: passed ? "checkmark.circle" : "exclamationmark.triangle").font(.largeTitle)
                Text(passed ? "Validasi lokal berhasil" : "Validasi memerlukan perbaikan").font(.headline)
                Text(report["error"] as? String ?? "Hasil tersimpan di self-test.json").font(.caption).multilineTextAlignment(.center)
                Button("Tutup") { NSApp.terminate(nil) }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity))
        }
    }
}
