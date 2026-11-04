import AppKit
import Combine

// MARK: - Daemon client

struct MidasEvent: Decodable, Identifiable, Equatable {
    let id: Int
    let time: String
    let kind: String  // "transcript", "request" or "answer"
    let text: String
    let title: String

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
}

final class MidasClient: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    /// The whole meeting so far, oldest first; each poll fetches only what is new.
    @Published private(set) var events: [MidasEvent] = []
    @Published private(set) var connected = false
    /// Local models to choose from, fetched when the Ollama settings are shown.
    @Published var ollama: OllamaCatalog?
    @Published private(set) var refreshingOllama = false
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
        if snapshot.session != self.snapshot?.session {
            // A (re)started daemon numbers its events from 1 again: start over.
            events = since == 0 ? snapshot.events : []
        } else {
            let last = events.last?.id ?? 0
            events += snapshot.events.filter { $0.id > last }
        }
        self.snapshot = snapshot
        connected = true
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

    func summarize() { ask("Summarize the meeting so far and list the action items.") }

    var statusLine: String {
        guard connected, let snapshot else { return "can't reach the daemon" }
        let listening = snapshot.paused ? "paused" : snapshot.status
        let model = snapshot.copilot?.isOllama == true ? snapshot.copilot?.ollama_model ?? "" : ""
        return "\(listening) · \(copilotName) \(snapshot.claude)" + (model.isEmpty ? "" : " (\(model))")
    }

    func togglePause() {
        post("control", ["action": snapshot?.paused == true ? "resume" : "pause"])
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

    /// Stops the whole of Midas (daemon, Claude copilot and this panel).
    func quit() {
        post("control", ["action": "quit"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }
}
