import AppKit
import SwiftUI

// MARK: - Hidden overlay panel
//
// The key trick that makes this a "screen-share invisible" copilot on macOS:
// `sharingType = .none` excludes the window from *all* screen capture and
// recording (Zoom/Meet/Teams screen share, QuickTime, ScreenCaptureKit, etc.).
// You still see it locally; nobody on the call — or in a recording — does.

final class OverlayPanel: NSPanel {
    init(rootView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 470),
            styleMask: [.titled, .closable, .resizable,
                        .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        // Exclude from screen sharing & recordings.
        sharingType = .none

        // Float above normal windows, appear on every Space, survive fullscreen.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                              .stationary]

        isFloatingPanel = true
        hidesOnDeactivate = false
        // Closing the overlay should hide it, not destroy it — the menu bar
        // "Show overlay" reopens the same panel.
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        contentView = rootView
        setFrameAutosaveName("InterviewCopilotOverlay")
    }

    // Allow a borderless/nonactivating panel to still receive keystrokes.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: OverlayPanel!
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    let settings = AppSettings()
    lazy var vm = CopilotViewModel(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = NSHostingView(rootView: ContentView(vm: vm))
        panel = OverlayPanel(rootView: host)
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        setupMainMenu()   // enables ⌘X/⌘C/⌘V/⌘A in text fields
        setupMenuBar()

        setupHotKeys()

        NSApp.setActivationPolicy(.accessory) // no Dock icon; menu-bar app
        NSApp.activate(ignoringOtherApps: true)
    }

    // App keeps running in the menu bar after the overlay is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool {
        false
    }

    // MARK: Main menu (for editing shortcuts)

    // An accessory app has no menu bar, but a main menu is still what routes
    // ⌘C/⌘V/⌘X/⌘A/⌘Z to the focused text field via the responder chain. Without
    // it, paste doesn't work in the Settings fields.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Interview Copilot",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo",
                         action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo",
                         action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut",
                         action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",
                         action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",
                         action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "waveform.circle",
            accessibilityDescription: "Interview Copilot")

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        func add(_ title: String, _ action: Selector, _ key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        add("Start listening", #selector(startListening))
        add("Stop listening", #selector(stopListening))
        menu.addItem(.separator())
        add("Show overlay", #selector(showOverlay))
        add("Hide overlay", #selector(hideOverlay))
        menu.addItem(.separator())
        add("Get answer now  (⌃⌥A)", #selector(getAnswer))
        add("Answer from screen  (⌃⌥S)", #selector(answerScreen))
        menu.addItem(.separator())
        add("Shortcuts:  ⌃⌥A answer · ⌃⌥S screen", #selector(noop))
        add("           ⌃⌥H hide · ⌃⌥M mic · ⌃⌥R résumé", #selector(noop))
        menu.addItem(.separator())
        add("Open settings…", #selector(openSettings), ",")
        menu.addItem(.separator())
        add("Relaunch app  (after granting permissions)", #selector(relaunch))
        add("Quit Interview Copilot", #selector(quit), "q")
        statusItem.menu = menu
    }

    @objc private func startListening() { Task { await vm.start() } }
    @objc private func stopListening() { vm.stop() }
    @objc private func showOverlay() {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func hideOverlay() { panel.orderOut(nil) }
    @objc private func getAnswer() { vm.requestSuggestion() }
    @objc private func answerScreen() { vm.answerFromScreen() }

    private func setupHotKeys() {
        let hk = HotKeyCenter.shared
        hk.register(keyCode: Shortcuts.answer.keyCode) { [weak self] in
            self?.vm.requestSuggestion()
        }
        hk.register(keyCode: Shortcuts.screen.keyCode) { [weak self] in
            self?.vm.answerFromScreen()
        }
        hk.register(keyCode: Shortcuts.overlay.keyCode) { [weak self] in
            self?.toggleOverlay()
        }
        hk.register(keyCode: Shortcuts.mic.keyCode) { [weak self] in
            guard let self else { return }
            self.vm.setMic(!self.vm.micEnabled)
        }
        hk.register(keyCode: Shortcuts.resume.keyCode) { [weak self] in
            self?.vm.useResume.toggle()
        }
        hk.register(keyCode: Shortcuts.askLast.keyCode) { [weak self] in
            self?.vm.askLast()
        }
        hk.register(keyCode: Shortcuts.compact.keyCode) { [weak self] in
            self?.vm.compactMode.toggle()
        }
    }

    private func toggleOverlay() {
        if panel.isVisible { panel.orderOut(nil) }
        else {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func noop() {}

    /// Reliably relaunch the app (macOS's own "Quit & Reopen" permission button
    /// is flaky for ad-hoc-signed apps). Spawns a fresh instance after we exit,
    /// so the new process picks up newly-granted permissions.
    @objc private func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings) { [weak self] in
                self?.vm.rebuildProvider()
                self?.settingsWindow?.close()
            }
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 440),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.title = "Interview Copilot Settings"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.sharingType = .none   // hide Settings from screen share too
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// Enable/disable Start vs Stop and Show vs Hide based on current state.
extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            switch item.action {
            case #selector(startListening): item.isEnabled = !vm.isRunning
            case #selector(stopListening): item.isEnabled = vm.isRunning
            case #selector(showOverlay): item.isEnabled = !panel.isVisible
            case #selector(hideOverlay): item.isEnabled = panel.isVisible
            default: break
            }
        }
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
