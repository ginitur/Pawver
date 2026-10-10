import AppKit
import PawverCore

/// Combines all drag signals into a single decision:
///  - mouse press state (from the active engine, cross-checked with
///    NSEvent.pressedMouseButtons at trigger time),
///  - NSPasteboard(name: .drag).changeCount relative to the previous press
///    (auxiliary signal, instrumented — not trusted blindly),
///  - drag pasteboard types (must contain public.file-url),
///  - the shake gesture.
/// Every press with drag events is summarised in the log so the user's manual
/// tests (file drags, window drags, text selections) produce evidence.
@MainActor
final class DragSignalProcessor {
    private let pasteboard = NSPasteboard(name: .drag)
    private var tracker: DragSessionTracker
    private var shake: ShakeDetector
    private var triggeredThisPress = false
    private var shakeRejectionsThisPress = 0
    private var pressCounter = 0

    var requireDragPasteboardChange = true
    var onShake: ((CGPoint) -> Void)?

    init(config: ShakeConfig) {
        tracker = DragSessionTracker(initialChangeCount: NSPasteboard(name: .drag).changeCount)
        shake = ShakeDetector(config: config)
    }

    func updateShakeConfig(_ config: ShakeConfig) {
        shake = ShakeDetector(config: config)
        Diag.info(.shake, "shake config: minSwing=\(config.minSwingDistance)pt reversals=\(config.requiredReversals) window=\(config.timeWindow)s maxVerticalRatio=\(config.maxVerticalRatio) cooldown=\(config.cooldown)s")
    }

    /// Called after Pawver's own drag-out session wrote the drag pasteboard.
    func resetBaseline(reason: String) {
        let cc = pasteboard.changeCount
        tracker.resetBaseline(cc)
        Diag.debug(.drag, "baseline reset to changeCount=\(cc) (\(reason))")
    }

    private func dragTypes() -> [String] {
        pasteboard.types?.map(\.rawValue) ?? []
    }

    func mouseDown(engine: String, time: Double, location: CGPoint) {
        let cc = pasteboard.changeCount
        pressCounter += 1
        tracker.pressBegan(time: time, changeCount: cc)
        shake.resetMotion()
        triggeredThisPress = false
        shakeRejectionsThisPress = 0
        Diag.debug(.drag, "[\(engine)] press#\(pressCounter) mouseDown t=\(String(format: "%.3f", time)) loc=\(fmt(location)) changeCount=\(cc) idleBaseline=\(tracker.idleBaseline) buttons=\(NSEvent.pressedMouseButtons)")
    }

    func mouseDragged(engine: String, time: Double, location: CGPoint) {
        let cc = pasteboard.changeCount
        let classificationChanged = tracker.dragged(time: time, changeCount: cc, types: dragTypes)
        guard let r = tracker.current else { return }
        if r.draggedEvents == 1 {
            Diag.debug(.drag, "[\(engine)] press#\(pressCounter) first leftMouseDragged after \(ms(r.firstDraggedDelay)) loc=\(fmt(location)) changeCount=\(cc) implicitPress=\(r.implicitPress)")
        }
        if classificationChanged {
            Diag.info(.drag, "[\(engine)] press#\(pressCounter) classification → \(r.classification.rawValue) | changeCount=\(cc) idleBaseline=\(r.idleBaseline) atPress=\(r.changeCountAtPress) | change seen at drag event #\(r.changeObservedAtEvent.map(String.init) ?? "-") (\(ms(r.changeObservedDelay)) after press) | types=[\(r.typesAtClassification.joined(separator: ", "))] | buttons=\(NSEvent.pressedMouseButtons)")
        }

        guard !triggeredThisPress else { return }
        guard shake.addSample(x: location.x, y: location.y, time: time) else { return }

        let cls = r.classification
        let buttonDown = (NSEvent.pressedMouseButtons & 1) != 0
        let qualifies = cls == .confirmedFileDrag || (cls == .staleFileURL && !requireDragPasteboardChange)
        if qualifies && buttonDown {
            triggeredThisPress = true
            Diag.notice(.shake, "[\(engine)] press#\(pressCounter) SHAKE → open shelf at \(fmt(location)) classification=\(cls.rawValue) leftButtonDown=\(buttonDown) dragEvents=\(r.draggedEvents)")
            onShake?(location)
        } else {
            shakeRejectionsThisPress += 1
            Diag.info(.shake, "[\(engine)] press#\(pressCounter) shake recognised but NOT opening: classification=\(cls.rawValue) leftButtonDown=\(buttonDown) requireChange=\(requireDragPasteboardChange)")
        }
    }

    func mouseUp(engine: String, time: Double, location: CGPoint) {
        let cc = pasteboard.changeCount
        let report = tracker.pressEnded(time: time, changeCount: cc)
        shake.resetMotion()
        guard let r = report else { return }
        if r.draggedEvents == 0 {
            Diag.debug(.drag, "[\(engine)] press#\(pressCounter) click (no drag events) changeCount=\(cc)")
            return
        }
        Diag.info(.drag, "[\(engine)] press#\(pressCounter) SUMMARY classification=\(r.classification.rawValue) duration=\(ms(r.duration)) dragEvents=\(r.draggedEvents) firstDrag=\(ms(r.firstDraggedDelay)) | changeCount idle=\(r.idleBaseline) press=\(r.changeCountAtPress) end=\(cc) changedBeforePressObserved=\(r.changedBeforePressObserved) changeSeenAtEvent=\(r.changeObservedAtEvent.map(String.init) ?? "never") (\(ms(r.changeObservedDelay))) | fileURL=\(r.typesAtClassification.contains(DragSessionTracker.fileURLType)) | shakeTriggered=\(triggeredThisPress) shakeRejected=\(shakeRejectionsThisPress) implicitPress=\(r.implicitPress) | endLoc=\(fmt(location))")
    }
}
