import AppKit

/// Borderless, non-activating floating panel. It never becomes key or main,
/// so showing it (even mid-drag) does not take keyboard focus from the
/// frontmost app or activate FloatShelf.
final class ShelfPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Button that reacts to the first click even though its panel is never key.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
protocol ShelfDropHandling: AnyObject {
    func dropOperation(for info: NSDraggingInfo, phase: String) -> NSDragOperation
    func performDrop(_ info: NSDraggingInfo) -> Bool
    func dropTargetExited(_ info: NSDraggingInfo?)
}

/// Root view of the panel and the AppKit NSDraggingDestination for the whole
/// shelf (no SwiftUI onDrop). Registered for file URLs only in Phase 0.
final class ShelfDropView: NSView {
    weak var handler: ShelfDropHandling?
    var onTargetedChange: ((Bool) -> Void)?

    private var isTargeted = false {
        didSet { if oldValue != isTargeted { onTargetedChange?(isTargeted) } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = handler?.dropOperation(for: sender, phase: "entered") ?? []
        isTargeted = !op.isEmpty
        return op
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = handler?.dropOperation(for: sender, phase: "updated") ?? []
        isTargeted = !op.isEmpty
        return op
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isTargeted = false
        handler?.dropTargetExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        handler?.performDrop(sender) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isTargeted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isTargeted = false
    }
}

/// Flipped container so the item list grows downward from the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
