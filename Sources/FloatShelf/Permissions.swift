import ApplicationServices
import CoreGraphics

/// Read-only permission probes. Phase 0's primary path (NSEvent global mouse
/// monitor + Carbon hot key) is not expected to need either permission; these
/// values are logged so the user's test run documents the actual state.
/// Nothing here requests a permission or opens a system prompt.
@MainActor
enum PermissionProbe {
    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }
    static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }

    static func summary() -> String {
        "Accessibility(AXIsProcessTrusted)=\(accessibilityTrusted) InputMonitoring(CGPreflightListenEventAccess)=\(inputMonitoringGranted)"
    }
}
