import CoreGraphics

/// A screen as seen by AppKit: global coordinates with the origin at the
/// bottom-left of the primary screen, y pointing up, units in points.
public struct ScreenGeometry: Sendable, Equatable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var scale: CGFloat

    public init(frame: CGRect, visibleFrame: CGRect, scale: CGFloat) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.scale = scale
    }
}

public enum ShelfPositioning {
    /// AppKit converts the CG pixel grid (top-left origin, half-open) into
    /// points whose y range is (minY, maxY]. A pointer on the top row of the
    /// primary screen therefore reports y == frame.maxY.
    public static func contains(_ rect: CGRect, _ p: CGPoint) -> Bool {
        p.x >= rect.minX && p.x < rect.maxX && p.y > rect.minY && p.y <= rect.maxY
    }

    public static func distance(from p: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - p.x, 0, p.x - rect.maxX)
        let dy = max(rect.minY - p.y, 0, p.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Index of the screen containing the point, or the nearest screen if the
    /// point falls in a gap between screens. `nil` only when there are no screens.
    public static func screenIndex(for point: CGPoint, in screens: [ScreenGeometry]) -> Int? {
        guard !screens.isEmpty else { return nil }
        if let i = screens.firstIndex(where: { contains($0.frame, point) }) { return i }
        return screens.indices.min { distance(from: point, to: screens[$0].frame) < distance(from: point, to: screens[$1].frame) }
    }

    /// Frame for a shelf of `size` placed so that `cursor` sits at `anchor`
    /// (unit coordinates inside the shelf; 0.5/0.5 = centred, which keeps the
    /// cursor inside the drop area), clamped to the visible frame of the
    /// cursor's screen and aligned to that screen's pixel grid.
    public static func shelfFrame(
        size: CGSize,
        cursor: CGPoint,
        screens: [ScreenGeometry],
        anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)
    ) -> CGRect? {
        guard let index = screenIndex(for: cursor, in: screens) else { return nil }
        let screen = screens[index]
        let vf = screen.visibleFrame.isEmpty ? screen.frame : screen.visibleFrame
        let w = min(size.width, vf.width)
        let h = min(size.height, vf.height)
        var x = cursor.x - w * anchor.x
        var y = cursor.y - h * anchor.y
        let scale = max(screen.scale, 1)
        x = (x * scale).rounded() / scale
        y = (y * scale).rounded() / scale
        x = clamp(x, vf.minX, vf.maxX - w)
        y = clamp(y, vf.minY, vf.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        hi < lo ? lo : min(max(v, lo), hi)
    }
}
