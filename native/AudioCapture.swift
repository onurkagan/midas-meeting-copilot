// midas-audio: captures what one app plays (the meeting app), or everything the Mac
// plays, through a Core Audio process tap and streams it to stdout as mono signed
// 16-bit PCM. No virtual audio driver and no meeting bot: the tap is private to this
// process.
//
// Usage: midas-audio [--rate 16000] [--app <bundle ID> | --app auto] [--mic]
//        midas-audio --list   (the apps using audio, as JSON)
// With --app the tap runs only while that app uses the microphone, that is, while it is
// in a call; "auto" follows whichever app does. --mic captures the user's microphone
// instead, with macOS's echo cancellation, also only during that app's calls. Status
// lines go to stderr, raw PCM goes to stdout.

import AVFoundation
import AppKit
import AudioToolbox
import CoreAudio
import Foundation

signal(SIGPIPE, SIG_IGN)

func log(_ message: String) {
    FileHandle.standardError.write(Data(("[midas-audio] " + message + "\n").utf8))
}

struct CoreAudioError: Error, CustomStringConvertible {
    let what: String
    let status: OSStatus
    var description: String { "\(what) failed (OSStatus \(status))" }
}

func check(_ status: OSStatus, _ what: String) throws {
    if status != noErr { throw CoreAudioError(what: what, status: status) }
}

func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
}

func defaultOutputDevice() throws -> AudioObjectID {
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    var deviceID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    try check(
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID),
        "read default output device")
    return deviceID
}

func deviceUID(_ deviceID: AudioObjectID) throws -> String {
    var addr = address(kAudioDevicePropertyDeviceUID)
    var uid: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    try check(AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &uid), "read device UID")
    guard let uid else { throw CoreAudioError(what: "read device UID", status: -1) }
    return uid.takeRetainedValue() as String
}

func tapFormat(_ tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
    var addr = address(kAudioTapPropertyFormat)
    var asbd = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
    try check(AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &asbd), "read tap format")
    return asbd
}

/// Writes the whole buffer to stdout; exits quietly when the reader went away.
func writeStdout(_ pointer: UnsafeRawPointer, _ count: Int) {
    var offset = 0
    while offset < count {
        let written = write(STDOUT_FILENO, pointer + offset, count - offset)
        if written < 0 {
            if errno == EINTR { continue }
            exit(0)
        }
        offset += written
    }
}

// MARK: - Permission

/// macOS attributes the "System Audio Recording" permission to the responsible process:
/// the terminal or app that started us, which may never prompt (no usage string) and
/// differs per launcher. Re-spawning ourselves with responsibility disclaimed makes
/// midas-audio, with its embedded Info.plist, the one that asks and gets the grant.
func relaunchAsResponsibleProcess() {
    typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim"),
        let path = Bundle.main.executablePath
    else { return }
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    _ = unsafeBitCast(symbol, to: SetDisclaim.self)(&attributes, 1)

    let arguments = [path] + CommandLine.arguments.dropFirst() + ["--disclaimed"]
    var argv = arguments.map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) } }
    var pid: pid_t = 0
    guard posix_spawn(&pid, path, nil, &attributes, &argv, environ) == 0 else {
        log("could not relaunch as responsible process, continuing inline")
        return
    }

    childPID = pid
    for signalNumber in [SIGINT, SIGTERM] {
        signal(signalNumber) { received in kill(childPID, received) }
    }
    var status: Int32 = 0
    while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
    exit((status & 0x7f) == 0 ? (status >> 8) & 0xff : 1)
}

nonisolated(unsafe) var childPID: pid_t = 0

enum AudioPermission {
    private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    private static let service = "kTCCServiceAudioCapture" as CFString

    /// 0 granted, 1 denied, 2 not asked yet; nil when the TCC SPI is unavailable.
    static func status() -> Int? {
        typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
        guard let symbol = dlsym(tcc, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: Preflight.self)(service, nil)
    }

    static func request() -> Bool {
        typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void
        guard let symbol = dlsym(tcc, "TCCAccessRequest") else { return true }
        let done = DispatchSemaphore(value: 0)
        var granted = false
        unsafeBitCast(symbol, to: Request.self)(service, nil) { result in
            granted = result
            done.signal()
        }
        _ = done.wait(timeout: .now() + 300)
        return granted
    }

    static func ensure() {
        let deniedHelp =
            "error: no System Audio Recording permission. Enable midas-audio in System Settings › "
            + "Privacy & Security › Screen & System Audio Recording › System Audio Recording Only"
        switch status() {
        case 1:
            log(deniedHelp)
            exit(3)
        case 2:
            log("requesting System Audio Recording permission")
            if !request() {
                log(deniedHelp)
                exit(3)
            }
        default:
            break
        }
    }
}

/// Something the follower turns on for a call and off after it: the app's tap, or the microphone.
protocol CallCapture: AnyObject {
    var running: Bool { get }
    func start(processes: [AudioObjectID]?) throws
    func stop()
}

final class SystemAudioCapture: CallCapture {
    private let outputFormat: AVAudioFormat
    private let queue = DispatchQueue(label: "midas.audio.io", qos: .userInteractive)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var sourceFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var tapBufferCount = 1
    private var tapBuffers: UnsafeMutableAudioBufferListPointer?
    private var silentSince = Date()
    private var warnedSilence = false

    init(sampleRate: Double) {
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
    }

    /// Taps these processes (Core Audio process objects), or every process when nil.
    func start(processes: [AudioObjectID]?) throws {
        let outputID = try defaultOutputDevice()
        let outputUID = try deviceUID(outputID)

        // A stereo mixdown of the chosen processes, or of every process; nothing is muted.
        let description = processes.map { CATapDescription(stereoMixdownOfProcesses: $0) }
            ?? CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Midas"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tapID), "AudioHardwareCreateProcessTap")

        // The output device only provides the clock; the tap delivers the audio.
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Midas Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]
            ],
        ]
        try check(
            AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID),
            "AudioHardwareCreateAggregateDevice")

        var asbd = try tapFormat(tapID)
        guard let source = AVAudioFormat(streamDescription: &asbd) else {
            throw CoreAudioError(what: "unsupported tap format", status: -1)
        }
        guard let converter = AVAudioConverter(from: source, to: outputFormat) else {
            throw CoreAudioError(what: "create AVAudioConverter", status: -1)
        }
        converter.downmix = true
        self.sourceFormat = source
        self.converter = converter
        // Devices with inputs (headsets, AirPods) put their own streams first,
        // so the tap's buffers are always the last ones in the list.
        tapBufferCount = source.isInterleaved ? 1 : Int(source.channelCount)
        tapBuffers = AudioBufferList.allocate(maximumBuffers: tapBufferCount)

        try check(
            AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
                self?.process(input)
            }, "AudioDeviceCreateIOProcIDWithBlock")
        try check(AudioDeviceStart(aggregateID, procID), "AudioDeviceStart")

        log(
            "ready source=\(Int(source.sampleRate))Hz/\(source.channelCount)ch "
                + "output=\(Int(outputFormat.sampleRate))Hz/1ch/s16le device=\(outputUID)")
    }

    var running: Bool { aggregateID != kAudioObjectUnknown }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        queue.sync {
            converter = nil
            sourceFormat = nil
            tapBuffers?.unsafeMutablePointer.deallocate()
            tapBuffers = nil
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private func process(_ input: UnsafePointer<AudioBufferList>) {
        guard let sourceFormat, let converter, let tapBuffers else { return }
        let all = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard all.count >= tapBufferCount else { return }
        for index in 0..<tapBufferCount {
            tapBuffers[index] = all[all.count - tapBufferCount + index]
        }
        guard
            let inBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat, bufferListNoCopy: tapBuffers.unsafePointer, deallocator: nil),
            inBuffer.frameLength > 0
        else { return }

        let ratio = outputFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio) + 64
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return inBuffer
        }
        if let error {
            log("convert error: \(error.localizedDescription)")
            return
        }
        guard outBuffer.frameLength > 0, let samples = outBuffer.int16ChannelData?[0] else { return }
        noteSilence(samples, Int(outBuffer.frameLength))
        writeStdout(samples, Int(outBuffer.frameLength) * MemoryLayout<Int16>.size)
    }

    /// Without the "System Audio Recording" permission the tap delivers pure zeros.
    private func noteSilence(_ samples: UnsafePointer<Int16>, _ count: Int) {
        var allZero = true
        for i in 0..<count where samples[i] != 0 {
            allZero = false
            break
        }
        if !allZero {
            silentSince = Date()
            warnedSilence = false
        } else if !warnedSilence && Date().timeIntervalSince(silentSince) > 20 {
            warnedSilence = true
            log("silence: 20s of digital zeros (nothing playing, or permission missing)")
        }
    }
}

// MARK: - Microphone

/// The user's own voice, through macOS's voice processing: it removes what the speakers
/// play (the other participants) from the microphone, as call apps do.
final class MicrophoneCapture: CallCapture {
    private let outputFormat: AVAudioFormat
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var observer: NSObjectProtocol?

    init(sampleRate: Double) {
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
    }

    var running: Bool { engine != nil }

    func start(processes: [AudioObjectID]?) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        do {
            try input.setVoiceProcessingEnabled(true)
            // Leave the meeting app's volume alone.
            input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        } catch {
            log("echo cancellation unavailable, using the plain microphone: \(error.localizedDescription)")
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let converter = AVAudioConverter(from: format, to: outputFormat) else {
            throw CoreAudioError(what: "open the microphone", status: -1)
        }
        converter.downmix = true
        self.converter = converter
        input.installTap(onBus: 0, bufferSize: 1600, format: format) { [weak self] buffer, _ in self?.write(buffer) }
        _ = engine.mainMixerNode  // voice processing needs the output side of the graph too
        engine.prepare()
        try engine.start()
        self.engine = engine
        // Another microphone (AirPods, a headset): start over on it.
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, self.running else { return }
            log("microphone changed, restarting")
            self.stop()
            do { try self.start(processes: nil) } catch { log("error: microphone restart failed: \(error)") }
        }
        log("ready source=microphone \(Int(format.sampleRate))Hz/\(format.channelCount)ch output=\(Int(outputFormat.sampleRate))Hz/1ch/s16le")
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64)
        else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let samples = out.int16ChannelData?[0] else { return }
        writeStdout(samples, Int(out.frameLength) * MemoryLayout<Int16>.size)
    }
}

enum MicrophonePermission {
    static func ensure() {
        let help = "error: no Microphone permission. Enable midas-audio in System Settings › Privacy & Security › Microphone"
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            log("requesting Microphone permission")
            let done = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .audio) { result in
                granted = result
                done.signal()
            }
            _ = done.wait(timeout: .now() + 300)
            if !granted {
                log(help)
                exit(3)
            }
        default:
            log(help)
            exit(3)
        }
    }
}

// MARK: - Apps

/// A process Core Audio knows, and the app it plays for.
struct AudioProcess {
    let id: AudioObjectID
    let pid: pid_t
    let app: String  // the bundle ID of the app it plays for
    let name: String
    let output: Bool
    let input: Bool
}

enum AudioApps {
    private typealias Responsible = @convention(c) (pid_t) -> pid_t
    private static let responsible = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: Responsible.self) }

    static func processes() -> [AudioProcess] {
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        return ids.compactMap { id in
            let pid: pid_t = value(id, kAudioProcessPropertyPID) ?? -1
            guard pid > 0, pid != getpid(), let app = owner(of: id, pid: pid, apps: apps) else { return nil }
            return AudioProcess(
                id: id, pid: pid, app: app.bundleIdentifier ?? "", name: app.localizedName ?? app.bundleIdentifier ?? "",
                output: (value(id, kAudioProcessPropertyIsRunningOutput) as UInt32? ?? 0) != 0,
                input: (value(id, kAudioProcessPropertyIsRunningInput) as UInt32? ?? 0) != 0)
        }
    }

    /// The app a process plays for. Helpers belong to the app responsible for them (Chrome's
    /// helpers to Chrome, WebKit's to Safari); failing that, to the app whose bundle ID
    /// begins theirs. Midas itself and background agents belong to no app.
    private static func owner(of id: AudioObjectID, pid: pid_t, apps: [NSRunningApplication]) -> NSRunningApplication? {
        let boss = responsible?(pid) ?? pid
        if let app = apps.first(where: { $0.processIdentifier == boss || $0.processIdentifier == pid }) {
            return app.bundleIdentifier?.hasPrefix("dev.midas") == true ? nil : app
        }
        guard let bundle = bundleID(id), !bundle.hasPrefix("dev.midas") else { return nil }
        return apps.first { app in app.bundleIdentifier.map { bundle == $0 || bundle.hasPrefix($0 + ".") } ?? false }
    }

    private static func value<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, result) == noErr else { return nil }
        return result.pointee
    }

    private static func bundleID(_ id: AudioObjectID) -> String? {
        var addr = address(kAudioProcessPropertyBundleID)
        var bundle: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &bundle) == noErr, let bundle else { return nil }
        return bundle.takeRetainedValue() as String
    }

    /// The apps using audio, those in a call (microphone on) first, as JSON for the panel.
    static func list() -> String {
        var apps: [String: [String: Any]] = [:]
        for process in processes() {
            var app = apps[process.app] ?? ["bundle": process.app, "name": process.name, "output": false, "input": false]
            if process.output { app["output"] = true }
            if process.input { app["input"] = true }
            apps[process.app] = app
        }
        let sorted = apps.values.sorted { a, b in
            let rank = { (app: [String: Any]) in (app["input"] as! Bool ? 0 : 2) + (app["output"] as! Bool ? 0 : 1) }
            return rank(a) != rank(b) ? rank(a) < rank(b) : (a["name"] as! String) < (b["name"] as! String)
        }
        let data = try? JSONSerialization.data(withJSONObject: sorted, options: [.sortedKeys])
        return String(data: data ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }
}

/// Taps the meeting app only while it is in a call (its microphone is on), and nothing in
/// between: a video in another app, or in the same app outside a call, never reaches Midas.
final class AppFollower {
    private let target: String?  // a bundle ID, or nil to follow whichever app uses the microphone
    private let capture: CallCapture
    private var app: String?
    private var tapped: Set<AudioObjectID> = []
    private var watched: Set<AudioObjectID> = []
    private var micOffSince: Date?
    private var reported = ""
    /// A microphone briefly off (some apps release it on mute) doesn't end the call.
    private let grace: TimeInterval = 15

    init(target: String?, capture: CallCapture) {
        self.target = target
        self.capture = capture
    }

    func start() {
        var list = address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &list, .main) { [weak self] _, _ in
            self?.evaluate()
        }
        evaluate()
    }

    /// Rebuilds the tap after the output device changed, if it was running.
    func restart() {
        guard capture.running else { return }
        capture.stop()
        tapped = []
        evaluate()
    }

    func evaluate() {
        let processes = AudioApps.processes()
        watch(processes)
        let inCall = Set(processes.filter(\.input).map(\.app))
        if let target {
            app = target
        } else if app.map({ !inCall.contains($0) }) ?? true, let next = inCall.sorted().first {
            app = next  // the app in a call; a current one keeps the tap while it stays in its call
        }
        let members = processes.filter { $0.app == app }
        let name = members.first?.name ?? app ?? ""
        if members.contains(where: \.input) {
            micOffSince = nil
            let ids = Set(members.map(\.id))
            if !capture.running || ids != tapped {
                capture.stop()
                do {
                    try capture.start(processes: Array(ids))
                    tapped = ids
                    report("app: \(app ?? "") \(name)")
                } catch {
                    log("error: \(error)")
                }
            }
            return
        }
        guard capture.running else {
            report(app == nil || target == nil && inCall.isEmpty
                ? "waiting: no app is in a call (using the microphone)"
                : "waiting: \(name.isEmpty ? app ?? "" : name) isn't in a call (its microphone is off)")
            return
        }
        let since = micOffSince ?? Date()
        micOffSince = since
        if Date().timeIntervalSince(since) < grace {
            DispatchQueue.main.asyncAfter(deadline: .now() + grace + 0.1) { [weak self] in self?.evaluate() }
            return
        }
        capture.stop()
        tapped = []
        micOffSince = nil
        if target == nil { app = nil }
        log("stopped: \(name) left the call (microphone off)")
        reported = ""
        evaluate()
    }

    /// Listens for each process's microphone going on or off.
    private func watch(_ processes: [AudioProcess]) {
        for process in processes where !watched.contains(process.id) {
            watched.insert(process.id)
            var input = address(kAudioProcessPropertyIsRunningInput)
            AudioObjectAddPropertyListenerBlock(process.id, &input, .main) { [weak self] _, _ in self?.evaluate() }
        }
    }

    private func report(_ line: String) {
        if line != reported {
            reported = line
            log(line)
        }
    }
}

var sampleRate = 16000.0
var disclaimed = false
var follow: String?  // --app: a bundle ID, or "auto"
var microphone = false  // --mic: the user's own voice instead of the app's audio
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--rate":
        if let value = arguments.next(), let rate = Double(value) { sampleRate = rate }
    case "--disclaimed":
        disclaimed = true
    case "--app":
        follow = arguments.next()
    case "--mic":
        microphone = true
    case "--list":
        print(AudioApps.list())
        exit(0)
    case "-h", "--help":
        print("usage: midas-audio [--rate 16000] [--app <bundle ID>|auto] [--mic] | --list  (PCM s16le mono on stdout)")
        exit(0)
    default:
        log("unknown argument: \(argument)")
        exit(64)
    }
}

if !disclaimed {
    relaunchAsResponsibleProcess()
}
if microphone {
    MicrophonePermission.ensure()
    follow = follow ?? "auto"  // the microphone only ever runs during a call
} else {
    AudioPermission.ensure()
}

let capture = SystemAudioCapture(sampleRate: sampleRate)
let call: CallCapture = microphone ? MicrophoneCapture(sampleRate: sampleRate) : capture
let follower = follow.map { AppFollower(target: $0 == "auto" ? nil : $0, capture: call) }
if let follower {
    follower.start()
} else {
    do {
        try capture.start(processes: nil)
    } catch {
        log("error: \(error)")
        exit(1)
    }
}

// Rebuild the tap when the user switches output (speakers <-> headphones).
var outputAddress = address(kAudioHardwarePropertyDefaultOutputDevice)
AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &outputAddress, DispatchQueue.main) {
    _, _ in
    log("default output device changed, restarting tap")
    if let follower {
        follower.restart()
        return
    }
    capture.stop()
    do {
        try capture.start(processes: nil)
    } catch {
        log("error: restart failed: \(error)")
        exit(2)
    }
}

var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGINT, SIGTERM] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        call.stop()
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

// A run loop rather than dispatchMain(), so the list of running apps stays current.
RunLoop.main.run()
