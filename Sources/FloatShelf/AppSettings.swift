import Foundation
import FloatShelfCore

/// Phase 0 settings, persisted in the app's own UserDefaults domain
/// (com.weijiaren.FloatShelf). Can also be set with `defaults write`.
@MainActor
final class AppSettings {
    enum Engine: String, CaseIterable {
        case globalMonitor
        case polling
    }

    private enum Key {
        static let engine = "DragDetectionEngine"
        static let sensitivity = "ShakeSensitivity"
        static let allowMove = "AllowMoveOnDragOut"
        static let verbose = "VerboseDiagnostics"
        static let requireChange = "ShakeRequiresDragPasteboardChange"
    }

    private let defaults = UserDefaults.standard

    var engine: Engine {
        get { Engine(rawValue: defaults.string(forKey: Key.engine) ?? "") ?? .globalMonitor }
        set { defaults.set(newValue.rawValue, forKey: Key.engine) }
    }

    var sensitivity: ShakeConfig.Sensitivity {
        get { ShakeConfig.Sensitivity(rawValue: defaults.string(forKey: Key.sensitivity) ?? "") ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: Key.sensitivity) }
    }

    /// Off by default: Phase 0 drag-out offers COPY only.
    var allowMoveOnDragOut: Bool {
        get { defaults.bool(forKey: Key.allowMove) }
        set { defaults.set(newValue, forKey: Key.allowMove) }
    }

    var verbose: Bool {
        get { defaults.bool(forKey: Key.verbose) }
        set { defaults.set(newValue, forKey: Key.verbose) }
    }

    /// On by default: only trigger on a confirmed (changeCount changed) file drag.
    var requireDragPasteboardChange: Bool {
        get { defaults.object(forKey: Key.requireChange) == nil ? true : defaults.bool(forKey: Key.requireChange) }
        set { defaults.set(newValue, forKey: Key.requireChange) }
    }
}
