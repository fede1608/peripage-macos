// Sudoku generator: Simon Tatham's Solo (`solo.c`, MIT licence). A random solved grid is built, clues are
// removed in 180°-symmetric pairs in random order while the human-technique solver can still solve the
// puzzle at the target level, and the result is kept only if it actually needs that level.

import Foundation
import PeriPageKit

struct SudokuPuzzle: Sendable {
    let n: Int
    let boxWidth: Int
    let boxHeight: Int
    let clues: [Int]
    let solution: [Int]
    /// Hardest technique level the solver needed (see `DigitGridSolver.sudokuSteps`).
    let grade: Int
}

enum SudokuGenerator {
    static func targetLevel(_ size: SudokuSize, _ difficulty: PuzzleDifficulty) -> Int {
        switch size {
        case .classic: [1, 2, 3, 4][difficulty.level]
        case .mini: [0, 1, 2, 2][difficulty.level]
        }
    }

    private static func clueCount(_ g: [Int]) -> Int { g.reduce(0) { $0 + ($1 != 0 ? 1 : 0) } }

    static func generate(size: SudokuSize, difficulty: PuzzleDifficulty, seed: UInt64) -> SudokuPuzzle {
        let (n, bw, bh) = size == .classic ? (9, 3, 3) : (6, 3, 2)
        let geo = GridGeometry(n: n, boxWidth: bw, boxHeight: bh)
        let solver = DigitGridSolver(geometry: geo, steps: DigitGridSolver.sudokuSteps)
        let target = targetLevel(size, difficulty)
        var rng = PuzzleRNG(seed: seed, salt: 0x5D0C &+ UInt64(difficulty.level) << 8 &+ (size == .mini ? 1 : 0))
        var best: SudokuPuzzle?

        // Solo loops until the grade matches; a bounded number of attempts keeps the preview responsive
        // and falls back to the hardest puzzle found (still unique) for the rare unlucky seed.
        for _ in 0..<250 {
            let solution = randomFilledGrid(geo, rng: &rng)
            var grid = solution
            // 180° rotational symmetry (Solo's default); the hardest 6×6 needs free removal to ever require
            // more than singles (Tatham's own presets stop at "2x3 Basic").
            let symmetric = size == .classic || target < 2
            func mate(_ i: Int) -> Int { symmetric ? geo.count - 1 - i : i }
            var locs = (0..<geo.count).filter { $0 <= mate($0) }
            rng.shuffle(&locs)
            for i in locs {
                var trial = grid
                trial[i] = 0
                trial[mate(i)] = 0
                if case .solved = solver.solve(trial, maxLevel: target) { grid = trial }
            }
            guard case .solved(let grade) = solver.solve(grid, maxLevel: target) else { continue }
            let puzzle = SudokuPuzzle(n: n, boxWidth: bw, boxHeight: bh, clues: grid, solution: solution, grade: grade)
            if grade == target { return puzzle }
            if let b = best, grade < b.grade || (grade == b.grade && clueCount(grid) >= clueCount(b.clues)) { continue }
            best = puzzle
        }
        return best!
    }
}

enum SudokuSheet {
    static func render(_ doc: PuzzleDoc, _ p: SudokuPuzzle, width: Int, solution: Bool) -> MonoBitmap {
        var sheet = SheetBuilder(width: width)
        let diff = doc.effectiveDifficulty
        let sizeLabel = "\(p.n)×\(p.n)"
        if solution {
            sheet.header(title: "Solución", tag: "Sudoku \(sizeLabel)")
        } else {
            let levels = p.n == 9 ? 4 : 3
            sheet.header(title: "Sudoku", tag: diff.label(for: .sudoku), level: min(diff.level, levels - 1), levels: levels)
            sheet.text("Completá la grilla: cada fila, cada columna y cada caja de \(p.boxWidth)×\(p.boxHeight) llevan los números del 1 al \(p.n), sin repetir.")
        }
        sheet.add(grid(p, sheet: sheet, solution: solution), gap: 14)
        sheet.footer(left: "Sudoku \(sizeLabel) · \(diff.label(for: .sudoku))", right: "#\(doc.seed)")
        return sheet.build()
    }

    private static func grid(_ p: SudokuPuzzle, sheet: SheetBuilder, solution: Bool) -> Canvas {
        let n = p.n
        let thick = max(3, sheet.px(3)), thin = max(1, sheet.px(1))
        func isThickV(_ i: Int) -> Bool { i % p.boxWidth == 0 }
        func isThickH(_ i: Int) -> Bool { i % p.boxHeight == 0 }
        let vLines = (0...n).reduce(0) { $0 + (isThickV($1) ? thick : thin) }
        let hLines = (0...n).reduce(0) { $0 + (isThickH($1) ? thick : thin) }
        let maxCell = n == 9 ? 46 : 52
        let cell = min(sheet.px(CGFloat(maxCell)), (sheet.innerWidth - max(vLines, hLines)) / n)
        // Offsets of each cell's left/top edge.
        var xs: [Int] = [], ys: [Int] = []
        var x = 0, y = 0
        for i in 0..<n {
            x += isThickV(i) ? thick : thin
            xs.append(x)
            x += cell
            y += isThickH(i) ? thick : thin
            ys.append(y)
            y += cell
        }
        let w = x + thick, h = y + thick
        var canvas = Canvas(width: w, height: h)
        // Lines: thin first, thick on top.
        var pos = 0
        for i in 0...n {
            let t = isThickV(i) ? thick : thin
            canvas.fill(x: pos, y: 0, w: t, h: h)
            pos += t + cell
        }
        pos = 0
        for i in 0...n {
            let t = isThickH(i) ? thick : thin
            canvas.fill(x: 0, y: pos, w: w, h: t)
            pos += t + cell
        }
        let given = GlyphSet(PuzzleFont.demi(CGFloat(cell) * 0.64))
        let filled = GlyphSet(PuzzleFont.named("AvenirNext-Regular", CGFloat(cell) * 0.58, fallback: .regular))
        for r in 0..<n {
            for c in 0..<n {
                let i = r * n + c
                let cx = Double(xs[c]) + Double(cell) / 2, cy = Double(ys[r]) + Double(cell) / 2
                if p.clues[i] != 0 {
                    given.draw(String(p.clues[i]), on: &canvas, cx: cx, cy: cy)
                } else if solution {
                    filled.draw(String(p.solution[i]), on: &canvas, cx: cx, cy: cy)
                }
            }
        }
        return canvas
    }
}
