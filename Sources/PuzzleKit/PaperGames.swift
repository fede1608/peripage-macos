import Foundation
import PeriPageKit

/// Two-player paper games: fixed layouts, no solution sheet.
enum PaperGameSheet {
    static func render(_ doc: PuzzleDoc, width: Int) -> MonoBitmap {
        let size = doc.effectiveDifficulty
        var sheet = SheetBuilder(width: width)
        switch doc.kind {
        case .battleship: battleship(&sheet, size)
        case .dotsAndBoxes: dotsAndBoxes(&sheet, size)
        default: ticTacToe(&sheet, size)
        }
        sheet.footer(left: "\(doc.kind.title) · \(size.label(for: doc.kind))", right: "Para 2 jugadores")
        return sheet.build()
    }

    // MARK: Batalla naval

    struct Ship { let name: String; let length: Int; let count: Int }

    static func fleet(_ size: PuzzleDifficulty) -> (grid: Int, ships: [Ship]) {
        switch size {
        case .easy:
            (8, [Ship(name: "Acorazado", length: 4, count: 1), Ship(name: "Crucero", length: 3, count: 1),
                 Ship(name: "Submarino", length: 3, count: 1), Ship(name: "Destructor", length: 2, count: 1)])
        case .medium:
            (10, [Ship(name: "Portaaviones", length: 5, count: 1), Ship(name: "Acorazado", length: 4, count: 1),
                  Ship(name: "Crucero", length: 3, count: 1), Ship(name: "Submarino", length: 3, count: 1),
                  Ship(name: "Destructor", length: 2, count: 1)])
        case .hard, .expert:
            (12, [Ship(name: "Portaaviones", length: 5, count: 1), Ship(name: "Acorazado", length: 4, count: 2),
                  Ship(name: "Crucero", length: 3, count: 2), Ship(name: "Submarino", length: 3, count: 1),
                  Ship(name: "Destructor", length: 2, count: 2)])
        }
    }

    private static func battleship(_ sheet: inout SheetBuilder, _ size: PuzzleDifficulty) {
        let (n, ships) = fleet(size)
        sheet.header(title: "Batalla naval", tag: size.label(for: .battleship))
        sheet.text("Una hoja por jugador. Ubicá tus barcos en «Mi flota», en línea recta y sin que se toquen. Por turnos, cantá una casilla (por ejemplo B7): el rival responde «agua», «tocado» o «hundido». Anotá tus tiros en «Rival».")
        let mine = labeledGrid("Mi flota", n: n, sheet: sheet)
        sheet.add(mine.canvas, gap: 14)
        // The fleet list lines up with the grid's left edge.
        var list = fleetList(ships, width: mine.canvas.width - mine.gridX, sheet: sheet)
        list = list.padded(left: mine.gridX)
        sheet.add(list.trimmedRight(to: mine.canvas.width), gap: 14)
        sheet.add(labeledGrid("Rival", n: n, sheet: sheet).canvas, gap: 14)
    }

    private static func labeledGrid(_ title: String, n: Int, sheet: SheetBuilder) -> (canvas: Canvas, gridX: Int) {
        let titleGlyphs = GlyphSet(PuzzleFont.bold(18 * sheet.scale))
        let labelSize = CGFloat(n > 10 ? 13 : 15) * sheet.scale
        let labels = GlyphSet(PuzzleFont.demi(labelSize))
        let labelW = labels.glyph("10").width + sheet.px(8)
        let cell = min(sheet.px(n <= 8 ? 34 : 29), (sheet.innerWidth - labelW) / n)
        let titleH = titleGlyphs.capHeight + sheet.px(12)
        let thick = max(3, sheet.px(3)), thin = max(1, sheet.px(1))
        let x0 = labelW, y0 = titleH + labelW
        var canvas = Canvas(width: x0 + n * cell + thick, height: y0 + n * cell + thick)
        titleGlyphs.draw(title.uppercased(), on: &canvas, x: x0, cy: Double(titleGlyphs.capHeight) / 2 + 2)
        let letters = Array("ABCDEFGHIJKLMNOP")
        for i in 0..<n {
            let c = Double(i * cell) + Double(cell) / 2
            labels.draw(String(letters[i]), on: &canvas, cx: Double(x0) + c, cy: Double(titleH) + Double(labelW) / 2)
            labels.draw(String(i + 1), on: &canvas, x: x0 - sheet.px(5), cy: Double(y0) + c, alignRight: true)
        }
        for i in 0...n {
            let t = i == 0 || i == n ? thick : thin
            canvas.fill(x: x0 + i * cell - (t - 1) / 2, y: y0 - (thick - 1) / 2, w: t, h: n * cell + thick)
            canvas.fill(x: x0 - (thick - 1) / 2, y: y0 + i * cell - (t - 1) / 2, w: n * cell + thick, h: t)
        }
        return (canvas, x0)
    }

    private static func fleetList(_ ships: [Ship], width: Int, sheet: SheetBuilder) -> MonoBitmap {
        let glyphs = GlyphSet(PuzzleFont.demi(15 * sheet.scale))
        let box = sheet.px(13), boxGap = sheet.px(3)
        var items: [(String, Int)] = []
        for ship in ships {
            for _ in 0..<ship.count { items.append((ship.name, ship.length)) }
        }
        // Two columns when a row of boxes plus the longest name fits twice, otherwise one.
        let maxLength = items.map(\.1).max() ?? 5
        let widestName = items.map { glyphs.glyph($0.0).width }.max() ?? 0
        let needed = maxLength * (box + boxGap) + sheet.px(4) + widestName
        let columns = 2 * needed + sheet.px(14) <= width ? 2 : 1
        let rows = (items.count + columns - 1) / columns
        let lineH = box + sheet.px(9)
        let colW = columns == 2 ? width - needed - sheet.px(2) : width
        var canvas = Canvas(width: width, height: rows * lineH)
        for (i, (name, length)) in items.enumerated() {
            let column = i / rows
            let longest = items[(column * rows)..<min(items.count, (column + 1) * rows)].map(\.1).max() ?? length
            let x = column * colW, y = (i % rows) * lineH
            for k in 0..<length {
                canvas.strokeRect(x: x + k * (box + boxGap), y: y, w: box, h: box, t: max(2, sheet.px(2)))
            }
            glyphs.draw(name, on: &canvas, x: x + longest * (box + boxGap) + sheet.px(4), cy: Double(y) + Double(box) / 2)
        }
        return canvas.bitmap()
    }

    // MARK: Timbiriche

    private static func dotsAndBoxes(_ sheet: inout SheetBuilder, _ size: PuzzleDifficulty) {
        let (cols, rows) = [(6, 7), (8, 10), (10, 13), (10, 13)][size.level]
        sheet.header(title: "Timbiriche", tag: size.label(for: .dotsAndBoxes))
        sheet.text("Por turnos, uní dos puntos vecinos con una raya. Si cerrás un cuadradito, poné tu inicial adentro y jugá de nuevo. Gana quien cierre más cuadraditos.")
        let spacing = min(sheet.px(52), (sheet.innerWidth - sheet.px(12)) / (cols - 1))
        let pad = sheet.px(6)
        var canvas = Canvas(width: (cols - 1) * spacing + 2 * pad, height: (rows - 1) * spacing + 2 * pad)
        let r = max(3.2, Double(spacing) * 0.09)
        for y in 0..<rows {
            for x in 0..<cols {
                canvas.disc(Double(pad + x * spacing) + 0.5, Double(pad + y * spacing) + 0.5, radius: r)
            }
        }
        sheet.add(canvas, gap: 16)
        sheet.add(scoreLine(["Jugador 1", "Jugador 2"], sheet: sheet), gap: 18)
    }

    private static func scoreLine(_ names: [String], sheet: SheetBuilder) -> Canvas {
        let glyphs = GlyphSet(PuzzleFont.demi(15 * sheet.scale))
        let h = glyphs.capHeight + sheet.px(14)
        var canvas = Canvas(width: sheet.innerWidth, height: h)
        let colW = sheet.innerWidth / names.count
        for (i, name) in names.enumerated() {
            let x = i * colW
            let g = glyphs.glyph(name + ":")
            glyphs.draw(name + ":", on: &canvas, x: x, cy: Double(h) / 2)
            canvas.fill(x: x + g.width + sheet.px(6), y: h - sheet.px(5), w: colW - g.width - sheet.px(16), h: max(1, sheet.px(2)))
        }
        return canvas
    }

    // MARK: Ta-te-ti

    private static func ticTacToe(_ sheet: inout SheetBuilder, _ size: PuzzleDifficulty) {
        if size.level >= 2 {
            sheet.header(title: "Ta-te-ti gigante", tag: size.label(for: .ticTacToe))
            sheet.text("Nueve ta-te-tis en uno. La casilla donde jugás dentro de un tablero chico manda al rival al tablero chico de esa misma posición (si ya está cerrado, elige cualquiera). Quien gana un tablero chico lo tacha con su letra; gana quien consiga tres tableros en línea.")
            sheet.add(ultimateBoard(sheet: sheet), gap: 14)
        } else {
            let count = size.level == 0 ? 4 : 9
            let columns = size.level == 0 ? 2 : 3
            sheet.header(title: "Ta-te-ti", tag: size.label(for: .ticTacToe))
            sheet.text("Por turnos, uno marca X y el otro O. Gana quien complete primero una línea de tres: horizontal, vertical o diagonal.")
            let gap = sheet.px(20)
            let boardSize = (sheet.innerWidth - (columns - 1) * gap) / columns
            let rows = (count + columns - 1) / columns
            var canvas = Canvas(width: sheet.innerWidth, height: rows * boardSize + (rows - 1) * gap)
            for i in 0..<count {
                let x = (i % columns) * (boardSize + gap), y = (i / columns) * (boardSize + gap)
                let drawn = Double(boardSize) * 0.9
                let inset = (Double(boardSize) - drawn) / 2
                hash(&canvas, x: Double(x) + inset, y: Double(y) + inset, size: drawn, stroke: max(3, Double(sheet.px(3))))
            }
            sheet.add(canvas, gap: 16)
        }
        sheet.add(scoreLine(["X", "O", "Empates"], sheet: sheet), gap: 18)
    }

    /// The "#" of a ta-te-ti board: four strokes with round ends.
    private static func hash(_ canvas: inout Canvas, x: Double, y: Double, size: Double, stroke: Double) {
        let inset = size * 0.04
        for k in [1.0, 2.0] {
            let p = size * k / 3
            canvas.line(x + p, y + inset, x + p, y + size - inset, width: stroke)
            canvas.line(x + inset, y + p, x + size - inset, y + p, width: stroke)
        }
    }

    private static func ultimateBoard(sheet: SheetBuilder) -> Canvas {
        let size = sheet.innerWidth
        var canvas = Canvas(width: size, height: size)
        let big = Double(size)
        let thick = max(5, Double(sheet.px(5)))
        for k in [1.0, 2.0] {
            let p = big * k / 3
            canvas.line(p, 2, p, big - 2, width: thick)
            canvas.line(2, p, big - 2, p, width: thick)
        }
        let small = big / 3
        for r in 0..<3 {
            for c in 0..<3 {
                let inset = small * 0.12
                hash(&canvas, x: Double(c) * small + inset, y: Double(r) * small + inset, size: small - 2 * inset,
                     stroke: max(2, Double(sheet.px(2))))
            }
        }
        return canvas
    }
}
