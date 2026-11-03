// midas-audio: captures everything the Mac plays (system output) through a
// Core Audio process tap and streams it to stdout as mono signed 16-bit PCM.
// No virtual audio driver and no meeting bot: the tap is private to this process.
//
// Usage: midas-audio [--rate 16000]
// Status lines go to stderr, raw PCM goes to stdout.

import AVFoundation
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

final class SystemAudioCapture {
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

    func start() throws {
        let outputID = try defaultOutputDevice()
        let outputUID = try deviceUID(outputID)

        // Global stereo mixdown of every process; nothing is excluded or muted.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
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

var sampleRate = 16000.0
var disclaimed = false
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--rate":
        if let value = arguments.next(), let rate = Double(value) { sampleRate = rate }
    case "--disclaimed":
        disclaimed = true
    case "-h", "--help":
        print("usage: midas-audio [--rate 16000]  (PCM s16le mono on stdout)")
        exit(0)
    default:
        log("unknown argument: \(argument)")
        exit(64)
    }
}

if !disclaimed {
    relaunchAsResponsibleProcess()
}
AudioPermission.ensure()

let capture = SystemAudioCapture(sampleRate: sampleRate)
do {
    try capture.start()
} catch {
    log("error: \(error)")
    exit(1)
}

// Rebuild the tap when the user switches output (speakers <-> headphones).
var outputAddress = address(kAudioHardwarePropertyDefaultOutputDevice)
AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &outputAddress, DispatchQueue.main) {
    _, _ in
    log("default output device changed, restarting tap")
    capture.stop()
    do {
        try capture.start()
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
        capture.stop()
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

dispatchMain()
