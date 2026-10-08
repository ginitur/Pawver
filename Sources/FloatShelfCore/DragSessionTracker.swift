import Foundation

/// How the current mouse press has been classified, combining the
/// drag-pasteboard changeCount with the pasteboard's types.
public enum DragClassification: String, Sendable, Equatable {
    /// No press in progress.
    case idle
    /// Button down, no drag event analysed yet.
    case pending
    /// Dragging, but the drag pasteboard has no file URLs (window move,
    /// text selection, or a non-file drag).
    case nonFileDrag
    /// File URLs are on the drag pasteboard but its changeCount did not change
    /// since the previous press ended — likely leftovers from an earlier drag.
    case staleFileURL
    /// changeCount changed since the previous press AND file URLs are present.
    case confirmedFileDrag
}

/// Everything measured for one press, logged at mouse-up as evidence.
public struct DragPressReport: Sendable, Equatable {
    public var pressStart: Double
    /// True when the first event seen was a drag (mouse-down was missed).
    public var implicitPress: Bool
    /// changeCount when the previous press ended (or at start-up).
    public var idleBaseline: Int
    public var changeCountAtPress: Int
    public var draggedEvents = 0
    public var firstDraggedDelay: Double?
    public var changeObservedDelay: Double?
    public var changeObservedAtEvent: Int?
    public var typesAtClassification: [String] = []
    public var classification: DragClassification = .pending
    public var changeCountAtEnd: Int?
    public var duration: Double?

    public var changedBeforePressObserved: Bool { changeCountAtPress != idleBaseline }
}

/// State machine for one mouse press at a time. Pure logic; the app feeds it
/// changeCount / types read from NSPasteboard(name: .drag).
public struct DragSessionTracker: Sendable {
    public static let fileURLType = "public.file-url"

    public private(set) var idleBaseline: Int
    public private(set) var current: DragPressReport?

    public init(initialChangeCount: Int) {
        idleBaseline = initialChangeCount
    }

    public var classification: DragClassification { current?.classification ?? .idle }

    /// Call after FloatShelf's own drag-out session so that our own write to
    /// the drag pasteboard is not mistaken for a new external file drag.
    public mutating func resetBaseline(_ changeCount: Int) {
        idleBaseline = changeCount
    }

    public mutating func pressBegan(time: Double, changeCount: Int, implicit: Bool = false) {
        current = DragPressReport(
            pressStart: time,
            implicitPress: implicit,
            idleBaseline: idleBaseline,
            changeCountAtPress: changeCount
        )
    }

    /// Returns true when the classification changed with this event.
    @discardableResult
    public mutating func dragged(time: Double, changeCount: Int, types: () -> [String]) -> Bool {
        if current == nil { pressBegan(time: time, changeCount: changeCount, implicit: true) }
        guard var r = current else { return false }
        let old = r.classification
        r.draggedEvents += 1
        if r.firstDraggedDelay == nil { r.firstDraggedDelay = time - r.pressStart }
        let changed = changeCount != idleBaseline
        if changed && r.changeObservedDelay == nil {
            r.changeObservedDelay = time - r.pressStart
            r.changeObservedAtEvent = r.draggedEvents
            let t = types()
            r.typesAtClassification = t
            r.classification = t.contains(Self.fileURLType) ? .confirmedFileDrag : .nonFileDrag
        } else if !changed && r.classification == .pending {
            let t = types()
            r.typesAtClassification = t
            r.classification = t.contains(Self.fileURLType) ? .staleFileURL : .nonFileDrag
        }
        current = r
        return r.classification != old
    }

    /// Ends the press, makes the end changeCount the new idle baseline and
    /// returns the report (nil if no press was in progress).
    public mutating func pressEnded(time: Double, changeCount: Int) -> DragPressReport? {
        idleBaseline = changeCount
        guard var r = current else { return nil }
        r.changeCountAtEnd = changeCount
        r.duration = time - r.pressStart
        current = nil
        return r
    }
}
