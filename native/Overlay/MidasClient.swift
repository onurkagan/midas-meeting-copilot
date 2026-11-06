import AppKit
import Combine

// MARK: - Daemon client

struct MidasEvent: Decodable, Identifiable, Equatable {
    let id: Int
    let time: String
    let kind: String  // "transcript", "request", "answer" or "marker" (off the record and back)
    let text: String
    let title: String
    var ts: Double? = nil  // Unix time
    var speaker: String? = nil  // transcript lines: "others" (the call) or "you" (the microphone)

    var isYou: Bool { speaker == "you" }

    /// "HH:MM", for the timeline.
    var minute: String { String(time.prefix(5)) }
}

struct CopilotSettings: Decodable, Equatable {
    var provider: String? = nil  // "claude" or "ollama"; older daemons send none
    let model: String  // Claude's
    let effort: String
    var ollama_model: String? = nil

    var isOllama: Bool { provider == "ollama" }
}

/// A model pulled into Ollama, as the daemon lists it.
struct OllamaModel: Decodable, Identifiable, Equatable {
    let name: String
    let size: Int64
    let parameters: String
    let quantization: String

    var id: String { name }
    /// "3.2B · 2.0 GB", written like Ollama writes the parameter count.
    var detail: String {
        [parameters, String(format: "%.1f GB", Double(size) / 1e9)].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct OllamaCatalog: Decodable {
    let reachable: Bool
    let models: [OllamaModel]
    var error: String? = nil
}

/// What the panel shows about privacy: the reminder to tell the others, and where answers go.
struct PrivacySettings: Decodable {
    let reminder: Bool
    let notices: [String: String]  // "en", "tr", or "custom": the message to paste into the chat
    let local_only: Bool
    let auto_answer: Bool
}

struct Snapshot: Decodable {
    let status: String
    let paused: Bool
    let speaking: Bool
    let claude: String
    let pending_request: Bool
    let partial: String
    let copilot: CopilotSettings?  // nil when Claude runs in a terminal, not under Midas
    let session: Double
    let count: Int
    let events: [MidasEvent]
    var draft: String? = nil  // the answer as a streaming copilot (Ollama) writes it
    var privacy: PrivacySettings? = nil
    var map: MapInfo? = nil  // the meeting map's version and counts; nil from older daemons
    var source: AudioSource? = nil  // what Midas listens to; nil from older daemons
    var mic: MicState? = nil  // the user's microphone; nil when it is turned off in config.toml
}

/// Midas's microphone: on during the chosen app's calls, and muted with ⌃⌥V.
struct MicState: Decodable, Equatable {
    let state: String  // listening (in a call), waiting
    let muted: Bool
}

/// What Midas listens to: "auto" (the app in a call), "all" (the whole Mac), an app's
/// bundle ID, or "file" in a test; and whether it hears it now.
struct AudioSource: Decodable, Equatable {
    let listen_to: String
    let app: String
    let name: String
    let state: String  // listening, waiting (for the app's call), all
    let browser: Bool
}

/// An app that uses audio, for the panel's Listen to list.
struct AudioApp: Decodable, Identifiable, Equatable {
    let bundle: String
    let name: String
    let output: Bool
    let input: Bool  // in a call: its microphone is on
    let browser: Bool
    var id: String { bundle }
}

private struct AudioAppList: Decodable {
    let apps: [AudioApp]
}

final class MidasClient: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    /// The whole meeting so far, oldest first; each poll fetches only what is new.
    @Published private(set) var events: [MidasEvent] = []
    @Published private(set) var connected = false
    /// Local models to choose from, fetched when the Ollama settings are shown.
    @Published var ollama: OllamaCatalog?
    @Published private(set) var refreshingOllama = false
    /// The apps using audio, fetched when the settings are shown.
    @Published private(set) var audioApps: [AudioApp]?
    /// Time to remind the user to tell the others: when Midas starts, and when speech
    /// returns after a long quiet spell (a new meeting).
    @Published private(set) var noticeDue = false
    /// The meeting map, fetched again whenever its version changes.
    @Published private(set) var meetingMap: MeetingMapData?
    /// From Save map until the daemon reports the map saved.
    @Published private(set) var mapSaving = false
    /// How many items the user has seen on the Map tab, for its "new" dot.
    @Published private(set) var mapSeen = 0
    private var mapFetching = false
    private var pictureVersion = 0
    private let base: URL
    private var timer: Timer?
    private var inFlight = false

    init(port: Int) {
        base = URL(string: "http://127.0.0.1:\(port)/api/")!
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    var pending: Bool { snapshot?.pending_request == true }
    var partial: String { snapshot?.partial ?? "" }
    var draft: String { snapshot?.draft ?? "" }
    /// Who answers: "Claude", or "Ollama" for a local model.
    var copilotName: String { snapshot?.copilot?.isOllama == true ? "Ollama" : "Claude" }

    private func poll() {
        guard !inFlight else { return }
        inFlight = true
        let since = events.last?.id ?? 0
        let url = base.appendingPathComponent("snapshot")
            .appending(queryItems: [URLQueryItem(name: "since", value: String(since))])
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let snapshot = data.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
            DispatchQueue.main.async {
                self.inFlight = false
                if let snapshot { self.apply(snapshot, since: since) } else { self.connected = false }
            }
        }.resume()
    }

    func apply(_ snapshot: Snapshot, since: Int) {
        let reminder = snapshot.privacy?.reminder == true
        if snapshot.session != self.snapshot?.session {
            // A new meeting (the daemon starts one after a long quiet) or a restarted daemon,
            // which numbers its events from 1 again: start over.
            events = since == 0 ? snapshot.events : []
            noticeDue = reminder
        } else {
            let last = events.last?.id ?? 0
            events += snapshot.events.filter { $0.id > last }
        }
        self.snapshot = snapshot
        connected = true
        if let info = snapshot.map {
            if info.version != meetingMap?.version || info.state != meetingMap?.state { fetchMap() }
            if mapSaving, let saved = info.saved?.version, saved == info.version { mapSaving = false }
            if mapSaving, info.error != nil { mapSaving = false }
            writePicture(info)
        }
    }

    /// Save map: the daemon writes the text files, the panel adds the picture of the graph.
    private func writePicture(_ info: MapInfo) {
        guard let version = info.saved?.version, let path = info.saved?.png, version != pictureVersion,
              let map = meetingMap, map.version == version else { return }
        pictureVersion = version
        let written = MainActor.assumeIsolated { MapPicture.write(map, to: path) }
        if !written { NSLog("Midas: couldn't write the map picture to \(path)") }
    }

    // MARK: Meeting map

    private func fetchMap() {
        guard !mapFetching else { return }
        mapFetching = true
        var request = URLRequest(url: base.appendingPathComponent("map"))
        request.timeoutInterval = 3
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let map = data.flatMap { try? JSONDecoder().decode(MeetingMapData.self, from: $0) }
            DispatchQueue.main.async {
                self.mapFetching = false
                if let map { self.meetingMap = map }
            }
        }.resume()
    }

    /// The map follows the meeting by itself (a local model, or auto answer).
    var mapIsLive: Bool { snapshot?.map?.live == true }

    var mapHasNews: Bool { (snapshot?.map?.items ?? 0) > mapSeen }

    func markMapSeen() { mapSeen = snapshot?.map?.items ?? mapSeen }

    /// For previews: a map without a daemon.
    func show(map: MeetingMapData) { meetingMap = map }

    /// Reads the lines since the last update into the map now.
    func updateMap() { post("map", ["action": "update"]) }

    /// Catches the map up, then saves it next to the meeting log.
    func saveMap() {
        mapSaving = true
        post("map", ["action": "save"])
    }

    /// The user's own marks: an answer they said, an action item that's done.
    func mark(_ node: MapNode, _ flag: String, _ value: Bool) {
        post("map", ["action": flag, "id": node.id, "value": value])
    }

    func removeFromMap(_ node: MapNode) { post("map", ["action": "remove", "id": node.id]) }

    /// The saved map's Markdown note, once Save map has run.
    var savedMapFile: URL? {
        guard let png = snapshot?.map?.saved?.png else { return nil }
        return URL(fileURLWithPath: String(png.dropLast(4)) + ".map.md")
    }

    /// The meeting seems to be winding down: its summary has come, or nobody has spoken
    /// for a few minutes. Then the timeline offers the map.
    var offersMap: Bool {
        guard let info = snapshot?.map, info.items > 0 else { return false }
        if mapSaving || info.updating { return true }
        if let request = events.last(where: { $0.kind == "request" }), request.text == Self.summaryRequest,
           events.last?.kind == "answer", events.last!.id > request.id {
            return true
        }
        guard let spoken = events.last(where: { $0.kind == "transcript" })?.ts else { return false }
        return Date().timeIntervalSince1970 - spoken >= 180
    }

    func dismissNotice() { noticeDue = false }

    /// Where answers are worked out, for the line under the Answer button.
    var destination: (text: String, local: Bool) {
        let privacy = snapshot?.privacy
        if let copilot = snapshot?.copilot, copilot.isOllama {
            let model = copilot.ollama_model.map { $0.isEmpty ? "" : " · \($0)" } ?? ""
            let lock = privacy?.local_only == true ? "Local only" : "Stays on this Mac"
            return ("\(lock) · Ollama\(model)", true)
        }
        if privacy?.auto_answer == true {
            return ("Claude reads the meeting as it happens (auto answer)", false)
        }
        return ("Sent to Claude only when you ask", false)
    }

    private func post(_ path: String, _ body: [String: Any]) {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { [weak self] _, _, _ in
            DispatchQueue.main.async { self?.poll() }
        }.resume()
    }

    func ask(_ text: String) { post("request", ["text": text]) }

    static let summaryRequest = "Summarize the meeting so far and list the action items."

    func summarize() { ask(Self.summaryRequest) }

    var statusLine: String {
        guard connected, let snapshot else { return "can't reach the daemon" }
        let listening = snapshot.paused ? "paused" : snapshot.status
        let model = snapshot.copilot?.isOllama == true ? snapshot.copilot?.ollama_model ?? "" : ""
        return "\(listening) · \(copilotName) \(snapshot.claude)" + (model.isEmpty ? "" : " (\(model))")
    }

    func togglePause() {
        post("control", ["action": snapshot?.paused == true ? "resume" : "pause"])
    }

    /// Midas mute: what you say isn't transcribed until you unmute.
    func toggleMute() {
        guard let mic = snapshot?.mic else { return }
        post("control", ["action": mic.muted ? "unmute" : "mute"])
    }

    /// Switches between Claude and Ollama, or restarts the copilot with another model or effort.
    func setCopilot(provider: String? = nil, model: String? = nil, effort: String? = nil, ollamaModel: String? = nil) {
        var body: [String: Any] = ["action": "copilot"]
        if let provider { body["provider"] = provider }
        if let model { body["model"] = model }
        if let effort { body["effort"] = effort }
        if let ollamaModel { body["ollama_model"] = ollamaModel }
        post("control", body)
    }

    func refreshOllama() {
        guard !refreshingOllama else { return }
        refreshingOllama = true
        var request = URLRequest(url: base.appendingPathComponent("ollama"))
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let catalog = data.flatMap { try? JSONDecoder().decode(OllamaCatalog.self, from: $0) }
            DispatchQueue.main.async {
                self.refreshingOllama = false
                // If the daemon didn't answer, keep the list from last time.
                if let catalog { self.ollama = catalog } else if self.ollama == nil {
                    self.ollama = OllamaCatalog(reachable: false, models: [], error: "Can't reach the Midas daemon.")
                }
            }
        }.resume()
    }

    func refreshApps() {
        var request = URLRequest(url: base.appendingPathComponent("apps"))
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let list = data.flatMap { try? JSONDecoder().decode(AudioAppList.self, from: $0) }
            DispatchQueue.main.async { if let list { self.audioApps = list.apps } }
        }.resume()
    }

    /// Shows these apps without asking the daemon (previews).
    func show(apps: [AudioApp]) { audioApps = apps }

    /// "auto", "all" or an app's bundle ID.
    func listen(to target: String) {
        post("control", ["action": "listen", "app": target])
    }

    /// Stops the whole of Midas (daemon, Claude copilot and this panel).
    func quit() {
        post("control", ["action": "quit"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }
}
