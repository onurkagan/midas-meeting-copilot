import AppKit
import SwiftUI

/// `midas-overlay --render-preview <folder>` draws the panel with a sample meeting in a
/// few states, for design work: the live panel is hidden from screenshots by design.
enum Preview {
    static func render(into folder: String) {
        _ = NSApplication.shared
        let meeting = sample(pending: false)
        draw(meeting, settings: false, to: folder + "/meeting.png")
        draw(sample(pending: true), settings: true, to: folder + "/drafting-settings.png")
        draw(empty, settings: false, to: folder + "/empty.png")
    }

    private static func draw(_ snapshot: Snapshot, settings: Bool, to path: String) {
        let size = NSRect(x: 0, y: 0, width: 420, height: 640)
        let client = MidasClient(port: 0)
        client.apply(snapshot, since: 0)
        let view = OverlayView(client: client, root: "/tmp", hide: {}, showSettings: settings)
            .frame(width: size.width, height: size.height)
            .background(Color(red: 0.12, green: 0.13, blue: 0.16))
        let hosting = NSHostingView(rootView: view)
        hosting.frame = size
        let window = NSWindow(contentRect: size, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static func sample(pending: Bool) -> Snapshot {
        var lines: [(String, String, String, String)] = [
            ("10:02:05", "transcript", "Thanks for joining, everyone. Let's start with the payments project.", ""),
            ("10:02:11", "transcript", "The API integration is mostly done, testing starts tomorrow.", ""),
            ("10:02:24", "transcript", "Can we realistically ship it by Friday, or should we move the deadline?", ""),
            ("10:02:26", "request", "", ""),
            (
                "10:02:30", "answer",
                "**Friday works for the core flow.** I'd ship the happy path and treat refunds as a follow-up.\n- Sandbox tests finish Thursday\n- Risk: webhook retries, needs one more day",
                "Ship payments by Friday?"
            ),
            ("10:03:02", "transcript", "Okay. And which database are we using for analytics?", ""),
        ]
        if pending { lines.append(("10:03:05", "request", "", "")) }
        let events = lines.enumerated().map { index, line in
            MidasEvent(id: index + 1, time: line.0, kind: line.1, text: line.2, title: line.3)
        }
        return Snapshot(
            status: "listening", paused: false, speaking: true, claude: pending ? "thinking" : "ready",
            pending_request: pending, partial: pending ? "" : "We were thinking ClickHouse, but",
            copilot: CopilotSettings(model: "opus", effort: "medium"), session: 1, count: events.count,
            events: events)
    }

    private static let empty = Snapshot(
        status: "listening", paused: false, speaking: false, claude: "ready", pending_request: false, partial: "",
        copilot: CopilotSettings(model: "opus", effort: "medium"), session: 1, count: 0, events: [])
}
