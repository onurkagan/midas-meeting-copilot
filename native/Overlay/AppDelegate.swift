import AppKit
import Combine
import SwiftUI

// MARK: - Window

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let client: MidasClient
    let port: Int
    let parentPID: pid_t?
    let root: String?
    let launchesDaemon: Bool
    var panel: OverlayPanel!
    private var daemon: Process?
    private var statusItem: NSStatusItem!
    private var subscriptions: Set<AnyCancellable> = []

    init(port: Int, parentPID: pid_t?, root: String?, launchesDaemon: Bool) {
        client = MidasClient(port: port)
        self.port = port
        self.parentPID = parentPID
        self.root = root
        self.launchesDaemon = launchesDaemon
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        TideFont.register()
        if launchesDaemon, let root {
            startDaemonIfNeeded(root: root)
            watchDaemon(root: root)
        }
        panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.sharingType = .none  // excluded from screen sharing, screenshots and recordings
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.minSize = NSSize(width: 340, height: 400)
        // Follows the Mac's appearance: Tide by day, Tide at night in dark mode.
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = panelRadius
        background.layer?.masksToBounds = true

        let hosting = NSHostingView(
            rootView: OverlayView(client: client, root: root, hide: { [weak self] in self?.toggle() }).modifier(TideTheme()))
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background

        if !panel.setFrameUsingName("MidasPanel"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 440, y: screen.maxY - 640))
        }
        panel.setFrameAutosaveName("MidasPanel")
        panel.orderFrontRegardless()

        client.start()
        HotKeys.install { [weak self] id in self?.hotKey(id) }
        setUpStatusItem()

        if let parentPID {
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                if kill(parentPID, 0) != 0 { NSApp.terminate(nil) }
            }
        }
    }

    // Opening Midas.app again (Spotlight, Launchpad, Finder) brings the panel back,
    // and the daemon too if it went away.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.orderFrontRegardless()
        if launchesDaemon, let root, !client.connected { startDaemonIfNeeded(root: root) }
        return false
    }

    /// Restarts the daemon when it has been unreachable for a while (crash, `midas stop`).
    private func watchDaemon(root: String) {
        var unreachableSince: Date?
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.client.connected || self.daemon?.isRunning == true {
                unreachableSince = nil
            } else if let since = unreachableSince, Date().timeIntervalSince(since) > 10 {
                unreachableSince = nil
                self.startDaemonIfNeeded(root: root)
            } else if unreachableSince == nil {
                unreachableSince = Date()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let daemon, daemon.isRunning { daemon.terminate() }
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
            Toast.show("Midas is hidden · click the menu bar icon or press ⌃⌥M to bring it back", over: panel.frame)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// In Midas.app the panel is the main program: it starts the daemon (with the
    /// headless Claude copilot) unless one is already running, e.g. after a crash.
    private func startDaemonIfNeeded(root: String) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/health")!)
        request.timeoutInterval = 1
        let checked = DispatchSemaphore(value: 0)
        var running = false
        URLSession.shared.dataTask(with: request) { data, _, _ in
            running = data != nil
            checked.signal()
        }.resume()
        _ = checked.wait(timeout: .now() + 2)
        if running { return }

        let logs = root + "/logs"
        try? FileManager.default.createDirectory(atPath: logs, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logs + "/daemon.log", contents: nil)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: root + "/midas")
        process.arguments = ["run", "--copilot", "--no-overlay"]
        var environment = ProcessInfo.processInfo.environment
        // Apps opened from Finder get a bare PATH; claude lives in ~/.local/bin.
        environment["PATH"] = NSHomeDirectory() + "/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        let log = FileHandle(forWritingAtPath: logs + "/daemon.log")
        process.standardOutput = log
        process.standardError = log
        do {
            try process.run()
            daemon = process
        } catch {
            NSLog("Midas: could not start the daemon: \(error)")
        }
    }

    private func hotKey(_ id: UInt32) {
        switch id {
        case 1: toggle()
        case 2:
            client.ask("")
            panel.orderFrontRegardless()
        case 3: client.togglePause()
        default: break
        }
    }

    // MARK: Menu bar

    /// A click on the icon shows/hides the panel. There is deliberately no dropdown:
    /// AppKit draws menus in its own windows, which screen sharing would capture.
    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = EarsArt.glyph(size: 18)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        updateStatusItem()
        client.$snapshot.combineLatest(client.$connected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &subscriptions)
    }

    @objc private func statusItemClicked() { toggle() }

    private func updateStatusItem() {
        // Same treatment as the panel: keep the icon out of screen sharing.
        statusItem.button?.window?.sharingType = .none
        statusItem.button?.toolTip = "Midas · " + client.statusLine + "\nClick to show/hide the panel (⌃⌥M)"
        // Midas's ears, dimmed while it isn't listening.
        statusItem.button?.appearsDisabled = !client.connected || client.snapshot?.paused == true
    }
}
