// Crops the rounded-square app icon out of Resources/Brand/pawver-source.png
// (excluding the wordmark below it), masks the corners transparent and writes
// a 1024x1024 master PNG laid out on the macOS icon grid (824 px tile, 100 px margin).
// Usage: swift scripts/make-icon.swift <source.png> <out-1024.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else { FileHandle.standardError.write("usage: make-icon.swift src out\n".data(using: .utf8)!); exit(2) }
func fail(_ m: String) -> Never { FileHandle.standardError.write("make-icon: \(m)\n".data(using: .utf8)!); exit(1) }

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fail("cannot read \(args[1])") }
let W = img.width, H = img.height
var px = [UInt8](repeating: 0, count: W * H * 4)
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                          space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("ctx") }
ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))   // row 0 = top in memory

// Background = average of the four 8x8 corners.
var bg = [0.0, 0.0, 0.0]; var n = 0.0
for (cx, cy) in [(0, 0), (W - 8, 0), (0, H - 8), (W - 8, H - 8)] {
    for y in cy..<cy + 8 { for x in cx..<cx + 8 { let i = (y * W + x) * 4; for c in 0..<3 { bg[c] += Double(px[i + c]) }; n += 1 } }
}
bg = bg.map { $0 / n }
let threshold = Double(ProcessInfo.processInfo.environment["ICON_THRESHOLD"] ?? "14")!
@inline(__always) func isContent(_ x: Int, _ y: Int) -> Bool {
    let i = (y * W + x) * 4
    var d = 0.0
    for c in 0..<3 { d = max(d, abs(Double(px[i + c]) - bg[c])) }
    return d > threshold
}
// Row profile: a row "has content" when >= 2% of its pixels differ from background.
let minCount = max(4, W / 50)
let rowHas = (0..<H).map { y in (0..<W).reduce(0) { $0 + (isContent($1, y) ? 1 : 0) } >= minCount }
guard let top = rowHas.firstIndex(of: true) else { fail("no content") }
// The tile ends at the first gap of >= 1.5% of the height of empty rows (the wordmark gap).
let gap = max(6, H * 15 / 1000)
var bottom = top; var empty = 0; var y = top
while y < H { if rowHas[y] { bottom = y; empty = 0 } else { empty += 1; if empty >= gap { break } }; y += 1 }
// Columns within the tile's middle rows (avoid the shadow and the sparkle marks outside).
let midA = top + (bottom - top) / 3, midB = top + 2 * (bottom - top) / 3
var left = W, right = 0
for yy in stride(from: midA, to: midB, by: 2) {
    var run = 0
    for x in 0..<W { if isContent(x, yy) { run += 1; if run >= 6 { left = min(left, x - 5); break } } else { run = 0 } }
    run = 0
    for x in stride(from: W - 1, through: 0, by: -1) { if isContent(x, yy) { run += 1; if run >= 6 { right = max(right, x + 5); break } } else { run = 0 } }
}
guard right > left else { fail("no columns") }
// The coarse box above still includes the soft drop shadow. The tile's real edge is
// where luminance jumps up sharply (grey shadow -> light cream tile), so refine each
// side by the largest inward brightness step within a window past the coarse bound.
@inline(__always) func lum(_ x: Int, _ y: Int) -> Double {
    let i = (y * W + x) * 4
    return 0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])
}
let win = max(16, W / 15)
func edge(from start: Int, step: Int, count: Int = win, at: (Int) -> (Int, Int)) -> Int {
    var best = start, jump = -1.0
    var k = start
    for _ in 0..<count {
        let (ax, ay) = at(k), (bx, by) = at(k + step)
        let j = lum(bx, by) - lum(ax, ay)
        if j > jump { jump = j; best = k + step }
        k += step
    }
    return best
}
func median(_ v: [Int]) -> Int { v.sorted()[v.count / 2] }
let rows = Array(stride(from: midA, to: midB, by: 3))
let cMidA = left + (right - left) / 3, cMidB = left + 2 * (right - left) / 3
let cols = Array(stride(from: cMidA, to: cMidB, by: 3))
let L = median(rows.map { yy in edge(from: left, step: 1) { ($0, yy) } })
let R = median(rows.map { yy in edge(from: right, step: -1) { ($0, yy) } })
let T = median(cols.map { xx in edge(from: top, step: 1) { (xx, $0) } })
let B = median(cols.map { xx in edge(from: bottom, step: -1) { (xx, $0) } })
let w = R - L + 1, h = B - T + 1
let side = (w + h) / 2
let ox = L + (w - side) / 2, oy = T + (h - side) / 2
// Corner radius: same edge search along the top-left diagonal; inset d = r(1 - 1/sqrt2).
let d = edge(from: ox, step: 1, count: side / 5) { ($0, oy + ($0 - ox)) } - ox
let radius = Double(d) / (1 - 1 / 2.0.squareRoot())
print(String(format: "make-icon: source %dx%d bg=(%.0f,%.0f,%.0f) coarse x=%d..%d y=%d..%d; tile x=%d..%d y=%d..%d (%dx%d) square=%d at (%d,%d) diagonalInset=%d radius≈%.1f (%.1f%% of side)",
             W, H, bg[0], bg[1], bg[2], left, right, top, bottom, L, R, T, B, w, h, side, ox, oy, d, radius, radius / Double(side) * 100))
guard let crop = img.cropping(to: CGRect(x: ox, y: oy, width: side, height: side)) else { fail("crop") }

// Master: 1024 canvas, 824 tile centred (Apple macOS icon grid), corners masked.
let S = 1024, tile = 824.0, m = (1024.0 - tile) / 2
guard let out = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: rgb,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("out ctx") }
out.interpolationQuality = .high
let rect = CGRect(x: m, y: m, width: tile, height: tile)
// Inset by ~1.5 px so the soft halo around the original tile edge is cut off.
let inset = 2.0 * tile / Double(side)
let r = radius * tile / Double(side) - inset
out.addPath(CGPath(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerWidth: r, cornerHeight: r, transform: nil))
out.clip()
out.draw(crop, in: rect)
guard let result = out.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fail("dest") }
CGImageDestinationAddImage(dest, result, nil)
guard CGImageDestinationFinalize(dest) else { fail("write") }
print("make-icon: wrote \(args[2])")
