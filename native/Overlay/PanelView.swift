import AppKit
import SwiftUI

/// The panel's corner radius, shared with the window's glass so the rim follows it.
let panelRadius: CGFloat = 18

/// The panel: a slim header, the meeting timeline, and the Answer button.
struct OverlayView: View {
    @ObservedObject var client: MidasClient
    let root: String?
    let hide: () -> Void
    @Environment(\.tide) private var tide
    @State private var question = ""
    @State private var showSettings: Bool

    init(client: MidasClient, root: String?, hide: @escaping () -> Void, showSettings: Bool = false) {
        self.client = client
        self.root = root
        self.hide = hide
        _showSettings = State(initialValue: showSettings)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
            if showSettings {
                SettingsDrawer(client: client, root: root)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            if client.noticeDue, let notices = client.snapshot?.privacy?.notices, !notices.isEmpty {
                ConsentBanner(notices: notices, dismiss: client.dismissNotice)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            TimelineView(client: client)
            Rectangle().fill(tide.divider).frame(height: 1)
            composer.padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(Tide.font(13))
        .foregroundStyle(tide.ink)
        .background(tide.glass)
        .overlay(RoundedRectangle(cornerRadius: panelRadius).strokeBorder(tide.rim, lineWidth: 1))
        .tint(tide.accent)
    }

    private var header: some View {
        HStack(spacing: 8) {
            MidasMark(size: 24)
            Text("Midas").font(Tide.font(15, .heavy))
            StatusPill(client: client)
            Spacer(minLength: 4)
            HeaderButton(
                icon: client.snapshot?.paused == true ? .play : .pause,
                help: client.snapshot?.paused == true
                    ? "Back on the record: transcribe again (⌃⌥P)"
                    : "Go off the record: stop transcribing until you resume (⌃⌥P)",
                action: client.togglePause)
            HeaderButton(icon: .minimize, help: "Hide the panel (⌃⌥M)", action: hide)
            HeaderButton(icon: .settings, help: "Settings", active: showSettings) {
                withAnimation(.easeOut(duration: 0.15)) { showSettings.toggle() }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField("Ask \(client.copilotName) anything…", text: $question)
                    .textFieldStyle(.plain)
                    .font(Tide.font(12.5))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(tide.field))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tide.fieldStroke))
                    .onSubmit {
                        // Enter on an empty field is the same as pressing Answer.
                        client.ask(question.trimmingCharacters(in: .whitespacesAndNewlines))
                        question = ""
                    }
                Button(action: client.summarize) {
                    Text("Summary").font(Tide.font(12.5, .semibold))
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!client.connected || client.pending)
                .help("Summarize the meeting so far and list the action items")
            }
            Button {
                client.ask("")
            } label: {
                HStack(spacing: 8) {
                    if client.pending {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    Text(client.pending ? "Drafting…" : "Answer").font(Tide.font(14.5, .bold))
                    Text("⌃⌥A").font(Tide.font(11, .medium)).opacity(0.75)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!client.connected || client.pending)
            .help("Reply to what has been said so far (⌃⌥A)")
            if client.connected {
                let destination = client.destination
                HStack(spacing: 5) {
                    Icon(destination.local ? .lock : .send, size: 12, weight: 2)
                    Text(destination.text)
                }
                    .font(Tide.font(10.5, .medium))
                    .foregroundStyle(destination.local ? tide.foamText : tide.muted)
                    .lineLimit(1)
                    .help(destination.local
                        ? "A local model answers: the meeting never leaves this Mac."
                        : "Answers come from Claude: what was said goes to Anthropic under your Claude account. Choose Ollama in Settings to keep it on this Mac.")
            }
        }
    }
}

/// A small app icon: the glass bubble and its sound wave on a tile of sea blue to seafoam.
struct MidasMark: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3)
            .fill(LinearGradient(
                colors: [Color(hex: 0x1B62A8), Color(hex: 0x2A8FB6), Color(hex: 0x3BB3A6)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Canvas { context, canvas in
                let art = BubbleArt.fitted(in: CGRect(origin: .zero, size: canvas), fill: 0.72)
                let line = { (width: CGFloat) in StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round) }
                context.fill(Path(art.disc), with: .color(.white.opacity(0.16)))
                context.stroke(Path(art.disc), with: .color(.white.opacity(0.9)), style: line(art.ringWidth * 0.8))
                context.stroke(Path(art.wave), with: .color(.white), style: line(art.waveWidth))
            })
            .accessibilityHidden(true)
    }
}

/// Always Tide blue: AppKit greys out prominent buttons in windows that aren't key, and this
/// panel deliberately never takes focus from the meeting app.
private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.tide) private var tide

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(tide.accent.opacity(configuration.isPressed ? 0.8 : 1))
                    .shadow(color: tide.accent.opacity(isEnabled ? 0.32 : 0), radius: 10, y: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center)))
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(Rectangle())
    }
}

/// Small rounded choices, such as the reminder's copy buttons.
private struct PillButtonStyle: ButtonStyle {
    @Environment(\.tide) private var tide

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tide.accentText)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background {
                // One shape, filled and then stroked on its own edge, so no fill shows past the rim.
                Capsule().fill(tide.field.opacity(configuration.isPressed ? 0.6 : 1))
                    .overlay(Capsule().stroke(tide.cardStroke, lineWidth: 1))
            }
            .contentShape(Capsule())
    }
}

/// Summary and similar: glass with a thin rim.
private struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.tide) private var tide

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tide.fieldText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(tide.field.opacity(configuration.isPressed ? 0.6 : 1)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tide.fieldStroke))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

private struct HeaderButton: View {
    let icon: TideIcon
    let help: String
    var active = false
    let action: () -> Void
    @Environment(\.tide) private var tide

    var body: some View {
        Button(action: action) {
            Icon(icon, size: 16, weight: 1.8)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 8).fill(active ? tide.accent.opacity(0.15) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? tide.accentText : tide.muted)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// One glance tells whether Midas is listening and the copilot is ready.
private struct StatusPill: View {
    @ObservedObject var client: MidasClient
    @Environment(\.tide) private var tide

    private enum Mood { case listening, quiet, warning }

    var body: some View {
        let (text, mood, live) = state
        let (dot, ink, fill): (Color, Color, Color) = switch mood {
        case .listening: (tide.foam, tide.foamText, tide.foamFill)
        case .quiet: (tide.faint, tide.quietText, tide.quiet)
        case .warning: (.orange, tide.quietText, Color.orange.opacity(0.14))
        }
        HStack(spacing: 6) {
            if live {
                PulsingDot(color: dot)
            } else {
                Circle().fill(dot).frame(width: 7, height: 7)
            }
            Text(text).font(Tide.font(11, .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(fill))
        .foregroundStyle(ink)
        .help(client.statusLine)
    }

    private var state: (String, Mood, Bool) {
        guard client.connected, let snapshot = client.snapshot else { return ("Offline", .warning, false) }
        let copilot = "\(client.copilotName) \(snapshot.claude)"
        if snapshot.paused { return ("Off the record · \(copilot)", .quiet, false) }
        if snapshot.status == "listening" { return ("Listening · \(copilot)", .listening, snapshot.speaking) }
        if snapshot.status.hasPrefix("listening") { return ("No sound · \(copilot)", .quiet, false) }
        if snapshot.status.contains("error") || snapshot.status.contains("not found") {
            return (snapshot.status, .warning, false)
        }
        return (snapshot.status.prefix(1).uppercased() + snapshot.status.dropFirst(), .quiet, false)
    }
}

/// Everything you rarely need, out of the way until you open it.
private struct SettingsDrawer: View {
    @ObservedObject var client: MidasClient
    let root: String?
    @Environment(\.tide) private var tide
    @AppStorage(TideAppearance.key) private var theme = TideAppearance.system.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            row("Theme") {
                Picker("Theme", selection: $theme) {
                    ForEach(TideAppearance.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
            }
            if let copilot = client.snapshot?.copilot {
                // Segmented controls and an inline list on purpose: pop-up menus open in
                // separate windows that screen sharing would capture.
                if client.snapshot?.privacy?.local_only == true {
                    row("Copilot") { Text("Ollama · local only").foregroundStyle(tide.muted) }
                } else {
                    row("Copilot") {
                        Picker("Copilot", selection: Binding(
                            get: { copilot.isOllama ? "ollama" : "claude" },
                            set: { provider in
                                client.setCopilot(provider: provider)
                                if provider == "ollama" { client.refreshOllama() }
                            })
                        ) {
                            Text("Claude").tag("claude")
                            Text("Ollama · local").tag("ollama")
                        }
                    }
                }
                if copilot.isOllama {
                    OllamaModels(client: client, selected: copilot.ollama_model ?? "")
                    note(client.snapshot?.privacy?.local_only == true
                        ? "Claude is turned off (local_only in config.toml): the meeting never leaves this Mac."
                        : "Runs on this Mac: the meeting never leaves it. Smaller models answer faster.")
                } else {
                    row("Model") {
                        Picker("Model", selection: Binding(get: { copilot.model }, set: { client.setCopilot(model: $0) })) {
                            Text("Opus").tag("opus")
                            Text("Sonnet").tag("sonnet")
                            Text("Haiku").tag("haiku")
                        }
                    }
                    row("Effort") {
                        Picker("Effort", selection: Binding(get: { copilot.effort }, set: { client.setCopilot(effort: $0) })) {
                            Text("Low").tag("low")
                            Text("Medium").tag("medium")
                            Text("High").tag("high")
                            Text("Max").tag("max")
                        }
                    }
                    note("Claude restarts with the new setting (~10 s). A stronger model and higher effort give better but slower replies and use more of your limit.")
                }
                Rectangle().fill(tide.divider).frame(height: 1)
            }
            HStack(spacing: 14) {
                shortcut("⌃⌥A", "Answer")
                shortcut("⌃⌥M", "Show / hide")
                shortcut("⌃⌥P", "Off the record")
            }
            HStack {
                if let root {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: root))
                    } label: {
                        HStack(spacing: 6) { Icon(.folder, size: 14); Text("Open folder") }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("context.md, config.toml and meeting logs")
                }
                Spacer()
                Button(action: client.quit) {
                    HStack(spacing: 6) { Icon(.power, size: 14); Text("Quit Midas") }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .font(Tide.font(11.5, .medium))
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(tide.card))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tide.cardStroke))
        .onAppear {
            if client.snapshot?.copilot?.isOllama == true { client.refreshOllama() }
        }
    }

    private func row(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label).frame(width: 50, alignment: .leading)
            control().labelsHidden()
        }
    }

    private func shortcut(_ keys: String, _ action: String) -> some View {
        HStack(spacing: 5) {
            Text(keys).font(Tide.font(10.5, .bold)).foregroundStyle(tide.accentText)
            Text(action).font(Tide.font(10.5)).foregroundStyle(tide.muted)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Tide.font(10.5))
            .foregroundStyle(tide.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The models pulled into Ollama, as an inline list (a pop-up menu would show in screen
/// shares).
private struct OllamaModels: View {
    @ObservedObject var client: MidasClient
    let selected: String
    @Environment(\.tide) private var tide

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Model")
                Spacer()
                Button(action: client.refreshOllama) {
                    Icon(.refresh, size: 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(tide.muted)
                .disabled(client.refreshingOllama)
                .help("Refresh the list of models")
                .accessibilityLabel("Refresh the list of models")
            }
            if let catalog = client.ollama {
                if !catalog.reachable {
                    notice("Ollama isn't running. Open the Ollama app, then refresh.") {
                        Button("Get Ollama") { NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                } else if catalog.models.isEmpty {
                    notice("No models yet. Pull one in Terminal, then refresh:") {
                        CopyCommand(command: "ollama pull llama3.2")
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(catalog.models) { model in modelRow(model) }
                        }
                    }
                    .frame(height: min(CGFloat(catalog.models.count) * 29 - 3, 124))
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Looking for Ollama…").foregroundStyle(tide.muted)
                }
            }
        }
    }

    private func modelRow(_ model: OllamaModel) -> some View {
        let isSelected = model.name == selected
        return Button {
            client.setCopilot(ollamaModel: model.name)
        } label: {
            HStack(spacing: 7) {
                Icon(.radio, size: 15, filled: isSelected)
                    .foregroundStyle(isSelected ? tide.accent : tide.muted)
                Text(model.name)
                    .font(Tide.font(11.5, isSelected ? .bold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Text(model.detail).font(Tide.font(10.5)).foregroundStyle(tide.muted)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9).fill(isSelected ? tide.accent.opacity(0.14) : tide.field))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func notice(_ text: String, @ViewBuilder action: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).foregroundStyle(tide.muted).fixedSize(horizontal: false, vertical: true)
            action()
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(tide.field))
    }
}

/// At the start of a meeting: a reminder to tell the others, with a message to paste into
/// the chat. The panel stays private; the transcription shouldn't be.
private struct ConsentBanner: View {
    let notices: [String: String]
    let dismiss: () -> Void
    @Environment(\.tide) private var tide
    @State private var copied: String?

    private var languages: [(key: String, label: String)] {
        [("en", "English"), ("tr", "Türkçe"), ("custom", "Message")].filter { notices[$0.key] != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 7) {
                Icon(.waves, size: 16)
                Text("Let the others know you're transcribing").font(Tide.font(12.5, .bold))
                Spacer(minLength: 4)
                Button(action: dismiss) {
                    Icon(.close, size: 13)
                }
                .buttonStyle(.plain)
                .foregroundStyle(tide.muted)
                .help("Done")
                .accessibilityLabel("Dismiss the reminder")
            }
            .foregroundStyle(tide.accentText)
            Text("A short, friendly note for the chat. Some places need everyone's OK.")
                .font(Tide.font(11.5))
                .foregroundStyle(tide.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(languages, id: \.key) { language in
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(notices[language.key] ?? "", forType: .string)
                        copied = language.key
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
                    } label: {
                        HStack(spacing: 5) {
                            if copied == language.key { Icon(.check, size: 12, weight: 2.2) }
                            Text(copied == language.key ? "Copied" : "Copy · \(language.label)")
                        }
                        .font(Tide.font(11.5, .semibold))
                    }
                    .buttonStyle(PillButtonStyle())
                    .help(notices[language.key] ?? "")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(tide.card))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tide.cardStroke))
    }
}

/// A Terminal command with a copy button.
private struct CopyCommand: View {
    let command: String
    @Environment(\.tide) private var tide
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(command).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Icon(copied ? .check : .copy, size: 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(tide.muted)
            .help("Copy")
            .accessibilityLabel("Copy the command")
        }
    }
}
