import AppKit
import Carbon.HIToolbox

/// Global hot key ⌃⌥S.
///
/// Primary path: Carbon RegisterEventHotKey (no privacy permission needed).
/// Known platform limits (developer reports, see docs/PHASE0_TESTING.md):
/// the hot key is dispatched only if the frontmost app / input method does not
/// consume the key event first (e.g. some terminals, or IMEs composing
/// Option+letter), so it can silently not fire in some apps.
///
/// Diagnostics/robustness added after the Phase 0 test:
///  - every Carbon hot-key event (pressed AND released) is logged with the
///    frontmost app, so "never delivered" vs "delivered but no visible result"
///    can be told apart;
///  - registration can be repeated (menu item, wake from sleep, session
///    re-activation) and its status is shown in the menu;
///  - if — and only if — Accessibility is ALREADY granted, an NSEvent global
///    keyDown monitor is added as a second path (never requested by FloatShelf).
@MainActor
final class HotkeyManager {
    var onPress: (() -> Void)?

    private(set) var registrationStatus: OSStatus?
    private(set) var fireCount = 0
    private(set) var lastFire: Date?
    private(set) var keyMonitorActive = false

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var keyMonitor: Any?
    private var lastFireUptime: TimeInterval = 0

    static let signature: OSType = 0x4653_4846  // 'FSHF'
    static let hotKeyID: UInt32 = 1
    let keyCode = UInt32(kVK_ANSI_S)
    let carbonModifiers = UInt32(controlKey | optionKey)

    var isRegistered: Bool { hotKeyRef != nil && registrationStatus == noErr }

    @discardableResult
    func register(reason: String) -> OSStatus {
        unregister()
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let s = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let kind = GetEventKind(event)
            let signature = hkID.signature
            let id = hkID.id
            MainActor.assumeIsolated {
                Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                    .carbonEvent(kind: kind, paramStatus: s, signature: signature, id: id)
            }
            return noErr
        }, specs.count, &specs, context, &handlerRef)
        guard installStatus == noErr else {
            registrationStatus = installStatus
            Diag.error(.hotkey, "InstallEventHandler failed: \(installStatus) (reason=\(reason))")
            return installStatus
        }
        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(keyCode, carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        registrationStatus = status
        if status == noErr {
            Diag.info(.hotkey, "registered global hot key ⌃⌥S (Carbon, status=noErr, reason=\(reason), firedSoFar=\(fireCount))")
        } else {
            hotKeyRef = nil
            Diag.error(.hotkey, "RegisterEventHotKey ⌃⌥S failed: \(status)\(status == OSStatus(eventHotKeyExistsErr) ? " (eventHotKeyExistsErr: combination already registered)" : "") reason=\(reason)")
        }
        updateKeyMonitor()
        return status
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let h = handlerRef { RemoveEventHandler(h); handlerRef = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil; keyMonitorActive = false }
    }

    /// Second path, only when Accessibility is already trusted (never requested).
    private func updateKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        keyMonitorActive = false
        guard AXIsProcessTrusted() else {
            Diag.info(.hotkey, "NSEvent keyDown fallback not installed (Accessibility not granted; FloatShelf does not request it)")
            return
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            MainActor.assumeIsolated {
                guard let self, code == UInt16(kVK_ANSI_S),
                      flags.intersection([.control, .option, .command, .shift]) == [.control, .option] else { return }
                self.trigger(source: "nsevent-global-keyDown")
            }
        }
        keyMonitorActive = keyMonitor != nil
        Diag.info(.hotkey, "NSEvent keyDown fallback installed=\(keyMonitorActive) (Accessibility already granted)")
    }

    private func carbonEvent(kind: UInt32, paramStatus: OSStatus, signature: OSType, id: UInt32) {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        let kindName = kind == UInt32(kEventHotKeyPressed) ? "pressed" : (kind == UInt32(kEventHotKeyReleased) ? "released" : "kind=\(kind)")
        let ours = paramStatus == noErr && signature == Self.signature && id == Self.hotKeyID
        Diag.info(.hotkey, "carbon hot-key event \(kindName) ours=\(ours) paramStatus=\(paramStatus) frontmostApp=\(front) appActive=\(NSApp.isActive)")
        if ours && kind == UInt32(kEventHotKeyPressed) {
            trigger(source: "carbon")
        }
    }

    private func trigger(source: String) {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastFireUptime < 0.3 {
            Diag.debug(.hotkey, "duplicate trigger from \(source) ignored (<300ms)")
            return
        }
        lastFireUptime = now
        fireCount += 1
        lastFire = Date()
        Diag.notice(.hotkey, "hot key ⌃⌥S fired (source=\(source), count=\(fireCount), frontmostApp=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"))")
        onPress?()
    }

    var menuStatusText: String {
        let reg: String
        switch registrationStatus {
        case nil: reg = "未注册"
        case noErr?: reg = "已注册"
        case let s?: reg = "注册失败(\(s))"
        }
        var t = "快捷键 ⌃⌥S：\(reg)，已触发 \(fireCount) 次"
        if let d = lastFire {
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            t += "（最近 \(f.string(from: d))）"
        }
        if keyMonitorActive { t += "，含辅助功能后备" }
        return t
    }
}
