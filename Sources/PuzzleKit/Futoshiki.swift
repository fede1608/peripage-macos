// Futoshiki after Simon Tatham's "Unequal" (`unequal.c` + `latin.c`, MIT licence): starting from a random
// Latin square, clues (numbers and "greater than" signs) are added — always the one on the cell with the
// most remaining candidates — until the graded solver can finish the grid; then every clue that is not
// needed is stripped (numbers first), and the puzzle is rejected if a lower level would already solve it.

import Foundation
import PeriPageKit

struct FutoshikiLink: Sendable, Hashable {
    let greater: Int
    let lesser: Int
}

struct FutoshikiPuzzle: Sendable {
    let n: Int
    let clues: [Int]
    let links: [FutoshikiLink]
    let solution: [Int]
    let grade: Int
}

enum FutoshikiGenerator {
    /// Unequal's levels: 0 trivial, 1 easy, 2 tricky (set), 3 extreme.
    static func targetLevel(_ d: PuzzleDifficulty) -> Int { [1, 2, 3, 3][d.level] }

    /// Unequal's direction order: up, right, down, left.
    private static let directions = [(0, -1), (1, 0), (0, 1), (-1, 0)]

    static func generate(size n: Int, difficulty: PuzzleDifficulty, seed: UInt64) -> FutoshikiPuzzle {
        let geo = GridGeometry(n: n)
        let solver = DigitGridSolver(geometry: geo, steps: DigitGridSolver.futoshikiSteps)
        let o2 = n * n
        var target = targetLevel(difficulty)
        var rng = PuzzleRNG(seed: seed, salt: 0xF070 &+ UInt64(difficulty.level) << 8 &+ UInt64(n))

        // Clue codes: loc * 5 + which (0...3 a sign pointing from loc to a neighbor, 4 the number).
        // Numbers come first so they are stripped first; each group is shuffled separately.
        var codes = (0..<(5 * o2)).map { ($0 % o2) * 5 + 4 - $0 / o2 }

        var tries = 0
        while true {
            tries += 1
            let latin = randomFilledGrid(geo, rng: &rng)
            var head = Array(codes[0..<o2]), tail = Array(codes[o2...])
            rng.shuffle(&head)
            rng.shuffle(&tail)
            codes = head + tail

            var nums = [Int](repeating: 0, count: o2)
            var flags = [UInt8](repeating: 0, count: o2)

            func neighbor(_ loc: Int, _ which: Int) -> Int? {
                let x = loc % n + directions[which].0, y = loc / n + directions[which].1
                return x >= 0 && y >= 0 && x < n && y < n ? y * n + x : nil
            }
            func links() -> [(Int, Int)] {
                var out: [(Int, Int)] = []
                for loc in 0..<o2 where flags[loc] != 0 {
                    for w in 0..<4 where flags[loc] & (1 << UInt8(w)) != 0 { out.append((loc, neighbor(loc, w)!)) }
                }
                return out
            }
            func solve(_ level: Int) -> DigitGridSolver.Outcome {
                solver.links = links()
                return solver.solve(nums, maxLevel: level)
            }
            func canPlace(_ code: Int, known: [Int]) -> Bool {
                let loc = code / 5, which = code % 5
                if which == 4 { return known[loc] == 0 }
                guard flags[loc] & (1 << UInt8(which)) == 0, let nb = neighbor(loc, which) else { return false }
                return latin[loc] > latin[nb]
            }
            func place(_ code: Int) {
                let loc = code / 5, which = code % 5
                if which == 4 { nums[loc] = latin[loc] } else { flags[loc] |= 1 << UInt8(which) }
            }

            // game_assemble: add the clue on the least constrained cell until solvable.
            while true {
                if case .solved = solve(target) { break }
                let known = solver.values, cand = solver.candidates
                var best = -1, maxPoss = 0, minClues = 5
                for i in stride(from: codes.count - 1, through: 0, by: -1) where canPlace(codes[i], known: known) {
                    let loc = codes[i] / 5
                    let poss = cand[loc].nonzeroBitCount
                    let clues = flags[loc].nonzeroBitCount
                    if poss > maxPoss || (poss == maxPoss && clues < minClues) {
                        best = i
                        maxPoss = poss
                        minClues = clues
                    }
                }
                guard best >= 0 else { break }
                place(codes[best])
            }
            // game_strip: drop every clue the solver can do without.
            for code in codes {
                let loc = code / 5, which = code % 5
                if which == 4 {
                    guard nums[loc] != 0 else { continue }
                    nums[loc] = 0
                    if case .solved = solve(target) { continue }
                    nums[loc] = latin[loc]
                } else {
                    let bit = UInt8(1) << UInt8(which)
                    guard flags[loc] & bit != 0 else { continue }
                    flags[loc] &= ~bit
                    if case .solved = solve(target) { continue }
                    flags[loc] |= bit
                }
            }
            guard case .solved(let grade) = solve(target) else { continue }
            // Too easy? Try again (Unequal gives up after 50 tries and lowers the level).
            if target > 0, case .solved = solve(target - 1) {
                if tries < 50 { continue }
                target -= 1
            }
            let finalLinks = links().map { FutoshikiLink(greater: $0.0, lesser: $0.1) }
            return FutoshikiPuzzle(n: n, clues: nums, links: finalLinks, solution: latin, grade: grade)
        }
    }
}

enum FutoshikiSheet {
    static func render(_ doc: PuzzleDoc, _ p: FutoshikiPuzzle, width: Int, solution: Bool) -> MonoBitmap {
        var sheet = SheetBuilder(width: width)
        let diff = doc.effectiveDifficulty
        let sizeLabel = "\(p.n)×\(p.n)"
        if solution {
            sheet.header(title: "Solución", tag: "Futoshiki \(sizeLabel)")
        } else {
            sheet.header(title: "Futoshiki", tag: diff.label(for: .futoshiki), level: diff.level, levels: 3)
            sheet.text("Completá con los números del 1 al \(p.n) sin repetir en ninguna fila ni columna, respetando los signos: la punta señala al número menor.")
        }
        sheet.add(grid(p, sheet: sheet, solution: solution), gap: 14)
        sheet.footer(left: "Futoshiki \(sizeLabel) · \(diff.label(for: .futoshiki))", right: "#\(doc.seed)")
        return sheet.build()
    }

    private static func grid(_ p: FutoshikiPuzzle, sheet: SheetBuilder, solution: Bool) -> Canvas {
        let n = p.n
        let unit = Double(sheet.innerWidth) / (Double(n) + Double(n - 1) * 0.55)
        let cell = min(sheet.px(50), Int(unit))
        let gap = min(Int(Double(cell) * 0.55), (sheet.innerWidth - n * cell) / max(1, n - 1))
        let total = n * cell + (n - 1) * gap
        var canvas = Canvas(width: total, height: total)
        let border = max(2, sheet.px(3))
        func origin(_ i: Int) -> Int { i * (cell + gap) }
        for r in 0..<n {
            for c in 0..<n {
                canvas.strokeRect(x: origin(c), y: origin(r), w: cell, h: cell, t: border)
            }
        }
        let given = GlyphSet(PuzzleFont.demi(CGFloat(cell) * 0.6))
        let filled = GlyphSet(PuzzleFont.named("AvenirNext-Regular", CGFloat(cell) * 0.56, fallback: .regular))
        for i in 0..<(n * n) {
            let cx = Double(origin(i % n)) + Double(cell) / 2, cy = Double(origin(i / n)) + Double(cell) / 2
            if p.clues[i] != 0 {
                given.draw(String(p.clues[i]), on: &canvas, cx: cx, cy: cy)
            } else if solution {
                filled.draw(String(p.solution[i]), on: &canvas, cx: cx, cy: cy)
            }
        }
        // Signs: a chevron in the gap whose point faces the smaller cell.
        let s = Double(gap) * 0.34
        let stroke = max(2.5, Double(sheet.px(3)))
        for link in p.links {
            let (g, l) = (link.greater, link.lesser)
            let gx = g % n, gy = g / n, lx = l % n, ly = l / n
            let dx = Double(lx - gx), dy = Double(ly - gy)
            // Center of the gap between the two cells.
            let mx = (Double(origin(gx)) + Double(origin(lx))) / 2 + Double(cell) / 2
            let my = (Double(origin(gy)) + Double(origin(ly))) / 2 + Double(cell) / 2
            let tip = (mx + dx * s * 0.6, my + dy * s * 0.6)
            let back1 = (mx - dx * s * 0.6 - dy * s, my - dy * s * 0.6 - dx * s)
            let back2 = (mx - dx * s * 0.6 + dy * s, my - dy * s * 0.6 + dx * s)
            canvas.line(back1.0, back1.1, tip.0, tip.1, width: stroke)
            canvas.line(back2.0, back2.1, tip.0, tip.1, width: stroke)
        }
        return canvas
    }
}
