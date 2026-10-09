import Foundation
import PeriPageKit

/// Letters are stored as codes 0...26 (A–Z, then Ñ).
enum Alphabet {
    static let letters: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZÑ")

    static func code(_ ch: Character) -> UInt8? {
        if ch == "Ñ" { return 26 }
        guard let a = ch.asciiValue, a >= 65, a <= 90 else { return nil }
        return a - 65
    }

    static func codes(_ word: String) -> [UInt8] { word.compactMap(code) }

    /// Approximate Spanish letter frequencies (per mille), used for the filler letters.
    static let spanishWeights: [Int] = [
        125, 14, 47, 59, 137, 7, 10, 7, 63, 4, 1, 50, 32, 67, 87, 25, 9, 69, 80, 46, 39, 9, 1, 2, 9, 5, 3,
    ]
}

struct PlacedWord: Sendable, Equatable {
    /// As printed in the list (uppercase, accents kept).
    let display: String
    let codes: [UInt8]
    let row: Int
    let col: Int
    let dr: Int
    let dc: Int

    var cells: [(Int, Int)] { (0..<codes.count).map { (row + $0 * dr, col + $0 * dc) } }
}

struct WordSearchPuzzle: Sendable {
    let rows: Int
    let cols: Int
    let grid: [UInt8]
    let words: [PlacedWord]
    let themeLabel: String
    let directionsHint: String
}

enum WordSearchGenerator {
    static let allDirections = [(0, 1), (1, 0), (1, 1), (-1, 1), (0, -1), (-1, 0), (-1, -1), (1, -1)]

    struct Config {
        let size: Int
        let wordCount: Int
        let directions: [(Int, Int)]
        /// Probability of preferring a placement that shares letters with words already placed.
        let overlapBias: Double
        /// Share of filler letters drawn from the hidden words (decoys) instead of plain frequencies.
        let decoyShare: Double
        let hint: String
    }

    static func config(_ difficulty: PuzzleDifficulty) -> Config {
        switch difficulty {
        case .easy:
            Config(size: 10, wordCount: 8, directions: [(0, 1), (1, 0)], overlapBias: 0.1, decoyShare: 0.15,
                   hint: "Las palabras van de izquierda a derecha o de arriba hacia abajo.")
        case .medium:
            Config(size: 12, wordCount: 12, directions: [(0, 1), (1, 0), (1, 1), (-1, 1)], overlapBias: 0.35,
                   decoyShare: 0.3, hint: "Las palabras van hacia la derecha, hacia abajo o en diagonal.")
        case .hard, .expert:
            Config(size: 14, wordCount: 16, directions: allDirections, overlapBias: 0.6, decoyShare: 0.45,
                   hint: "Las palabras van en cualquier dirección, también al revés y en diagonal.")
        }
    }

    static func generate(theme: WordTheme, customWords: String, difficulty: PuzzleDifficulty, seed: UInt64) -> WordSearchPuzzle {
        let cfg = config(difficulty)
        var rng = PuzzleRNG(seed: seed, salt: 0x50FA &+ UInt64(difficulty.level) << 8)
        // Candidate words: (display, letters).
        var pool: [(String, [UInt8])]
        var label = theme.label
        let custom = theme == .custom ? customEntries(customWords) : []
        if theme == .custom && !custom.isEmpty {
            pool = Array(custom.prefix(30))     // more would not fit a 16×16 grid anyway
        } else {
            let source = theme == .custom ? WordTheme.animals : theme
            if theme == .custom { label = source.label }
            pool = rng.shuffled(source.words).map { ($0.uppercased(), Alphabet.codes(WordNormalizer.normalize($0))) }
        }
        let longest = pool.map(\.1.count).max() ?? 3
        let size = theme == .custom && !custom.isEmpty ? min(16, max(cfg.size, longest)) : cfg.size
        pool = pool.filter { $0.1.count >= 2 && $0.1.count <= size }
        let target = theme == .custom && !custom.isEmpty ? pool.count : cfg.wordCount

        // Keep the attempt that hides the most words (custom lists may not all fit).
        var best: WordSearchPuzzle?
        for _ in 0..<(target > cfg.wordCount ? 12 : 40) {
            guard let puzzle = attempt(pool: pool, target: target, size: size, cfg: cfg, label: label, rng: &rng) else { continue }
            if puzzle.words.count >= target { return puzzle }
            if best == nil || puzzle.words.count > best!.words.count { best = puzzle }
        }
        if let best { return best }
        // Practically unreachable: a grid of random letters is still a valid sheet.
        return attempt(pool: [], target: 0, size: size, cfg: cfg, label: label, rng: &rng)!
    }

    /// User words: split on commas / new lines (spaces inside an entry are joined in the grid), or on spaces
    /// when there are no commas or new lines.
    static func customEntries(_ text: String) -> [(String, [UInt8])] {
        let byLine = text.contains(",") || text.contains("\n") || text.contains(";")
        let parts = text.split(whereSeparator: { byLine ? ",;\n".contains($0) : " \t".contains($0) })
        var seen = Set<[UInt8]>()
        var out: [(String, [UInt8])] = []
        for part in parts {
            let display = part.split(separator: " ").joined(separator: " ").uppercased()
            let codes = Alphabet.codes(WordNormalizer.normalize(display))
            if codes.count >= 2, seen.insert(codes).inserted { out.append((display, codes)) }
        }
        return out
    }

    private static func related(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        func contains(_ big: [UInt8], _ small: [UInt8]) -> Bool {
            guard small.count <= big.count else { return false }
            for s in 0...(big.count - small.count) where Array(big[s..<(s + small.count)]) == small { return true }
            return false
        }
        let rb = Array(b.reversed())
        return contains(a, b) || contains(b, a) || contains(a, rb) || contains(rb, a)
    }

    private static func attempt(pool: [(String, [UInt8])], target: Int, size: Int, cfg: Config, label: String,
                                rng: inout PuzzleRNG) -> WordSearchPuzzle? {
        let rows = size, cols = size
        var grid = [UInt8](repeating: 255, count: rows * cols)
        var placed: [PlacedWord] = []

        // Choose words that do not contain each other (forwards or backwards), longest placed first.
        var chosen: [(String, [UInt8])] = []
        for entry in pool where chosen.count < target + 6 {
            if !chosen.contains(where: { related($0.1, entry.1) }) { chosen.append(entry) }
        }
        let ordered = chosen.enumerated().sorted { a, b in
            a.element.1.count != b.element.1.count ? a.element.1.count > b.element.1.count : a.offset < b.offset
        }.map(\.element)

        for (display, codes) in ordered where placed.count < target {
            var options: [(Int, Int, Int, Int, Int)] = []   // r, c, dr, dc, overlap
            for (dr, dc) in cfg.directions {
                let len = codes.count
                for r in 0..<rows {
                    let endR = r + dr * (len - 1)
                    guard endR >= 0, endR < rows else { continue }
                    for c in 0..<cols {
                        let endC = c + dc * (len - 1)
                        guard endC >= 0, endC < cols else { continue }
                        var overlap = 0, ok = true
                        var k = 0
                        while k < len {
                            let g = grid[(r + k * dr) * cols + c + k * dc]
                            if g != 255 {
                                if g != codes[k] { ok = false; break }
                                overlap += 1
                            }
                            k += 1
                        }
                        // Never hide a word entirely inside another one.
                        if ok, overlap < len { options.append((r, c, dr, dc, overlap)) }
                    }
                }
            }
            guard !options.isEmpty else { continue }
            // Spread words over the allowed directions: favor the ones used least so far.
            var weights: [Double] = []
            var dirs: [(Int, Int)] = []
            for (dr, dc) in cfg.directions where options.contains(where: { $0.2 == dr && $0.3 == dc }) {
                let used = placed.filter { $0.dr == dr && $0.dc == dc }.count
                dirs.append((dr, dc))
                weights.append(1 / Double((1 + used) * (1 + used)))
            }
            var x = rng.unit() * weights.reduce(0, +)
            var di = 0
            while di < weights.count - 1 && x >= weights[di] { x -= weights[di]; di += 1 }
            let inDirection = options.filter { $0.2 == dirs[di].0 && $0.3 == dirs[di].1 }
            let crossing = inDirection.filter { $0.4 > 0 }
            let pickFrom = !crossing.isEmpty && rng.chance(cfg.overlapBias) ? crossing : inDirection
            let (r, c, dr, dc, _) = rng.pick(pickFrom)
            for k in 0..<codes.count { grid[(r + k * dr) * cols + c + k * dc] = codes[k] }
            placed.append(PlacedWord(display: display, codes: codes, row: r, col: c, dr: dr, dc: dc))
        }

        // Fill the rest; re-roll the filler until every word appears exactly once.
        let free = (0..<(rows * cols)).filter { grid[$0] == 255 }
        let wordLetters = placed.flatMap(\.codes)
        let totalWeight = Alphabet.spanishWeights.reduce(0, +)
        for _ in 0..<60 {
            for i in free {
                if !wordLetters.isEmpty && rng.chance(cfg.decoyShare) {
                    grid[i] = rng.pick(wordLetters)
                } else {
                    var x = rng.int(totalWeight)
                    var letter = 0
                    while x >= Alphabet.spanishWeights[letter] { x -= Alphabet.spanishWeights[letter]; letter += 1 }
                    grid[i] = UInt8(letter)
                }
            }
            if placed.allSatisfy({ occurrences(of: $0.codes, in: grid, rows: rows, cols: cols) == 1 }) {
                let spanish = Locale(identifier: "es")
                let sorted = placed.sorted {
                    $0.display.compare($1.display, options: [.caseInsensitive], range: nil, locale: spanish) == .orderedAscending
                }
                return WordSearchPuzzle(rows: rows, cols: cols, grid: grid, words: sorted, themeLabel: label,
                                        directionsHint: cfg.hint)
            }
        }
        return nil
    }

    /// Distinct placements of `word` in any of the 8 directions (a palindrome read both ways counts once).
    static func occurrences(of word: [UInt8], in grid: [UInt8], rows: Int, cols: Int) -> Int {
        let len = word.count
        guard len > 0 else { return 0 }
        var found = 0
        let isPalindrome = word == word.reversed()
        for r in 0..<rows {
            for c in 0..<cols where grid[r * cols + c] == word[0] {
                for (i, (dr, dc)) in allDirections.enumerated() {
                    let endR = r + dr * (len - 1), endC = c + dc * (len - 1)
                    guard endR >= 0, endR < rows, endC >= 0, endC < cols else { continue }
                    var k = 1
                    while k < len && grid[(r + k * dr) * cols + c + k * dc] == word[k] { k += 1 }
                    if k == len {
                        // Directions 4...7 are the reverses of 0...3: count a palindrome only once.
                        if isPalindrome && i >= 4 && len > 1 { continue }
                        found += 1
                    }
                }
            }
        }
        return found
    }
}

enum WordSearchSheet {
    static func render(_ doc: PuzzleDoc, _ p: WordSearchPuzzle, width: Int, solution: Bool) -> MonoBitmap {
        var sheet = SheetBuilder(width: width)
        let diff = doc.effectiveDifficulty
        if solution {
            sheet.header(title: "Solución", tag: "Sopa de letras")
        } else {
            sheet.header(title: "Sopa de letras", tag: diff.label(for: .wordSearch), level: diff.level, levels: 3)
            sheet.text("Tema: \(p.themeLabel). Encontrá las \(p.words.count) palabras de la lista. \(p.directionsHint)")
        }
        sheet.add(grid(p, sheet: sheet, solution: solution), gap: 14)
        if !solution {
            sheet.add(wordList(p, sheet: sheet), gap: 14)
        }
        sheet.footer(left: "Sopa de letras · \(p.themeLabel) · \(diff.label(for: .wordSearch))", right: "#\(doc.seed)")
        return sheet.build()
    }

    private static func grid(_ p: WordSearchPuzzle, sheet: SheetBuilder, solution: Bool) -> Canvas {
        let border = max(3, sheet.px(3))
        let pad = sheet.px(6)
        let cell = min(sheet.px(38), (sheet.innerWidth - 2 * (border + pad)) / p.cols)
        let w = p.cols * cell + 2 * (border + pad), h = p.rows * cell + 2 * (border + pad)
        var canvas = Canvas(width: w, height: h)
        canvas.strokeRect(x: 0, y: 0, w: w, h: h, t: border)
        // Round the outer corners a little.
        for (cx, cy) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)] {
            canvas[cx, cy] = false
        }
        let origin = Double(border + pad)
        func center(_ r: Int, _ c: Int) -> (Double, Double) {
            (origin + (Double(c) + 0.5) * Double(cell), origin + (Double(r) + 0.5) * Double(cell))
        }
        var inWord = Set<Int>()
        if solution {
            let radius = Double(cell) * 0.44
            let stroke = max(2, Double(sheet.px(2)))
            for word in p.words {
                let (ax, ay) = center(word.row, word.col)
                let last = word.codes.count - 1
                let (bx, by) = center(word.row + last * word.dr, word.col + last * word.dc)
                canvas.capsule(ax, ay, bx, by, radius: radius, width: stroke)
                for (r, c) in word.cells { inWord.insert(r * p.cols + c) }
            }
        }
        let font = PuzzleFont.bold(CGFloat(cell) * 0.64)
        let glyphs = GlyphSet(font)
        for r in 0..<p.rows {
            for c in 0..<p.cols {
                let (cx, cy) = center(r, c)
                if solution && !inWord.contains(r * p.cols + c) {
                    canvas.disc(cx, cy, radius: max(1.2, Double(cell) * 0.06))
                    continue
                }
                glyphs.draw(String(Alphabet.letters[Int(p.grid[r * p.cols + c])]), on: &canvas, cx: cx, cy: cy)
            }
        }
        return canvas
    }

    private static func wordList(_ p: WordSearchPuzzle, sheet: SheetBuilder) -> Canvas {
        let glyphs = GlyphSet(PuzzleFont.demi(17 * sheet.scale))
        let widest = p.words.map { glyphs.glyph($0.display).width }.max() ?? 10
        let box = sheet.px(11)
        let itemW = box + sheet.px(7) + widest
        let gap = sheet.px(14)
        let columns = max(1, min(3, (sheet.innerWidth + gap) / (itemW + gap)))
        let rowsPerColumn = (p.words.count + columns - 1) / columns
        let lineH = glyphs.capHeight + sheet.px(13)
        let colW = (sheet.innerWidth - (columns - 1) * gap) / columns
        var canvas = Canvas(width: sheet.innerWidth, height: rowsPerColumn * lineH)
        for (i, word) in p.words.enumerated() {
            let col = i / rowsPerColumn, row = i % rowsPerColumn
            let x = col * (colW + gap)
            let cy = Double(row * lineH) + Double(lineH) / 2
            canvas.strokeRect(x: x, y: Int(cy) - box / 2, w: box, h: box, t: max(1, sheet.px(2)))
            glyphs.draw(word.display, on: &canvas, x: x + box + sheet.px(7), cy: cy)
        }
        return canvas
    }
}
