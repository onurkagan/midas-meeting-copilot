import AppKit
import Combine

// MARK: - Daemon client

struct MidasEvent: Decodable, Identifiable, Equatable {
    let id: Int
    let time: String
    let kind: String
    let text: String
    let title: String
}

struct CopilotSettings: Decodable, Equatable {
    let model: String
    let effort: String
}

struct Snapshot: Decodable {
    let status: String
    let paused: Bool
    let speaking: Bool
    let claude: String
    let pending_request: Bool
    let partial: String
    let transcript: [MidasEvent]
    let answers: [MidasEvent]
    let copilot: CopilotSettings?  // nil when Claude runs in a terminal, not under Midas
}

final class MidasClient: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var connected = false
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

    private func poll() {
        guard !inFlight else { return }
        inFlight = true
        var request = URLRequest(url: base.appendingPathComponent("snapshot"))
        request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let snapshot = data.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
            DispatchQueue.main.async {
                self.inFlight = false
                self.connected = snapshot != nil
                if let snapshot { self.snapshot = snapshot }
            }
        }.resume()
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

    var statusLine: String {
        guard connected, let snapshot else { return "can't reach the daemon" }
        let listening = snapshot.paused ? "paused" : snapshot.status
        return "\(listening) · Claude \(snapshot.claude)"
    }

    func togglePause() {
        post("control", ["action": snapshot?.paused == true ? "resume" : "pause"])
    }

    /// Restarts the copilot with another model or effort level.
    func setCopilot(model: String? = nil, effort: String? = nil) {
        var body: [String: Any] = ["action": "copilot"]
        if let model { body["model"] = model }
        if let effort { body["effort"] = effort }
        post("control", body)
    }

    /// Stops the whole of Midas (daemon, Claude copilot and this panel).
    func quit() {
        post("control", ["action": "quit"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }
}
