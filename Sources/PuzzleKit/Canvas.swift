import Foundation
import PeriPageKit

/// Byte-per-pixel 1-bit drawing surface (1 = black). Faster to draw into than `MonoBitmap`;
/// converted with `bitmap()` at the end. Shapes are rasterized by distance to the pixel center,
/// so strokes keep an exact, even width without antialiasing.
struct Canvas {
    let width: Int
    let height: Int
    var px: [UInt8]

    init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(0, height)
        px = [UInt8](repeating: 0, count: self.width * self.height)
    }

    subscript(x: Int, y: Int) -> Bool {
        get { x >= 0 && y >= 0 && x < width && y < height && px[y * width + x] != 0 }
        set { if x >= 0, y >= 0, x < width, y < height { px[y * width + x] = newValue ? 1 : 0 } }
    }

    func bitmap() -> MonoBitmap {
        let bpr = (width + 7) / 8
        var bytes = [UInt8](repeating: 0, count: bpr * height)
        px.withUnsafeBufferPointer { src in
            bytes.withUnsafeMutableBufferPointer { dst in
                var y = 0
                while y < height {
                    var x = 0
                    let row = y * width, out = y * bpr
                    while x < width {
                        if src[row + x] != 0 { dst[out + x >> 3] |= 0x80 >> UInt8(x & 7) }
                        x += 1
                    }
                    y += 1
                }
            }
        }
        return MonoBitmap(width: width, height: height, bytes: bytes)
    }

    // MARK: Rectangles

    mutating func fill(x: Int, y: Int, w: Int, h: Int, black: Bool = true) {
        let x0 = max(0, x), x1 = min(width, x + w), y0 = max(0, y), y1 = min(height, y + h)
        guard x0 < x1, y0 < y1 else { return }
        let v: UInt8 = black ? 1 : 0
        px.withUnsafeMutableBufferPointer { p in
            for yy in y0..<y1 {
                let row = yy * width
                for xx in x0..<x1 { p[row + xx] = v }
            }
        }
    }

    /// Stroke inside the rectangle's bounds.
    mutating func strokeRect(x: Int, y: Int, w: Int, h: Int, t: Int) {
        fill(x: x, y: y, w: w, h: t)
        fill(x: x, y: y + h - t, w: w, h: t)
        fill(x: x, y: y, w: t, h: h)
        fill(x: x + w - t, y: y, w: t, h: h)
    }

    mutating func invert(x: Int, y: Int, w: Int, h: Int) {
        let x0 = max(0, x), x1 = min(width, x + w), y0 = max(0, y), y1 = min(height, y + h)
        guard x0 < x1, y0 < y1 else { return }
        for yy in y0..<y1 {
            for xx in x0..<x1 { px[yy * width + xx] ^= 1 }
        }
    }

    // MARK: Distance-rasterized shapes

    /// `lo...hi` clipped to `0..<limit`, or nil when empty.
    private func span(_ lo: Int, _ hi: Int, _ limit: Int) -> ClosedRange<Int>? {
        let a = max(0, lo), b = min(limit - 1, hi)
        return a <= b ? a...b : nil
    }

    /// Straight stroke with round caps, `w` pixels wide.
    mutating func line(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, width w: Double) {
        let r = w / 2
        let minX = Int((min(ax, bx) - r).rounded(.down)), maxX = Int((max(ax, bx) + r).rounded(.up))
        let minY = Int((min(ay, by) - r).rounded(.down)), maxY = Int((max(ay, by) + r).rounded(.up))
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        let r2 = r * r
        let W = width
        guard let ys = span(minY, maxY, height), let xs = span(minX, maxX, width) else { return }
        px.withUnsafeMutableBufferPointer { p in
            for y in ys {
                let py = Double(y) + 0.5
                for x in xs {
                    let pxx = Double(x) + 0.5
                    var t = len2 > 0 ? ((pxx - ax) * dx + (py - ay) * dy) / len2 : 0
                    t = min(1, max(0, t))
                    let qx = ax + t * dx - pxx, qy = ay + t * dy - py
                    if qx * qx + qy * qy <= r2 { p[y * W + x] = 1 }
                }
            }
        }
    }

    /// Straight stroke with square (butt) ends: covers exactly the segment, `w` wide.
    mutating func buttLine(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, width w: Double) {
        let r = w / 2
        let dx = bx - ax, dy = by - ay
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0 else { return }
        let ux = dx / len, uy = dy / len
        let minX = Int((min(ax, bx) - r).rounded(.down)), maxX = Int((max(ax, bx) + r).rounded(.up))
        let minY = Int((min(ay, by) - r).rounded(.down)), maxY = Int((max(ay, by) + r).rounded(.up))
        guard let ys = span(minY, maxY, height), let xs = span(minX, maxX, width) else { return }
        for y in ys {
            let py = Double(y) + 0.5 - ay
            for x in xs {
                let pxx = Double(x) + 0.5 - ax
                let along = pxx * ux + py * uy
                let across = abs(-pxx * uy + py * ux)
                if along >= 0, along <= len, across <= r { px[y * width + x] = 1 }
            }
        }
    }

    /// Outline of a stadium (capsule) around the segment a–b: the band between `radius - width` and `radius`.
    mutating func capsule(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, radius r: Double, width w: Double) {
        let minX = Int((min(ax, bx) - r).rounded(.down)), maxX = Int((max(ax, bx) + r).rounded(.up))
        let minY = Int((min(ay, by) - r).rounded(.down)), maxY = Int((max(ay, by) + r).rounded(.up))
        guard let ys = span(minY, maxY, height), let xs = span(minX, maxX, width) else { return }
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        let outer2 = r * r, inner = max(0, r - w), inner2 = inner * inner
        for y in ys {
            let py = Double(y) + 0.5
            for x in xs {
                let pxx = Double(x) + 0.5
                var t = len2 > 0 ? ((pxx - ax) * dx + (py - ay) * dy) / len2 : 0
                t = min(1, max(0, t))
                let qx = ax + t * dx - pxx, qy = ay + t * dy - py
                let d2 = qx * qx + qy * qy
                if d2 <= outer2 && d2 > inner2 { px[y * width + x] = 1 }
            }
        }
    }

    mutating func polyline(_ points: [(Double, Double)], width w: Double) {
        guard points.count > 1 else { return }
        for i in 1..<points.count {
            line(points[i - 1].0, points[i - 1].1, points[i].0, points[i].1, width: w)
        }
    }

    /// Round dots every `spacing` pixels along a polyline (reads as "the path", distinct from solid walls).
    mutating func dottedPolyline(_ points: [(Double, Double)], spacing: Double, radius: Double) {
        guard let first = points.first else { return }
        disc(first.0, first.1, radius: radius)
        var carry = 0.0
        for i in 1..<max(1, points.count) {
            let (ax, ay) = points[i - 1], (bx, by) = points[i]
            let len = ((bx - ax) * (bx - ax) + (by - ay) * (by - ay)).squareRoot()
            guard len > 0 else { continue }
            var d = spacing - carry
            while d <= len {
                disc(ax + (bx - ax) * d / len, ay + (by - ay) * d / len, radius: radius)
                d += spacing
            }
            carry = len - (d - spacing)
        }
        if let last = points.last { disc(last.0, last.1, radius: radius) }
    }

    mutating func disc(_ cx: Double, _ cy: Double, radius r: Double, black: Bool = true) {
        let r2 = r * r
        let v: UInt8 = black ? 1 : 0
        guard let ys = span(Int(cy - r - 1), Int(cy + r + 1), height),
              let xs = span(Int(cx - r - 1), Int(cx + r + 1), width) else { return }
        for y in ys {
            let dy = Double(y) + 0.5 - cy
            for x in xs {
                let dx = Double(x) + 0.5 - cx
                if dx * dx + dy * dy <= r2 { px[y * width + x] = v }
            }
        }
    }

    /// Circle outline whose outer edge is at `radius`.
    mutating func ring(_ cx: Double, _ cy: Double, radius r: Double, width w: Double) {
        let outer2 = r * r, inner = max(0, r - w), inner2 = inner * inner
        guard let ys = span(Int(cy - r - 1), Int(cy + r + 1), height),
              let xs = span(Int(cx - r - 1), Int(cx + r + 1), width) else { return }
        for y in ys {
            let dy = Double(y) + 0.5 - cy
            for x in xs {
                let dx = Double(x) + 0.5 - cx
                let d2 = dx * dx + dy * dy
                if d2 <= outer2, d2 > inner2 { px[y * width + x] = 1 }
            }
        }
    }

    /// Filled polygon (even-odd, sampled at pixel centers).
    mutating func polygon(_ pts: [(Double, Double)]) {
        guard pts.count > 2 else { return }
        let minY = max(0, Int(pts.map(\.1).min()!.rounded(.down)))
        let maxY = min(height - 1, Int(pts.map(\.1).max()!.rounded(.up)))
        guard minY <= maxY else { return }
        for y in minY...maxY {
            let py = Double(y) + 0.5
            var xs: [Double] = []
            for i in 0..<pts.count {
                let (x0, y0) = pts[i], (x1, y1) = pts[(i + 1) % pts.count]
                if (y0 <= py && y1 > py) || (y1 <= py && y0 > py) {
                    xs.append(x0 + (py - y0) / (y1 - y0) * (x1 - x0))
                }
            }
            xs.sort()
            var i = 0
            while i + 1 < xs.count {
                let a = max(0, Int((xs[i] - 0.5).rounded(.up))), b = min(width - 1, Int((xs[i + 1] - 0.5).rounded(.down)))
                if a <= b { for x in a...b { px[y * width + x] = 1 } }
                i += 2
            }
        }
    }

    // MARK: Compositing

    /// ORs the black dots of `bmp` at (x, y).
    mutating func blit(_ bmp: MonoBitmap, x: Int, y: Int) {
        let bpr = bmp.bytesPerRow
        let bytes = bmp.bytes
        for oy in 0..<bmp.height {
            let ty = y + oy
            guard ty >= 0, ty < height else { continue }
            for ox in 0..<bmp.width where bytes[oy * bpr + ox / 8] & (0x80 >> UInt8(ox % 8)) != 0 {
                let tx = x + ox
                if tx >= 0, tx < width { px[ty * width + tx] = 1 }
            }
        }
    }

    /// Clears to white where `bmp` is black (white text on a black fill).
    mutating func knockout(_ bmp: MonoBitmap, x: Int, y: Int) {
        let bpr = bmp.bytesPerRow
        let bytes = bmp.bytes
        for oy in 0..<bmp.height {
            let ty = y + oy
            guard ty >= 0, ty < height else { continue }
            for ox in 0..<bmp.width where bytes[oy * bpr + ox / 8] & (0x80 >> UInt8(ox % 8)) != 0 {
                let tx = x + ox
                if tx >= 0, tx < width { px[ty * width + tx] = 0 }
            }
        }
    }

    mutating func blit(_ other: Canvas, x: Int, y: Int) {
        for oy in 0..<other.height {
            let ty = y + oy
            guard ty >= 0, ty < height else { continue }
            for ox in 0..<other.width where other.px[oy * other.width + ox] != 0 {
                let tx = x + ox
                if tx >= 0, tx < width { px[ty * width + tx] = 1 }
            }
        }
    }
}

extension MonoBitmap {
    /// Same bitmap cropped or extended on the right to `width`.
    func trimmedRight(to width: Int) -> MonoBitmap {
        var out = MonoBitmap(width: width, height: height)
        out.blit(self, x: 0, y: 0)
        return out
    }

    /// Removes fully white columns on both sides.
    func trimmedHorizontally() -> MonoBitmap {
        guard width > 0, height > 0 else { return self }
        var minX = width, maxX = -1
        for y in 0..<height {
            for x in 0..<width where self[x, y] {
                minX = Swift.min(minX, x)
                maxX = Swift.max(maxX, x)
            }
        }
        guard maxX >= minX else { return MonoBitmap(width: 1, height: height) }
        var out = MonoBitmap(width: maxX - minX + 1, height: height)
        out.blit(self, x: -minX, y: 0)
        return out
    }
}
