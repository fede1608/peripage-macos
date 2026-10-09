// Chess mate puzzles. Positions come from the Lichess puzzle database (CC0, https://database.lichess.org/#puzzles),
// which ships each puzzle as the position before the opponent's last move plus the full UCI line; see ChessPuzzleData.swift.
import AppKit
import PeriPageKit
import PeriRender

enum ChessColor: Sendable {
    case white, black
    var opposite: ChessColor { self == .white ? .black : .white }
}

struct ChessPiece: Equatable, Sendable {
    /// Lowercase FEN letter: k q r b n p.
    let kind: Character
    let color: ChessColor

    /// Spanish algebraic letter (Rey, Dama, Torre, Alfil, Caballo); pawns have none.
    var spanishLetter: String {
        switch kind {
        case "k": "R"
        case "q": "D"
        case "r": "T"
        case "b": "A"
        case "n": "C"
        default: ""
        }
    }

    /// Unicode chess symbols: the "black" glyph is the filled silhouette, the "white" one its outline.
    var filledGlyph: String { ["k": "♚", "q": "♛", "r": "♜", "b": "♝", "n": "♞", "p": "♟"][kind] ?? "?" }
    var outlineGlyph: String { ["k": "♔", "q": "♕", "r": "♖", "b": "♗", "n": "♘", "p": "♙"][kind] ?? "?" }
}

struct ChessMove: Sendable {
    let from: Int
    let to: Int
    let piece: ChessPiece
    let capture: Bool
    let promotion: Character?
    /// 1 = short castle, 2 = long castle.
    let castle: Int

    /// Long algebraic in Spanish (Dh5xf7, e7-e8=D, O-O), unambiguous without move generation.
    func notation(mate: Bool = false) -> String {
        var s: String
        switch castle {
        case 1: s = "O-O"
        case 2: s = "O-O-O"
        default:
            s = piece.spanishLetter + ChessPosition.name(from) + (capture ? "x" : "-") + ChessPosition.name(to)
            if let promotion { s += "=" + ChessPiece(kind: promotion, color: piece.color).spanishLetter }
        }
        return mate ? s + "#" : s
    }
}

/// Board squares are indexed rank * 8 + file, with rank 0 = rank 1 (White's back rank).
struct ChessPosition: Sendable {
    var squares: [ChessPiece?] = Array(repeating: nil, count: 64)
    var sideToMove: ChessColor = .white

    init?(fen: String) {
        let fields = fen.split(separator: " ")
        guard let placement = fields.first else { return nil }
        let ranks = placement.split(separator: "/")
        guard ranks.count == 8 else { return nil }
        for (i, row) in ranks.enumerated() {
            let rank = 7 - i
            var file = 0
            for ch in row {
                if let empty = ch.wholeNumberValue {
                    file += empty
                } else {
                    guard file < 8 else { return nil }
                    squares[rank * 8 + file] = ChessPiece(kind: Character(ch.lowercased()), color: ch.isUppercase ? .white : .black)
                    file += 1
                }
            }
            guard file == 8 else { return nil }
        }
        sideToMove = fields.count > 1 && fields[1] == "b" ? .black : .white
    }

    static func name(_ square: Int) -> String {
        String(UnicodeScalar(UInt8(97 + square % 8))) + String(square / 8 + 1)
    }

    static func square(_ s: Substring) -> Int? {
        let chars = Array(s.utf8)
        guard chars.count == 2, (97...104).contains(chars[0]), (49...56).contains(chars[1]) else { return nil }
        return Int(chars[1] - 49) * 8 + Int(chars[0] - 97)
    }

    /// Plays a UCI move (e2e4, e7e8q). Handles castling, en passant and promotion; does not check legality.
    @discardableResult
    mutating func apply(uci: String) -> ChessMove? {
        guard uci.count >= 4,
              let from = ChessPosition.square(uci.prefix(2)),
              let to = ChessPosition.square(uci.dropFirst(2).prefix(2)),
              let piece = squares[from] else { return nil }
        let promotion = uci.count >= 5 ? uci.last : nil
        var capture = squares[to] != nil
        var castle = 0
        if piece.kind == "p", from % 8 != to % 8, squares[to] == nil {
            // En passant: the captured pawn sits beside the moving one.
            squares[(from / 8) * 8 + to % 8] = nil
            capture = true
        }
        if piece.kind == "k", abs(from % 8 - to % 8) == 2 {
            let rank = from / 8
            let short = to % 8 == 6
            castle = short ? 1 : 2
            let rookFrom = rank * 8 + (short ? 7 : 0), rookTo = rank * 8 + (short ? 5 : 3)
            squares[rookTo] = squares[rookFrom]
            squares[rookFrom] = nil
        }
        squares[to] = promotion.map { ChessPiece(kind: $0, color: piece.color) } ?? piece
        squares[from] = nil
        sideToMove = sideToMove.opposite
        return ChessMove(from: from, to: to, piece: piece, capture: capture, promotion: promotion, castle: castle)
    }
}

struct ChessPuzzle: Sendable {
    let id: String
    let mateIn: Int
    let rating: Int
    /// Position to solve (after the opponent's last move).
    let position: ChessPosition
    let lastMove: ChessMove
    /// Solver's moves interleaved with the opponent's replies; the last one mates.
    let solution: [ChessMove]
}

enum ChessLibrary {
    struct Entry: Sendable {
        let mateIn: Int
        let quartile: Int
        let id: String
        let fen: String
        let moves: [String]
        let rating: Int
    }

    static let entries: [Entry] = ChessPuzzleData.raw.split(separator: "\n").compactMap { line in
        let f = line.split(separator: "|", omittingEmptySubsequences: false)
        guard f.count == 6, let mateIn = Int(f[0]), let q = Int(f[1]), let rating = Int(f[5]) else { return nil }
        return Entry(mateIn: mateIn, quartile: q, id: String(f[2]), fen: String(f[3]),
                     moves: f[4].split(separator: " ").map(String.init), rating: rating)
    }

    static func puzzle(from entry: Entry) -> ChessPuzzle? {
        guard var position = ChessPosition(fen: entry.fen), let first = entry.moves.first,
              let last = position.apply(uci: first) else { return nil }
        let start = position
        var solution: [ChessMove] = []
        for uci in entry.moves.dropFirst() {
            guard let move = position.apply(uci: uci) else { return nil }
            solution.append(move)
        }
        return ChessPuzzle(id: entry.id, mateIn: entry.mateIn, rating: entry.rating, position: start, lastMove: last, solution: solution)
    }

    /// `count` distinct puzzles for the level, chosen deterministically from the seed.
    static func pick(mateIn: Int, difficulty: PuzzleDifficulty, count: Int, seed: UInt64) -> [ChessPuzzle] {
        let pool = entries.filter { $0.mateIn == mateIn && $0.quartile == difficulty.level }
        guard !pool.isEmpty else { return [] }
        var rng = PuzzleRNG(seed: seed, salt: UInt64(mateIn * 16 + difficulty.level))
        let order = rng.shuffled(Array(pool.indices))
        return order.prefix(max(1, count)).compactMap { puzzle(from: pool[$0]) }
    }
}

enum ChessSheet {
    static func render(_ doc: PuzzleDoc, _ puzzles: [ChessPuzzle], width: Int, solution: Bool) -> MonoBitmap {
        var sheet = SheetBuilder(width: width)
        let diff = doc.effectiveDifficulty
        let mate = "Mate en \(doc.clampedChessMateIn)"
        if solution {
            sheet.header(title: "Solución", tag: mate)
        } else {
            sheet.header(title: "Ajedrez", tag: mate, level: diff.level, levels: 4)
            if puzzles.count == 1, let p = puzzles.first {
                sheet.text("Juegan las \(p.position.sideToMove == .white ? "blancas" : "negras") y dan mate en \(p.mateIn)"
                           + (p.mateIn == 1 ? " jugada." : " jugadas, contra cualquier defensa."))
            } else {
                sheet.text("En cada posición, el bando indicado da mate en \(doc.clampedChessMateIn)"
                           + (doc.clampedChessMateIn == 1 ? " jugada." : " jugadas."))
            }
        }
        for (i, p) in puzzles.enumerated() {
            let side = p.position.sideToMove == .white ? "Juegan blancas" : "Juegan negras"
            if puzzles.count > 1 || solution {
                sheet.text("\(puzzles.count > 1 ? "\(i + 1). " : "")\(side)", size: 16, bold: true, gap: i == 0 ? 10 : 18)
            }
            if solution {
                sheet.text(solutionLines(p), size: 18, bold: true, gap: 6)
                sheet.add(board(p, sheet: sheet, highlight: p.solution.first, size: 0.62), gap: 8)
            } else {
                sheet.add(board(p, sheet: sheet, highlight: nil, size: 1), gap: 10)
            }
            sheet.text("Lichess #\(p.id) · rating \(p.rating)", size: 12, align: .center, gap: 4)
        }
        sheet.footer(left: "Ajedrez · \(mate) · \(diff.label(for: .chess))", right: "#\(doc.seed)")
        return sheet.build()
    }

    /// "1. Dh5xf7  Rg8-h8\n2. Df7-f8#": the solver's moves numbered, the opponent's replies beside them.
    static func solutionLines(_ p: ChessPuzzle) -> String {
        var lines: [String] = []
        var i = 0, n = 1
        while i < p.solution.count {
            let isLast = i == p.solution.count - 1
            var line = "\(n). " + p.solution[i].notation(mate: isLast)
            if i + 1 < p.solution.count { line += "   " + p.solution[i + 1].notation() }
            lines.append(line)
            i += 2
            n += 1
        }
        return lines.joined(separator: "\n")
    }

    /// Board from the solver's point of view, with coordinates, dotted dark squares and haloed pieces.
    static func board(_ p: ChessPuzzle, sheet: SheetBuilder, highlight: ChessMove?, size: CGFloat) -> Canvas {
        let coord = sheet.px(16)
        let border = max(2, sheet.px(2))
        let sq = max(16, Int(CGFloat(min(sheet.px(40), (sheet.innerWidth - coord - 2 * border) / 8)) * size))
        let boardPx = 8 * sq
        let w = coord + boardPx + 2 * border, h = boardPx + 2 * border + coord
        var canvas = Canvas(width: w, height: h)
        let x0 = coord + border, y0 = border
        let flipped = p.position.sideToMove == .black

        func origin(_ square: Int) -> (x: Int, y: Int) {
            let file = square % 8, rank = square / 8
            let col = flipped ? 7 - file : file
            let row = flipped ? rank : 7 - rank
            return (x0 + col * sq, y0 + row * sq)
        }

        // Dark squares: a sparse dot pattern reads as gray on thermal paper and keeps pieces legible.
        for square in 0..<64 where (square / 8 + square % 8) % 2 == 0 {
            let o = origin(square)
            for y in 0..<sq where y % 2 == 0 {
                for x in 0..<sq where (x + (y / 2) % 2) % 2 == 0 {
                    canvas.fill(x: o.x + x, y: o.y + y, w: 1, h: 1)
                }
            }
        }
        canvas.strokeRect(x: coord, y: 0, w: boardPx + 2 * border, h: boardPx + 2 * border, t: border)

        // Last move (or the first solution move) framed inside its squares.
        let marked = highlight ?? p.lastMove
        let frame = highlight == nil ? max(1, sheet.px(1.5)) : max(2, sheet.px(3))
        for square in [marked.from, marked.to] {
            let o = origin(square)
            canvas.fill(x: o.x + 1, y: o.y + 1, w: sq - 2, h: sq - 2, black: false)
            canvas.strokeRect(x: o.x + 2, y: o.y + 2, w: sq - 4, h: sq - 4, t: frame)
        }

        let pieces = PieceGlyphs(square: sq)
        for square in 0..<64 {
            guard let piece = p.position.squares[square] else { continue }
            let o = origin(square)
            pieces.draw(piece, on: &canvas, x: o.x, y: o.y)
        }

        let labels = GlyphSet(PuzzleFont.demi(12 * sheet.scale))
        for i in 0..<8 {
            let file = flipped ? 7 - i : i
            let rank = flipped ? i + 1 : 8 - i
            labels.draw(String(UnicodeScalar(UInt8(97 + file))), on: &canvas,
                        cx: Double(x0 + i * sq) + Double(sq) / 2, cy: Double(h) - Double(coord) / 2)
            labels.draw(String(rank), on: &canvas, cx: Double(coord) / 2, cy: Double(y0 + i * sq) + Double(sq) / 2)
        }
        return canvas
    }
}

/// Piece rendering: the filled silhouette (dilated) is cleared first so pieces stand out on dotted squares,
/// then white pieces get their outline glyph and black pieces their filled glyph.
/// Arial Unicode MS has the cleanest set; Apple Symbols swaps the two queens, so it is corrected when used.
private struct PieceGlyphs {
    let font: NSFont
    let swapsQueens: Bool
    let square: Int

    init(square: Int) {
        self.square = square
        let names = ["Arial Unicode MS", "STIXGeneral", "Apple Symbols"]
        let name = names.first { NSFont(name: $0, size: 10) != nil } ?? "Apple Symbols"
        swapsQueens = name == "Apple Symbols"
        // Size the font so the king (tallest piece) fills ~84% of the square.
        let probe = NSFont(name: name, size: 100) ?? .systemFont(ofSize: 100)
        let kingHeight = PieceGlyphs.inkBox(PieceGlyphs.raster("♚", font: probe, canvas: 200))?.h ?? 80
        font = NSFont(name: name, size: 100 * CGFloat(square) * 0.84 / CGFloat(max(1, kingHeight))) ?? probe
    }

    func draw(_ piece: ChessPiece, on canvas: inout Canvas, x: Int, y: Int) {
        var filled = piece.filledGlyph, outline = piece.outlineGlyph
        if swapsQueens && piece.kind == "q" { swap(&filled, &outline) }
        let size = square * 2
        let silhouette = PieceGlyphs.raster(filled, font: font, canvas: size)
        guard let box = PieceGlyphs.inkBox(silhouette) else { return }
        let ink = piece.color == .white ? PieceGlyphs.raster(outline, font: font, canvas: size) : silhouette
        let dx = x + (square - box.w) / 2 - box.x, dy = y + (square - box.h) / 2 - box.y
        let r = max(1, square / 20)
        // Halo: clear a slightly dilated silhouette, clipped to the square.
        for py in max(0, box.y - r)..<min(size, box.y + box.h + r) {
            for px in max(0, box.x - r)..<min(size, box.x + box.w + r) {
                let tx = px + dx, ty = py + dy
                guard tx >= x, ty >= y, tx < x + square, ty < y + square else { continue }
                if PieceGlyphs.near(silhouette, px, py, r) { canvas.fill(x: tx, y: ty, w: 1, h: 1, black: false) }
            }
        }
        canvas.blit(ink, x: dx, y: dy)
    }

    private static func near(_ b: MonoBitmap, _ x: Int, _ y: Int, _ r: Int) -> Bool {
        for oy in -r...r {
            for ox in -r...r where ox * ox + oy * oy <= r * r {
                let nx = x + ox, ny = y + oy
                if nx >= 0, ny >= 0, nx < b.width, ny < b.height, b[nx, ny] { return true }
            }
        }
        return false
    }

    static func raster(_ glyph: String, font: NSFont, canvas: Int) -> MonoBitmap {
        let attributed = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: NSColor.black])
        return TextRenderer.draw(width: canvas, height: canvas) {
            attributed.draw(at: CGPoint(x: CGFloat(canvas) * 0.1, y: CGFloat(canvas) * 0.05))
        }
    }

    static func inkBox(_ b: MonoBitmap) -> (x: Int, y: Int, w: Int, h: Int)? {
        var minX = b.width, minY = b.height, maxX = -1, maxY = -1
        for y in 0..<b.height {
            for x in 0..<b.width where b[x, y] {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return maxX < 0 ? nil : (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }
}
