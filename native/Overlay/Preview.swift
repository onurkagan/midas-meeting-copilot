import AppKit
import SwiftUI

/// `midas-overlay --render-preview <folder>` draws the panel with a sample meeting in a
/// few states, in light (Tide) and dark (Tide at night), for design work: the live panel is
/// hidden from screenshots by design. Dark versions end in "-dark".
enum Preview {
    static func render(into folder: String) {
        _ = NSApplication.shared
        TideFont.register()
        for dark in [false, true] {
            let suffix = dark ? "-dark" : ""
            draw(sample(pending: false), settings: false, dark: dark, to: folder + "/meeting\(suffix).png")
            draw(sample(pending: true), settings: true, dark: dark, to: folder + "/drafting-settings\(suffix).png")
            draw(empty, settings: false, dark: dark, to: folder + "/empty\(suffix).png")
            draw(sample(pending: true, local: true), settings: true, ollama: models, dark: dark, to: folder + "/ollama-settings\(suffix).png")
            draw(meetingStart, settings: false, dark: dark, to: folder + "/consent\(suffix).png")
        }
    }

    private static func draw(_ snapshot: Snapshot, settings: Bool, ollama: OllamaCatalog? = nil, dark: Bool, to path: String) {
        let size = NSRect(x: 0, y: 0, width: 420, height: 640)
        let client = MidasClient(port: 0)
        client.apply(snapshot, since: 0)
        client.ollama = ollama
        // The desktop the glass sits on: a calm sea by day, the night sea in dark mode.
        let desk = dark
            ? LinearGradient(colors: [Color(hex: 0x0B2231), Color(hex: 0x0D4A55)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(hex: 0xCFE6F0), Color(hex: 0x6FAFCB)], startPoint: .top, endPoint: .bottom)
        let view = OverlayView(client: client, root: "/tmp", hide: {}, showSettings: settings)
            .modifier(TideTheme())
            .clipShape(RoundedRectangle(cornerRadius: panelRadius))
            .frame(width: size.width, height: size.height)
            .background(desk)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = size
        let window = NSWindow(contentRect: size, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// `local`: answered by an Ollama model, its reply still streaming in.
    private static func sample(pending: Bool, local: Bool = false) -> Snapshot {
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
            copilot: local
                ? CopilotSettings(provider: "ollama", model: "opus", effort: "medium", ollama_model: "llama3.2:3b")
                : CopilotSettings(model: "opus", effort: "medium"),
            session: 1, count: events.count, events: events,
            draft: local ? "**Postgres for now.** Our volumes are small, and we can move analytics to" : nil,
            privacy: privacy(reminder: false))
    }

    private static func privacy(reminder: Bool) -> PrivacySettings {
        PrivacySettings(
            reminder: reminder,
            notices: ["en": "Heads-up: I'm using an AI assistant on my Mac (Midas) that transcribes this call…", "tr": "Bilginize…"],
            local_only: false, auto_answer: false)
    }

    /// The first minutes of a meeting: the reminder to tell the others, and a stretch off the record.
    private static let meetingStart: Snapshot = {
        let lines: [(String, String, String)] = [
            ("10:00:12", "transcript", "Hi everyone, can you hear me okay?"),
            ("10:00:20", "transcript", "Great. Before we start, a quick personal matter, one second."),
            ("10:00:24", "marker", "Off the record"),
            ("10:02:41", "marker", "Back on the record"),
            ("10:02:45", "transcript", "Okay, first item: the hiring plan for next quarter."),
        ]
        let events = lines.enumerated().map { index, line in
            MidasEvent(id: index + 1, time: line.0, kind: line.1, text: line.2, title: "")
        }
        return Snapshot(
            status: "listening", paused: false, speaking: false, claude: "ready", pending_request: false, partial: "",
            copilot: CopilotSettings(model: "opus", effort: "medium"), session: 1, count: events.count, events: events,
            privacy: privacy(reminder: true))
    }()

    private static let models = OllamaCatalog(reachable: true, models: [
        OllamaModel(name: "gemma3:4b", size: 3_338_801_804, parameters: "4.3B", quantization: "Q4_K_M"),
        OllamaModel(name: "llama3.2:3b", size: 2_019_393_189, parameters: "3.2B", quantization: "Q4_K_M"),
        OllamaModel(name: "qwen3:8b", size: 5_225_388_164, parameters: "8.2B", quantization: "Q4_K_M"),
    ])

    private static let empty = Snapshot(
        status: "listening", paused: false, speaking: false, claude: "ready", pending_request: false, partial: "",
        copilot: CopilotSettings(model: "opus", effort: "medium"), session: 1, count: 0, events: [],
        privacy: privacy(reminder: false))
}
