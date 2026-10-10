import Foundation
import Testing
@testable import PawverCore

@Suite("ShelfStore")
struct ShelfStoreTests {
    @Test func deduplicatesByStandardizedPath() {
        var store = ShelfStore()
        let r = store.add([
            URL(fileURLWithPath: "/fx/source/A/report.txt"),
            URL(fileURLWithPath: "/fx/source/A/./report.txt"),
            URL(fileURLWithPath: "/fx/source/A/sub/../report.txt"),
        ])
        #expect(r.added.count == 1)
        #expect(r.duplicates.count == 2)
        #expect(store.count == 1)
        #expect(store.items[0].key == "/fx/source/A/report.txt")
    }

    @Test func directoryWithAndWithoutTrailingSlashIsOneItem() {
        var store = ShelfStore()
        store.add([URL(fileURLWithPath: "/fx/source/A/Folder With Spaces/", isDirectory: true)])
        let r = store.add([URL(fileURLWithPath: "/fx/source/A/Folder With Spaces")])
        #expect(r.duplicates.count == 1)
        #expect(store.count == 1)
    }

    @Test func sameNameInDifferentDirectoriesAreDistinct() throws {
        var store = ShelfStore()
        store.add([
            URL(fileURLWithPath: "/fx/source/A/report.txt"),
            URL(fileURLWithPath: "/fx/source/B/report.txt"),
            URL(fileURLWithPath: "/fx/source/A/notes.md"),
        ])
        #expect(store.count == 3)
        let names = store.displayNames()
        let a = try #require(names[store.items[0].id])
        let b = try #require(names[store.items[1].id])
        #expect(a != b)
        #expect(a == "report.txt — A")
        #expect(b == "report.txt — B")
        #expect(names[store.items[2].id] == "notes.md")
    }

    @Test func sameNameAndSameParentNameFallsBackToFullPath() throws {
        var store = ShelfStore()
        store.add([
            URL(fileURLWithPath: "/x/A/report.txt"),
            URL(fileURLWithPath: "/y/A/report.txt"),
        ])
        let names = store.displayNames()
        #expect(names[store.items[0].id] == "report.txt — /x/A")
        #expect(names[store.items[1].id] == "report.txt — /y/A")
    }

    @Test func rejectsNonFileURLs() throws {
        var store = ShelfStore()
        let r = store.add([try #require(URL(string: "https://example.com/a.txt"))])
        #expect(r.rejected.count == 1)
        #expect(store.isEmpty)
    }

    @Test func preservesOrderAndSupportsRemoval() {
        var store = ShelfStore()
        store.add(["/a/1", "/a/2", "/a/3"].map { URL(fileURLWithPath: $0) })
        #expect(store.items.map(\.name) == ["1", "2", "3"])
        let removed = store.remove(id: store.items[1].id)
        #expect(removed?.name == "2")
        #expect(store.items.map(\.name) == ["1", "3"])
        #expect(store.remove(id: UUID()) == nil)
        store.removeAll()
        #expect(store.isEmpty)
    }

    @Test func containsUsesNormalizedKey() {
        var store = ShelfStore()
        store.add([URL(fileURLWithPath: "/a/b/c.txt")])
        #expect(store.contains(URL(fileURLWithPath: "/a/b/../b/c.txt")))
        #expect(!store.contains(URL(fileURLWithPath: "/a/b/d.txt")))
    }

    @Test func dragOutRemovalRuleOnlyRemovesConfirmedMoves() {
        #expect(ShelfStore.shouldRemoveAfterDragOut(operationWasMove: true, sourceStillExists: false))
        #expect(!ShelfStore.shouldRemoveAfterDragOut(operationWasMove: true, sourceStillExists: true))
        #expect(!ShelfStore.shouldRemoveAfterDragOut(operationWasMove: false, sourceStillExists: false))
        #expect(!ShelfStore.shouldRemoveAfterDragOut(operationWasMove: false, sourceStillExists: true))
    }
}
