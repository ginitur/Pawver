import Foundation

/// Finder-style list selection for the shelf, independent of AppKit.
/// `order` is always the shelf's current item order (ids).
public struct ShelfSelection: Sendable, Equatable {
    public enum ClickKind: Sendable {
        /// Plain click: select only this item.
        case plain
        /// ⌘-click: toggle this item.
        case toggle
        /// ⇧-click: select the range from the anchor to this item.
        case extend
    }

    public private(set) var selected: Set<UUID> = []
    /// Item a ⇧-click range starts from (last plain or ⌘ click).
    public private(set) var anchor: UUID?

    public init() {}

    public var isEmpty: Bool { selected.isEmpty }
    public var count: Int { selected.count }
    public func contains(_ id: UUID) -> Bool { selected.contains(id) }

    public mutating func click(_ id: UUID, kind: ClickKind, order: [UUID]) {
        guard order.contains(id) else { return }
        switch kind {
        case .plain:
            selected = [id]
            anchor = id
        case .toggle:
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            anchor = id
        case .extend:
            guard let a = anchor, let i = order.firstIndex(of: a), let j = order.firstIndex(of: id) else {
                selected = [id]; anchor = id; return
            }
            // Like Finder: the range replaces the selection, the anchor stays.
            selected = Set(order[min(i, j)...max(i, j)])
        }
    }

    public mutating func clear() {
        selected = []
        anchor = nil
    }

    public mutating func selectAll(order: [UUID]) {
        selected = Set(order)
        if anchor == nil || !order.contains(anchor!) { anchor = order.first }
    }

    /// Drops ids that are no longer on the shelf (after removal / clear).
    public mutating func prune(order: [UUID]) {
        let live = Set(order)
        selected.formIntersection(live)
        if let a = anchor, !live.contains(a) { anchor = nil }
    }

    /// Selected ids in shelf order.
    public func ordered(in order: [UUID]) -> [UUID] {
        order.filter { selected.contains($0) }
    }

    /// What a drag that starts on `pressed` should carry: the whole selection if the
    /// pressed item is part of it, otherwise just that item.
    public func dragIDs(pressed: UUID, order: [UUID]) -> [UUID] {
        selected.contains(pressed) ? ordered(in: order) : [pressed]
    }
}
