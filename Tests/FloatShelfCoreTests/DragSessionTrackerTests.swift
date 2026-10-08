import Testing
@testable import FloatShelfCore

private let fileTypes = ["public.file-url", "NSFilenamesPboardType"]
private let textTypes = ["public.utf8-plain-text"]

@Suite("DragSessionTracker")
struct DragSessionTrackerTests {
    @Test func changeWithFileURLConfirmsFileDrag() throws {
        var t = DragSessionTracker(initialChangeCount: 10)
        t.pressBegan(time: 1.0, changeCount: 10)
        #expect(t.classification == .pending)
        t.dragged(time: 1.02, changeCount: 10, types: { [] })
        #expect(t.classification == .nonFileDrag)
        let changed = t.dragged(time: 1.05, changeCount: 11, types: { fileTypes })
        #expect(changed)
        #expect(t.classification == .confirmedFileDrag)
        let ended = t.pressEnded(time: 1.5, changeCount: 11)
        let r = try #require(ended)
        #expect(r.changeObservedAtEvent == 2)
        #expect(abs((r.changeObservedDelay ?? -1) - 0.05) < 1e-9)
        #expect(abs((r.firstDraggedDelay ?? -1) - 0.02) < 1e-9)
        #expect(t.idleBaseline == 11)
        #expect(t.classification == .idle)
    }

    @Test func leftoverFileURLWithoutChangeIsStale() throws {
        var t = DragSessionTracker(initialChangeCount: 10)
        t.pressBegan(time: 0, changeCount: 10)
        t.dragged(time: 0.1, changeCount: 10, types: { fileTypes })
        #expect(t.classification == .staleFileURL)
        let ended = t.pressEnded(time: 0.3, changeCount: 10)
        let r = try #require(ended)
        #expect(r.classification == .staleFileURL)
        #expect(r.changeObservedDelay == nil)
    }

    @Test func changeWithoutFileURLIsNonFileDrag() {
        var t = DragSessionTracker(initialChangeCount: 3)
        t.pressBegan(time: 0, changeCount: 3)
        t.dragged(time: 0.1, changeCount: 4, types: { textTypes })
        #expect(t.classification == .nonFileDrag)
    }

    @Test func baselineAdvancesSoNextWindowDragIsNotConfirmed() {
        var t = DragSessionTracker(initialChangeCount: 1)
        t.pressBegan(time: 0, changeCount: 1)
        t.dragged(time: 0.1, changeCount: 2, types: { fileTypes })
        _ = t.pressEnded(time: 0.5, changeCount: 2)
        // A later window move: pasteboard still holds the old file URLs.
        t.pressBegan(time: 5, changeCount: 2)
        t.dragged(time: 5.1, changeCount: 2, types: { fileTypes })
        #expect(t.classification == .staleFileURL)
    }

    @Test func changeBeforeMouseDownIsStillCounted() throws {
        // If the mouse-down event is delivered late, the source app may already
        // have written the drag pasteboard; comparison is against the idle baseline.
        var t = DragSessionTracker(initialChangeCount: 7)
        t.pressBegan(time: 0, changeCount: 8)
        t.dragged(time: 0.05, changeCount: 8, types: { fileTypes })
        #expect(t.classification == .confirmedFileDrag)
        let ended = t.pressEnded(time: 0.2, changeCount: 8)
        let r = try #require(ended)
        #expect(r.changedBeforePressObserved)
        #expect(r.changeObservedAtEvent == 1)
    }

    @Test func missedMouseDownCreatesImplicitPress() throws {
        var t = DragSessionTracker(initialChangeCount: 0)
        t.dragged(time: 2, changeCount: 1, types: { fileTypes })
        #expect(t.classification == .confirmedFileDrag)
        let ended = t.pressEnded(time: 2.5, changeCount: 1)
        let r = try #require(ended)
        #expect(r.implicitPress)
    }

    @Test func ownDragOutCanResetBaseline() {
        var t = DragSessionTracker(initialChangeCount: 0)
        t.resetBaseline(5)
        t.pressBegan(time: 0, changeCount: 5)
        t.dragged(time: 0.1, changeCount: 5, types: { fileTypes })
        #expect(t.classification == .staleFileURL)
    }

    @Test func typesAreOnlyReadWhenNeeded() {
        var t = DragSessionTracker(initialChangeCount: 0)
        t.pressBegan(time: 0, changeCount: 0)
        var reads = 0
        for i in 1...20 {
            t.dragged(time: Double(i) * 0.01, changeCount: i < 10 ? 0 : 1, types: { reads += 1; return fileTypes })
        }
        // once at first event (pending→stale), once at the change (→confirmed)
        #expect(reads == 2)
        #expect(t.classification == .confirmedFileDrag)
    }
}
