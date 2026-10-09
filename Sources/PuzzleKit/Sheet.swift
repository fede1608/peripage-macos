import AppKit
import PeriPageKit
import PeriRender

/// Fonts used on puzzle sheets. Bold weights survive thermal printing much better than light ones.
enum PuzzleFont {
    static func named(_ name: String, _ size: CGFloat, fallback weight: NSFont.Weight) -> NSFont {
        NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
    static func title(_ size: CGFloat) -> NSFont { named("AvenirNextCondensed-Heavy", size, fallback: .heavy) }
    static func heavy(_ size: CGFloat) -> NSFont { named("AvenirNext-Heavy", size, fallback: .heavy) }
    static func bold(_ size: CGFloat) -> NSFont { named("AvenirNext-Bold", size, fallback: .bold) }
    static func demi(_ size: CGFloat) -> NSFont { named("AvenirNext-DemiBold", size, fallback: .semibold) }
    static func medium(_ size: CGFloat) -> NSFont { named("AvenirNext-Medium", size, fallback: .medium) }
    static func condensed(_ size: CGFloat) -> NSFont { named("AvenirNextCondensed-DemiBold", size, fallback: .semibold) }
}

/// A rendered piece of text: trimmed horizontally to its ink, with the cap-height band located so that
/// letters and digits of one font share a baseline when centered in cells.
struct Glyph {
    let bitmap: MonoBitmap
    /// Rows (within `bitmap`) of the top of a capital letter and of the baseline.
    let capTop: Int
    let baseline: Int
    var width: Int { bitmap.width }
    /// Vertical middle of the cap band.
    var capMiddle: Double { Double(capTop + baseline) / 2 }
}

/// Renders and memoizes short strings in one font. Not thread-safe: create one per render.
final class GlyphSet {
    let font: NSFont
    private let boxHeight: Int
    private let capTop: Int
    private let baseline: Int
    private var cache: [String: Glyph] = [:]

    init(_ font: NSFont) {
        self.font = font
        boxHeight = Int(ceil(font.ascender - font.descender + font.leading)) + 6
        let probe = TextRenderer.renderLine("H", font: font, kern: 0, height: boxHeight)
        var top = 0, bottom = probe.height - 1
        func rowHasInk(_ y: Int) -> Bool { (0..<probe.width).contains { probe[$0, y] } }
        while top < probe.height && !rowHasInk(top) { top += 1 }
        while bottom > top && !rowHasInk(bottom) { bottom -= 1 }
        capTop = top
        baseline = bottom + 1
    }

    func glyph(_ text: String) -> Glyph {
        if let g = cache[text] { return g }
        let line = TextRenderer.renderLine(text, font: font, kern: 0, height: boxHeight).trimmedHorizontally()
        let g = Glyph(bitmap: line, capTop: capTop, baseline: baseline)
        cache[text] = g
        return g
    }

    /// Draws `text` centered on (cx, cy), using the cap band for vertical centering.
    func draw(_ text: String, on canvas: inout Canvas, cx: Double, cy: Double, knockout: Bool = false) {
        let g = glyph(text)
        let x = Int((cx - Double(g.width) / 2).rounded())
        let y = Int((cy - g.capMiddle).rounded())
        if knockout { canvas.knockout(g.bitmap, x: x, y: y) } else { canvas.blit(g.bitmap, x: x, y: y) }
    }

    /// Draws `text` with its left edge at x (or right edge when `alignRight`), vertically centered on cy.
    func draw(_ text: String, on canvas: inout Canvas, x: Int, cy: Double, alignRight: Bool = false) {
        let g = glyph(text)
        let left = alignRight ? x - g.width : x
        canvas.blit(g.bitmap, x: left, y: Int((cy - g.capMiddle).rounded()))
    }

    /// Height of the cap band in pixels.
    var capHeight: Int { baseline - capTop }
}

/// Lays out a puzzle sheet top to bottom: header, instructions, content blocks and footer.
struct SheetBuilder {
    let width: Int
    /// Scale relative to the 384-dot A6 reference layout.
    let scale: CGFloat
    let margin: Int
    private var blocks: [(bitmap: MonoBitmap, gap: Int)] = []

    init(width: Int) {
        self.width = width
        scale = CGFloat(width) / 384
        margin = Int((6 * CGFloat(width) / 384).rounded())
    }

    var innerWidth: Int { width - 2 * margin }

    func px(_ v: CGFloat) -> Int { Int((v * scale).rounded()) }

    /// Title on the left, difficulty tag and level pips on the right, thick rule below.
    mutating func header(title: String, tag: String?, level: Int? = nil, levels: Int = 0) {
        let ruleT = max(3, px(3))
        let top = px(9)     // room for accents above the capitals (SOLUCIÓN)
        let pipR = 5.0 * Double(scale), pipGap = 4.0 * Double(scale)
        let tagGlyphs = GlyphSet(PuzzleFont.bold(17 * scale))
        let tagGlyph = tag.flatMap { $0.isEmpty ? nil : tagGlyphs.glyph($0.uppercased()) }
        var rightWidth = 0
        if let level = level, levels > 1, level >= 0 { rightWidth += Int(Double(levels) * (2 * pipR + pipGap)) + px(4) }
        if let tagGlyph { rightWidth += tagGlyph.width }
        // Largest title size (≤ 38 pt) that leaves room for the tag.
        var size: CGFloat = 38
        var titleGlyphs = GlyphSet(PuzzleFont.title(size * scale))
        var t = titleGlyphs.glyph(title.uppercased())
        while size > 22 && t.width + rightWidth + px(12) > innerWidth {
            size -= 2
            titleGlyphs = GlyphSet(PuzzleFont.title(size * scale))
            t = titleGlyphs.glyph(title.uppercased())
        }
        let rowH = GlyphSet(PuzzleFont.title(38 * scale)).capHeight + px(6)
        var canvas = Canvas(width: width, height: top + rowH + px(8) + ruleT)
        let cy = Double(top) + Double(rowH) / 2
        canvas.blit(t.bitmap, x: margin - 1, y: Int((cy - t.capMiddle).rounded()))

        var right = width - margin
        if let level, levels > 1 {
            for i in stride(from: levels - 1, through: 0, by: -1) {
                let cx = Double(right) - pipR
                if i <= level {
                    canvas.disc(cx, cy, radius: pipR)
                } else {
                    canvas.ring(cx, cy, radius: pipR, width: max(2, 2 * Double(scale)))
                }
                right -= Int(2 * pipR + pipGap)
            }
            right -= px(4)
        }
        if let tagGlyph {
            canvas.blit(tagGlyph.bitmap, x: right - tagGlyph.width, y: Int((cy - tagGlyph.capMiddle).rounded()))
        }
        canvas.fill(x: margin, y: canvas.height - ruleT, w: innerWidth, h: ruleT)
        blocks.append((canvas.bitmap(), 0))
    }

    /// Wrapped paragraph (instructions).
    mutating func text(_ text: String, size: CGFloat = 17, bold: Bool = false, align: TextAlign = .left, gap: CGFloat = 8) {
        let font = bold ? PuzzleFont.demi(size * scale) : PuzzleFont.medium(size * scale)
        let block = TextRenderer.render(text, font: font, align: align, width: innerWidth).trimmedVertically()
        add(block.padded(left: margin, right: margin), gap: gap)
    }

    /// Adds a block, centered horizontally.
    mutating func add(_ bitmap: MonoBitmap, gap: CGFloat = 12) {
        guard bitmap.height > 0 else { return }
        let placed = bitmap.width == width ? bitmap : bitmap.placed(inWidth: width, .center)
        blocks.append((placed, px(gap)))
    }

    mutating func add(_ canvas: Canvas, gap: CGFloat = 12) { add(canvas.bitmap(), gap: gap) }

    /// Thin rule and a small line with the puzzle name on the left and the id on the right.
    mutating func footer(left: String, right: String?) {
        let glyphs = GlyphSet(PuzzleFont.demi(14 * scale))
        let lineH = glyphs.capHeight + px(8)
        var canvas = Canvas(width: width, height: lineH + px(6))
        canvas.fill(x: margin, y: 0, w: innerWidth, h: max(1, px(1)))
        let cy = Double(px(6)) + Double(lineH) / 2
        glyphs.draw(left, on: &canvas, x: margin, cy: cy)
        if let right { glyphs.draw(right, on: &canvas, x: width - margin, cy: cy, alignRight: true) }
        blocks.append((canvas.bitmap(), px(14)))
    }

    func build() -> MonoBitmap {
        // Every block is sheet-wide, so the sheet is just their rows concatenated.
        let pad = px(4)
        let bpr = (width + 7) / 8
        let total = blocks.reduce(0) { $0 + $1.bitmap.height + $1.gap } + 2 * pad
        var bytes = [UInt8](repeating: 0, count: pad * bpr)
        bytes.reserveCapacity(total * bpr)
        for (bitmap, gap) in blocks {
            bytes += [UInt8](repeating: 0, count: gap * bpr)
            bytes += bitmap.width == width ? bitmap.bytes : bitmap.placed(inWidth: width).bytes
        }
        bytes += [UInt8](repeating: 0, count: pad * bpr)
        return MonoBitmap(width: width, height: total, bytes: bytes)
    }
}
