import AppKit

@MainActor
protocol DragEventEngine: AnyObject {
    var name: String { get }
    func start() -> Bool
    func stop()
}

/// Primary engine: NSEvent global monitors for left mouse down/dragged/up.
/// Apple documents that only key events require Accessibility for global
/// monitors; whether mouse events keep arriving during another app's drag
/// session on this macOS version is exactly what Phase 0 tests.
@MainActor
final class GlobalMonitorEngine: DragEventEngine {
    let name = "global"
    private let processor: DragSignalProcessor
    private var monitor: Any?
    private var loggedFirstDrag = false

    init(processor: DragSignalProcessor) {
        self.processor = processor
    }

    func start() -> Bool {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
        if monitor == nil {
            Diag.error(.drag, "addGlobalMonitorForEvents returned nil")
            return false
        }
        Diag.info(.drag, "global monitor installed (leftMouseDown/Dragged/Up)")
        return true
    }

    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
            Diag.info(.drag, "global monitor removed")
        }
    }

    private func handle(_ event: NSEvent) {
        let loc = Self.appKitLocation(of: event)
        switch event.type {
        case .leftMouseDown:
            processor.mouseDown(engine: name, time: event.timestamp, location: loc)
        case .leftMouseDragged:
            if !loggedFirstDrag {
                loggedFirstDrag = true
                Diag.info(.drag, "global monitor received its first leftMouseDragged (cg→appkit loc=\(fmt(loc)) NSEvent.mouseLocation=\(fmt(NSEvent.mouseLocation)))")
            }
            processor.mouseDragged(engine: name, time: event.timestamp, location: loc)
        case .leftMouseUp:
            processor.mouseUp(engine: name, time: event.timestamp, location: loc)
        default:
            break
        }
    }

    /// CG event locations use a top-left origin on the primary screen;
    /// AppKit uses bottom-left: y_appkit = primary.maxY - y_cg.
    static func appKitLocation(of event: NSEvent) -> CGPoint {
        if let cg = event.cgEvent?.location, let primary = NSScreen.screens.first {
            return CGPoint(x: cg.x, y: primary.frame.maxY - cg.y)
        }
        return NSEvent.mouseLocation
    }
}

/// Permission-free fallback for comparison: polls NSEvent.pressedMouseButtons
/// at 5 Hz while idle and samples NSEvent.mouseLocation at 60 Hz only while
/// the left button is held.
@MainActor
final class PollingEngine: DragEventEngine {
    let name = "polling"
    static let idleInterval: TimeInterval = 0.2
    static let activeInterval: TimeInterval = 1.0 / 60.0

    private let processor: DragSignalProcessor
    private var timer: Timer?
    private var pressed = false
    private var lastLocation: CGPoint = .zero

    init(processor: DragSignalProcessor) {
        self.processor = processor
    }

    func start() -> Bool {
        schedule(Self.idleInterval)
        Diag.info(.drag, "polling engine started (idle \(Int(1 / Self.idleInterval)) Hz, active \(Int(1 / Self.activeInterval)) Hz)")
        return true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if pressed {
            pressed = false
            processor.mouseUp(engine: name, time: ProcessInfo.processInfo.systemUptime, location: NSEvent.mouseLocation)
        }
        Diag.info(.drag, "polling engine stopped")
    }

    private func schedule(_ interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let down = (NSEvent.pressedMouseButtons & 1) != 0
        let now = ProcessInfo.processInfo.systemUptime
        let loc = NSEvent.mouseLocation
        if down && !pressed {
            pressed = true
            lastLocation = loc
            processor.mouseDown(engine: name, time: now, location: loc)
            schedule(Self.activeInterval)
        } else if down && pressed {
            if loc != lastLocation {
                lastLocation = loc
                processor.mouseDragged(engine: name, time: now, location: loc)
            }
        } else if !down && pressed {
            pressed = false
            processor.mouseUp(engine: name, time: now, location: loc)
            schedule(Self.idleInterval)
        }
    }
}
