import Foundation

/// One shelf entry. FloatShelf stores a *reference* (URL) only: it never
/// copies, moves, modifies or deletes the file itself.
public struct ShelfItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    /// Standardized path used for de-duplication.
    public let key: String
    public let addedAt: Date

    public var name: String { url.lastPathComponent }
    public var parentDirectoryPath: String { url.deletingLastPathComponent().path }
}

public struct ShelfAddResult: Sendable, Equatable {
    public var added: [ShelfItem] = []
    public var duplicates: [URL] = []
    public var rejected: [URL] = []
}

public struct ShelfStore: Sendable {
    public private(set) var items: [ShelfItem] = []

    public init() {}

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }

    /// Converts file-reference URLs (file:///.file/id=…) to path URLs and
    /// standardizes the path (removes "." / ".." and trailing slashes).
    /// Symlinks are intentionally NOT resolved: a symlink and its target are
    /// different items.
    public static func normalizedFileURL(_ url: URL) -> URL {
        var u = url
        if u.isFileURL, (u as NSURL).isFileReferenceURL(), let p = (u as NSURL).filePathURL {
            u = p
        }
        return u.standardizedFileURL
    }

    /// De-duplication key: the standardized absolute path, or nil for
    /// non-file URLs.
    public static func referenceKey(for url: URL) -> String? {
        guard url.isFileURL else { return nil }
        var path = normalizedFileURL(url).path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path.isEmpty ? nil : path
    }

    public func contains(_ url: URL) -> Bool {
        guard let key = Self.referenceKey(for: url) else { return false }
        return items.contains { $0.key == key }
    }

    @discardableResult
    public mutating func add(_ urls: [URL], now: Date = Date()) -> ShelfAddResult {
        var result = ShelfAddResult()
        var keys = Set(items.map(\.key))
        for raw in urls {
            guard let key = Self.referenceKey(for: raw) else {
                result.rejected.append(raw)
                continue
            }
            if keys.contains(key) {
                result.duplicates.append(raw)
                continue
            }
            keys.insert(key)
            let item = ShelfItem(id: UUID(), url: Self.normalizedFileURL(raw), key: key, addedAt: now)
            items.append(item)
            result.added.append(item)
        }
        return result
    }

    @discardableResult
    public mutating func remove(id: UUID) -> ShelfItem? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: i)
    }

    public mutating func removeAll() {
        items.removeAll()
    }

    /// Names to show in the UI. Items whose file names collide get the parent
    /// folder name appended; if that still collides, the full parent path.
    public func displayNames() -> [UUID: String] {
        var byName: [String: [ShelfItem]] = [:]
        for item in items { byName[item.name.lowercased(), default: []].append(item) }
        var result: [UUID: String] = [:]
        for group in byName.values {
            if group.count == 1 {
                result[group[0].id] = group[0].name
                continue
            }
            let parents = group.map { URL(fileURLWithPath: $0.parentDirectoryPath).lastPathComponent }
            let parentsUnique = Set(parents.map { $0.lowercased() }).count == parents.count
            for (item, parent) in zip(group, parents) {
                result[item.id] = parentsUnique ? "\(item.name) — \(parent)" : "\(item.name) — \(item.parentDirectoryPath)"
            }
        }
        return result
    }

    /// Drag-out bookkeeping rule: an entry is dropped from the shelf only if
    /// the destination reported a move AND the original path is gone. In every
    /// other case (copy, link, cancelled, move that did not happen) it stays.
    public static func shouldRemoveAfterDragOut(operationWasMove: Bool, sourceStillExists: Bool) -> Bool {
        operationWasMove && !sourceStillExists
    }
}
