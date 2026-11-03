// midas-overlay: floating answer panel that screen sharing and recording can't see
// (NSWindow.sharingType = .none). No Dock icon, never steals focus from the meeting app.
//
// Hotkeys: ⌃⌥M show/hide · ⌃⌥A ask Claude to answer now · ⌃⌥P pause/resume listening

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

// MARK: - Daemon client

struct MidasEvent: Decodable, Identifiable, Equatable {
    let id: Int
    let time: String
    let kind: String
    let text: String
    let title: String
}

struct CopilotSettings: Decodable, Equatable {
    let model: String
    let effort: String
}

struct Snapshot: Decodable {
    let status: String
    let paused: Bool
    let speaking: Bool
    let claude: String
    let pending_request: Bool
    let partial: String
    let transcript: [MidasEvent]
    let answers: [MidasEvent]
    let copilot: CopilotSettings?  // nil when Claude runs in a terminal, not under Midas
}

final class MidasClient: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var connected = false
    private let base: URL
    private var timer: Timer?
    private var inFlight = false

    init(port: Int) {
        base = URL(string: "http://127.0.0.1:\(port)/api/")!
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    private func poll() {
        guard !inFlight else { return }
        inFlight = true
        var request = URLRequest(url: base.appendingPathComponent("snapshot"))
        request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let snapshot = data.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
            DispatchQueue.main.async {
                self.inFlight = false
                self.connected = snapshot != nil
                if let snapshot { self.snapshot = snapshot }
            }
        }.resume()
    }

    private func post(_ path: String, _ body: [String: Any]) {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { [weak self] _, _, _ in
            DispatchQueue.main.async { self?.poll() }
        }.resume()
    }

    func ask(_ text: String) { post("request", ["text": text]) }

    var statusLine: String {
        guard connected, let snapshot else { return "can't reach the daemon" }
        let listening = snapshot.paused ? "paused" : snapshot.status
        return "\(listening) · Claude \(snapshot.claude)"
    }

    func togglePause() {
        post("control", ["action": snapshot?.paused == true ? "resume" : "pause"])
    }

    /// Restarts the copilot with another model or effort level.
    func setCopilot(model: String? = nil, effort: String? = nil) {
        var body: [String: Any] = ["action": "copilot"]
        if let model { body["model"] = model }
        if let effort { body["effort"] = effort }
        post("control", body)
    }

    /// Stops the whole of Midas (daemon, Claude copilot and this panel).
    func quit() {
        post("control", ["action": "quit"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }
}

// MARK: - Views

func markdown(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
}

struct AnswerCard: View {
    let answer: MidasEvent
    let latest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(answer.title.isEmpty ? "Suggestion" : answer.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(latest ? Color.yellow : Color.secondary)
                    .lineLimit(1)
                Spacer()
                Text(answer.time).font(.system(size: 10)).foregroundStyle(.tertiary)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(answer.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy")
            }
            Text(markdown(answer.text))
                .font(.system(size: latest ? 14 : 12.5))
                .foregroundStyle(latest ? Color.primary : Color.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(latest ? 0.10 : 0.04))
        )
    }
}

struct OverlayView: View {
    @ObservedObject var client: MidasClient
    let root: String?
    let hide: () -> Void
    @State private var question = ""
    @State private var showSettings = false

    private var statusColor: Color {
        guard client.connected, let snapshot = client.snapshot else { return .red }
        if snapshot.paused { return .orange }
        if snapshot.status != "listening" { return .yellow }
        return snapshot.speaking ? .green : .green.opacity(0.6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if showSettings, let copilot = client.snapshot?.copilot {
                settings(copilot)
            }
            answers
            Divider().opacity(0.4)
            transcript
            controls
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text("Midas").font(.system(size: 13, weight: .bold))
            Text(client.statusLine).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if client.snapshot?.copilot != nil {
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .foregroundStyle(showSettings ? Color.yellow : Color.primary)
                .help("Claude model and effort")
            }
            Button(action: client.togglePause) {
                Image(systemName: client.snapshot?.paused == true ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.plain)
            .help("Pause / resume listening (⌃⌥P)")
            if let root {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: root))
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("Open the Midas folder (context.md, config.toml, meeting logs)")
            }
            Button(action: hide) { Image(systemName: "eye.slash") }
                .buttonStyle(.plain)
                .help("Hide (⌃⌥M)")
            Button(action: client.quit) { Image(systemName: "power") }
                .buttonStyle(.plain)
                .help("Quit Midas")
        }
        .foregroundStyle(.primary)
    }

    /// Segmented controls on purpose: pop-up menus open in separate windows that
    /// screen sharing would capture.
    private func settings(_ copilot: CopilotSettings) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Model").frame(width: 40, alignment: .leading)
                Picker("Model", selection: Binding(get: { copilot.model }, set: { client.setCopilot(model: $0) })) {
                    Text("Opus").tag("opus")
                    Text("Sonnet").tag("sonnet")
                    Text("Haiku").tag("haiku")
                }
            }
            HStack {
                Text("Effort").frame(width: 40, alignment: .leading)
                Picker("Effort", selection: Binding(get: { copilot.effort }, set: { client.setCopilot(effort: $0) })) {
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                    Text("Max").tag("max")
                }
            }
            Text("Claude restarts with the new setting (~10 s). A stronger model and higher effort give better but slower replies and use more of your limit.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .font(.system(size: 11))
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }

    private var answers: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    let items = client.snapshot?.answers ?? []
                    if items.isEmpty {
                        Text("When someone asks a question, press **Answer** (⌃⌥A).\nClaude replies based on what has been said so far.")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 20)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(items) { answer in
                        AnswerCard(answer: answer, latest: answer.id == items.last?.id).id(answer.id)
                    }
                    if client.snapshot?.pending_request == true {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Claude is drafting…").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        .id(-1)
                    }
                }
            }
            .onChange(of: client.snapshot?.answers.last?.id) { _, last in
                if let last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    let lines = client.snapshot?.transcript ?? []
                    let partial = client.snapshot?.partial ?? ""
                    if lines.isEmpty && partial.isEmpty {
                        Text("The conversation is transcribed here live.")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !partial.isEmpty {
                        Text(partial + " …")
                            .font(.system(size: 11.5).italic()).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: client.snapshot?.transcript.last?.id) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: client.snapshot?.partial) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
        .frame(height: 110)
    }

    private var controls: some View {
        VStack(spacing: 6) {
            TextField("Ask Claude something specific… (Enter)", text: $question)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit {
                    client.ask(question.trimmingCharacters(in: .whitespacesAndNewlines))
                    question = ""
                }
            HStack(spacing: 6) {
                Button {
                    client.ask("")
                } label: {
                    Label("Answer", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.80, green: 0.56, blue: 0.10))
                .controlSize(.large)
                .disabled(client.snapshot?.pending_request == true)
                .help("Reply to what has been said so far (⌃⌥A)")
                Button("Summary") { client.ask("Summarize the meeting so far and list the action items.") }
                    .controlSize(.large)
            }
        }
    }
}

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
    private var statusIcon = ""
    private var subscriptions: Set<AnyCancellable> = []

    init(port: Int, parentPID: pid_t?, root: String?, launchesDaemon: Bool) {
        client = MidasClient(port: port)
        self.port = port
        self.parentPID = parentPID
        self.root = root
        self.launchesDaemon = launchesDaemon
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if launchesDaemon, let root {
            startDaemonIfNeeded(root: root)
            watchDaemon(root: root)
        }
        panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
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
        panel.minSize = NSSize(width: 300, height: 260)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true

        let hosting = NSHostingView(
            rootView: OverlayView(client: client, root: root, hide: { [weak self] in self?.toggle() }))
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

        if !panel.setFrameUsingName("MidasOverlay"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 420, y: screen.maxY - 520))
        }
        panel.setFrameAutosaveName("MidasOverlay")
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
        let name =
            !client.connected ? "waveform.slash" : client.snapshot?.paused == true ? "pause.circle" : "waveform"
        guard name != statusIcon else { return }
        statusIcon = name
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Midas")
    }
}

/// A short-lived hint bubble, hidden from screen sharing like the panel.
enum Toast {
    static func show(_ text: String, over frame: NSRect) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        let size = label.fittingSize
        let rect = NSRect(
            x: frame.midX - size.width / 2 - 14, y: frame.maxY - size.height - 40,
            width: size.width + 28, height: size.height + 16)
        let window = NSPanel(
            contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.sharingType = .none
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: rect.size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        label.frame = NSRect(x: 14, y: 8, width: size.width, height: size.height)
        background.addSubview(label)
        window.contentView = background
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                window.animator().alphaValue = 0
            } completionHandler: {
                window.orderOut(nil)
            }
        }
    }
}

// MARK: - Global hotkeys (Carbon: no Accessibility permission needed)

enum HotKeys {
    static var handler: ((UInt32) -> Void)?
    static var refs: [EventHotKeyRef?] = []

    static func install(_ handler: @escaping (UInt32) -> Void) {
        self.handler = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                HotKeys.handler?(hotKeyID.id)
                return noErr
            }, 1, &spec, nil, nil)
        let modifiers = UInt32(controlKey | optionKey)
        for (id, key, name) in [(UInt32(1), kVK_ANSI_M, "⌃⌥M"), (2, kVK_ANSI_A, "⌃⌥A"), (3, kVK_ANSI_P, "⌃⌥P")] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(key), modifiers, EventHotKeyID(signature: OSType(0x4D44_4153), id: id),
                GetApplicationEventTarget(), 0, &ref)
            if status != noErr {
                FileHandle.standardError.write(Data("[midas-overlay] could not register the \(name) hotkey (\(status))\n".utf8))
            }
            refs.append(ref)
        }
    }
}

// MARK: - Main

var port = 47821
var parentPID: pid_t?
var root: String?
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--port": port = arguments.next().flatMap(Int.init) ?? port
    case "--parent-pid": parentPID = arguments.next().flatMap { pid_t($0) }
    case "--root": root = arguments.next()
    default: break
    }
}

// Inside Midas.app (no daemon parent) the bundle names the runtime folder to start from.
let bundleRoot = Bundle.main.object(forInfoDictionaryKey: "MidasRoot") as? String
let launchesDaemon = parentPID == nil && bundleRoot != nil
if launchesDaemon { root = bundleRoot }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(port: port, parentPID: parentPID, root: root, launchesDaemon: launchesDaemon)
app.delegate = delegate
app.run()
