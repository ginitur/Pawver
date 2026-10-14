import Foundation
import Testing
@testable import PawverCore

@Suite("ShelfSelection")
struct ShelfSelectionTests {
    let ids = (0..<5).map { _ in UUID() }

    @Test func plainClickSelectsOnlyThatItem() {
        var s = ShelfSelection()
        s.click(ids[1], kind: .plain, order: ids)
        s.click(ids[3], kind: .plain, order: ids)
        #expect(s.selected == [ids[3]])
        #expect(s.anchor == ids[3])
    }

    @Test func commandClickToggles() {
        var s = ShelfSelection()
        s.click(ids[0], kind: .plain, order: ids)
        s.click(ids[2], kind: .toggle, order: ids)
        s.click(ids[4], kind: .toggle, order: ids)
        #expect(s.ordered(in: ids) == [ids[0], ids[2], ids[4]])
        s.click(ids[2], kind: .toggle, order: ids)
        #expect(s.ordered(in: ids) == [ids[0], ids[4]])
    }

    @Test func commandClickCanEmptyTheSelection() {
        var s = ShelfSelection()
        s.click(ids[1], kind: .toggle, order: ids)
        s.click(ids[1], kind: .toggle, order: ids)
        #expect(s.isEmpty)
    }

    @Test func shiftClickSelectsRangeFromAnchorInBothDirections() {
        var s = ShelfSelection()
        s.click(ids[1], kind: .plain, order: ids)
        s.click(ids[3], kind: .extend, order: ids)
        #expect(s.ordered(in: ids) == [ids[1], ids[2], ids[3]])
        s.click(ids[0], kind: .extend, order: ids)   // anchor stays at 1
        #expect(s.ordered(in: ids) == [ids[0], ids[1]])
    }

    @Test func shiftClickWithoutAnchorActsLikePlainClick() {
        var s = ShelfSelection()
        s.click(ids[2], kind: .extend, order: ids)
        #expect(s.selected == [ids[2]])
        #expect(s.anchor == ids[2])
    }

    @Test func clearAndSelectAll() {
        var s = ShelfSelection()
        s.selectAll(order: ids)
        #expect(s.count == 5)
        s.clear()
        #expect(s.isEmpty && s.anchor == nil)
    }

    @Test func unknownIDIsIgnored() {
        var s = ShelfSelection()
        s.click(ids[0], kind: .plain, order: ids)
        s.click(UUID(), kind: .toggle, order: ids)
        #expect(s.selected == [ids[0]])
    }

    @Test func pruneAfterRemovalKeepsSelectionConsistent() {
        var s = ShelfSelection()
        s.click(ids[1], kind: .plain, order: ids)
        s.click(ids[3], kind: .toggle, order: ids)   // anchor = 3
        let remaining = ids.filter { $0 != ids[3] }
        s.prune(order: remaining)
        #expect(s.selected == [ids[1]])
        #expect(s.anchor == nil)
        s.click(ids[4], kind: .extend, order: remaining)   // no anchor → plain
        #expect(s.selected == [ids[4]])
        s.prune(order: [])
        #expect(s.isEmpty)
    }

    @Test func dragCarriesSelectionOnlyWhenPressedItemIsSelected() {
        var s = ShelfSelection()
        s.click(ids[3], kind: .plain, order: ids)
        s.click(ids[0], kind: .toggle, order: ids)
        #expect(s.dragIDs(pressed: ids[3], order: ids) == [ids[0], ids[3]])   // shelf order
        #expect(s.dragIDs(pressed: ids[2], order: ids) == [ids[2]])
    }
}
