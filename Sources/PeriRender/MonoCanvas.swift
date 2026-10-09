import CoreGraphics
import PeriPageKit

/// Grayscale CoreGraphics canvas with a top-left origin (y grows downward), white background and black ink.
/// Shapes are drawn antialiased and thresholded into a `MonoBitmap`.
public struct MonoCanvas {
    public let width: Int
    public let height: Int
    public let context: CGContext

    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        context = CGContext(data: nil, width: self.width, height: self.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: self.width, height: self.height))
        context.translateBy(x: 0, y: CGFloat(self.height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(gray: 0, alpha: 1)
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setLineCap(.round)
        context.setLineJoin(.round)
    }

    public func makeBitmap(threshold: Float = 0.5) -> MonoBitmap {
        let image = context.makeImage()!
        return ImageProcessor.dither(GrayImage(cgImage: image, width: width)!, algorithm: .threshold, threshold: Double(threshold))
    }
}

/// Small vector shapes used by decorative frames, centered on `c` and sized by `r` (≈ radius).
public enum Shapes {
    public static func heart(_ c: CGPoint, _ r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x, y: c.y + r * 0.95))
        p.addCurve(to: CGPoint(x: c.x - r, y: c.y - r * 0.15),
                   control1: CGPoint(x: c.x - r * 0.45, y: c.y + r * 0.55), control2: CGPoint(x: c.x - r, y: c.y + r * 0.3))
        p.addCurve(to: CGPoint(x: c.x, y: c.y - r * 0.45),
                   control1: CGPoint(x: c.x - r, y: c.y - r * 0.85), control2: CGPoint(x: c.x - r * 0.15, y: c.y - r * 0.85))
        p.addCurve(to: CGPoint(x: c.x + r, y: c.y - r * 0.15),
                   control1: CGPoint(x: c.x + r * 0.15, y: c.y - r * 0.85), control2: CGPoint(x: c.x + r, y: c.y - r * 0.85))
        p.addCurve(to: CGPoint(x: c.x, y: c.y + r * 0.95),
                   control1: CGPoint(x: c.x + r, y: c.y + r * 0.3), control2: CGPoint(x: c.x + r * 0.45, y: c.y + r * 0.55))
        p.closeSubpath()
        return p
    }

    public static func star(_ c: CGPoint, _ r: CGFloat, points: Int = 5, inner: CGFloat = 0.45, rotation: CGFloat = 0) -> CGPath {
        let p = CGMutablePath()
        for i in 0..<(points * 2) {
            let radius = i % 2 == 0 ? r : r * inner
            let a = rotation - .pi / 2 + CGFloat(i) * .pi / CGFloat(points)
            let pt = CGPoint(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }

    public static func diamond(_ c: CGPoint, _ r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addLine(to: CGPoint(x: c.x + r * 0.7, y: c.y))
        p.addLine(to: CGPoint(x: c.x, y: c.y + r))
        p.addLine(to: CGPoint(x: c.x - r * 0.7, y: c.y))
        p.closeSubpath()
        return p
    }

    public static func flower(_ c: CGPoint, _ r: CGFloat, petals: Int = 5) -> CGPath {
        let p = CGMutablePath()
        for i in 0..<petals {
            let a = CGFloat(i) * 2 * .pi / CGFloat(petals) - .pi / 2
            let pc = CGPoint(x: c.x + cos(a) * r * 0.55, y: c.y + sin(a) * r * 0.55)
            p.addEllipse(in: CGRect(x: pc.x - r * 0.45, y: pc.y - r * 0.45, width: r * 0.9, height: r * 0.9))
        }
        return p
    }

    /// Evenly spaced positions from `a` to `b` (inclusive) with roughly `spacing` between them.
    public static func positions(from a: CGFloat, to b: CGFloat, spacing: CGFloat) -> [CGFloat] {
        let n = max(1, Int(((b - a) / spacing).rounded()))
        return (0...n).map { a + (b - a) * CGFloat($0) / CGFloat(n) }
    }
}
