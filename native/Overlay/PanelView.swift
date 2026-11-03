import AppKit
import SwiftUI

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
