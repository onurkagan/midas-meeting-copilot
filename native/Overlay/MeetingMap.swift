import AppKit
import SwiftUI

// MARK: - The meeting map, as the daemon serves it (src/midas/meeting_map.py)

/// The map's version and counts, sent with every snapshot so the panel knows when to
/// fetch the whole map.
struct MapInfo: Decodable, Equatable {
    let version: Int
    let state: String
    let counts: [String: Int]
    var saved: MapSaved? = nil
    var live: Bool? = nil  // the map follows the meeting by itself (a local model, or auto answer)

    /// Everything but the topics.
    var items: Int { counts.filter { $0.key != "topic" }.values.reduce(0, +) }
    var updating: Bool { state == "updating" }
    var error: String? { state.hasPrefix("error: ") ? String(state.dropFirst(7)) : nil }
}

struct MapSaved: Decodable, Equatable {
    var version: Int? = nil
    var at: String? = nil
    var png: String? = nil  // where the panel writes the picture of the map
}

/// A line of the meeting that a map item rests on.
struct MapSource: Decodable, Equatable, Identifiable {
    let id: Int
    let time: String
    let text: String

    var minute: String { String(time.prefix(5)) }
}

struct MapNode: Decodable, Equatable, Identifiable {
    let id: String
    let type: String  // topic, question, answer, decision, action, open
    let label: String
    var topic: String? = nil
    var parent: String? = nil  // the question an answer answers
    let sources: [MapSource]
    let time: String
    let first: Int
    var side: String? = nil  // "left" or "right" of the meeting on the graph
    var sub: String? = nil  // "Risk" or "Open question"
    var owner: String? = nil
    var due: String? = nil
    var said: Bool? = nil
    var done: Bool? = nil
    var carried: String? = nil  // the earlier meeting it came from, "2026-11-04_10-00"
    var y: Double? = nil  // its row on the graph; `side` says which side of the meeting

    /// What kind of item this is, as the panel names it.
    var kindName: String {
        switch type {
        case "topic": "Topic"
        case "question": "Asked of you"
        case "answer": said == true ? "You said" : "Your answer · draft"
        case "decision": "Decision"
        case "action": "Action item"
        default: sub ?? "Open"
        }
    }

    /// "4 Nov, 10:00" for an item carried over from an earlier meeting.
    var carriedFrom: String? {
        guard let carried, carried.count == 16 else { return nil }
        // English month names, like the rest of the panel, whatever the Mac's language.
        let english = Locale(identifier: "en_US_POSIX")
        let input = DateFormatter()
        input.locale = english
        input.dateFormat = "yyyy-MM-dd_HH-mm"
        guard let date = input.date(from: carried) else { return nil }
        let output = DateFormatter()
        output.locale = english
        output.dateFormat = "d MMM, HH:mm"
        return output.string(from: date)
    }

    /// Owner and due date of an action item, "Mert · Thursday".
    var assignment: String {
        [owner, due].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct MapLink: Decodable, Equatable {
    let from: String
    let to: String
}

struct MeetingMapData: Decodable, Equatable {
    let version: Int
    let state: String
    let title: String
    let date: String
    let start: String
    let updated: String
    let height: Double
    var picture: String? = nil  // where the panel draws the picture the HTML and PDF include
    let nodes: [MapNode]
    let links: [MapLink]
    var saved: MapSaved? = nil

    var topics: [MapNode] { nodes.filter { $0.type == "topic" }.sorted { $0.first < $1.first } }

    func node(_ id: String?) -> MapNode? { nodes.first { $0.id == id } }

    /// A topic's items in the order they came up, each question followed by its answers.
    func rows(of topic: String) -> [MapNode] {
        let items = nodes.filter { $0.topic == topic }
        let answered = Set(items.filter { $0.type == "answer" }.compactMap(\.parent))
        var rows: [MapNode] = []
        for item in items.sorted(by: { $0.first < $1.first }) {
            if item.type == "answer", let parent = item.parent, items.contains(where: { $0.id == parent }) { continue }
            rows.append(item)
            if answered.contains(item.id) {
                rows += items.filter { $0.type == "answer" && $0.parent == item.id }.sorted { $0.first < $1.first }
            }
        }
        return rows
    }

    func count(_ type: String) -> Int { nodes.filter { $0.type == type }.count }
}

/// The colours of the map's kinds of items, by day and at night.
enum MapPalette {
    static func color(_ type: String, dark: Bool) -> Color {
        switch type {
        case "question": Color(hex: dark ? 0x6CB8F0 : 0x2B86C9)
        case "answer": Color(hex: dark ? 0x5ED1C2 : 0x1E9688)
        case "decision": Color(hex: dark ? 0x8CCBF5 : 0x1F5FA8)
        case "action": Color(hex: dark ? 0xA8ABF7 : 0x5A5FC8)
        case "open": Color(hex: dark ? 0xF09A84 : 0xC95B43)
        default: Color(hex: dark ? 0x5AA6E6 : 0x1F6FB8)
        }
    }

    static let kinds: [(type: String, name: String)] = [
        ("decision", "decisions"), ("action", "action items"), ("question", "questions"), ("open", "open"),
    ]

    /// "1 decision", "4 action items", "2 open"
    static func count(_ type: String, _ n: Int) -> String {
        let name = kinds.first { $0.type == type }?.name ?? type
        return "\(n) \(n == 1 && name.hasSuffix("s") ? String(name.dropLast()) : name)"
    }
}

// MARK: - The card at the end of the timeline

/// When the meeting winds down (a summary, or a few quiet minutes), the map is offered at
/// the end of the timeline: what it holds, Update, and Save.
struct MapCard: View {
    @ObservedObject var client: MidasClient
    @Environment(\.tide) private var tide
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let info = client.snapshot?.map
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Icon(.map, size: 16)
                Text("Meeting map").font(Tide.font(13.5, .bold))
                Spacer(minLength: 4)
                if info?.updating == true {
                    ProgressView().controlSize(.mini)
                    Text("Updating…").font(Tide.font(11, .medium)).foregroundStyle(tide.muted)
                } else if let updated = client.meetingMap?.updated, !updated.isEmpty {
                    Text("Updated \(updated)").font(Tide.font(10.5, .medium)).monospacedDigit().foregroundStyle(tide.faint)
                }
            }
            .foregroundStyle(tide.accentText)
            if let info {
                HStack(spacing: 6) {
                    ForEach(MapPalette.kinds, id: \.type) { kind in
                        if let n = info.counts[kind.type], n > 0 {
                            HStack(spacing: 4) {
                                Circle().fill(MapPalette.color(kind.type, dark: scheme == .dark)).frame(width: 7, height: 7)
                                Text(MapPalette.count(kind.type, n))
                            }
                        }
                    }
                }
                .font(Tide.font(11.5, .medium))
                .foregroundStyle(tide.body)
                if let error = info.error {
                    Text(error).font(Tide.font(11)).foregroundStyle(tide.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Button(action: client.saveMap) {
                    Text(client.mapSaving ? "Saving…" : "Save map").font(Tide.font(12, .bold))
                }
                .buttonStyle(CompactPrimaryStyle())
                .disabled(client.mapSaving || info?.updating == true)
                .help("Save the map next to the meeting log: Markdown, JSON Canvas and a picture")
                Button(action: client.updateMap) {
                    Text("Update").font(Tide.font(12, .semibold))
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(info?.updating == true)
                .help(client.snapshot?.copilot?.isOllama == true
                    ? "Read the latest lines into the map now"
                    : "Send the lines since the last update to Claude and add what's new")
                Spacer(minLength: 0)
                if let saved = client.savedMapFile {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([saved])
                    } label: {
                        HStack(spacing: 4) {
                            Icon(.check, size: 12, weight: 2.2)
                            Text("Saved \(info?.saved?.at ?? "")")
                        }
                        .font(Tide.font(11, .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tide.foamText)
                    .help("Show in Finder")
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(tide.card))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tide.cardStroke))
        .padding(.vertical, 4)
    }
}

/// The Answer button's blue in a smaller size, for cards.
struct CompactPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.tide) private var tide

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 11).fill(tide.accent.opacity(configuration.isPressed ? 0.8 : 1)))
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(Rectangle())
    }
}
