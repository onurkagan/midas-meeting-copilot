import AppKit
import SwiftUI

/// The whole meeting in one scroll, oldest first: what was said, when you asked for an
/// answer, and Claude's answers right where you asked for them.
struct TimelineView: View {
    @ObservedObject var client: MidasClient
    @State private var atBottom = true
    @State private var unseen = false
    private let bottom = "bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if client.events.isEmpty && client.partial.isEmpty {
                        EmptyTimeline().padding(.top, 48)
                    }
                    ForEach(Array(client.events.enumerated()), id: \.element.id) { index, event in
                        row(event, after: index > 0 ? client.events[index - 1] : nil)
                    }
                    if client.pending { DraftingCard(name: client.copilotName, draft: client.draft) }
                    if !client.partial.isEmpty { LiveLine(text: client.partial) }
                    Color.clear.frame(height: 1).id(bottom)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .modifier(BottomTracker(atBottom: $atBottom))
            .onAppear { proxy.scrollTo(bottom, anchor: .bottom) }
            .onChange(of: client.events.last?.id) { _, _ in
                // Follow the conversation while you're at the bottom; your requests and
                // Claude's answers always come into view.
                if atBottom || client.events.last?.kind != "transcript" {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottom, anchor: .bottom) }
                } else {
                    unseen = true
                }
            }
            .onChange(of: client.partial) { _, _ in
                if atBottom { proxy.scrollTo(bottom, anchor: .bottom) }
            }
            .onChange(of: client.draft) { _, _ in
                if atBottom { proxy.scrollTo(bottom, anchor: .bottom) }
            }
            .onChange(of: client.pending) { _, pending in
                if pending { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottom, anchor: .bottom) } }
            }
            .onChange(of: atBottom) { _, atBottom in
                if atBottom { unseen = false }
            }
            .overlay(alignment: .bottom) {
                if unseen {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottom, anchor: .bottom) }
                        unseen = false
                    } label: {
                        Label("New", systemImage: "arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Brand.blue))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ event: MidasEvent, after previous: MidasEvent?) -> some View {
        switch event.kind {
        case "transcript":
            // The time only where the minute changes keeps the column quiet.
            let sameMinute = previous?.kind == "transcript" && previous?.minute == event.minute
            TranscriptLine(event: event, showTime: !sameMinute)
        case "request":
            RequestMarker(event: event)
        default:
            AnswerCard(event: event)
        }
    }
}

/// Tracks whether the timeline is scrolled to the end (macOS 15+; earlier it always follows).
private struct BottomTracker: ViewModifier {
    @Binding var atBottom: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 40
            } action: { _, isAtBottom in
                atBottom = isAtBottom
            }
        } else {
            content
        }
    }
}

/// Inline Markdown (bold, italics, code), with "- " list items shown as bullets.
func markdown(_ text: String) -> AttributedString {
    let bulleted = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
        line.hasPrefix("- ") || line.hasPrefix("* ") ? "• " + line.dropFirst(2) : String(line)
    }.joined(separator: "\n")
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: bulleted, options: options)) ?? AttributedString(bulleted)
}

private struct TimeLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: 34, alignment: .leading)
    }
}

/// Something another participant said.
struct TranscriptLine: View {
    let event: MidasEvent
    let showTime: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TimeLabel(text: showTime ? event.minute : "")
            Text(event.text)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.82))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Where you pressed Answer or asked Claude something.
struct RequestMarker: View {
    let event: MidasEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: event.text.isEmpty ? "sparkles" : "text.bubble")
            Text(event.text.isEmpty ? "You asked for an answer" : event.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(event.minute).foregroundStyle(.tertiary)
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Brand.lightBlue)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 12).fill(Brand.blue.opacity(0.15)))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 4)
    }
}

/// Claude's reply, ready to say out loud.
struct AnswerCard: View {
    let event: MidasEvent
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "sparkles")
                Text(event.title.isEmpty ? "Suggested answer" : event.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text(event.minute).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(event.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy")
            }
            .foregroundStyle(Brand.lightBlue)
            Text(markdown(event.text))
                .font(.system(size: 13.5))
                .foregroundStyle(.white)
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Brand.blue.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Brand.blue.opacity(0.5), lineWidth: 1))
        .padding(.vertical, 4)
    }
}

/// Holds the place where the answer will appear; a streaming copilot (Ollama) fills it in
/// as it writes.
struct DraftingCard: View {
    let name: String
    let draft: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(draft.isEmpty ? "\(name) is drafting an answer…" : "\(name) is writing…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            if !draft.isEmpty {
                Text(markdown(draft))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Brand.blue.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .padding(.vertical, 4)
    }
}

/// The sentence still being spoken.
struct LiveLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            PulsingDot().frame(width: 34, alignment: .leading)
            Text(text + " …")
                .font(.system(size: 12.5).italic())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PulsingDot: View {
    var color = Brand.blue
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(dim ? 0.3 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
    }
}

struct EmptyTimeline: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: EarsArt.glyph(size: 44)).renderingMode(.template).foregroundStyle(Brand.blue)
            Text("Listening to the meeting").font(.system(size: 14, weight: .semibold))
            Text("Everything said appears here as it's transcribed.\nWhen you need a reply, press Answer (⌃⌥A).")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
