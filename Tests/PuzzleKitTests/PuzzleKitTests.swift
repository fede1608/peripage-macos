import Foundation
import PeriPageKit
import Testing
@testable import PuzzleKit

// MARK: Independent brute-force checkers (no shared code with the generators' solvers)

/// Counts solutions of an n×n grid with optional boxes and "greater than" links, stopping at `limit`.
/// Plain bitmask backtracking (most constrained cell first), independent of the graded solver.
private func countDigitGridSolutions(_ clues: [Int], n: Int, boxWidth: Int?, boxHeight: Int?,
                                     links: [(Int, Int)] = [], limit: Int = 2) -> Int {
    let full = (1 << n) - 1
    var grid = clues
    var rowUsed = [Int](repeating: 0, count: n), colUsed = rowUsed, boxUsed = rowUsed
    let boxOf: [Int] = (0..<(n * n)).map { i in
        guard let bw = boxWidth, let bh = boxHeight else { return 0 }
        return (i / n) / bh * (n / bw) + (i % n) / bw
    }
    let hasBoxes = boxWidth != nil
    var greaterThan = [[Int]](repeating: [], count: n * n)   // cell must exceed these cells
    var lessThan = [[Int]](repeating: [], count: n * n)      // cell must be below these cells
    for (g, l) in links {
        greaterThan[g].append(l)
        lessThan[l].append(g)
    }
    func options(_ i: Int) -> Int {
        var m = full & ~rowUsed[i / n] & ~colUsed[i % n]
        if hasBoxes { m &= ~boxUsed[boxOf[i]] }
        for l in greaterThan[i] where grid[l] != 0 { m &= ~((1 << grid[l]) - 1) }       // > grid[l]
        for g in lessThan[i] where grid[g] != 0 { m &= (1 << (grid[g] - 1)) - 1 }        // < grid[g]
        return m
    }
    func set(_ i: Int, _ d: Int, _ on: Bool) {
        let b = 1 << (d - 1)
        if on { rowUsed[i / n] |= b; colUsed[i % n] |= b; boxUsed[boxOf[i]] |= hasBoxes ? b : 0 } else {
            rowUsed[i / n] &= ~b; colUsed[i % n] &= ~b
            if hasBoxes { boxUsed[boxOf[i]] &= ~b }
        }
    }
    // Clues must be consistent among themselves.
    for i in 0..<(n * n) where clues[i] != 0 {
        let d = clues[i]
        grid[i] = 0
        guard options(i) & (1 << (d - 1)) != 0 else { return 0 }
        grid[i] = d
        set(i, d, true)
    }
    // Units for "each digit once" branching (Knuth's heuristic: branch on the most constrained cell or on
    // the most constrained digit-in-unit, whichever has fewer choices).
    var units: [[Int]] = (0..<n).map { r in (0..<n).map { r * n + $0 } } + (0..<n).map { c in (0..<n).map { $0 * n + c } }
    if hasBoxes { units += (0..<n).map { b in (0..<(n * n)).filter { boxOf[$0] == b } } }
    var count = 0
    func search() {
        guard count < limit else { return }
        var opts = [Int](repeating: 0, count: n * n)
        var bestChoices: [(Int, Int)] = []      // (cell, digit) alternatives
        var bestCount = Int.max
        var empty = false
        for i in 0..<(n * n) {
            if grid[i] == 0 { empty = true; opts[i] = options(i) } else { opts[i] = 1 << (grid[i] - 1) }
        }
        // Bounds along the links until stable: greater > min(lesser), lesser < max(greater).
        var changed = !links.isEmpty
        while changed {
            changed = false
            for (g, l) in links {
                guard opts[g] != 0, opts[l] != 0 else { return }
                let lmin = opts[l].trailingZeroBitCount + 1
                let gmax = Int.bitWidth - opts[g].leadingZeroBitCount
                let newG = opts[g] & ~((1 << lmin) - 1), newL = opts[l] & ((1 << (gmax - 1)) - 1)
                if newG != opts[g] || newL != opts[l] { opts[g] = newG; opts[l] = newL; changed = true }
            }
        }
        for i in 0..<(n * n) where grid[i] == 0 {
            let m = opts[i]
            let c = m.nonzeroBitCount
            if c == 0 { return }
            if c < bestCount {
                bestCount = c
                bestChoices = (1...n).filter { m & (1 << ($0 - 1)) != 0 }.map { (i, $0) }
            }
        }
        for i in 0..<(n * n) where grid[i] != 0 && opts[i] == 0 { return }
        if !empty { count += 1; return }
        for unit in units where bestCount > 1 {
            var used = 0
            for i in unit where grid[i] != 0 { used |= 1 << (grid[i] - 1) }
            for d in 1...n where used & (1 << (d - 1)) == 0 {
                let places = unit.filter { grid[$0] == 0 && opts[$0] & (1 << (d - 1)) != 0 }
                if places.isEmpty { return }
                if places.count < bestCount {
                    bestCount = places.count
                    bestChoices = places.map { ($0, d) }
                }
            }
        }
        for (cell, d) in bestChoices {
            grid[cell] = d
            set(cell, d, true)
            search()
            set(cell, d, false)
            grid[cell] = 0
        }
    }
    search()
    return count
}

private func isLatin(_ g: [Int], n: Int) -> Bool {
    for k in 0..<n {
        if Set((0..<n).map { g[k * n + $0] }) != Set(1...n) { return false }
        if Set((0..<n).map { g[$0 * n + k] }) != Set(1...n) { return false }
    }
    return true
}

// MARK: Sudoku

@Suite struct SudokuTests {
    @Test(arguments: PuzzleDifficulty.allCases)
    func classicIsValidUniqueAndGraded(_ difficulty: PuzzleDifficulty) {
        for seed in [11, 222, 3333] as [UInt64] {
            let p = SudokuGenerator.generate(size: .classic, difficulty: difficulty, seed: seed)
            #expect(p.n == 9)
            #expect(isLatin(p.solution, n: 9))
            for b in 0..<9 {
                let cells = (0..<81).filter { ($0 / 9) / 3 * 3 + ($0 % 9) / 3 == b }
                #expect(Set(cells.map { p.solution[$0] }) == Set(1...9))
            }
            for i in 0..<81 where p.clues[i] != 0 { #expect(p.clues[i] == p.solution[i]) }
            #expect(countDigitGridSolutions(p.clues, n: 9, boxWidth: 3, boxHeight: 3) == 1)
            #expect(p.grade == SudokuGenerator.targetLevel(.classic, difficulty))
            // 180° symmetric clue pattern, as in Solo.
            for i in 0..<81 { #expect((p.clues[i] == 0) == (p.clues[80 - i] == 0)) }
        }
    }

    @Test(arguments: [PuzzleDifficulty.easy, .medium, .hard])
    func miniIsValidAndUnique(_ difficulty: PuzzleDifficulty) {
        let p = SudokuGenerator.generate(size: .mini, difficulty: difficulty, seed: 77)
        #expect(p.n == 6 && p.boxWidth == 3 && p.boxHeight == 2)
        #expect(isLatin(p.solution, n: 6))
        for i in 0..<36 where p.clues[i] != 0 { #expect(p.clues[i] == p.solution[i]) }
        #expect(countDigitGridSolutions(p.clues, n: 6, boxWidth: 3, boxHeight: 2) == 1)
    }

    @Test func easierLevelsCannotSolveHarderPuzzles() {
        let geo = GridGeometry(n: 9, boxWidth: 3, boxHeight: 3)
        let solver = DigitGridSolver(geometry: geo, steps: DigitGridSolver.sudokuSteps)
        for difficulty in [PuzzleDifficulty.medium, .hard, .expert] {
            let p = SudokuGenerator.generate(size: .classic, difficulty: difficulty, seed: 5)
            let target = SudokuGenerator.targetLevel(.classic, difficulty)
            #expect(solver.solve(p.clues, maxLevel: target) == .solved(level: target))
            #expect(solver.solve(p.clues, maxLevel: target - 1) == .stuck)
        }
    }
}

// MARK: Word search

@Suite struct WordSearchTests {
    private func check(_ p: WordSearchPuzzle, directions: [(Int, Int)]) {
        for w in p.words {
            for (k, (r, c)) in w.cells.enumerated() {
                #expect(r >= 0 && r < p.rows && c >= 0 && c < p.cols)
                #expect(p.grid[r * p.cols + c] == w.codes[k])
            }
            #expect(directions.contains { $0 == (w.dr, w.dc) })
            #expect(WordSearchGenerator.occurrences(of: w.codes, in: p.grid, rows: p.rows, cols: p.cols) == 1)
        }
        #expect(p.grid.allSatisfy { $0 < 27 })
    }

    @Test(arguments: [PuzzleDifficulty.easy, .medium, .hard])
    func everyWordIsPlacedExactlyOnce(_ difficulty: PuzzleDifficulty) {
        let cfg = WordSearchGenerator.config(difficulty)
        for theme in WordTheme.allCases where theme != .custom {
            let p = WordSearchGenerator.generate(theme: theme, customWords: "", difficulty: difficulty, seed: 4242)
            #expect(p.words.count == cfg.wordCount, "\(theme)")
            #expect(p.rows == cfg.size && p.cols == cfg.size)
            check(p, directions: cfg.directions)
            // Listed words come from the theme.
            let themeWords = Set(theme.words.map { $0.uppercased() })
            #expect(p.words.allSatisfy { themeWords.contains($0.display) })
        }
    }

    @Test func themesHaveEnoughWords() {
        for theme in WordTheme.allCases where theme != .custom {
            let normalized = Set(theme.words.map(WordNormalizer.normalize))
            #expect(normalized.count >= 25, "\(theme)")
            #expect(normalized.allSatisfy { $0.allSatisfy { Alphabet.code($0) != nil } }, "\(theme)")
        }
    }

    @Test func customWordsKeepÑAndDropAccents() {
        let p = WordSearchGenerator.generate(theme: .custom, customWords: "Ñandú, pingüino, árbol, dulce de leche, mate",
                                             difficulty: .hard, seed: 9)
        #expect(Set(p.words.map(\.display)) == ["ÑANDÚ", "PINGÜINO", "ÁRBOL", "DULCE DE LECHE", "MATE"])
        let nandu = p.words.first { $0.display == "ÑANDÚ" }!
        #expect(nandu.codes == Alphabet.codes("ÑANDU"))
        #expect(p.words.first { $0.display == "DULCE DE LECHE" }!.codes.count == 12)
        #expect(p.cols >= 12)
        check(p, directions: WordSearchGenerator.allDirections)
        #expect(WordNormalizer.normalize("Pingüino Ñoño Ácido") == "PINGUINOÑOÑOACIDO")
    }
}

// MARK: Mazes

@Suite struct MazeTests {
    private func checkPerfect(_ p: MazePuzzle) {
        let edges = p.links.reduce(0) { $0 + $1.count } / 2
        #expect(edges == p.cellCount - 1)
        let dist = MazeGenerator.distances(from: 0, links: p.links)
        #expect(dist.allSatisfy { $0 >= 0 })
        for (a, list) in p.links.enumerated() {
            for b in list { #expect(p.links[b].contains(a)) }
        }
        #expect(p.path.first == p.entrance)
        #expect(p.path.last == p.exit)
        #expect(Set(p.path).count == p.path.count)
        for (a, b) in zip(p.path, p.path.dropFirst()) { #expect(p.linked(a, b)) }
    }

    @Test(arguments: MazeStyle.allCases)
    func rectangularIsPerfectAndSolved(_ style: MazeStyle) {
        for difficulty in PuzzleDifficulty.allCases {
            let p = MazeGenerator.generate(shape: .rectangular, style: style, difficulty: difficulty, seed: 31)
            guard case .rect(let cols, let rows) = p.layout else { Issue.record("layout"); return }
            #expect(cols == MazeGenerator.rectColumns(difficulty))
            #expect(p.entrance < cols)
            #expect(p.exit >= (rows - 1) * cols)
            // Passages only between grid neighbors.
            for (a, list) in p.links.enumerated() {
                for b in list { #expect(abs(a - b) == 1 && a / cols == b / cols || abs(a - b) == cols) }
            }
            checkPerfect(p)
        }
    }

    @Test(arguments: MazeStyle.allCases)
    func circularIsPerfectAndReachesCenter(_ style: MazeStyle) {
        for difficulty in PuzzleDifficulty.allCases {
            let p = MazeGenerator.generate(shape: .circular, style: style, difficulty: difficulty, seed: 31)
            guard case .polar(let counts) = p.layout else { Issue.record("layout"); return }
            #expect(counts.count == MazeGenerator.polarRings(difficulty))
            #expect(counts[0] == 1)
            for i in 1..<counts.count { #expect(counts[i] % counts[i - 1] == 0) }
            #expect(p.exit == 0)
            #expect(p.entrance >= p.cellCount - counts.last!)
            checkPerfect(p)
        }
    }
}

// MARK: Nonograms

@Suite struct NonogramTests {
    @Test(arguments: [PuzzleDifficulty.easy, .medium, .hard])
    func cluesMatchAndLineSolverFindsTheUniqueSolution(_ difficulty: PuzzleDifficulty) {
        for seed in [1, 2, 3] as [UInt64] {
            let p = NonogramGenerator.generate(difficulty: difficulty, seed: seed)
            let size = NonogramGenerator.size(difficulty)
            #expect(p.cols == size.cols && p.rows == size.rows)
            for r in 0..<p.rows {
                #expect(p.rowClues[r] == NonogramGenerator.clues((0..<p.cols).map { p.cells[r * p.cols + $0] }))
            }
            for c in 0..<p.cols {
                #expect(p.colClues[c] == NonogramGenerator.clues((0..<p.rows).map { p.cells[$0 * p.cols + c] }))
            }
            // The line solver only makes forced deductions, so finishing means the solution is unique.
            #expect(NonogramSolver.solve(rowClues: p.rowClues, colClues: p.colClues) == p.cells)
        }
    }

    @Test func lineSolverDeducesOverlaps() {
        var line = [Int8](repeating: -1, count: 10)
        let changed = NonogramSolver.solveLine([7], &line)
        #expect(changed == [3, 4, 5, 6])
        var ambiguous: [Int8] = [-1, -1, -1, -1]
        #expect(NonogramSolver.solveLine([1], &ambiguous) == [])
        var bad: [Int8] = [1, 1, 1, -1]
        #expect(NonogramSolver.solveLine([2], &bad) == nil)
    }

    @Test func ambiguousCluesAreRejected() {
        // Two diagonal cells: two solutions, the line solver cannot finish.
        #expect(NonogramSolver.solve(rowClues: [[1], [1]], colClues: [[1], [1]]) == nil)
    }
}

// MARK: Futoshiki

@Suite struct FutoshikiTests {
    @Test(arguments: [4, 5, 6, 7])
    func validAndUnique(_ n: Int) {
        for difficulty in [PuzzleDifficulty.easy, .medium, .hard] {
            let p = FutoshikiGenerator.generate(size: n, difficulty: difficulty, seed: 99)
            #expect(isLatin(p.solution, n: n))
            for i in 0..<(n * n) where p.clues[i] != 0 { #expect(p.clues[i] == p.solution[i]) }
            for link in p.links {
                #expect(p.solution[link.greater] > p.solution[link.lesser])
                let dx = abs(link.greater % n - link.lesser % n), dy = abs(link.greater / n - link.lesser / n)
                #expect(dx + dy == 1)
            }
            let links = p.links.map { ($0.greater, $0.lesser) }
            #expect(countDigitGridSolutions(p.clues, n: n, boxWidth: nil, boxHeight: nil, links: links) == 1)
        }
    }

    @Test func gradedLikeUnequal() {
        let geo = GridGeometry(n: 6)
        let solver = DigitGridSolver(geometry: geo, steps: DigitGridSolver.futoshikiSteps)
        for difficulty in [PuzzleDifficulty.easy, .medium, .hard] {
            let p = FutoshikiGenerator.generate(size: 6, difficulty: difficulty, seed: 3)
            let target = FutoshikiGenerator.targetLevel(difficulty)
            solver.links = p.links.map { ($0.greater, $0.lesser) }
            #expect(p.grade == target)
            #expect(solver.solve(p.clues, maxLevel: target) == .solved(level: target))
            #expect(solver.solve(p.clues, maxLevel: target - 1) != .solved(level: target - 1))
        }
    }
}

// MARK: Bridges

@Suite struct BridgesTests {
    /// Exhaustive count of bridge assignments satisfying counts, crossings and connectivity (up to `limit`).
    private func countSolutions(_ p: BridgesPuzzle, limit: Int = 2) -> Int {
        let graph = BridgeGraph(w: p.w, h: p.h, islands: p.islands)
        var values = [Int](repeating: 0, count: graph.edges.count)
        var remaining = graph.islands.map(\.count)
        var count = 0
        func connected() -> Bool {
            var seen = Set([0]), stack = [0]
            while let i = stack.popLast() {
                for e in graph.incident[i] where values[e] > 0 {
                    let j = graph.edges[e].a == i ? graph.edges[e].b : graph.edges[e].a
                    if seen.insert(j).inserted { stack.append(j) }
                }
            }
            return seen.count == graph.islands.count
        }
        func search(_ e: Int) {
            guard count < limit else { return }
            if e == graph.edges.count {
                if remaining.allSatisfy({ $0 == 0 }) && connected() { count += 1 }
                return
            }
            let (a, b) = graph.edges[e]
            for v in 0...min(2, remaining[a], remaining[b]) {
                if v > 0 && graph.crossing[e].contains(where: { $0 < e && values[$0] > 0 }) { break }
                values[e] = v
                remaining[a] -= v
                remaining[b] -= v
                // Prune: an island whose last edge is decided must be complete.
                let done = [a, b].allSatisfy { i in graph.incident[i].allSatisfy { $0 <= e } ? remaining[i] == 0 : true }
                if done { search(e + 1) }
                remaining[a] += v
                remaining[b] += v
                values[e] = 0
            }
        }
        search(0)
        return count
    }

    @Test(arguments: [PuzzleDifficulty.easy, .medium, .hard])
    func solutionIsValidAndUnique(_ difficulty: PuzzleDifficulty) {
        for seed in [7, 8] as [UInt64] {
            let p = BridgesGenerator.generate(difficulty: difficulty, seed: seed)
            #expect(p.grade == min(2, difficulty.level))
            for (i, isl) in p.islands.enumerated() {
                let total = p.edges.filter { $0.a == i || $0.b == i }.reduce(0) { $0 + $1.bridges }
                #expect(total == isl.count)
                #expect(isl.count >= 1 && isl.count <= 8)
            }
            #expect(countSolutions(p) == 1)
            let solver = BridgesSolver(graph: BridgeGraph(w: p.w, h: p.h, islands: p.islands))
            #expect(solver.solve(level: p.grade) == .solved)
            #expect(solver.lo == p.edges.map(\.bridges))
        }
    }
}

// MARK: Rendering, determinism, documents

@Suite struct RenderingTests {
    private static var allDocs: [PuzzleDoc] {
        var docs: [PuzzleDoc] = []
        for kind in PuzzleKind.allCases {
            for difficulty in kind.difficulties {
                var doc = PuzzleDoc(kind: kind, difficulty: difficulty, seed: 123_456)
                docs.append(doc)
                switch kind {
                case .sudoku:
                    doc.sudokuSize = .mini
                    docs.append(doc)
                case .maze:
                    doc.mazeShape = .circular
                    docs.append(doc)
                case .wordSearch:
                    doc.wordTheme = .custom
                    doc.customWords = "uno, dos, tres, cuatro"
                    docs.append(doc)
                default:
                    break
                }
            }
        }
        return docs
    }

    @Test func everyKindRendersAt384() {
        for doc in Self.allDocs {
            let sheet = PuzzleRenderer.render(doc, widthDots: 384)
            #expect(sheet.width == 384)
            #expect(sheet.height > 200 && sheet.height < 1400, "\(doc.kind) \(doc.difficulty): \(sheet.height)")
            #expect(sheet.blackDotCount > 1000)
            let solution = PuzzleRenderer.renderSolution(doc, widthDots: 384)
            #expect((solution == nil) == doc.kind.isPaperGame)
            if let solution { #expect(solution.width == 384) }
        }
    }

    @Test func otherWidthsWork() {
        for kind in PuzzleKind.allCases {
            let doc = PuzzleDoc(kind: kind, difficulty: .medium, seed: 5)
            #expect(PuzzleRenderer.render(doc, widthDots: 576).width == 576)
        }
    }

    @Test func sameDocGivesSameBytes() {
        for doc in Self.allDocs {
            let a = PuzzleRenderer.render(doc, widthDots: 384)
            PuzzleCache.shared.removeAll()
            let b = PuzzleRenderer.render(doc, widthDots: 384)
            #expect(a == b, "\(doc.kind) \(doc.difficulty)")
            #expect(PuzzleRenderer.renderSolution(doc, widthDots: 384) == PuzzleRenderer.renderSolution(doc, widthDots: 384))
        }
    }

    @Test func seedsChangeThePuzzle() {
        for kind in PuzzleKind.allCases where kind.usesSeed {
            let a = PuzzleRenderer.render(PuzzleDoc(kind: kind, seed: 1), widthDots: 384)
            let b = PuzzleRenderer.render(PuzzleDoc(kind: kind, seed: 2), widthDots: 384)
            #expect(a != b, "\(kind)")
        }
    }

    @Test func concurrentRendersAgree() async {
        PuzzleCache.shared.removeAll()
        let doc = PuzzleDoc(kind: .sudoku, difficulty: .hard, seed: 2024)
        let results = await withTaskGroup(of: MonoBitmap.self) { group in
            for _ in 0..<4 { group.addTask { PuzzleRenderer.render(doc, widthDots: 384) } }
            return await group.reduce(into: [MonoBitmap]()) { $0.append($1) }
        }
        #expect(Set(results.map(\.bytes)).count == 1)
    }

    @Test func docRoundTripsAndToleratesMissingFields() throws {
        var doc = PuzzleDoc(kind: .wordSearch, difficulty: .hard, seed: 42)
        doc.wordTheme = .custom
        doc.customWords = "mate, asado"
        let data = try JSONEncoder().encode(doc)
        #expect(try JSONDecoder().decode(PuzzleDoc.self, from: data) == doc)
        let partial = try JSONDecoder().decode(PuzzleDoc.self, from: Data(#"{"kind":"maze","seed":7,"unknown":1}"#.utf8))
        #expect(partial.kind == .maze && partial.seed == 7 && partial.difficulty == .medium)
        let garbage = try JSONDecoder().decode(PuzzleDoc.self, from: Data(#"{"kind":"poker","difficulty":"insane"}"#.utf8))
        #expect(garbage.kind == .sudoku && garbage.difficulty == .medium)
    }

    @Test func rerollChangesSeed() {
        var doc = PuzzleDoc()
        let before = doc.seed
        doc.reroll()
        #expect(doc.seed != before)
        #expect(doc.seed >= 100_000 && doc.seed <= 999_999)
    }

    @Test func difficultyIsClampedPerKind() {
        var doc = PuzzleDoc(kind: .nonogram, difficulty: .expert, seed: 1)
        #expect(doc.effectiveDifficulty == .hard)
        doc.kind = .sudoku
        #expect(doc.effectiveDifficulty == .expert)
        doc.sudokuSize = .mini
        #expect(doc.effectiveDifficulty == .hard)
    }

    @Test func kindMetadataIsComplete() {
        for kind in PuzzleKind.allCases {
            #expect(!kind.title.isEmpty && !kind.icon.isEmpty && !kind.summary.isEmpty)
            #expect(!kind.difficulties.isEmpty)
        }
    }
}

@Suite struct RandomTests {
    @Test func deterministicAndInRange() {
        var a = PuzzleRNG(seed: 1), b = PuzzleRNG(seed: 1), c = PuzzleRNG(seed: 2)
        let sa = (0..<100).map { _ in a.next() }, sb = (0..<100).map { _ in b.next() }, sc = (0..<100).map { _ in c.next() }
        #expect(sa == sb)
        #expect(sa != sc)
        var r = PuzzleRNG(seed: 9)
        for n in 1...50 {
            for _ in 0..<20 { #expect((0..<n).contains(r.int(n))) }
        }
        // Golden values pin the generator so printed ids keep reproducing the same puzzles.
        var g = PuzzleRNG(seed: 0)
        #expect((0..<3).map { _ in g.int(1000) } == [601, 747, 103])
    }
}
