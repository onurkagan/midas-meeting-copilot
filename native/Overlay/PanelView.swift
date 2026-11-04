import AppKit
import SwiftUI

/// The panel: a slim header, the meeting timeline, and the Answer button.
struct OverlayView: View {
    @ObservedObject var client: MidasClient
    let root: String?
    let hide: () -> Void
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
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)
            if showSettings {
                SettingsDrawer(client: client, root: root)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            Divider().opacity(0.3)
            TimelineView(client: client)
            Divider().opacity(0.3)
            composer.padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(Brand.blue)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: EarsArt.glyph(size: 22)).renderingMode(.template).foregroundStyle(Brand.blue)
            Text("Midas").font(.system(size: 13, weight: .bold))
            StatusPill(client: client)
            Spacer(minLength: 4)
            HeaderButton(
                symbol: client.snapshot?.paused == true ? "play.fill" : "pause.fill",
                help: client.snapshot?.paused == true ? "Resume listening (⌃⌥P)" : "Pause listening (⌃⌥P)",
                action: client.togglePause)
            HeaderButton(symbol: "eye.slash", help: "Hide (⌃⌥M)", action: hide)
            HeaderButton(symbol: "gearshape", help: "Settings", active: showSettings) {
                withAnimation(.easeOut(duration: 0.15)) { showSettings.toggle() }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField("Ask \(client.copilotName) anything…", text: $question)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.12)))
                    .onSubmit {
                        // Enter on an empty field is the same as pressing Answer.
                        client.ask(question.trimmingCharacters(in: .whitespacesAndNewlines))
                        question = ""
                    }
                Button(action: client.summarize) {
                    Label("Summary", systemImage: "list.bullet")
                }
                .controlSize(.large)
                .disabled(!client.connected || client.pending)
                .help("Summarize the meeting so far and list the action items")
            }
            Button {
                client.ask("")
            } label: {
                HStack(spacing: 8) {
                    if client.pending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(client.pending ? "Drafting…" : "Answer").font(.system(size: 14, weight: .semibold))
                    Text("⌃⌥A").font(.system(size: 11)).opacity(0.65)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!client.connected || client.pending)
            .help("Reply to what has been said so far (⌃⌥A)")
        }
    }
}

/// Always blue: AppKit greys out prominent buttons in windows that aren't key, and this
/// panel deliberately never takes focus from the meeting app.
private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Brand.deepBlue.opacity(configuration.isPressed ? 0.75 : 1)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.12)))
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(Rectangle())
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(active ? Brand.blue.opacity(0.25) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Brand.lightBlue : Color.secondary)
        .help(help)
    }
}

/// One glance tells whether Midas is listening and Claude is ready.
private struct StatusPill: View {
    @ObservedObject var client: MidasClient

    var body: some View {
        let (text, color, live) = state
        HStack(spacing: 6) {
            if live {
                PulsingDot(color: color)
            } else {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.16)))
        .foregroundStyle(.secondary)
        .help(client.statusLine)
    }

    private var state: (String, Color, Bool) {
        guard client.connected, let snapshot = client.snapshot else { return ("Offline", .red, false) }
        let copilot = "\(client.copilotName) \(snapshot.claude)"
        if snapshot.paused { return ("Paused · \(copilot)", .gray, false) }
        if snapshot.status == "listening" { return ("Listening · \(copilot)", Brand.blue, snapshot.speaking) }
        if snapshot.status.hasPrefix("listening") { return ("No sound · \(copilot)", .gray, false) }
        if snapshot.status.contains("error") || snapshot.status.contains("not found") {
            return (snapshot.status, .orange, false)
        }
        return (snapshot.status.prefix(1).uppercased() + snapshot.status.dropFirst(), .gray, false)
    }
}

/// Everything you rarely need, out of the way until you open it.
private struct SettingsDrawer: View {
    @ObservedObject var client: MidasClient
    let root: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let copilot = client.snapshot?.copilot {
                // Segmented controls and an inline list on purpose: pop-up menus open in
                // separate windows that screen sharing would capture.
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
                if copilot.isOllama {
                    OllamaModels(client: client, selected: copilot.ollama_model ?? "")
                    note("Runs on this Mac: the meeting never leaves it. Smaller models answer faster.")
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
                Divider().opacity(0.3)
            }
            Text("⌃⌥A  Answer     ⌃⌥M  Show / hide     ⌃⌥P  Pause")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack {
                if let root {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: root))
                    } label: {
                        Label("Open folder", systemImage: "folder")
                    }
                    .help("context.md, config.toml and meeting logs")
                }
                Spacer()
                Button(action: client.quit) {
                    Label("Quit Midas", systemImage: "power")
                }
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .font(.system(size: 11))
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
        .onAppear {
            if client.snapshot?.copilot?.isOllama == true { client.refreshOllama() }
        }
    }

    private func row(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label).frame(width: 46, alignment: .leading)
            control().labelsHidden()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The models pulled into Ollama, as an inline list (a pop-up menu would show in screen
/// shares).
private struct OllamaModels: View {
    @ObservedObject var client: MidasClient
    let selected: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Model")
                Spacer()
                Button(action: client.refreshOllama) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(client.refreshingOllama)
                .help("Refresh the list of models")
            }
            if let catalog = client.ollama {
                if !catalog.reachable {
                    notice("Ollama isn't running. Open the Ollama app, then refresh.") {
                        Button("Get Ollama") { NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!) }
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
                    .frame(height: min(CGFloat(catalog.models.count) * 27 - 3, 118))
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Looking for Ollama…").foregroundStyle(.secondary)
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
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Brand.blue : Color.secondary)
                Text(model.name)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Text(model.detail).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Brand.blue.opacity(0.2) : Color.white.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func notice(_ text: String, @ViewBuilder action: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            action()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
    }
}

/// A Terminal command with a copy button.
private struct CopyCommand: View {
    let command: String
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
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy")
        }
    }
}
