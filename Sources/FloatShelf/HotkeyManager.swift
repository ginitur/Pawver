import Carbon.HIToolbox
import Foundation

/// Global hot key via Carbon RegisterEventHotKey. Needs no privacy
/// permission (unlike NSEvent global keyDown monitors, which need
/// Accessibility). Default: Control + Option + S.
@MainActor
final class HotkeyManager {
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    static let signature: OSType = 0x4653_4846  // 'FSHF'

    @discardableResult
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_S), modifiers: UInt32 = UInt32(controlKey | optionKey)) -> OSStatus {
        unregister()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().fire()
            }
            return noErr
        }, 1, &spec, context, &handlerRef)
        guard installStatus == noErr else {
            Diag.error(.hotkey, "InstallEventHandler failed: \(installStatus)")
            return installStatus
        }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            Diag.info(.hotkey, "registered global hot key ⌃⌥S (Carbon RegisterEventHotKey, status=noErr)")
        } else {
            Diag.error(.hotkey, "RegisterEventHotKey ⌃⌥S failed: \(status)\(status == OSStatus(eventHotKeyExistsErr) ? " (already registered by another app)" : "")")
        }
        return status
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let h = handlerRef { RemoveEventHandler(h); handlerRef = nil }
    }

    private func fire() {
        Diag.notice(.hotkey, "hot key ⌃⌥S fired")
        onPress?()
    }
}
