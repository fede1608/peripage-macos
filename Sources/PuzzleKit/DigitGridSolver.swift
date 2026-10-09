// Human-style deductive solver for "each digit once per unit" grids (Sudoku and Latin squares).
//
// The deduction steps, their order and the difficulty grading follow Simon Tatham's Portable Puzzle
// Collection (MIT licence, https://www.chiark.greenend.org.uk/~sgtatham/puzzles/): `solo.c` (Sudoku:
// block / simple / intersect / set / extreme) and `latin.c` + `unequal.c` (Latin squares and Futoshiki
// inequality links). The solver never guesses, so whenever it fills the grid the solution is unique.
//
// Puzzle generation calls the solver thousands of times, and previews run debug builds too, so the hot
// paths use candidate bitmasks and raw buffers instead of nested arrays.

import Foundation

/// Cells, units and peers of an n×n digit grid, optionally with rectangular boxes.
final class GridGeometry: @unchecked Sendable {
    let n: Int
    let count: Int
    let rowOf: [Int]
    let colOf: [Int]
    let boxOf: [Int]
    let hasBoxes: Bool
    let fullMask: UInt16
    /// Units as n-cell runs: rows, then columns, then boxes (if any).
    let unitCells: [Int]
    let unitCount: Int
    /// Fixed-size peer lists (every cell has `peerCount` peers).
    let peerCells: [Int]
    let peerCount: Int
    /// Box/line intersections for box-line reduction: (intersection, rest of line, rest of box).
    let intersections: [(inter: [Int], lineRest: [Int], boxRest: [Int])]

    /// `boxWidth`×`boxHeight` boxes (Sudoku), or none (Latin square).
    init(n: Int, boxWidth: Int? = nil, boxHeight: Int? = nil) {
        self.n = n
        count = n * n
        fullMask = UInt16((1 << n) - 1)
        rowOf = (0..<(n * n)).map { $0 / n }
        colOf = (0..<(n * n)).map { $0 % n }
        var units: [[Int]] = (0..<n).map { y in (0..<n).map { y * n + $0 } }
        units += (0..<n).map { x in (0..<n).map { $0 * n + x } }
        if let bw = boxWidth, let bh = boxHeight {
            hasBoxes = true
            let perRow = n / bw
            let boxOf = (0..<(n * n)).map { ($0 / n) / bh * perRow + ($0 % n) / bw }
            self.boxOf = boxOf
            var boxes = [[Int]](repeating: [], count: n)
            for i in 0..<(n * n) { boxes[boxOf[i]].append(i) }
            units += boxes
            var inter: [(inter: [Int], lineRest: [Int], boxRest: [Int])] = []
            for box in boxes {
                for useRows in [true, false] {
                    let lineIDs = Set(box.map { useRows ? $0 / n : $0 % n }).sorted()
                    for id in lineIDs {
                        let line = units[useRows ? id : n + id]
                        inter.append((line.filter(box.contains), line.filter { !box.contains($0) }, box.filter { !line.contains($0) }))
                    }
                }
            }
            intersections = inter
        } else {
            hasBoxes = false
            boxOf = [Int](repeating: -1, count: n * n)
            intersections = []
        }
        unitCount = units.count
        unitCells = units.flatMap { $0 }
        var peers: [[Int]] = []
        let (rows, cols, boxes, boxed) = (rowOf, colOf, boxOf, hasBoxes)
        for i in 0..<(n * n) {
            peers.append((0..<(n * n)).filter { j in
                j != i && (rows[j] == rows[i] || cols[j] == cols[i] || (boxed && boxes[j] == boxes[i]))
            })
        }
        peerCount = peers[0].count
        peerCells = peers.flatMap { $0 }
    }

    func sees(_ a: Int, _ b: Int) -> Bool {
        rowOf[a] == rowOf[b] || colOf[a] == colOf[b] || (hasBoxes && boxOf[a] == boxOf[b])
    }
}

final class DigitGridSolver {
    enum UnitKind { case rows, cols, boxes }

    enum Step {
        /// A digit with a single possible cell in a unit ("positional elimination").
        case hiddenSingles(UnitKind)
        /// A cell with a single candidate ("numeric elimination").
        case nakedSingles
        /// Box/line reduction (Solo's "intersectional analysis").
        case intersections
        /// Naked/hidden subsets inside a unit (Solo's "set elimination").
        case subsets(UnitKind)
        /// Row-vs-column set elimination on a single digit (X-wing, swordfish…).
        case fish
        /// Chains of two-candidate cells (Solo's "forcing chains").
        case forcingChains
        /// Futoshiki "greater than" links.
        case inequalities
    }

    enum Outcome: Equatable {
        case solved(level: Int)
        case stuck
        case impossible
    }

    /// Tatham Solo's ladder: 0 block, 1 simple, 2 intersect, 3 set, 4 extreme.
    static let sudokuSteps: [(step: Step, level: Int)] = [
        (.hiddenSingles(.boxes), 0),
        (.hiddenSingles(.rows), 1), (.hiddenSingles(.cols), 1), (.nakedSingles, 1),
        (.intersections, 2),
        (.subsets(.boxes), 3), (.subsets(.rows), 3), (.subsets(.cols), 3),
        (.fish, 4), (.forcingChains, 4),
    ]

    /// Tatham Unequal's ladder: 0 latin, 1 easy (links), 2 set, 3 extreme.
    static let futoshikiSteps: [(step: Step, level: Int)] = [
        (.hiddenSingles(.rows), 0), (.hiddenSingles(.cols), 0), (.nakedSingles, 0),
        (.inequalities, 1),
        (.subsets(.rows), 2), (.subsets(.cols), 2),
        (.fish, 3), (.forcingChains, 3),
    ]

    let geo: GridGeometry
    let steps: [(step: Step, level: Int)]
    /// (greater cell, lesser cell) pairs for `.inequalities`.
    var links: [(Int, Int)] = []

    private let n: Int
    private let count: Int
    private let grid: UnsafeMutablePointer<Int>
    private let cand: UnsafeMutablePointer<UInt16>
    private let units: UnsafeMutablePointer<Int>
    private let peers: UnsafeMutablePointer<Int>
    private let peerCount: Int
    private let matrix: UnsafeMutablePointer<UInt16>
    private let scratch: UnsafeMutablePointer<Int>
    private let setBuffer: UnsafeMutablePointer<UInt16>
    private var empties = 0

    init(geometry: GridGeometry, steps: [(step: Step, level: Int)]) {
        geo = geometry
        self.steps = steps
        n = geometry.n
        count = geometry.count
        grid = .allocate(capacity: count)
        grid.initialize(repeating: 0, count: count)
        cand = .allocate(capacity: count)
        cand.initialize(repeating: 0, count: count)
        units = .allocate(capacity: geometry.unitCells.count)
        units.initialize(from: geometry.unitCells, count: geometry.unitCells.count)
        peers = .allocate(capacity: geometry.peerCells.count)
        peers.initialize(from: geometry.peerCells, count: geometry.peerCells.count)
        peerCount = geometry.peerCount
        matrix = .allocate(capacity: 16)
        matrix.initialize(repeating: 0, count: 16)
        scratch = .allocate(capacity: 2 * count + 2)
        scratch.initialize(repeating: 0, count: 2 * count + 2)
        setBuffer = .allocate(capacity: 64 + 1024)
        setBuffer.initialize(repeating: 0, count: 64 + 1024)
    }

    deinit {
        grid.deallocate()
        cand.deallocate()
        units.deallocate()
        peers.deallocate()
        matrix.deallocate()
        scratch.deallocate()
        setBuffer.deallocate()
    }

    /// Current values (after `solve`), 0 for undetermined cells.
    var values: [Int] { Array(UnsafeBufferPointer(start: grid, count: count)) }
    /// Current candidate masks (after `solve`).
    var candidates: [UInt16] { Array(UnsafeBufferPointer(start: cand, count: count)) }

    @inline(__always) private func bit(_ d: Int) -> UInt16 { UInt16(1) << UInt16(d - 1) }

    /// Loads clues (0 = empty) and runs deductions up to `maxLevel`.
    func solve(_ clues: [Int], maxLevel: Int) -> Outcome {
        // `while` loops: Range iteration is slow in unoptimized builds, and previews run those.
        let full = geo.fullMask
        var i = 0
        while i < count {
            grid[i] = 0
            cand[i] = full
            i += 1
        }
        empties = count
        i = 0
        while i < count {
            let d = clues[i]
            if d != 0 && grid[i] != d {
                guard grid[i] == 0, cand[i] & bit(d) != 0 else { return .impossible }
                place(i, d)
            }
            i += 1
        }
        return run(maxLevel: maxLevel)
    }

    private func place(_ cell: Int, _ d: Int) {
        let b = bit(d)
        grid[cell] = d
        cand[cell] = b
        empties -= 1
        var p = peers + cell * peerCount
        let end = p + peerCount
        while p < end {
            let q = p.pointee
            if grid[q] == 0 { cand[q] &= ~b }
            p += 1
        }
    }

    private func run(maxLevel: Int) -> Outcome {
        var used = 0
        outer: while empties > 0 {
            for (step, level) in steps where level <= maxLevel {
                let r = apply(step)
                if r < 0 { return .impossible }
                if r > 0 {
                    used = max(used, level)
                    continue outer
                }
            }
            break
        }
        guard empties == 0 else { return .stuck }
        // A finished grid must also respect the links (they are unused at the lowest level).
        for (g, l) in links where grid[g] <= grid[l] { return .impossible }
        return .solved(level: used)
    }

    private func unitRange(_ kind: UnitKind) -> Range<Int> {
        switch kind {
        case .rows: 0..<n
        case .cols: n..<(2 * n)
        case .boxes: geo.hasBoxes ? (2 * n)..<(3 * n) : 0..<0
        }
    }

    private func apply(_ step: Step) -> Int {
        switch step {
        case .hiddenSingles(let kind): hiddenSingles(unitRange(kind))
        case .nakedSingles: nakedSingles()
        case .intersections: intersections()
        case .subsets(let kind): subsets(unitRange(kind))
        case .fish: fish()
        case .forcingChains: forcingChains()
        case .inequalities: inequalities()
        }
    }

    // MARK: Steps

    private func hiddenSingles(_ range: Range<Int>) -> Int {
        let full = geo.fullMask
        var u = range.lowerBound
        while u < range.upperBound {
            let cells = units + u * n
            var once: UInt16 = 0, twice: UInt16 = 0, placed: UInt16 = 0
            var k = 0
            while k < n {
                let c = cells[k]
                if grid[c] != 0 {
                    placed |= cand[c]
                } else {
                    let m = cand[c]
                    twice |= once & m
                    once |= m
                }
                k += 1
            }
            if full & ~placed & ~once != 0 { return -1 }
            let singles = once & ~twice & ~placed
            if singles != 0 {
                let b = singles & (0 &- singles)
                k = 0
                while k < n {
                    let c = cells[k]
                    if grid[c] == 0 && cand[c] & b != 0 {
                        place(c, b.trailingZeroBitCount + 1)
                        return 1
                    }
                    k += 1
                }
            }
            u += 1
        }
        return 0
    }

    private func nakedSingles() -> Int {
        var c = 0
        while c < count {
            if grid[c] == 0 {
                let m = cand[c]
                if m == 0 { return -1 }
                if m & (m &- 1) == 0 {
                    place(c, m.trailingZeroBitCount + 1)
                    return 1
                }
            }
            c += 1
        }
        return 0
    }

    private func intersections() -> Int {
        for (inter, lineRest, boxRest) in geo.intersections {
            var mInter: UInt16 = 0, mLine: UInt16 = 0, mBox: UInt16 = 0, placed: UInt16 = 0
            for c in inter { if grid[c] == 0 { mInter |= cand[c] } else { placed |= cand[c] } }
            for c in lineRest { if grid[c] == 0 { mLine |= cand[c] } else { placed |= cand[c] } }
            for c in boxRest { if grid[c] == 0 { mBox |= cand[c] } else { placed |= cand[c] } }
            // Line vs box: digits whose line positions all lie in the box leave the rest of the box.
            let fromBox = mInter & ~mLine & mBox & ~placed
            if fromBox != 0 {
                let d = UInt16(1) << UInt16(fromBox.trailingZeroBitCount)
                for c in boxRest where grid[c] == 0 { cand[c] &= ~d }
                return 1
            }
            // Box vs line.
            let fromLine = mInter & ~mBox & mLine & ~placed
            if fromLine != 0 {
                let d = UInt16(1) << UInt16(fromLine.trailingZeroBitCount)
                for c in lineRest where grid[c] == 0 { cand[c] &= ~d }
                return 1
            }
        }
        return 0
    }

    private func subsets(_ range: Range<Int>) -> Int {
        var u = range.lowerBound
        while u < range.upperBound {
            let cells = units + u * n
            var k = 0
            while k < n { matrix[k] = cand[cells[k]]; k += 1 }
            let r = setElimination(matrix)
            if r < 0 { return -1 }
            if r > 0 {
                k = 0
                while k < n {
                    let c = cells[k]
                    if grid[c] == 0 { cand[c] = matrix[k] }
                    k += 1
                }
                return 1
            }
            u += 1
        }
        return 0
    }

    private func fish() -> Int {
        for d in 1...n {
            let b = bit(d)
            for y in 0..<n {
                var row: UInt16 = 0
                for x in 0..<n where cand[y * n + x] & b != 0 { row |= UInt16(1) << UInt16(x) }
                matrix[y] = row
                scratch[y] = Int(row)
            }
            let r = setElimination(matrix)
            if r < 0 { return -1 }
            if r > 0 {
                for y in 0..<n {
                    let removed = UInt16(scratch[y]) & ~matrix[y]
                    guard removed != 0 else { continue }
                    for x in 0..<n where removed & (UInt16(1) << UInt16(x)) != 0 { cand[y * n + x] &= ~b }
                }
                return 1
            }
        }
        return 0
    }

    /// Solo's `solver_forcing`: BFS from each two-candidate cell along cells that would be forced.
    private func forcingChains() -> Int {
        let number = scratch                 // value each visited cell would take (0 = unvisited)
        let queue = scratch + count
        for start in 0..<count where grid[start] == 0 && cand[start].nonzeroBitCount == 2 {
            let pair = cand[start]
            for orig in 1...n where pair & bit(orig) != 0 {
                for i in 0..<count { number[i] = 0 }
                var head = 0, tail = 0
                queue[tail] = start
                tail += 1
                number[start] = (pair & ~bit(orig)).trailingZeroBitCount + 1
                while head < tail {
                    let cur = queue[head]
                    head += 1
                    let currn = number[cur]
                    let cb = bit(currn)
                    let base = cur * peerCount
                    for k in 0..<peerCount {
                        let nb = peers[base + k]
                        if number[nb] != 0 || cand[nb] & cb == 0 { continue }
                        if grid[nb] == 0 && cand[nb].nonzeroBitCount == 2 {
                            queue[tail] = nb
                            tail += 1
                            number[nb] = (cand[nb] & ~cb).trailingZeroBitCount + 1
                        }
                        if currn == orig && grid[nb] == 0 && geo.sees(nb, start) {
                            cand[nb] &= ~bit(orig)
                            return 1
                        }
                    }
                }
            }
        }
        return 0
    }

    /// Unequal's `solver_links`: the greater cell exceeds the lesser cell's minimum, and vice versa.
    private func inequalities() -> Int {
        var changed = false
        for (g, l) in links {
            guard cand[g] != 0, cand[l] != 0 else { return -1 }
            let gmax = 16 - cand[g].leadingZeroBitCount            // highest candidate digit of g
            let lmin = cand[l].trailingZeroBitCount + 1             // lowest candidate digit of l
            let keepG: UInt16 = ~UInt16((1 << lmin) - 1)            // digits > lmin
            let keepL: UInt16 = UInt16((1 << (gmax - 1)) - 1)       // digits < gmax
            if cand[g] & ~keepG != 0 {
                if grid[g] != 0 { return -1 }
                cand[g] &= keepG
                if cand[g] == 0 { return -1 }
                changed = true
            }
            if cand[l] & ~keepL != 0 {
                if grid[l] != 0 { return -1 }
                cand[l] &= keepL
                if cand[l] == 0 { return -1 }
                changed = true
            }
        }
        return changed ? 1 : 0
    }

    // MARK: Set elimination

    /// Solo's `solver_set` on the n×n boolean matrix `m` (rows as bitmasks over columns): find k columns
    /// confined to k rows and clear the other columns from those rows. -1 contradiction, 0 none, 1 progress.
    private func setElimination(_ m: UnsafeMutablePointer<UInt16>) -> Int {
        var liveRows: UInt16 = 0
        var colMask = geo.fullMask
        var k = 0
        var i = 0
        while i < n {
            let c = m[i].nonzeroBitCount
            if c == 0 { return -1 }
            if c == 1 { colMask &= ~m[i] } else { liveRows |= 1 << UInt16(i); k += 1 }
            i += 1
        }
        guard colMask.nonzeroBitCount == k else { return -1 }
        guard k >= 4 else { return 0 }
        // Compress live rows onto live columns; also record, per column, the rows that contain it.
        let cols = setBuffer, rowIndex = setBuffer + 16, rows = setBuffer + 32, colRows = setBuffer + 48
        let union = setBuffer + 64
        var j = 0
        i = 0
        while i < n {
            if colMask & (1 << UInt16(i)) != 0 { cols[j] = UInt16(i); j += 1 }
            i += 1
        }
        j = 0
        i = 0
        while i < n {
            if liveRows & (1 << UInt16(i)) != 0 {
                rowIndex[j] = UInt16(i)
                var packed: UInt16 = 0
                var ci = 0
                while ci < k {
                    if m[i] & (1 << cols[ci]) != 0 { packed |= 1 << UInt16(ci) }
                    ci += 1
                }
                rows[j] = packed
                j += 1
            }
            i += 1
        }
        var ci = 0
        while ci < k {
            var mask: UInt16 = 0
            var ri = 0
            while ri < k {
                if rows[ri] & (1 << UInt16(ci)) != 0 { mask |= 1 << UInt16(ri) }
                ri += 1
            }
            colRows[ci] = mask
            ci += 1
        }
        // For each column set S, union[S] = rows holding any column of S. |union| < |S| is a contradiction;
        // |union| == |S| means those rows hold exactly S, so their other columns can go.
        union[0] = 0
        let limit = 1 << k
        var s = 1
        while s < limit {
            let u = union[s & (s - 1)] | colRows[s.trailingZeroBitCount]
            union[s] = u
            let size = s.nonzeroBitCount
            if size > 1 && size < k - 1 {
                let covered = u.nonzeroBitCount
                if covered < size { return -1 }
                if covered == size {
                    let set = UInt16(s)
                    var progress = false
                    var ri = 0
                    while ri < k {
                        if u & (1 << UInt16(ri)) != 0 && rows[ri] & ~set != 0 {
                            rows[ri] &= set
                            progress = true
                        }
                        ri += 1
                    }
                    if progress {
                        ri = 0
                        while ri < k {
                            var full: UInt16 = 0
                            var cj = 0
                            while cj < k {
                                if rows[ri] & (1 << UInt16(cj)) != 0 { full |= 1 << cols[cj] }
                                cj += 1
                            }
                            m[Int(rowIndex[ri])] = full
                            ri += 1
                        }
                        return 1
                    }
                }
            }
            s += 1
        }
        return 0
    }
}

/// Random complete grid by randomized backtracking (most constrained cell first).
func randomFilledGrid(_ geo: GridGeometry, rng: inout PuzzleRNG) -> [Int] {
    var grid = [Int](repeating: 0, count: geo.count)
    var cand = [UInt16](repeating: geo.fullMask, count: geo.count)
    var budget = 0

    func fill() -> Bool {
        budget -= 1
        if budget < 0 { return false }
        var best = -1, bestCount = 99
        for i in 0..<geo.count where grid[i] == 0 {
            let c = cand[i].nonzeroBitCount
            if c == 0 { return false }
            if c < bestCount { best = i; bestCount = c }
        }
        if best < 0 { return true }
        var digits: [Int] = []
        for d in 1...geo.n where cand[best] & (1 << UInt16(d - 1)) != 0 { digits.append(d) }
        rng.shuffle(&digits)
        let base = best * geo.peerCount
        for d in digits {
            let b = UInt16(1) << UInt16(d - 1)
            var touched: [Int] = []
            for k in 0..<geo.peerCount {
                let p = geo.peerCells[base + k]
                if grid[p] == 0 && cand[p] & b != 0 {
                    cand[p] &= ~b
                    touched.append(p)
                }
            }
            grid[best] = d
            if fill() { return true }
            grid[best] = 0
            for p in touched { cand[p] |= b }
            if budget < 0 { return false }
        }
        return false
    }

    repeat {
        grid = [Int](repeating: 0, count: geo.count)
        cand = [UInt16](repeating: geo.fullMask, count: geo.count)
        budget = 100_000
    } while !fill()
    return grid
}
