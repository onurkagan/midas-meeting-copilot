import AppKit
import SwiftUI

/// The full map in its own window. Like the panel it stays out of screen sharing and never
/// takes focus from the meeting app.
final class MapWindowController {
    static let shared = MapWindowController()
    private var panel: OverlayPanel?

    func show(client: MidasClient) {
        if panel == nil { panel = make(client: client) }
        panel?.appearance = TideAppearance.current.appearance
        panel?.orderFrontRegardless()
    }

    private func make(client: MidasClient) -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1140, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.sharingType = .none  // excluded from screen sharing, screenshots and recordings
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.title = "Meeting map"
        panel.minSize = NSSize(width: 640, height: 420)
        panel.contentView = NSHostingView(rootView: MapWindowView(client: client).modifier(TideTheme()))
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        if !panel.setFrameUsingName("MidasMap") { panel.center() }
        panel.setFrameAutosaveName("MidasMap")
        return panel
    }
}

struct MapWindowView: View {
    @ObservedObject var client: MidasClient
    @State private var selected: String?

    init(client: MidasClient, selected: String? = nil) {
        self.client = client
        _selected = State(initialValue: selected)
    }
    @Environment(\.tide) private var tide
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.leading, 78)  // clear of the close button
                .padding(.trailing, 16)
                .frame(height: 52)
            Rectangle().fill(tide.divider).frame(height: 1)
            if let map = client.meetingMap, !map.nodes.isEmpty {
                HStack(spacing: 0) {
                    GeometryReader { space in
                        // Fits the map to the window's width (down to 55 %), then scrolls.
                        let graph = MapMetrics.layout(map).size
                        let full = CGSize(width: graph.width + 56, height: graph.height + 56)
                        let scale = min(1, max(0.55, space.size.width / full.width))
                        ScrollView([.horizontal, .vertical]) {
                            MapGraph(map: map, selected: selected) { id in selected = selected == id ? nil : id }
                                .padding(28)
                                .scaleEffect(scale, anchor: .topLeading)
                                .frame(width: full.width * scale, height: full.height * scale, alignment: .topLeading)
                        }
                    }
                    .background(DotGrid())
                    Rectangle().fill(tide.divider).frame(width: 1)
                    ScrollView {
                        Group {
                            if let node = map.node(selected) {
                                MapDetail(client: client, map: map, node: node) { selected = $0 }
                            } else {
                                overview(map)
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: 300)
                }
            } else {
                VStack(spacing: 8) {
                    Icon(.map, size: 40, weight: 1.5).foregroundStyle(tide.accentText)
                    Text("Nothing on the map yet").font(Tide.font(15, .bold))
                    Text("It fills in as the meeting goes.").foregroundStyle(tide.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .font(Tide.font(13))
        .foregroundStyle(tide.ink)
        .background(scheme == .dark ? Color(hex: 0x07141D) : Color(hex: 0xF2F7FA))
        .onChange(of: client.meetingMap?.version) { _, _ in
            if client.meetingMap?.node(selected) == nil { selected = nil }
        }
    }

    private var toolbar: some View {
        let info = client.snapshot?.map
        return HStack(spacing: 10) {
            MidasMark(size: 22)
            Text(client.meetingMap?.title ?? "Meeting map").font(Tide.font(15, .heavy)).lineLimit(1)
            if let map = client.meetingMap {
                Text("\(map.date) · \(map.start)").font(Tide.font(11.5, .medium)).foregroundStyle(tide.muted)
            }
            if info?.updating == true {
                ProgressView().controlSize(.mini)
                Text("Updating…").font(Tide.font(11.5, .medium)).foregroundStyle(tide.muted)
            } else if client.mapIsLive {
                HStack(spacing: 5) { PulsingDot(color: tide.foam); Text("Live") }
                    .font(Tide.font(11.5, .semibold)).foregroundStyle(tide.foamText)
            }
            Spacer(minLength: 8)
            if let saved = client.savedMapFile, !client.mapSaving {
                Button { NSWorkspace.shared.activateFileViewerSelecting([saved]) } label: {
                    HStack(spacing: 4) { Icon(.check, size: 12, weight: 2.2); Text("Saved \(info?.saved?.at ?? "")") }
                        .font(Tide.font(11.5, .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(tide.foamText)
                .help("Show in Finder")
            }
            Button(action: client.updateMap) {
                HStack(spacing: 5) { Icon(.refresh, size: 13); Text("Update") }.font(Tide.font(12, .semibold))
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(info?.updating == true || !client.connected)
            Button(action: client.saveMap) {
                Text(client.mapSaving ? "Saving…" : "Save map").font(Tide.font(12, .bold))
            }
            .buttonStyle(CompactPrimaryStyle())
            .disabled((info?.items ?? 0) == 0 || client.mapSaving || info?.updating == true)
            .help("Save the map next to the meeting log: Markdown, JSON Canvas and a picture")
        }
    }

    private func overview(_ map: MeetingMapData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(map.title).font(Tide.font(17, .heavy))
            Text("\(map.date) · \(map.start)" + (map.updated.isEmpty ? "" : " · updated \(map.updated)"))
                .font(Tide.font(11.5, .medium)).foregroundStyle(tide.muted)
            VStack(alignment: .leading, spacing: 7) {
                ForEach([("topic", "Topics"), ("question", "Questions to you"), ("answer", "Your answers"),
                         ("decision", "Decisions"), ("action", "Action items"), ("open", "Open questions and risks")], id: \.0) { kind in
                    HStack(spacing: 8) {
                        Circle().fill(MapPalette.color(kind.0, dark: scheme == .dark)).frame(width: 8, height: 8)
                        Text(kind.1)
                        Spacer()
                        Text("\(map.count(kind.0))").font(Tide.font(13, .bold)).monospacedDigit()
                    }
                    .font(Tide.font(12.5))
                }
            }
            Text("Click an item to see the lines it came from. Dashed answers are drafts until you mark them as said; Midas doesn't hear your own voice.")
                .font(Tide.font(11.5)).foregroundStyle(tide.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A faint dot grid behind the graph, like squared paper.
private struct DotGrid: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let color = scheme == .dark ? Color(hex: 0x8CCBF5, opacity: 0.07) : Color(hex: 0x1F6FB8, opacity: 0.09)
            var x: CGFloat = 9
            while x < size.width {
                var y: CGFloat = 9
                while y < size.height {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2)), with: .color(color))
                    y += 18
                }
                x += 18
            }
        }
    }
}
