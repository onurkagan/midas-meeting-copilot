// midas-overlay: floating answer panel that screen sharing and recording can't see
// (NSWindow.sharingType = .none). No Dock icon, never steals focus from the meeting app.
//
// Hotkeys: ⌃⌥M show/hide · ⌃⌥A ask Claude to answer now · ⌃⌥P pause/resume listening

import AppKit

var port = 47821
var parentPID: pid_t?
var root: String?
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--port": port = arguments.next().flatMap(Int.init) ?? port
    case "--parent-pid": parentPID = arguments.next().flatMap { pid_t($0) }
    case "--root": root = arguments.next()
    case "--print-pdf":
        // midas-overlay --print-pdf map.html map.pdf: the map's HTML on A4 pages, as Export › PDF does.
        guard let html = arguments.next(), let pdf = arguments.next() else { exit(64) }
        _ = NSApplication.shared
        MainActor.assumeIsolated {
            PDFPrinter.print(URL(fileURLWithPath: html), to: URL(fileURLWithPath: pdf)) { ok in exit(ok ? 0 : 1) }
        }
        NSApplication.shared.run()
    case "--render-preview":
        // Design check without a meeting: writes PNGs of the panel with sample data.
        guard let folder = arguments.next() else { exit(64) }
        Preview.render(into: folder)
        exit(0)
    default: break
    }
}

// Inside Midas.app (no daemon parent) the bundle names the runtime folder to start from.
let bundleRoot = Bundle.main.object(forInfoDictionaryKey: "MidasRoot") as? String
let launchesDaemon = parentPID == nil && bundleRoot != nil
if launchesDaemon { root = bundleRoot }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(port: port, parentPID: parentPID, root: root, launchesDaemon: launchesDaemon)
app.delegate = delegate
app.run()
