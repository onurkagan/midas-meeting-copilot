import AppKit
import SwiftUI

// MARK: - Geometry

/// Where each item of the map sits. The daemon gives every node an anchor (meeting_map.py
/// layout); the panel sizes the pills to their text, as the page and the saved picture do.
enum MapMetrics {
    static let pill: CGFloat = 32
    static let topic: CGFloat = 36
    static let center = CGSize(width: 210, height: 60)

    private static var widths: [String: CGFloat] = [:]

    /// A pill's width: its label as SwiftUI sets it, plus the badge and padding. (Measured
    /// by SwiftUI itself: AppKit measures the variable font at its regular weight.)
    static func width(of node: MapNode) -> CGFloat {
        let topic = node.type == "topic"
        let key = (topic ? "t|" : "i|") + node.label
        if let width = widths[key] { return width }
        let text = Text(node.label).font(Tide.font(topic ? 14 : 12.5, topic ? .bold : .semibold)).fixedSize()
        let measured = MainActor.assumeIsolated { NSHostingView(rootView: text).fittingSize.width }
        let width = ceil(measured) + (topic ? 36 : 46)
        widths[key] = width
        return width
    }

    static func boxes(_ map: MeetingMapData) -> [String: CGRect] {
        var boxes: [String: CGRect] = [:]
        for node in map.nodes {
            guard let x = node.x, let y = node.y else { continue }
            let w = width(of: node)
            let h = node.type == "topic" ? topic : pill
            let left = node.align == "end" ? x - w : node.align == "start" ? x : x - w / 2
            boxes[node.id] = CGRect(x: left, y: y - h / 2, width: w, height: h)
        }
        boxes["meeting"] = CGRect(x: map.center.x - center.width / 2, y: map.center.y - center.height / 2,
                                  width: center.width, height: center.height)
        return boxes
    }

    struct Edge {
        let path: Path
        let from: String
        let to: String
        var related = false
    }

    /// Topic → item curves, question → answer stubs, and dashed links between items about the same issue.
    static func edges(_ map: MeetingMapData, _ boxes: [String: CGRect]) -> [Edge] {
        var edges: [Edge] = []
        for node in map.nodes {
            let parentID = node.type == "topic" ? "meeting" : node.parent ?? node.topic ?? "meeting"
            guard let child = boxes[node.id], let parent = boxes[parentID] else { continue }
            var path = Path()
            if node.type == "answer", node.parent != nil {
                stub(&path, from: parent, to: child, left: node.align == "end")
            } else {
                curve(&path, from: parent, to: child)
            }
            edges.append(Edge(path: path, from: parentID, to: node.id))
        }
        for link in map.links {
            guard let a = boxes[link.from], let b = boxes[link.to], let na = map.node(link.from), let nb = map.node(link.to) else { continue }
            var path = Path()
            if na.align == nb.align {
                let (top, bottom) = a.minY < b.minY ? (a, b) : (b, a)
                stub(&path, from: top, to: bottom, left: na.align == "end")
            } else {
                curve(&path, from: a, to: b)
            }
            edges.append(Edge(path: path, from: link.from, to: link.to, related: true))
        }
        return edges
    }

    /// A short line down the inner edge of a column.
    private static func stub(_ path: inout Path, from top: CGRect, to bottom: CGRect, left: Bool) {
        let x = left ? top.maxX - 17 : top.minX + 17
        path.move(to: CGPoint(x: x, y: top.maxY))
        path.addLine(to: CGPoint(x: x, y: bottom.minY))
    }

    /// A soft S from one box's facing edge to the other's.
    private static func curve(_ path: inout Path, from a: CGRect, to b: CGRect) {
        let toLeft = b.midX < a.midX
        let start = CGPoint(x: toLeft ? a.minX : a.maxX, y: a.midY)
        let end = CGPoint(x: toLeft ? b.maxX : b.minX, y: b.midY)
        let mid = (start.x + end.x) / 2
        path.move(to: start)
        path.addCurve(to: end, control1: CGPoint(x: mid, y: start.y), control2: CGPoint(x: mid, y: end.y))
    }
}

// MARK: - Pieces

/// The small round badge in front of an item: its kind, in its colour.
struct MapKindBadge: View {
    let node: MapNode
    var size: CGFloat = 19
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let ink = dark ? Color(hex: 0x07141D) : .white
        ZStack {
            Circle().fill(MapPalette.color(node.type, dark: dark))
            switch node.type {
            case "question": Text("?").font(Tide.font(size * 0.58, .heavy)).foregroundStyle(ink)
            case "open": Text("!").font(Tide.font(size * 0.58, .heavy)).foregroundStyle(ink)
            default: KindGlyph(type: node.type, done: node.done == true).stroke(ink, style: StrokeStyle(lineWidth: size * 0.095, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A check for decisions, a box (ticked when done) for action items, a little wave for answers.
private struct KindGlyph: Shape {
    let type: String
    let done: Bool

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 19
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: c.x + x * s, y: c.y + y * s) }
        var path = Path()
        switch type {
        case "decision":
            path.move(to: p(-4, 0.5)); path.addLine(to: p(-1.2, 3.2)); path.addLine(to: p(4, -2.8))
        case "action":
            path.addRoundedRect(in: CGRect(origin: p(-3.8, -3.8), size: CGSize(width: 7.6 * s, height: 7.6 * s)), cornerSize: CGSize(width: 1.6 * s, height: 1.6 * s))
            if done { path.move(to: p(-2, 0)); path.addLine(to: p(-0.5, 1.6)); path.addLine(to: p(2.2, -1.6)) }
        case "answer":
            path.move(to: p(-5, 0))
            path.addCurve(to: p(-0.8, 0), control1: p(-3.6, -3.4), control2: p(-2, -3.4))
            path.addCurve(to: p(3.2, 0), control1: p(0.4, 3.4), control2: p(2, 3.4))
            path.addCurve(to: p(5, 0), control1: p(3.8, -1.6), control2: p(4.4, -1.6))
        default: break
        }
        return path
    }
}

/// One item on the graph: a pill with its badge and label; topics are solid Tide blue.
struct MapPill: View {
    let node: MapNode
    var selected = false
    @Environment(\.tide) private var tide
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if node.type == "topic" {
            Text(node.label)
                .font(Tide.font(14, .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x1B62A8), Color(hex: 0x2A8FB6)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Capsule().strokeBorder(selected ? tide.accentText : .clear, lineWidth: 2))
        } else {
            let color = MapPalette.color(node.type, dark: scheme == .dark)
            let draft = node.type == "answer" && node.said != true
            HStack(spacing: 7) {
                MapKindBadge(node: node)
                Text(node.label)
                    .font(Tide.font(12.5, .semibold))
                    .foregroundStyle(tide.ink)
                    .strikethrough(node.done == true, color: tide.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(scheme == .dark ? Color(hex: 0x0C1D29) : .white))
            .overlay(Capsule().strokeBorder(color, style: StrokeStyle(lineWidth: selected ? 2.4 : 1.4, dash: draft ? [4, 3] : [])))
            .shadow(color: selected ? color.opacity(0.35) : .clear, radius: 6, y: 3)
        }
    }
}

/// The meeting itself, in the middle of the map.
private struct MapCenter: View {
    let map: MeetingMapData
    @Environment(\.tide) private var tide
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            MidasMark(size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(map.title).font(Tide.font(14.5, .heavy)).foregroundStyle(tide.ink).lineLimit(1)
                Text("\(map.date) · \(map.start)").font(Tide.font(10.5, .medium)).foregroundStyle(tide.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(scheme == .dark ? Color(hex: 0x0C1D29) : .white))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(tide.accent, lineWidth: 1.4))
    }
}

/// The whole map, drawn to scale: the full-map window and the saved picture.
struct MapGraph: View {
    let map: MeetingMapData
    var selected: String? = nil
    var select: ((String) -> Void)? = nil
    @Environment(\.tide) private var tide
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let boxes = MapMetrics.boxes(map)
        let edges = MapMetrics.edges(map, boxes)
        let risk = MapPalette.color("open", dark: scheme == .dark)
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for edge in edges {
                    let active = selected != nil && (edge.from == selected || edge.to == selected)
                    // A link across the map runs behind the middle, so it stays faint.
                    let across = edge.related && (boxes[edge.from]?.midX ?? 0 < map.center.x) != (boxes[edge.to]?.midX ?? 0 < map.center.x)
                    let color = edge.related ? risk.opacity(across && !active ? 0.4 : 0.75) : active ? tide.accent : tide.muted.opacity(0.32)
                    let style = StrokeStyle(lineWidth: active ? 2.2 : 1.6, lineCap: .round, dash: edge.related ? [5, 5] : [])
                    context.stroke(edge.path, with: .color(color), style: style)
                }
            }
            .frame(width: map.width, height: map.height)
            if let box = boxes["meeting"] {
                MapCenter(map: map).frame(width: box.width, height: box.height).position(x: box.midX, y: box.midY)
            }
            ForEach(map.nodes) { node in
                if let box = boxes[node.id] {
                    MapPill(node: node, selected: node.id == selected)
                        .frame(width: box.width, height: box.height)
                        .contentShape(Capsule())
                        .onTapGesture { select?(node.id) }
                        .position(x: box.midX, y: box.midY)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(node.kindName): \(node.label)")
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
        .frame(width: map.width, height: map.height)
    }
}

/// The picture Save map writes next to the meeting log (Tide by day, at twice the size).
enum MapPicture {
    @MainActor
    static func write(_ map: MeetingMapData, to path: String) -> Bool {
        let view = MapGraph(map: map)
            .padding(28)
            .background(Color(hex: 0xF2F7FA))
            .environment(\.tide, Tide.light)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}

// MARK: - Item details

/// Everything about one item: where it came from, and the user's marks.
struct MapDetail: View {
    @ObservedObject var client: MidasClient
    let map: MeetingMapData
    let node: MapNode
    var select: (String) -> Void
    @Environment(\.tide) private var tide
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(MapPalette.color(node.type, dark: scheme == .dark)).frame(width: 8, height: 8)
                Text(node.kindName).font(Tide.font(11, .bold))
            }
            .foregroundStyle(MapPalette.color(node.type, dark: scheme == .dark))
            Text(node.label).font(Tide.font(17, .heavy)).foregroundStyle(tide.ink).fixedSize(horizontal: false, vertical: true)
            Text([node.time, map.node(node.topic)?.label].compactMap { $0 }.joined(separator: " · "))
                .font(Tide.font(11.5, .medium)).monospacedDigit().foregroundStyle(tide.muted)
            if node.type == "action" {
                if !node.assignment.isEmpty { Text(node.assignment).font(Tide.font(12.5, .semibold)) }
                MarkButton(on: node.done == true, onLabel: "Done", offLabel: "Mark as done") { client.mark(node, "done", $0) }
            }
            if node.type == "answer" {
                Text(node.said == true
                    ? "Marked as said: it goes into the saved map as your answer."
                    : "Draft. Midas doesn't hear your voice, so it can't tell whether you said this.")
                    .font(Tide.font(11.5)).foregroundStyle(tide.muted).fixedSize(horizontal: false, vertical: true)
                MarkButton(on: node.said == true, onLabel: "You said this", offLabel: "I said this") { client.mark(node, "said", $0) }
            }
            if !node.sources.isEmpty {
                Text(node.type == "answer" ? "MIDAS SUGGESTED" : node.type == "topic" ? "WHERE IT STARTED" : "FROM THE MEETING")
                    .font(Tide.font(10, .bold)).tracking(0.8).foregroundStyle(tide.muted)
                ForEach(node.sources) { source in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.minute).font(Tide.font(10, .medium)).monospacedDigit().foregroundStyle(tide.faint)
                        Text(markdown(source.text)).font(Tide.font(12.5)).foregroundStyle(tide.body)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 11).fill(tide.field))
                }
            }
            let connected = connections
            if !connected.isEmpty {
                Text("CONNECTED").font(Tide.font(10, .bold)).tracking(0.8).foregroundStyle(tide.muted)
                FlowRow(items: connected) { other in
                    Button { select(other.id) } label: {
                        HStack(spacing: 5) {
                            Circle().fill(MapPalette.color(other.type, dark: scheme == .dark)).frame(width: 7, height: 7)
                            Text(other.label).lineLimit(1)
                        }
                        .font(Tide.font(11.5, .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(tide.field))
                        .overlay(Capsule().strokeBorder(tide.fieldStroke))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(role: .destructive) { client.removeFromMap(node) } label: {
                Text(node.type == "topic" ? "Remove this topic" : "Remove from the map").font(Tide.font(11.5, .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(tide.muted)
            .help("Take it off the map, for example if the model got it wrong")
        }
    }

    private var connections: [MapNode] {
        var ids: [String] = []
        if node.type != "topic", let topic = node.topic { ids.append(topic) }
        if let parent = node.parent { ids.append(parent) }
        ids += map.nodes.filter { $0.parent == node.id || (node.type == "topic" && $0.topic == node.id) }.map(\.id)
        for link in map.links {
            if link.from == node.id { ids.append(link.to) }
            if link.to == node.id { ids.append(link.from) }
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }.compactMap { map.node($0) }
    }
}

/// A toggle drawn as a pill: "I said this" / "You said this".
private struct MarkButton: View {
    let on: Bool
    let onLabel: String
    let offLabel: String
    let set: (Bool) -> Void
    @Environment(\.tide) private var tide

    var body: some View {
        Button { set(!on) } label: {
            HStack(spacing: 5) {
                if on { Icon(.check, size: 12, weight: 2.2) }
                Text(on ? onLabel : offLabel)
            }
            .font(Tide.font(12, .bold))
        }
        .buttonStyle(on ? AnyButtonStyle(SecondaryButtonStyle()) : AnyButtonStyle(CompactPrimaryStyle()))
    }
}

struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// Chips that wrap onto new lines.
struct FlowRow<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: 6) { ForEach(items) { content($0) } }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += min(size.width, width) + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += min(size.width, bounds.width) + spacing
            line = max(line, size.height)
        }
    }
}
