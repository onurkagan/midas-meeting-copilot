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
