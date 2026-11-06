import AppKit
import SwiftUI

/// The whole meeting in one scroll, oldest first: what was said, when you asked for an
/// answer, and the copilot's answers right where you asked for them.
struct TimelineView: View {
    @ObservedObject var client: MidasClient
    @Environment(\.tide) private var tide
    @State private var atBottom = true
    @State private var unseen = false
    private let bottom = "bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    if client.events.isEmpty && client.partial.isEmpty {
                        EmptyTimeline().padding(.top, 48)
                    }
                    let turns = Self.turns(client.events)
                    ForEach(Array(client.events.enumerated()), id: \.element.id) { index, event in
                        row(event, after: index > 0 ? client.events[index - 1] : nil, turn: turns.contains(event.id))
                    }
                    if client.pending { DraftingCard(name: client.copilotName, draft: client.draft) }
                    if !client.partial.isEmpty { LiveLine(text: client.partial) }
                    if client.offersMap && !client.pending { MapCard(client: client) }
                    Color.clear.frame(height: 1).id(bottom)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .modifier(BottomTracker(atBottom: $atBottom))
            .onAppear { proxy.scrollTo(bottom, anchor: .bottom) }
            .onChange(of: client.events.last?.id) { _, _ in
                // Follow the conversation while you're at the bottom; your requests and
                // the copilot's answers always come into view.
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
            .onChange(of: client.offersMap) { _, offers in
                if offers && atBottom { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottom, anchor: .bottom) } }
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
                        HStack(spacing: 4) { Icon(.arrowDown, size: 12, weight: 2.2); Text("New") }
                            .font(Tide.font(11, .bold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(tide.accent).shadow(color: tide.accent.opacity(0.3), radius: 6, y: 3))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    /// The lines where the speaker changes between the call and you (the microphone): they
    /// get a name. A meeting heard only from the call has none.
    private static func turns(_ events: [MidasEvent]) -> Set<Int> {
        var turns: Set<Int> = []
        var you = false
        for event in events where event.kind == "transcript" {
            if event.isYou != you { turns.insert(event.id) }
            you = event.isYou
        }
        return turns
    }

    @ViewBuilder
    private func row(_ event: MidasEvent, after previous: MidasEvent?, turn: Bool) -> some View {
        switch event.kind {
        case "transcript":
            // The time only where the minute changes keeps the column quiet.
            let sameMinute = previous?.kind == "transcript" && previous?.minute == event.minute
            TranscriptLine(event: event, showTime: !sameMinute, speaker: turn ? (event.isYou ? "You" : "Others") : nil)
        case "request":
            RequestMarker(event: event)
        case "marker":
            RecordMarker(event: event)
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
    @Environment(\.tide) private var tide

    var body: some View {
        Text(text)
            .font(Tide.font(10.5, .medium))
            .monospacedDigit()
            .foregroundStyle(tide.faint)
            .frame(width: 36, alignment: .leading)
    }
}

/// Something another participant said.
struct TranscriptLine: View {
    let event: MidasEvent
    let showTime: Bool
    var speaker: String? = nil  // "You" or "Others" where the speaker changes
    @Environment(\.tide) private var tide

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TimeLabel(text: showTime ? event.minute : "")
            VStack(alignment: .leading, spacing: 2) {
                if let speaker {
                    Text(speaker)
                        .font(Tide.font(10.5, .bold))
                        .foregroundStyle(event.isYou ? tide.accentText : tide.muted)
                }
                Text(event.text)
                    .font(Tide.font(13, event.isYou ? .medium : .regular))
                    .foregroundStyle(event.isYou ? tide.ink : tide.body)
                    .lineSpacing(1.5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.isYou ? "You" : "Others"): \(event.text)")
    }
}

/// Where you pressed Answer or asked the copilot something.
struct RequestMarker: View {
    let event: MidasEvent
    @Environment(\.tide) private var tide

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Icon(event.text.isEmpty ? .sparkle : .chat, size: 13, weight: 2)
            Text(event.text.isEmpty ? "You asked for an answer" : event.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(event.minute).foregroundStyle(tide.faint)
        }
        .font(Tide.font(11.5, .semibold))
        .foregroundStyle(tide.foamText)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 13).fill(tide.foamFill))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 4)
    }
}

/// Where you went off the record (⌃⌥P) and came back: nothing in between was transcribed.
struct RecordMarker: View {
    let event: MidasEvent
    @Environment(\.tide) private var tide

    var body: some View {
        let off = event.text.hasPrefix("Off")
        HStack(spacing: 6) {
            Icon(off ? .pause : .play, size: 12, weight: 2)
            Text(off ? "Off the record · not transcribing" : "Back on the record")
            Text(event.minute).foregroundStyle(tide.faint)
        }
        .font(Tide.font(11, .semibold))
        .foregroundStyle(tide.quietText)
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
        .background(Capsule().fill(tide.quiet))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

/// The copilot's reply, ready to say out loud.
struct AnswerCard: View {
    let event: MidasEvent
    @Environment(\.tide) private var tide
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(event.title.isEmpty ? "Suggested answer" : event.title)
                    .font(Tide.font(13.5, .bold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text(event.minute).font(Tide.font(10.5, .medium)).monospacedDigit().foregroundStyle(tide.faint)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(event.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Icon(copied ? .check : .copy, size: 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(tide.muted)
                .help("Copy")
                .accessibilityLabel("Copy the answer")
            }
            .foregroundStyle(tide.accentText)
            Text(markdown(event.text))
                .font(Tide.font(13.5))
                .foregroundStyle(tide.answerBody)
                .lineSpacing(2.5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(tide.answerFill))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tide.answerStroke, lineWidth: 1))
        .padding(.vertical, 4)
    }
}

/// Holds the place where the answer will appear; a streaming copilot (Ollama) fills it in
/// as it writes.
struct DraftingCard: View {
    let name: String
    let draft: String
    @Environment(\.tide) private var tide

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(draft.isEmpty ? "\(name) is drafting an answer…" : "\(name) is writing…")
                    .font(Tide.font(12.5, .medium))
                    .foregroundStyle(tide.muted)
            }
            if !draft.isEmpty {
                Text(markdown(draft))
                    .font(Tide.font(13.5))
                    .foregroundStyle(tide.answerBody.opacity(0.9))
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(tide.answerStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .padding(.vertical, 4)
    }
}

/// The sentence still being spoken.
struct LiveLine: View {
    let text: String
    @Environment(\.tide) private var tide

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            PulsingDot(color: tide.foam).frame(width: 36, alignment: .leading)
            Text(text + " …")
                .font(Tide.font(13).italic())
                .foregroundStyle(tide.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A calm pulse with a soft ripple, like a buoy light.
struct PulsingDot: View {
    var color: Color
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .background(Circle().fill(color.opacity(0.22)).frame(width: 15, height: 15).scaleEffect(dim ? 1 : 0.6))
            .opacity(dim ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
    }
}

struct EmptyTimeline: View {
    @Environment(\.tide) private var tide

    var body: some View {
        VStack(spacing: 10) {
            MidasMark(size: 46)
            Text("Listening to the meeting").font(Tide.font(14.5, .bold)).foregroundStyle(tide.ink)
            Text("Everything said appears here as it's transcribed.\nWhen you need a reply, press Answer (⌃⌥A).")
                .font(Tide.font(12))
                .foregroundStyle(tide.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
