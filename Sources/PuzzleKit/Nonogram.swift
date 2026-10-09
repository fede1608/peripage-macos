// Nonograms after Simon Tatham's "Pattern" (`pattern.c`, MIT licence): a random field is smoothed once
// with a 3×3 average and thresholded at its median, which yields blobs rather than noise; grids with a
// single-colour row or column are rejected, and the clue set is kept only if a line-by-line solver can
// finish it, which guarantees a unique solution reachable without guessing.

import Foundation
import PeriPageKit

struct NonogramPuzzle: Sendable {
    let cols: Int
    let rows: Int
    /// Solution, row-major (true = filled).
    let cells: [Bool]
    let rowClues: [[Int]]
    let colClues: [[Int]]
}

enum NonogramGenerator {
    static func size(_ d: PuzzleDifficulty) -> (cols: Int, rows: Int) {
        switch d {
        case .easy: (10, 10)
        case .medium: (15, 15)
        // Portrait rather than 20×20: on a 48 mm strip that keeps cells and clues big enough to write in.
        case .hard, .expert: (15, 20)
        }
    }

    static func generate(difficulty: PuzzleDifficulty, seed: UInt64) -> NonogramPuzzle {
        let (w, h) = size(difficulty)
        var rng = PuzzleRNG(seed: seed, salt: 0x9A77 &+ UInt64(difficulty.level) << 8)
        while true {
            let cells = randomPattern(w: w, h: h, rng: &rng)
            guard everyLineMixed(cells, w: w, h: h) else { continue }
            let rowClues = (0..<h).map { r in clues((0..<w).map { cells[r * w + $0] }) }
            let colClues = (0..<w).map { c in clues((0..<h).map { cells[$0 * w + c] }) }
            if NonogramSolver.solve(rowClues: rowClues, colClues: colClues) != nil {
                return NonogramPuzzle(cols: w, rows: h, cells: cells, rowClues: rowClues, colClues: colClues)
            }
        }
    }

    /// Tatham's `generate`: uniform noise, one 3×3 averaging pass, threshold at the median.
    static func randomPattern(w: Int, h: Int, rng: inout PuzzleRNG) -> [Bool] {
        var field = (0..<(w * h)).map { _ in Float(rng.int(100_000_000)) / 100_000_000 }
        var smoothed = field
        for i in 0..<h {
            for j in 0..<w {
                var sum: Float = 0
                var n = 0
                for p in -1...1 {
                    for q in -1...1 {
                        guard i + p >= 0, i + p < h, j + q >= 0, j + q < w else { continue }
                        if (h == 2 && p != 0) || (w == 2 && q != 0) { continue }
                        n += 1
                        sum += field[(i + p) * w + j + q]
                    }
                }
                smoothed[i * w + j] = sum / Float(n)
            }
        }
        field = smoothed
        let sorted = field.sorted()
        var index = w * h / 2
        if w & h & 1 != 0 { index += rng.int(2) }
        let threshold = index < w * h ? sorted[index] : sorted[w * h - 1] + 1
        return field.map { $0 >= threshold }
    }

    private static func everyLineMixed(_ cells: [Bool], w: Int, h: Int) -> Bool {
        if w > 2 {
            for r in 0..<h {
                let row = cells[(r * w)..<(r * w + w)]
                if !row.contains(true) || !row.contains(false) { return false }
            }
        }
        if h > 2 {
            for c in 0..<w {
                let col = (0..<h).map { cells[$0 * w + c] }
                if !col.contains(true) || !col.contains(false) { return false }
            }
        }
        return true
    }

    static func clues(_ line: [Bool]) -> [Int] {
        var out: [Int] = []
        var run = 0
        for v in line {
            if v { run += 1 } else if run > 0 { out.append(run); run = 0 }
        }
        if run > 0 { out.append(run) }
        return out
    }
}

/// Line-by-line nonogram solver: for every row/column, a DP over all placements of its runs that agree with
/// the cells known so far marks cells that are filled (or empty) in every placement.
enum NonogramSolver {
    /// Cell states: -1 unknown, 0 empty, 1 filled.
    static func solve(rowClues: [[Int]], colClues: [[Int]]) -> [Bool]? {
        let h = rowClues.count, w = colClues.count
        var grid = [Int8](repeating: -1, count: w * h)
        var dirtyRows = [Bool](repeating: true, count: h)
        var dirtyCols = [Bool](repeating: true, count: w)
        var progress = true
        while progress {
            progress = false
            for r in 0..<h where dirtyRows[r] {
                dirtyRows[r] = false
                var line = Array(grid[(r * w)..<(r * w + w)])
                guard let changed = solveLine(rowClues[r], &line) else { return nil }
                for c in changed {
                    grid[r * w + c] = line[c]
                    dirtyCols[c] = true
                    progress = true
                }
            }
            for c in 0..<w where dirtyCols[c] {
                dirtyCols[c] = false
                var line = (0..<h).map { grid[$0 * w + c] }
                guard let changed = solveLine(colClues[c], &line) else { return nil }
                for r in changed {
                    grid[r * w + c] = line[r]
                    dirtyRows[r] = true
                    progress = true
                }
            }
        }
        guard !grid.contains(-1) else { return nil }
        return grid.map { $0 == 1 }
    }

    /// Settles every cell of `line` that has the same value in all placements consistent with it.
    /// Returns the indices that changed, or nil on a contradiction.
    static func solveLine(_ clues: [Int], _ line: inout [Int8]) -> [Int]? {
        let n = line.count, k = clues.count
        // blocked[i]: cells before i that cannot be filled.
        var blocked = [Int](repeating: 0, count: n + 1)
        for i in 0..<n { blocked[i + 1] = blocked[i] + (line[i] == 0 ? 1 : 0) }
        func canFill(_ a: Int, _ len: Int) -> Bool { a + len <= n && blocked[a + len] - blocked[a] == 0 }
        func canEmpty(_ i: Int) -> Bool { line[i] != 1 }

        // f[i][j]: cells i..<n can hold runs j..<k, with cell i free to start a run.
        let sw = k + 1
        var f = [Bool](repeating: false, count: (n + 1) * sw)
        f[n * sw + k] = true
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in 0...k {
                var ok = canEmpty(i) && f[(i + 1) * sw + j]
                if !ok && j < k && canFill(i, clues[j]) {
                    let end = i + clues[j]
                    ok = end == n ? j + 1 == k : canEmpty(end) && f[(end + 1) * sw + j + 1]
                }
                f[i * sw + j] = ok
            }
        }
        guard f[0] else { return nil }

        var canBeFilled = [Bool](repeating: false, count: n)
        var canBeEmpty = [Bool](repeating: false, count: n)
        var reach = [Bool](repeating: false, count: (n + 1) * sw)
        reach[0] = true
        for i in 0..<n {
            for j in 0...k where reach[i * sw + j] {
                if canEmpty(i) && f[(i + 1) * sw + j] {
                    canBeEmpty[i] = true
                    reach[(i + 1) * sw + j] = true
                }
                if j < k && canFill(i, clues[j]) {
                    let end = i + clues[j]
                    let ok = end == n ? j + 1 == k : canEmpty(end) && f[(end + 1) * sw + j + 1]
                    if ok {
                        for c in i..<end { canBeFilled[c] = true }
                        if end < n {
                            canBeEmpty[end] = true
                            reach[(end + 1) * sw + j + 1] = true
                        } else {
                            reach[n * sw + j + 1] = true
                        }
                    }
                }
            }
        }
        var changed: [Int] = []
        for i in 0..<n {
            if !canBeFilled[i] && !canBeEmpty[i] { return nil }
            guard line[i] == -1 else { continue }
            if canBeFilled[i] && !canBeEmpty[i] { line[i] = 1; changed.append(i) }
            if canBeEmpty[i] && !canBeFilled[i] { line[i] = 0; changed.append(i) }
        }
        return changed
    }
}

enum NonogramSheet {
    static func render(_ doc: PuzzleDoc, _ p: NonogramPuzzle, width: Int, solution: Bool) -> MonoBitmap {
        var sheet = SheetBuilder(width: width)
        let diff = doc.effectiveDifficulty
        let sizeLabel = "\(p.cols)×\(p.rows)"
        if solution {
            sheet.header(title: "Solución", tag: "Nonograma")
        } else {
            sheet.header(title: "Nonograma", tag: diff.label(for: .nonogram), level: diff.level, levels: 3)
            sheet.text("Los números dicen cuántas casillas seguidas hay que pintar en cada fila y columna, en orden y con al menos un espacio entre grupos.")
        }
        sheet.add(grid(p, sheet: sheet, solution: solution), gap: 12)
        sheet.footer(left: "Nonograma \(sizeLabel) · \(diff.label(for: .nonogram))", right: "#\(doc.seed)")
        return sheet.build()
    }

    private static func grid(_ p: NonogramPuzzle, sheet: SheetBuilder, solution: Bool) -> Canvas {
        let thick = max(3, sheet.px(3)), mid = max(2, sheet.px(2)), thin = max(1, sheet.px(1))
        let maxColClues = p.colClues.map(\.count).max() ?? 1
        let maxRowClues = max(1, p.rowClues.map(\.count).max() ?? 1)
        // Row clues sit in fixed-width slots so "3 11 5" never reads as "3115". Shrink the cell until the
        // slots plus the grid fit the width.
        var cell = sheet.px(34)
        var glyphs = GlyphSet(PuzzleFont.bold(CGFloat(cell) * 0.6))
        var slot = 0
        func fit() {
            glyphs = GlyphSet(PuzzleFont.bold(max(12, CGFloat(cell) * 0.6)))
            let widest = (p.rowClues.flatMap { $0 } + [0]).map { glyphs.glyph(String($0)).width }.max() ?? 8
            slot = max(widest + sheet.px(5), cell * 11 / 20)
        }
        fit()
        while cell > 12 && maxRowClues * slot + sheet.px(4) + p.cols * cell + thick > sheet.innerWidth {
            cell -= 1
            fit()
        }
        let clueW = maxRowClues * slot + sheet.px(4)
        let lineH = max(glyphs.capHeight + sheet.px(5), cell * 3 / 4)
        let clueH = maxColClues * lineH + sheet.px(6)
        let gw = p.cols * cell, gh = p.rows * cell
        let x0 = clueW, y0 = clueH
        var canvas = Canvas(width: x0 + gw + thick, height: y0 + gh + thick)

        if solution {
            let inset = 1
            for r in 0..<p.rows {
                for c in 0..<p.cols where p.cells[r * p.cols + c] {
                    canvas.fill(x: x0 + c * cell + inset, y: y0 + r * cell + inset, w: cell - inset, h: cell - inset)
                }
            }
        }
        // Grid lines: every 5th thicker, border thickest.
        for i in 0...p.cols {
            let t = i == 0 || i == p.cols ? thick : (i % 5 == 0 ? mid : thin)
            canvas.fill(x: x0 + i * cell - (t - 1) / 2, y: y0, w: t, h: gh + 1)
        }
        for i in 0...p.rows {
            let t = i == 0 || i == p.rows ? thick : (i % 5 == 0 ? mid : thin)
            canvas.fill(x: x0, y: y0 + i * cell - (t - 1) / 2, w: gw + 1, h: t)
        }
        canvas.fill(x: x0 - (thick - 1) / 2, y: y0 - (thick - 1) / 2, w: gw + thick, h: thick)
        canvas.fill(x: x0 - (thick - 1) / 2, y: y0 - (thick - 1) / 2, w: thick, h: gh + thick)

        // Row clues, right-aligned against the grid, one slot per number.
        for r in 0..<p.rows {
            let items = p.rowClues[r].isEmpty ? [0] : p.rowClues[r]
            let cy = Double(y0 + r * cell) + Double(cell) / 2
            for (k, v) in items.reversed().enumerated() {
                let cx = Double(x0 - sheet.px(4) - k * slot) - Double(slot) / 2
                glyphs.draw(String(v), on: &canvas, cx: cx, cy: cy)
            }
        }
        // Column clues, bottom-aligned above the grid.
        for c in 0..<p.cols {
            let items = p.colClues[c].isEmpty ? [0] : p.colClues[c]
            let cx = Double(x0 + c * cell) + Double(cell) / 2
            for (k, v) in items.reversed().enumerated() {
                let cy = Double(y0 - sheet.px(6)) - Double(k) * Double(lineH) - Double(lineH) / 2
                glyphs.draw(String(v), on: &canvas, cx: cx, cy: cy)
            }
        }
        return canvas
    }
}
