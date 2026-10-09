import CoreGraphics
import PeriPageKit

/// Printable frames drawn procedurally around any 1-bit content.
public enum DecorativeFrame: String, CaseIterable, Codable, Identifiable, Sendable {
    case none, thin, thick, rounded, double, dashed, dotted, ticket, stamp, film
    case hearts, stars, flowers, artDeco, ornate, checker, waves, confetti, polaroid

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: "Sin marco"
        case .thin: "Fino"
        case .thick: "Grueso"
        case .rounded: "Redondeado"
        case .double: "Doble línea"
        case .dashed: "Línea de corte"
        case .dotted: "Puntos"
        case .ticket: "Ticket dentado"
        case .stamp: "Estampilla"
        case .film: "Película"
        case .hearts: "Corazones"
        case .stars: "Estrellas"
        case .flowers: "Flores"
        case .artDeco: "Art déco"
        case .ornate: "Vintage"
        case .checker: "Damero"
        case .waves: "Ondas"
        case .confetti: "Confeti"
        case .polaroid: "Polaroid"
        }
    }

    /// Frames that make sense around text and labels (polaroid is photo-specific).
    public static let general: [DecorativeFrame] = allCases.filter { $0 != .polaroid }

    /// Horizontal space taken by the frame on each side, for a canvas `width` dots wide.
    public func margin(for width: Int) -> Int {
        let s = CGFloat(width) / 384
        let base: CGFloat = switch self {
        case .none: 0
        case .thin, .rounded: 10
        case .thick: 14
        case .double, .dashed, .dotted: 14
        case .ticket, .stamp: 18
        case .film: 34
        case .hearts, .stars, .flowers, .confetti: 26
        case .artDeco, .ornate: 24
        case .checker: 20
        case .waves: 18
        case .polaroid: 16
        }
        return Int((base * s).rounded())
    }

    public func contentWidth(for width: Int) -> Int { width - 2 * margin(for: width) }

    /// Wraps `content` in the frame on a canvas exactly `width` wide.
    /// `compact` reduces vertical margins (for short labels).
    public func apply(to content: MonoBitmap, width: Int, compact: Bool = false) -> MonoBitmap {
        guard self != .none else { return content.placed(inWidth: width) }
        let m = margin(for: width)
        let vm = compact ? max(4, m * 2 / 3) : m
        let w = width, h = content.height + 2 * vm
        let canvas = MonoCanvas(width: w, height: h)
        draw(in: canvas, margin: m, verticalMargin: vm)
        var out = canvas.makeBitmap()
        if self == .film {
            out = out.inverted()
            let holes = punchFilmHoles(width: w, height: h, margin: m)
            for y in 0..<h { for x in 0..<w where holes[x, y] { out[x, y] = false } }
        }
        out.blit(content, x: (w - content.width) / 2, y: vm)
        return out
    }

    private func draw(in canvas: MonoCanvas, margin m: Int, verticalMargin vm: Int) {
        let ctx = canvas.context
        let W = CGFloat(canvas.width), H = CGFloat(canvas.height)
        let s = W / 384
        let mid = CGFloat(m) / 2
        let rect = CGRect(x: 0, y: 0, width: W, height: H)

        func stroke(_ inset: CGFloat, _ lw: CGFloat, radius: CGFloat = 0, dash: [CGFloat] = []) {
            ctx.setLineWidth(lw)
            ctx.setLineDash(phase: 0, lengths: dash)
            let r = rect.insetBy(dx: inset + lw / 2, dy: inset + lw / 2)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        /// Calls `body` with centers spread evenly along a line `inset` from the edges, plus an index that is
        /// the same for mirrored positions (so alternating patterns stay symmetric).
        func alongBorder(spacing: CGFloat, inset: CGFloat, _ body: (CGPoint, Int) -> Void) {
            let xs = Shapes.positions(from: inset, to: W - inset, spacing: spacing)
            for (i, x) in xs.enumerated() { body(CGPoint(x: x, y: inset), i); body(CGPoint(x: x, y: H - inset), i) }
            let ys = Shapes.positions(from: inset, to: H - inset, spacing: spacing)
            for (i, y) in ys.enumerated().dropFirst().dropLast() { body(CGPoint(x: inset, y: y), i); body(CGPoint(x: W - inset, y: y), i) }
        }

        switch self {
        case .none:
            break
        case .thin:
            stroke(2 * s, 2 * s)
        case .thick:
            stroke(1 * s, 6 * s)
        case .rounded:
            stroke(2 * s, 3 * s, radius: 18 * s)
        case .polaroid:
            stroke(1 * s, 2 * s)
        case .double:
            stroke(1 * s, 4 * s)
            stroke(8 * s, 1.5 * s)
        case .dashed:
            stroke(5 * s, 2 * s, radius: 10 * s, dash: [9 * s, 6 * s])
            drawScissors(ctx, at: CGPoint(x: 26 * s, y: 6 * s), size: 9 * s)
        case .dotted:
            alongBorder(spacing: 11 * s, inset: mid) { c, _ in
                ctx.addEllipse(in: CGRect(x: c.x - 2.6 * s, y: c.y - 2.6 * s, width: 5.2 * s, height: 5.2 * s))
            }
            ctx.fillPath()
        case .ticket:
            // Sawtooth top and bottom edges plus a thin inner line.
            let tooth = 12 * s, depth = 9 * s
            for edgeY in [CGFloat(0), H] {
                let dir: CGFloat = edgeY == 0 ? 1 : -1
                ctx.move(to: CGPoint(x: 0, y: edgeY))
                var x: CGFloat = 0
                while x < W {
                    ctx.addLine(to: CGPoint(x: min(W, x + tooth / 2), y: edgeY + dir * depth))
                    ctx.addLine(to: CGPoint(x: min(W, x + tooth), y: edgeY))
                    x += tooth
                }
                ctx.closePath()
            }
            ctx.fillPath()
            stroke(depth + 4 * s, 1.5 * s)
        case .stamp:
            // Black perforated outer band (round bites) and a thin inner line.
            let band = 7 * s
            ctx.fill(rect)
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(rect.insetBy(dx: band, dy: band))
            let bite = 4.2 * s
            alongBorder(spacing: 11 * s, inset: 0) { c, _ in
                ctx.addEllipse(in: CGRect(x: c.x - bite, y: c.y - bite, width: bite * 2, height: bite * 2))
            }
            ctx.fillPath()
            ctx.setFillColor(gray: 0, alpha: 1)
            stroke(band + 4 * s, 1.5 * s)
        case .film:
            // Drawn inverted: the content area is black here and becomes white after inversion.
            ctx.fill(CGRect(x: CGFloat(m), y: 0, width: W - 2 * CGFloat(m), height: H))
        case .hearts:
            alongBorder(spacing: 22 * s, inset: mid) { c, _ in ctx.addPath(Shapes.heart(c, 8 * s)) }
            ctx.fillPath()
        case .stars:
            alongBorder(spacing: 21 * s, inset: mid) { c, i in
                ctx.addPath(Shapes.star(c, (i % 2 == 0 ? 9 : 6) * s, rotation: CGFloat(i % 3) * 0.3))
            }
            ctx.fillPath()
        case .flowers:
            alongBorder(spacing: 24 * s, inset: mid) { c, i in
                if i % 2 == 0 {
                    ctx.addPath(Shapes.flower(c, 9 * s))
                    ctx.fillPath()
                    ctx.setFillColor(gray: 1, alpha: 1)
                    ctx.fillEllipse(in: CGRect(x: c.x - 2.5 * s, y: c.y - 2.5 * s, width: 5 * s, height: 5 * s))
                    ctx.setFillColor(gray: 0, alpha: 1)
                } else {
                    ctx.fillEllipse(in: CGRect(x: c.x - 2.5 * s, y: c.y - 2.5 * s, width: 5 * s, height: 5 * s))
                }
            }
        case .artDeco:
            stroke(2 * s, 3 * s)
            stroke(9 * s, 1.5 * s)
            for (cx, cy, a0) in [(CGFloat(0), CGFloat(0), CGFloat(0)), (W, 0, .pi / 2), (W, H, .pi), (0, H, 3 * .pi / 2)] {
                for k in 0..<5 {
                    ctx.setLineWidth((k % 2 == 0 ? 2 : 1.2) * s)
                    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: (14 + CGFloat(k) * 6) * s,
                               startAngle: a0, endAngle: a0 + .pi / 2, clockwise: false)
                    ctx.strokePath()
                }
            }
            for c in [CGPoint(x: W / 2, y: 5.5 * s), CGPoint(x: W / 2, y: H - 5.5 * s)] {
                ctx.addPath(Shapes.diamond(c, 6 * s))
            }
            ctx.fillPath()
        case .ornate:
            stroke(3 * s, 1.5 * s)
            stroke(7 * s, 1 * s)
            for (cx, cy, sx, sy) in [(CGFloat(0), CGFloat(0), CGFloat(1), CGFloat(1)), (W, 0, -1, 1), (W, H, -1, -1), (0, H, 1, -1)] {
                drawFlourish(ctx, corner: CGPoint(x: cx, y: cy), sx: sx, sy: sy, s: s)
            }
        case .checker:
            let sq = 7 * s
            for (row, y0) in [CGFloat(0), H - 2 * sq].enumerated() {
                for (i, x) in stride(from: CGFloat(0), to: W, by: sq).enumerated() {
                    for j in 0..<2 where (i + j + row) % 2 == 0 {
                        ctx.fill(CGRect(x: x, y: y0 + CGFloat(j) * sq, width: sq, height: sq))
                    }
                }
            }
            for (col, x0) in [CGFloat(0), W - 2 * sq].enumerated() {
                for (i, y) in stride(from: 2 * sq, to: H - 2 * sq, by: sq).enumerated() {
                    for j in 0..<2 where (i + j + col) % 2 == 0 {
                        ctx.fill(CGRect(x: x0 + CGFloat(j) * sq, y: y, width: sq, height: min(sq, H - 2 * sq - y)))
                    }
                }
            }
        case .waves:
            ctx.setLineWidth(2.2 * s)
            for inset in [5 * s, 11 * s] {
                let amp = 2.6 * s, period = 16 * s
                let r = rect.insetBy(dx: inset, dy: inset)
                wave(ctx, from: CGPoint(x: r.minX, y: r.minY), to: CGPoint(x: r.maxX, y: r.minY), amp: amp, period: period)
                wave(ctx, from: CGPoint(x: r.maxX, y: r.minY), to: CGPoint(x: r.maxX, y: r.maxY), amp: amp, period: period)
                wave(ctx, from: CGPoint(x: r.maxX, y: r.maxY), to: CGPoint(x: r.minX, y: r.maxY), amp: amp, period: period)
                wave(ctx, from: CGPoint(x: r.minX, y: r.maxY), to: CGPoint(x: r.minX, y: r.minY), amp: amp, period: period)
            }
            ctx.strokePath()
        case .confetti:
            var rng = SplitMix(seed: UInt64(H) &* 2654435761)
            let band = CGFloat(m)
            for _ in 0..<Int((W + H) / (9 * s)) {
                let p: CGPoint
                if rng.next() % 2 == 0 {
                    let y = rng.next() % 2 == 0 ? CGFloat(rng.unit()) * band : H - CGFloat(rng.unit()) * band
                    p = CGPoint(x: CGFloat(rng.unit()) * W, y: y)
                } else {
                    let x = rng.next() % 2 == 0 ? CGFloat(rng.unit()) * band : W - CGFloat(rng.unit()) * band
                    p = CGPoint(x: x, y: CGFloat(rng.unit()) * H)
                }
                let size = (2.5 + CGFloat(rng.unit()) * 3.5) * s
                switch rng.next() % 4 {
                case 0:
                    ctx.fillEllipse(in: CGRect(x: p.x - size, y: p.y - size, width: size * 2, height: size * 2))
                case 1:
                    ctx.addPath(Shapes.star(p, size * 1.4, rotation: CGFloat(rng.unit()) * 3))
                    ctx.fillPath()
                case 2:
                    ctx.saveGState()
                    ctx.translateBy(x: p.x, y: p.y)
                    ctx.rotate(by: CGFloat(rng.unit()) * .pi)
                    ctx.fill(CGRect(x: -size * 1.4, y: -size * 0.45, width: size * 2.8, height: size * 0.9))
                    ctx.restoreGState()
                default:
                    ctx.addPath(Shapes.diamond(p, size * 1.2))
                    ctx.fillPath()
                }
            }
        }
    }

    private func punchFilmHoles(width w: Int, height h: Int, margin m: Int) -> MonoBitmap {
        let canvas = MonoCanvas(width: w, height: h)
        let s = CGFloat(w) / 384
        let holeW = CGFloat(m) * 0.45, holeH = 9 * s
        for y in stride(from: 6 * s, to: CGFloat(h) - holeH, by: 18 * s) {
            for x in [(CGFloat(m) - holeW) / 2, CGFloat(w) - (CGFloat(m) + holeW) / 2] {
                canvas.context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: holeW, height: holeH),
                                              cornerWidth: 2 * s, cornerHeight: 2 * s, transform: nil))
            }
        }
        canvas.context.fillPath()
        return canvas.makeBitmap()
    }

    private func wave(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, amp: CGFloat, period: CGFloat) {
        let len = hypot(b.x - a.x, b.y - a.y)
        let n = max(1, Int(len / 2))
        let ux = (b.x - a.x) / len, uy = (b.y - a.y) / len
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n) * len
            let off = sin(t / period * 2 * .pi) * amp
            let p = CGPoint(x: a.x + ux * t - uy * off, y: a.y + uy * t + ux * off)
            i == 0 ? ctx.move(to: p) : ctx.addLine(to: p)
        }
    }

    private func drawScissors(_ ctx: CGContext, at p: CGPoint, size r: CGFloat) {
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: p.x - r * 1.6, y: p.y - r * 0.9, width: r * 3.6, height: r * 1.8))
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.setLineWidth(r * 0.22)
        for dy in [-r * 0.45, r * 0.45] {
            ctx.strokeEllipse(in: CGRect(x: p.x - r * 1.3, y: p.y + dy - r * 0.32, width: r * 0.64, height: r * 0.64))
        }
        ctx.move(to: CGPoint(x: p.x - r * 0.7, y: p.y - r * 0.35))
        ctx.addLine(to: CGPoint(x: p.x + r * 1.6, y: p.y + r * 0.5))
        ctx.move(to: CGPoint(x: p.x - r * 0.7, y: p.y + r * 0.35))
        ctx.addLine(to: CGPoint(x: p.x + r * 1.6, y: p.y - r * 0.5))
        ctx.strokePath()
    }

    private func drawFlourish(_ ctx: CGContext, corner c: CGPoint, sx: CGFloat, sy: CGFloat, s: CGFloat) {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + sx * x * s, y: c.y + sy * y * s) }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: min(c.x, pt(30, 30).x), y: min(c.y, pt(30, 30).y), width: 30 * s, height: 30 * s))
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.setLineWidth(2 * s)
        // Two curls meeting at a diamond in the corner.
        ctx.move(to: pt(4, 26))
        ctx.addCurve(to: pt(12, 12), control1: pt(4, 18), control2: pt(6, 12))
        ctx.addCurve(to: pt(26, 4), control1: pt(18, 12), control2: pt(18, 4))
        ctx.strokePath()
        ctx.move(to: pt(4, 26))
        ctx.addCurve(to: pt(10, 22), control1: pt(4, 30), control2: pt(10, 28))
        ctx.move(to: pt(26, 4))
        ctx.addCurve(to: pt(22, 10), control1: pt(30, 4), control2: pt(28, 10))
        ctx.strokePath()
        ctx.addPath(Shapes.diamond(pt(13, 13), 5 * s))
        ctx.fillPath()
        ctx.fillEllipse(in: CGRect(x: pt(22, 22).x - 2 * s, y: pt(22, 22).y - 2 * s, width: 4 * s, height: 4 * s))
    }
}

/// Tiny deterministic PRNG for decorative randomness.
public struct SplitMix {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
