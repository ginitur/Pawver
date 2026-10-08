import AppKit
import FloatShelfCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    private(set) var shelf: ShelfController!
    private var processor: DragSignalProcessor!
    private var engine: DragEventEngine?
    private var statusController: StatusItemController?
    private let hotkey = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diag.verbose = settings.verbose
        Diag.configureFileMirror()
        let info = Bundle.main.infoDictionary ?? [:]
        Diag.notice(.app, "FloatShelf starting: version=\(info["CFBundleShortVersionString"] ?? "?") build=\(info["CFBundleVersion"] ?? "?") pid=\(ProcessInfo.processInfo.processIdentifier) bundle=\(Bundle.main.bundlePath) bundleID=\(Bundle.main.bundleIdentifier ?? "nil") macOS=\(ProcessInfo.processInfo.operatingSystemVersionString) logFile=\(Diag.logFileURL?.path ?? "none")")
        Diag.info(.permissions, "startup permission snapshot (read-only, nothing requested): \(PermissionProbe.summary())")

        shelf = ShelfController()
        shelf.dragOut.allowMove = { [weak self] in self?.settings.allowMoveOnDragOut ?? false }

        processor = DragSignalProcessor(config: .preset(settings.sensitivity))
        processor.onShake = { [weak self] point in
            self?.shelf.show(near: point, reason: "shake")
        }
        shelf.dragOut.onSessionEnded = { [weak self] in
            self?.processor.resetBaseline(reason: "own drag-out session ended")
        }
        applySettings()
        startEngine(settings.engine)

        hotkey.onPress = { [weak self] in
            self?.openShelf(reason: "hot key ⌃⌥S")
        }
        hotkey.register()

        statusController = StatusItemController(app: self)
        logScreens()
        Diag.notice(.app, "startup complete: engine=\(settings.engine.rawValue) sensitivity=\(settings.sensitivity.rawValue) requireChange=\(settings.requireDragPasteboardChange) allowMoveOnDragOut=\(settings.allowMoveOnDragOut) verbose=\(settings.verbose)")

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                Diag.info(.app, "screen parameters changed")
                self?.logScreens()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.stop()
        hotkey.unregister()
        Diag.notice(.app, "FloatShelf terminating")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Actions

    func openShelf(reason: String) {
        shelf.show(near: NSEvent.mouseLocation, reason: reason)
    }

    func setEngine(_ e: AppSettings.Engine) {
        settings.engine = e
        startEngine(e)
    }

    func setSensitivity(_ s: ShakeConfig.Sensitivity) {
        settings.sensitivity = s
        processor.updateShakeConfig(.preset(s))
    }

    func applySettings() {
        Diag.verbose = settings.verbose
        processor.requireDragPasteboardChange = settings.requireDragPasteboardChange
        processor.updateShakeConfig(.preset(settings.sensitivity))
        Diag.info(.app, "settings applied: verbose=\(settings.verbose) requireChange=\(settings.requireDragPasteboardChange)")
    }

    private func startEngine(_ e: AppSettings.Engine) {
        engine?.stop()
        let newEngine: DragEventEngine
        switch e {
        case .globalMonitor: newEngine = GlobalMonitorEngine(processor: processor)
        case .polling: newEngine = PollingEngine(processor: processor)
        }
        let ok = newEngine.start()
        engine = newEngine
        Diag.notice(.drag, "drag detection engine = \(newEngine.name) started=\(ok)")
    }

    func logScreens() {
        for (i, s) in NSScreen.screens.enumerated() {
            Diag.info(.app, "screen#\(i)\(i == 0 ? " (primary)" : "") '\(s.localizedName)' frame=\(fmt(s.frame)) visibleFrame=\(fmt(s.visibleFrame)) scale=\(s.backingScaleFactor)")
        }
    }
}
