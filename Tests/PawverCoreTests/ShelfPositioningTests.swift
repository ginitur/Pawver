import CoreGraphics
import Testing
@testable import PawverCore

// Mirrors the real setup: built-in Retina (main, 2x, menu bar 33pt) and a
// 1080p external screen (1x) placed left of it (negative x) or above it.
private let main = ScreenGeometry(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
    scale: 2)
private let externalLeft = ScreenGeometry(
    frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
    scale: 1)
private let externalAbove = ScreenGeometry(
    frame: CGRect(x: -200, y: 982, width: 1920, height: 1080),
    visibleFrame: CGRect(x: -200, y: 982, width: 1920, height: 1080),
    scale: 1)
private let externalBelowWithDock = ScreenGeometry(
    frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 0, y: -1010, width: 1920, height: 1010),
    scale: 1)
// Actual layout logged by Pawver on the development Mac (2026-10-08):
// external MT524 1080p to the RIGHT of the built-in screen, offset 98pt down.
private let externalRightActual = ScreenGeometry(
    frame: CGRect(x: 1512, y: -98, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 1512, y: -98, width: 1920, height: 1050),
    scale: 1)
private let size = CGSize(width: 280, height: 320)

@Suite("ShelfPositioning")
struct ShelfPositioningTests {
    @Test func centresOnCursorWhenThereIsRoom() throws {
        let f = try #require(ShelfPositioning.shelfFrame(size: size, cursor: CGPoint(x: 756, y: 491), screens: [main]))
        #expect(f == CGRect(x: 616, y: 331, width: 280, height: 320))
        #expect(ShelfPositioning.contains(f, CGPoint(x: 756, y: 491)))
    }

    @Test func clampsBelowMenuBarAndInsideRightEdge() throws {
        let f = try #require(ShelfPositioning.shelfFrame(size: size, cursor: CGPoint(x: 1511, y: 982), screens: [main]))
        #expect(f.maxX == 1512)
        #expect(f.maxY == 949)
        #expect(main.visibleFrame.contains(f))
    }

    @Test func clampsAtBottomLeftCorner() throws {
        let f = try #require(ShelfPositioning.shelfFrame(size: size, cursor: CGPoint(x: 0, y: 1), screens: [main]))
        #expect(f.origin == CGPoint(x: 0, y: 0))
    }

    @Test func picksNegativeOriginScreenOnTheLeft() throws {
        let screens = [main, externalLeft]
        #expect(ShelfPositioning.screenIndex(for: CGPoint(x: -10, y: 1075), in: screens) == 1)
        let f = try #require(ShelfPositioning.shelfFrame(size: size, cursor: CGPoint(x: -10, y: 1075), screens: screens))
        #expect(f.maxX == 0)
        #expect(f.maxY == 1080)
        #expect(externalLeft.visibleFrame.contains(f))
    }

    @Test func farLeftCornerOfNegativeScreen() throws {
        let f = try #require(ShelfPositioning.shelfFrame(size: size, cursor: CGPoint(x: -1920, y: 1), screens: [main, externalLeft]))
        #expect(f.origin == CGPoint(x: -1920, y: 0))
    }

    @Test func screenAboveMain() throws {
        let screens = [main, externalAbove]
        #expect(ShelfPositioning.screenIndex(for: CGPoint(x: 100, y: 1500), in: screens) == 1)
        let f = try #require(ShelfPositioning.shelfFrame(size: size, cursor: CGPoint(x: -190, y: 1000), screens: screens))
        #expect(f.minX == -200)
        #expect(f.minY == 982)
    }

    @Test func screenBelowRespectsDockInVisibleFrame() throws {
        let screens = [main, externalBelowWithDock]
        let f = try #require(ShelfPositioning.shelfFrame(size: size, cursor: CGPoint(x: 900, y: -1075), screens: screens))
        #expect(f.minY == -1010)
    }

    @Test func boundaryBetweenScreensIsDeterministic() {
        let screens = [main, externalLeft]
        // x == 0 belongs to the main screen (half-open on the right edge of the left screen).
        #expect(ShelfPositioning.screenIndex(for: CGPoint(x: 0, y: 500), in: screens) == 0)
        #expect(ShelfPositioning.screenIndex(for: CGPoint(x: -0.5, y: 500), in: screens) == 1)
        // Top row of the main screen reports y == maxY and still belongs to it.
        #expect(ShelfPositioning.screenIndex(for: CGPoint(x: 10, y: 982), in: [main, externalAbove]) == 0)
    }

    @Test func gapBetweenScreensFallsBackToNearest() {
        let screens = [main, externalLeft]
        #expect(ShelfPositioning.screenIndex(for: CGPoint(x: 1600, y: 100), in: screens) == 0)
        #expect(ShelfPositioning.screenIndex(for: CGPoint(x: -100, y: 1200), in: screens) == 1)
    }

    @Test func alignsToPixelGridPerScreenScale() throws {
        let onRetina = try #require(ShelfPositioning.shelfFrame(size: size, cursor: CGPoint(x: 700.3, y: 500.3), screens: [main]))
        #expect((onRetina.minX * 2).rounded() == onRetina.minX * 2)
        #expect((onRetina.minY * 2).rounded() == onRetina.minY * 2)
        let onExternal = try #require(ShelfPositioning.shelfFrame(size: size, cursor: CGPoint(x: -700.3, y: 500.3), screens: [main, externalLeft]))
        #expect(onExternal.minX.rounded() == onExternal.minX)
        #expect(onExternal.minY.rounded() == onExternal.minY)
    }

    @Test func shrinksWhenLargerThanVisibleFrame() throws {
        let f = try #require(ShelfPositioning.shelfFrame(size: CGSize(width: 4000, height: 4000), cursor: CGPoint(x: 10, y: 10), screens: [main]))
        #expect(f == main.visibleFrame)
    }

    @Test func actualDevLayoutExternalRightWithNegativeY() throws {
        let screens = [main, externalRightActual]
        // Just right of the seam, near the bottom of the external screen (below y = 0).
        #expect(ShelfPositioning.screenIndex(for: CGPoint(x: 1512, y: -90), in: screens) == 1)
        let f = try #require(ShelfPositioning.shelfFrame(size: size, cursor: CGPoint(x: 1513, y: -90), screens: screens))
        #expect(f.minX == 1512)
        #expect(f.minY == -98)
        #expect(externalRightActual.visibleFrame.contains(f))
        // Top of the external screen respects its own menu bar (visibleFrame maxY = 952).
        let top = try #require(ShelfPositioning.shelfFrame(size: size, cursor: CGPoint(x: 3000, y: 982), screens: screens))
        #expect(top.maxY == 952)
        // Cursor in the dead zone right of main above the external screen → nearest screen.
        #expect(ShelfPositioning.screenIndex(for: CGPoint(x: 1600, y: 990), in: screens) == 1)
    }

    @Test func noScreensGivesNil() {
        #expect(ShelfPositioning.shelfFrame(size: size, cursor: .zero, screens: []) == nil)
    }
}
