import AppKit
import Carbon.HIToolbox

// MARK: - Global hotkeys (Carbon: no Accessibility permission needed)

enum HotKeys {
    static var handler: ((UInt32) -> Void)?
    static var refs: [EventHotKeyRef?] = []

    static func install(_ handler: @escaping (UInt32) -> Void) {
        self.handler = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                HotKeys.handler?(hotKeyID.id)
                return noErr
            }, 1, &spec, nil, nil)
        let modifiers = UInt32(controlKey | optionKey)
        for (id, key, name) in [(UInt32(1), kVK_ANSI_M, "⌃⌥M"), (2, kVK_ANSI_A, "⌃⌥A"), (3, kVK_ANSI_P, "⌃⌥P")] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(key), modifiers, EventHotKeyID(signature: OSType(0x4D44_4153), id: id),
                GetApplicationEventTarget(), 0, &ref)
            if status != noErr {
                FileHandle.standardError.write(Data("[midas-overlay] could not register the \(name) hotkey (\(status))\n".utf8))
            }
            refs.append(ref)
        }
    }
}
