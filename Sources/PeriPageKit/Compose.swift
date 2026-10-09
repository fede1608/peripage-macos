import Foundation

public enum HorizontalPlacement: Sendable {
    case leading, center, trailing
}

extension MonoBitmap {
    /// Copies `other` onto self at (x, y), OR-ing black dots. Out-of-bounds parts are clipped.
    public mutating func blit(_ other: MonoBitmap, x: Int, y: Int) {
        for oy in 0..<other.height {
            let ty = y + oy
            guard ty >= 0, ty < height else { continue }
            for ox in 0..<other.width where other[ox, oy] {
                let tx = x + ox
                if tx >= 0, tx < width { self[tx, ty] = true }
            }
        }
    }

    /// Places self horizontally inside a canvas of `width`.
    public func placed(inWidth canvasWidth: Int, _ placement: HorizontalPlacement = .center) -> MonoBitmap {
        if canvasWidth == width { return self }
        var canvas = MonoBitmap(width: canvasWidth, height: height)
        let x: Int
        switch placement {
        case .leading: x = 0
        case .center: x = (canvasWidth - width) / 2
        case .trailing: x = canvasWidth - width
        }
        canvas.blit(self, x: x, y: 0)
        return canvas
    }

    public func padded(top: Int = 0, bottom: Int = 0, left: Int = 0, right: Int = 0) -> MonoBitmap {
        var canvas = MonoBitmap(width: width + left + right, height: height + top + bottom)
        canvas.blit(self, x: left, y: top)
        return canvas
    }

    public func inverted() -> MonoBitmap {
        var out = self
        let bpr = bytesPerRow
        let tailBits = width % 8
        let tailMask: UInt8 = tailBits == 0 ? 0xFF : ~(0xFF >> UInt8(tailBits))
        out.withBytes { bytes in
            for i in bytes.indices {
                bytes[i] = ~bytes[i]
                if i % bpr == bpr - 1 { bytes[i] &= tailMask }
            }
        }
        return out
    }

    public func rotatedClockwise() -> MonoBitmap {
        var out = MonoBitmap(width: height, height: width)
        for y in 0..<height {
            for x in 0..<width where self[x, y] {
                out[height - 1 - y, x] = true
            }
        }
        return out
    }

    /// Stacks blocks vertically on a canvas of `width`, centering narrower blocks.
    public static func stack(_ blocks: [MonoBitmap], width: Int, spacing: Int = 0) -> MonoBitmap {
        let visible = blocks.filter { $0.height > 0 }
        let total = visible.reduce(0) { $0 + $1.height } + max(0, visible.count - 1) * spacing
        var canvas = MonoBitmap(width: width, height: total)
        var y = 0
        for block in visible {
            canvas.blit(block, x: (width - block.width) / 2, y: y)
            y += block.height + spacing
        }
        return canvas
    }

    public mutating func fillRect(x: Int, y: Int, width w: Int, height h: Int, black: Bool = true) {
        for yy in max(0, y)..<min(height, y + h) {
            for xx in max(0, x)..<min(width, x + w) { self[xx, yy] = black }
        }
    }

    /// Strokes a rectangle. `dash` > 0 draws a dashed line with that segment length.
    public mutating func strokeRect(x: Int, y: Int, width w: Int, height h: Int,
                                    thickness t: Int = 2, radius r: Int = 0, dash: Int = 0) {
        guard w > 0, h > 0, t > 0 else { return }
        let x1 = x + w, y1 = y + h
        let radius = Double(r)
        for yy in max(0, y)..<min(height, y1) {
            for xx in max(0, x)..<min(width, x1) {
                let px = Double(xx) + 0.5, py = Double(yy) + 0.5
                let inStroke: Bool
                if r > 0 {
                    let rr = max(radius, Double(t))
                    let qx = min(max(px, Double(x) + rr), Double(x1) - rr)
                    let qy = min(max(py, Double(y) + rr), Double(y1) - rr)
                    let d = ((px - qx) * (px - qx) + (py - qy) * (py - qy)).squareRoot() - rr
                    inStroke = d <= 0 && d > -Double(t)
                } else {
                    inStroke = xx < x + t || xx >= x1 - t || yy < y + t || yy >= y1 - t
                }
                guard inStroke else { continue }
                if dash > 0 {
                    let alongHorizontal = yy < y + t || yy >= y1 - t
                    let pos = alongHorizontal ? xx - x : yy - y
                    if (pos / dash) % 2 == 1 { continue }
                }
                self[xx, yy] = true
            }
        }
    }

    public mutating func withBytes(_ body: (inout [UInt8]) -> Void) {
        var copy = bytes
        body(&copy)
        self = MonoBitmap(width: width, height: height, bytes: copy)
    }
}

/// Chamfer (3-4) distance, in pixels, from every pixel to the nearest `true` pixel of `mask`.
public func distanceToMask(_ mask: [Bool], width: Int, height: Int) -> [Float] {
    let inf: Float = 1e9
    var d = mask.map { $0 ? 0 : inf }
    func at(_ x: Int, _ y: Int) -> Float { d[y * width + x] }
    for y in 0..<height {
        for x in 0..<width {
            var v = d[y * width + x]
            if x > 0 { v = min(v, at(x - 1, y) + 3) }
            if y > 0 {
                v = min(v, at(x, y - 1) + 3)
                if x > 0 { v = min(v, at(x - 1, y - 1) + 4) }
                if x < width - 1 { v = min(v, at(x + 1, y - 1) + 4) }
            }
            d[y * width + x] = v
        }
    }
    for y in stride(from: height - 1, through: 0, by: -1) {
        for x in stride(from: width - 1, through: 0, by: -1) {
            var v = d[y * width + x]
            if x < width - 1 { v = min(v, at(x + 1, y) + 3) }
            if y < height - 1 {
                v = min(v, at(x, y + 1) + 3)
                if x < width - 1 { v = min(v, at(x + 1, y + 1) + 4) }
                if x > 0 { v = min(v, at(x - 1, y + 1) + 4) }
            }
            d[y * width + x] = v
        }
    }
    return d.map { $0 / 3 }
}
