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
            draw(inBrowser, settings: true, apps: apps, dark: dark, to: folder + "/listen-settings\(suffix).png")
            draw(summarized, settings: false, dark: dark, to: folder + "/map-card\(suffix).png")
            draw(summarized, settings: false, map: sampleMap, dark: dark, to: folder + "/map-tab\(suffix).png")
            drawWindow(dark: dark, to: folder + "/map-window\(suffix).png")
        }
        if let map = sampleMap {
            MainActor.assumeIsolated {
                _ = MapPicture.write(map, to: folder + "/map-picture.png")
                _ = MapPicture.write(map, to: folder + "/map-picture-dark.png", dark: true)
            }
        }
    }

    /// The full-map window with an answer selected.
    private static func drawWindow(dark: Bool, to path: String) {
        let size = NSRect(x: 0, y: 0, width: 1140, height: 700)
        let client = MidasClient(port: 0)
        client.apply(summarized, since: 0)
        if let sampleMap { client.show(map: sampleMap) }
        let view = MapWindowView(client: client, selected: "n2")
            .modifier(TideTheme())
            .frame(width: size.width, height: size.height)
        render(view, size: size, dark: dark, to: path)
    }

    private static func render(_ view: some View, size: NSRect, dark: Bool, to path: String) {
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

    private static func draw(
        _ snapshot: Snapshot, settings: Bool, ollama: OllamaCatalog? = nil, map: MeetingMapData? = nil, apps: [AudioApp]? = nil,
        dark: Bool, to path: String
    ) {
        let size = NSRect(x: 0, y: 0, width: 420, height: 640)
        let client = MidasClient(port: 0)
        client.apply(snapshot, since: 0)
        client.ollama = ollama
        if let map { client.show(map: map) }
        if let apps { client.show(apps: apps) }
        // The desktop the glass sits on: a calm sea by day, the night sea in dark mode.
        let desk = dark
            ? LinearGradient(colors: [Color(hex: 0x0B2231), Color(hex: 0x0D4A55)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(hex: 0xCFE6F0), Color(hex: 0x6FAFCB)], startPoint: .top, endPoint: .bottom)
        let view = OverlayView(client: client, root: "/tmp", hide: {}, showSettings: settings, tab: map == nil ? .timeline : .map)
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
    /// A call in Chrome: Midas follows it and says that every tab is heard.
    private static var inBrowser: Snapshot {
        var snapshot = sample(pending: false)
        snapshot.source = AudioSource(listen_to: "auto", app: "com.google.Chrome", name: "Google Chrome", state: "listening", browser: true)
        return snapshot
    }

    private static let apps = [
        AudioApp(bundle: "com.google.Chrome", name: "Google Chrome", output: true, input: true, browser: true),
        AudioApp(bundle: "com.spotify.client", name: "Spotify", output: true, input: false, browser: false),
        AudioApp(bundle: "us.zoom.xos", name: "zoom.us", output: false, input: false, browser: false),
    ]

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
            ("10:02:41", "you", "Friday works for the core flow. Refunds can follow next sprint.", ""),
            ("10:03:02", "transcript", "Okay. And which database are we using for analytics?", ""),
        ]
        if pending { lines.append(("10:03:05", "request", "", "")) }
        let events = lines.enumerated().map { index, line in
            // "you": a line from the user's microphone.
            MidasEvent(
                id: index + 1, time: line.0, kind: line.1 == "you" ? "transcript" : line.1, text: line.2, title: line.3,
                speaker: line.1 == "you" ? "you" : line.1 == "transcript" ? "others" : nil)
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

    /// The end of a meeting: the summary has come, and the timeline offers the map.
    private static let summarized: Snapshot = {
        let lines: [(String, String, String, String)] = [
            ("10:24:40", "transcript", "Mert, let's add an alert for failed webhooks before Thursday.", ""),
            ("10:25:02", "request", MidasClient.summaryRequest, ""),
            (
                "10:25:09", "answer",
                "**Ship the happy path Friday**, refunds next sprint.\n- Mert: sandbox tests and the webhook alert by Thursday\n- Deniz: managed ClickHouse estimate by Tuesday\n- Open: who runs the ClickHouse cluster",
                "Meeting summary"
            ),
        ]
        let events = lines.enumerated().map { index, line in
            MidasEvent(id: index + 40, time: line.0, kind: line.1, text: line.2, title: line.3)
        }
        let counts = ["topic": 4, "question": 4, "answer": 4, "decision": 3, "action": 4, "open": 3]
        return Snapshot(
            status: "listening", paused: false, speaking: false, claude: "ready", pending_request: false, partial: "",
            copilot: CopilotSettings(model: "opus", effort: "medium"), session: 1, count: events.count, events: events,
            privacy: privacy(reminder: false), map: MapInfo(version: 3, state: "idle", counts: counts))
    }()

    /// The sample meeting's map, laid out by the daemon (src/midas/meeting_map.py).
    private static let sampleMap = try? JSONDecoder().decode(MeetingMapData.self, from: Data(sampleMapJSON.utf8))

    private static let sampleMapJSON = #"{"version":3,"state":"idle","title":"Payments sync","date":"5 Nov 2026","start":"10:00","updated":"10:28","height":520,"nodes":[{"id":"t1","type":"topic","label":"Payments launch","sources":[{"id":1,"time":"10:00:30","text":"Thanks for joining, everyone. Let's start with the payments project."}],"first":1,"time":"10:00","side":"left","y":146.0},{"id":"t2","type":"topic","label":"Analytics database","sources":[{"id":4,"time":"10:03:10","text":"Okay. And which database are we using for analytics?"}],"first":4,"time":"10:03","side":"right","y":146.0},{"id":"t3","type":"topic","label":"Launch comms","sources":[{"id":13,"time":"10:15:00","text":"Next, launch comms. Do we announce on Friday, or wait until Monday?"}],"first":13,"time":"10:15","side":"left","y":398.0},{"id":"t4","type":"topic","label":"Monitoring","sources":[{"id":17,"time":"10:21:00","text":"Last thing, monitoring. We don't have an alert when webhooks fail, do we?"}],"first":17,"time":"10:21","side":"right","y":398.0},{"id":"n1","type":"question","label":"Ship by Friday?","topic":"t1","sources":[{"id":2,"time":"10:02:05","text":"Can we realistically ship it by Friday, or should we move the deadline?"}],"first":2,"time":"10:02","side":"left","y":50},{"id":"n2","type":"answer","label":"Yes, core flow by Friday","topic":"t1","sources":[{"id":3,"time":"10:02:30","text":"**Friday works for the core flow.** I'd ship the happy path and treat refunds as a follow-up."}],"first":3,"time":"10:02","parent":"n1","said":true,"side":"left","y":98},{"id":"n3","type":"open","label":"Webhook retries need a day","topic":"t1","sources":[{"id":7,"time":"10:04:20","text":"The only thing I'm worried about is webhook retries. That needs one more day."}],"first":7,"time":"10:04","sub":"Risk","side":"left","y":146},{"id":"n4","type":"decision","label":"Happy path ships Friday","topic":"t1","sources":[{"id":8,"time":"10:05:00","text":"Okay, let's ship the happy path on Friday and do refunds next sprint."}],"first":8,"time":"10:05","side":"left","y":194},{"id":"n5","type":"action","label":"Sandbox tests","topic":"t1","sources":[{"id":9,"time":"10:06:10","text":"Mert, can you finish the sandbox tests by Thursday?"}],"first":9,"time":"10:06","owner":"Mert","due":"Thursday","done":false,"side":"left","y":242},{"id":"n6","type":"question","label":"Which analytics database?","topic":"t2","sources":[{"id":4,"time":"10:03:10","text":"Okay. And which database are we using for analytics?"},{"id":5,"time":"10:03:40","text":"We were thinking ClickHouse, but nobody has really decided."}],"first":4,"time":"10:03","side":"right","y":50},{"id":"n7","type":"answer","label":"ClickHouse for events","topic":"t2","sources":[{"id":6,"time":"10:04:05","text":"**ClickHouse for product events.** Billing data stays in Postgres, so finance reports don't change."}],"first":6,"time":"10:04","parent":"n6","said":true,"side":"right","y":98},{"id":"n8","type":"decision","label":"Go with ClickHouse","topic":"t2","sources":[{"id":10,"time":"10:07:00","text":"Alright, ClickHouse for events then."}],"first":10,"time":"10:07","side":"right","y":146},{"id":"n9","type":"open","label":"Who runs the cluster?","topic":"t2","sources":[{"id":11,"time":"10:09:00","text":"Do we host ClickHouse ourselves or go managed? And who is on call for it?"}],"first":11,"time":"10:09","sub":"Open question","side":"right","y":194},{"id":"n10","type":"action","label":"Managed ClickHouse estimate","topic":"t2","sources":[{"id":12,"time":"10:11:00","text":"Deniz, could you get a cost estimate for managed ClickHouse by Tuesday?"}],"first":12,"time":"10:11","owner":"Deniz","due":"Tuesday","done":false,"side":"right","y":242},{"id":"n11","type":"question","label":"Announce Friday or Monday?","topic":"t3","sources":[{"id":13,"time":"10:15:00","text":"Next, launch comms. Do we announce on Friday, or wait until Monday?"}],"first":13,"time":"10:15","side":"left","y":326},{"id":"n12","type":"answer","label":"Monday, once it's stable","topic":"t3","sources":[{"id":14,"time":"10:16:10","text":"**Monday.** Let it run quietly in production over the weekend, then announce."}],"first":14,"time":"10:16","parent":"n11","said":false,"side":"left","y":374},{"id":"n13","type":"decision","label":"Announce Monday 10:00","topic":"t3","sources":[{"id":15,"time":"10:18:00","text":"Fine, Monday at ten it is."}],"first":15,"time":"10:18","side":"left","y":422},{"id":"n14","type":"action","label":"Launch email","topic":"t3","sources":[{"id":16,"time":"10:19:00","text":"Ayşe will draft the launch email by Friday."}],"first":16,"time":"10:19","owner":"Ayşe","due":"Friday","done":false,"side":"left","y":470},{"id":"n15","type":"open","label":"No failed-webhook alert","topic":"t4","sources":[{"id":17,"time":"10:21:00","text":"Last thing, monitoring. We don't have an alert when webhooks fail, do we?"}],"first":17,"time":"10:21","sub":"Risk","side":"right","y":326},{"id":"n16","type":"action","label":"Webhook alert","topic":"t4","sources":[{"id":18,"time":"10:23:00","text":"Mert, let's add an alert for failed webhooks before Thursday."}],"first":18,"time":"10:23","owner":"Mert","due":"Thursday","done":false,"side":"right","y":374},{"id":"n17","type":"question","label":"Who watches launch day?","topic":"t4","sources":[{"id":19,"time":"10:24:00","text":"Who is watching the dashboards on launch day?"}],"first":19,"time":"10:24","side":"right","y":422},{"id":"n18","type":"answer","label":"I'll be on call Friday","topic":"t4","sources":[{"id":20,"time":"10:24:30","text":"**I'll be on call on Friday** and keep an eye on the payment dashboards."}],"first":20,"time":"10:24","parent":"n17","said":false,"side":"right","y":470}],"links":[{"from":"n3","to":"n15"}],"saved":{}}"#

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
