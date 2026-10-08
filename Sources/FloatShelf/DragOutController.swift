import AppKit
import FloatShelfCore

/// NSDraggingSource for dragging shelf items out to Finder, browsers, etc.
///
/// Semantics (Apple docs): the source declares the operations it permits in
/// draggingSession(_:sourceOperationMaskFor:); if the source does not ignore
/// modifier keys, the system combines that mask with the modifier keys; the
/// destination then chooses one operation and reports it back through
/// draggingSession(_:endedAt:operation:). The source is responsible for any
/// follow-up of a move. FloatShelf never touches the file itself.
///
/// Phase 0 offers COPY only to other apps. MOVE is added only if the user
/// enables the experimental setting. DELETE is never offered.
@MainActor
final class DragOutController: NSObject, NSDraggingSource {
    weak var shelf: ShelfController?
    var allowMove: () -> Bool = { false }
    var onSessionEnded: (() -> Void)?

    private var activeItems: [Int: [ShelfItem]] = [:]

    func outsideMask() -> NSDragOperation {
        allowMove() ? [.copy, .move] : [.copy]
    }

    func beginDrag(items: [ShelfItem], from view: NSView, event: NSEvent, imageFrame: NSRect) {
        let fm = FileManager.default
        let existing = items.filter { fm.fileExists(atPath: $0.url.path) }
        let missing = items.count - existing.count
        if missing > 0 {
            Diag.error(.dragout, "skipping \(missing) item(s) whose source path no longer exists")
        }
        guard !existing.isEmpty else { return }

        let dragItems: [NSDraggingItem] = existing.enumerated().map { index, item in
            let di = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: item.url.path)
            icon.size = NSSize(width: 32, height: 32)
            let offset = CGFloat(min(index, 8)) * 4
            di.setDraggingFrame(imageFrame.offsetBy(dx: offset, dy: -offset), contents: icon)
            return di
        }
        let session = view.beginDraggingSession(with: dragItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = existing.count > 1 ? .stack : .none
        activeItems[session.draggingSequenceNumber] = existing
        Diag.notice(.dragout, "drag-out session #\(session.draggingSequenceNumber) began with \(existing.count) item(s); offered outside-app mask=\(outsideMask().names); modifiers at start=\(NSEvent.modifierFlags.names); items=\(existing.map(\.url.path))")
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            return outsideMask()
        case .withinApplication:
            // Dropping back onto a FloatShelf panel is not an operation in Phase 0.
            return []
        @unknown default:
            return [.copy]
        }
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        Diag.debug(.dragout, "session #\(session.draggingSequenceNumber) willBegin at \(fmt(screenPoint))")
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let items = activeItems.removeValue(forKey: session.draggingSequenceNumber) ?? []
        let fm = FileManager.default
        var toRemove: [UUID] = []
        var lines: [String] = []
        for item in items {
            let exists = fm.fileExists(atPath: item.url.path)
            let remove = ShelfStore.shouldRemoveAfterDragOut(operationWasMove: operation == .move, sourceStillExists: exists)
            if remove { toRemove.append(item.id) }
            lines.append("\(item.url.path) sourceExists=\(exists) removeFromShelf=\(remove)")
        }
        let outcome: String
        switch operation {
        case []: outcome = "cancelled/rejected (no operation) — shelf unchanged"
        case .copy: outcome = "destination performed COPY"
        case .move: outcome = "destination performed MOVE"
        default: outcome = "destination reported \(operation.names)"
        }
        Diag.notice(.dragout, "drag-out session #\(session.draggingSequenceNumber) ended at \(fmt(screenPoint)): operation=\(operation.names) → \(outcome); modifiers at end=\(NSEvent.modifierFlags.names); offered mask=\(outsideMask().names)")
        for l in lines { Diag.info(.dragout, "  \(l)") }
        if !toRemove.isEmpty { shelf?.removeItems(toRemove, reason: "moved by destination and source path is gone") }
        onSessionEnded?()
    }
}
