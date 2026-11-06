import AppKit
import SwiftUI

/// The panel's two views: the meeting as it was said, and its map.
enum PanelTab { case timeline, map }

/// Timeline | Map, drawn by hand: a system segmented control would look out of place on the glass.
struct PanelTabs: View {
    @Binding var tab: PanelTab
    let news: Bool
    @Environment(\.tide) private var tide

    var body: some View {
        HStack(spacing: 2) {
            button("Timeline", .timeline, dot: false)
            button("Map", .map, dot: news)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 11).fill(tide.quiet))
    }

    private func button(_ title: String, _ value: PanelTab, dot: Bool) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { tab = value }
        } label: {
            HStack(spacing: 5) {
                Text(title).font(Tide.font(12, .semibold))
                if dot { Circle().fill(tide.foam).frame(width: 6, height: 6) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(tab == value ? tide.field : .clear)
                .shadow(color: .black.opacity(tab == value ? 0.08 : 0), radius: 2, y: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tab == value ? tide.ink : tide.muted)
        .accessibilityAddTraits(tab == value ? .isSelected : [])
        .help(dot ? "New items on the map" : title)
    }
}

/// The map in the panel: a list, topic by topic, since a graph doesn't fit 420 points. The
/// full graph opens in its own window.
struct MapTabView: View {
    @ObservedObject var client: MidasClient
    @Environment(\.tide) private var tide
    @State private var expanded: String?
    /// The export row, opened with Export.
    @State private var exporting = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    status
                    if let map = client.meetingMap, !map.nodes.isEmpty {
                        ForEach(map.topics) { topic in
                            TopicCard(client: client, map: map, topic: topic, expanded: $expanded)
                        }
                    } else {
                        empty
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            Rectangle().fill(tide.divider).frame(height: 1)
            if exporting {
                VStack(alignment: .leading, spacing: 5) {
                    MapExportButtons(client: client)
                    if let file = client.exported {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([file]) } label: {
                            HStack(spacing: 4) { Icon(.check, size: 12, weight: 2.2); Text("Exported \(file.lastPathComponent)").lineLimit(1) }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(tide.foamText)
                        .font(Tide.font(11, .semibold))
                        .help("Show in Finder")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 9)
            }
            actions.padding(.horizontal, 12).padding(.vertical, 9)
        }
        .onAppear(perform: client.markMapSeen)
        .onChange(of: client.meetingMap?.version) { _, _ in client.markMapSeen() }
    }

    /// How the map is kept: live with a local model, or when you ask with Claude.
    private var status: some View {
        let info = client.snapshot?.map
        return HStack(spacing: 6) {
            if info?.updating == true {
                ProgressView().controlSize(.mini)
                Text("Updating the map…")
            } else if client.mapIsLive {
                PulsingDot(color: tide.foam)
                Text("Live · \(client.copilotName) adds to it as the meeting goes")
            } else {
                Icon(.send, size: 12, weight: 2)
                Text("Updates when you press Answer, Summary or Update")
            }
            Spacer(minLength: 4)
            if let updated = client.meetingMap?.updated, !updated.isEmpty, info?.updating != true {
                Text(updated).monospacedDigit().foregroundStyle(tide.faint)
            }
        }
        .font(Tide.font(11, .medium))
        .foregroundStyle(client.mapIsLive ? tide.foamText : tide.muted)
        .lineLimit(1)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Icon(.map, size: 34, weight: 1.6).foregroundStyle(tide.accentText)
            Text("The map fills in as the meeting goes").font(Tide.font(14, .bold)).foregroundStyle(tide.ink)
            Text(client.mapIsLive
                ? "Topics, questions put to you, decisions and action items appear here every minute or so."
                : "Topics, questions put to you, decisions and action items appear here when you press Answer or Summary, or Update below. Nothing is sent to Claude otherwise.")
                .font(Tide.font(12)).foregroundStyle(tide.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let error = client.snapshot?.map?.error {
                Text(error).font(Tide.font(11.5)).foregroundStyle(tide.quietText).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
        .padding(.horizontal, 16)
    }

    private var actions: some View {
        let info = client.snapshot?.map
        let hasItems = (info?.items ?? 0) > 0
        return HStack(spacing: 8) {
            Button(action: client.updateMap) {
                HStack(spacing: 5) { Icon(.refresh, size: 13); Text("Update") }.font(Tide.font(12, .semibold))
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(info?.updating == true || !client.connected)
            .help(client.mapIsLive ? "Read the latest lines into the map now" : "Send the lines since the last update to Claude and add what's new")
            Button { MapWindowController.shared.show(client: client) } label: {
                HStack(spacing: 5) { Icon(.map, size: 13); Text("Full map") }.font(Tide.font(12, .semibold))
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!hasItems)
            .help("Open the map as a graph in its own window, also hidden from screen sharing")
            Button {
                withAnimation(.easeOut(duration: 0.15)) { exporting.toggle() }
            } label: {
                Text("Export").font(Tide.font(12, .semibold))
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!hasItems)
            .help("Save the map to share: PDF, Markdown or HTML, with every item's explanation")
            Spacer(minLength: 0)
            if let saved = client.savedMapFile, !client.mapSaving {
                Button { NSWorkspace.shared.activateFileViewerSelecting([saved]) } label: {
                    HStack(spacing: 4) { Icon(.check, size: 12, weight: 2.2); Text("Saved \(info?.saved?.at ?? "")") }
                        .font(Tide.font(11, .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(tide.foamText)
                .help("Show in Finder")
            }
            Button(action: client.saveMap) {
                Text(client.mapSaving ? "Saving…" : "Save map").font(Tide.font(12, .bold))
            }
            .buttonStyle(CompactPrimaryStyle())
            .disabled(!hasItems || client.mapSaving || info?.updating == true)
            .help("Save the map next to the meeting log: Markdown, JSON Canvas and a picture")
        }
    }
}

/// One topic and its items; an item opens to show the lines it came from.
private struct TopicCard: View {
    @ObservedObject var client: MidasClient
    let map: MeetingMapData
    let topic: MapNode
    @Binding var expanded: String?
    @Environment(\.tide) private var tide
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let rows = map.rows(of: topic.id)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(topic.label).font(Tide.font(13.5, .heavy)).foregroundStyle(tide.ink).lineLimit(1)
                Spacer(minLength: 4)
                ForEach(["decision", "action", "open"], id: \.self) { type in
                    let n = rows.filter { $0.type == type }.count
                    if n > 0 {
                        HStack(spacing: 3) {
                            Circle().fill(MapPalette.color(type, dark: scheme == .dark)).frame(width: 6, height: 6)
                            Text("\(n)").monospacedDigit()
                        }
                        .font(Tide.font(10.5, .semibold)).foregroundStyle(tide.muted)
                    }
                }
            }
            .padding(.bottom, 2)
            ForEach(rows) { row in
                ItemRow(client: client, node: row, expanded: expanded == row.id) {
                    withAnimation(.easeOut(duration: 0.15)) { expanded = expanded == row.id ? nil : row.id }
                }
                .padding(.leading, row.type == "answer" && row.parent != nil ? 18 : 0)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(tide.card))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tide.cardStroke))
    }
}

private struct ItemRow: View {
    @ObservedObject var client: MidasClient
    let node: MapNode
    let expanded: Bool
    let toggle: () -> Void
    @Environment(\.tide) private var tide

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    MapKindBadge(node: node, size: 15).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.label)
                            .font(Tide.font(12.5, .semibold))
                            .foregroundStyle(node.done == true ? tide.muted : tide.ink)
                            .strikethrough(node.done == true, color: tide.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if node.type == "action", !node.assignment.isEmpty {
                            Text(node.assignment).font(Tide.font(11, .medium)).foregroundStyle(tide.muted)
                        } else if node.type == "answer" {
                            Text(node.said == true ? "You said this" : "Draft · not marked as said")
                                .font(Tide.font(11, .medium)).foregroundStyle(node.said == true ? tide.foamText : tide.muted)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(node.time).font(Tide.font(10.5, .medium)).monospacedDigit().foregroundStyle(tide.faint)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(node.kindName): \(node.label)")
            .accessibilityHint(expanded ? "Hides where it came from" : "Shows where it came from")
            if expanded { details.padding(.leading, 22).padding(.bottom, 4) }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(node.sources) { source in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(source.minute).font(Tide.font(10, .medium)).monospacedDigit().foregroundStyle(tide.faint)
                    Text(markdown(source.text)).font(Tide.font(12)).foregroundStyle(tide.body)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
            HStack(spacing: 8) {
                if node.type == "answer" {
                    Button(node.said == true ? "Mark as draft" : "I said this") { client.mark(node, "said", node.said != true) }
                        .buttonStyle(node.said == true ? AnyButtonStyle(SecondaryButtonStyle()) : AnyButtonStyle(CompactPrimaryStyle()))
                }
                if node.type == "action" {
                    Button(node.done == true ? "Not done" : "Mark as done") { client.mark(node, "done", node.done != true) }
                        .buttonStyle(node.done == true ? AnyButtonStyle(SecondaryButtonStyle()) : AnyButtonStyle(CompactPrimaryStyle()))
                }
                Button("Remove") { client.removeFromMap(node) }
                    .buttonStyle(.plain)
                    .foregroundStyle(tide.muted)
                    .help("Take it off the map, for example if the model got it wrong")
            }
            .font(Tide.font(11.5, .semibold))
        }
    }
}
