// Hashi ("Bridges") after Simon Tatham's `bridges.c` (MIT licence). The generator is Tatham's: grow a
// connected network by repeatedly extending a random island in a random direction (sometimes joining an
// existing island, which creates loops), with 1–2 bridges per join, until ~30% of the grid holds islands
// and every border is touched. The puzzle is kept only if the solver needs exactly the requested level.
//
// The solver follows the edge-based redesign sketched in the notes at the top of `bridges.c`: every
// potential bridge is an edge with a [min, max] bridge count, crossing edges exclude each other, and
// connectivity is reasoned about with groups of islands that would be sealed off.
//   level 0: local counting at each island (and crossings),
//   level 1: + no sealed-off groups (Tatham's stage 3),
//   level 2: + one-step lookahead: a value that leads to a contradiction under level 1 is ruled out.

import Foundation
import PeriPageKit

struct BridgeIsland: Sendable, Equatable {
    let x: Int
    let y: Int
    let count: Int
}

struct BridgeEdge: Sendable, Equatable {
    let a: Int
    let b: Int
    /// Bridges in the solution (0...2).
    let bridges: Int
}

struct BridgesPuzzle: Sendable {
    let w: Int
    let h: Int
    let islands: [BridgeIsland]
    /// Every potential bridge (pairs of islands that see each other), with the solution count.
    let edges: [BridgeEdge]
    let grade: Int
}

/// Islands, the potential bridges between them and which bridges cross.
struct BridgeGraph {
    let islands: [BridgeIsland]
    let edges: [(a: Int, b: Int)]
    let incident: [[Int]]
    let crossing: [[Int]]

    init(w: Int, h: Int, islands: [BridgeIsland]) {
        self.islands = islands
        var at = [Int](repeating: -1, count: w * h)
        for (i, isl) in islands.enumerated() { at[isl.y * w + isl.x] = i }
        var edges: [(a: Int, b: Int)] = []
        for (i, isl) in islands.enumerated() {
            for (dx, dy) in [(1, 0), (0, 1)] {
                var x = isl.x + dx, y = isl.y + dy
                while x < w && y < h {
                    let j = at[y * w + x]
                    if j >= 0 { edges.append((i, j)); break }
                    x += dx
                    y += dy
                }
            }
        }
        self.edges = edges
        var incident = [[Int]](repeating: [], count: islands.count)
        for (e, edge) in edges.enumerated() {
            incident[edge.a].append(e)
            incident[edge.b].append(e)
        }
        self.incident = incident
        var crossing = [[Int]](repeating: [], count: edges.count)
        for (e, eh) in edges.enumerated() where islands[eh.a].y == islands[eh.b].y {
            let y = islands[eh.a].y, x1 = islands[eh.a].x, x2 = islands[eh.b].x
            for (f, ev) in edges.enumerated() where islands[ev.a].x == islands[ev.b].x {
                let x = islands[ev.a].x, y1 = islands[ev.a].y, y2 = islands[ev.b].y
                if x > x1 && x < x2 && y > y1 && y < y2 {
                    crossing[e].append(f)
                    crossing[f].append(e)
                }
            }
        }
        self.crossing = crossing
    }
}

final class BridgesSolver {
    enum Outcome: Equatable { case solved, stuck, impossible }

    let graph: BridgeGraph
    let maxBridges: Int
    private(set) var lo: [Int]
    private(set) var hi: [Int]

    init(graph: BridgeGraph, maxBridges: Int = 2) {
        self.graph = graph
        self.maxBridges = maxBridges
        lo = [Int](repeating: 0, count: graph.edges.count)
        hi = graph.edges.map { min(maxBridges, graph.islands[$0.a].count, graph.islands[$0.b].count) }
    }

    func solve(level: Int) -> Outcome {
        while true {
            guard local() else { return .impossible }
            if lo == hi { return connected(lo) ? .solved : .impossible }
            if level >= 1 {
                guard !sealedGroupExists(lo) else { return .impossible }
                if isolationStep() { continue }
            }
            if level >= 2 && lookaheadStep() { continue }
            return .stuck
        }
    }

    // MARK: Level 0

    /// Crossing exclusion and per-island counting, to a fixpoint. False on a contradiction.
    private func local() -> Bool {
        var changed = true
        while changed {
            changed = false
            for e in 0..<lo.count where lo[e] > 0 {
                for f in graph.crossing[e] where hi[f] > 0 {
                    if lo[f] > 0 { return false }
                    hi[f] = 0
                    changed = true
                }
            }
            for (i, isl) in graph.islands.enumerated() {
                let inc = graph.incident[i]
                var sumLo = 0, sumHi = 0
                for e in inc { sumLo += lo[e]; sumHi += hi[e] }
                if sumHi < isl.count || sumLo > isl.count { return false }
                for e in inc {
                    let newLo = max(lo[e], isl.count - (sumHi - hi[e]))
                    let newHi = min(hi[e], isl.count - (sumLo - lo[e]))
                    if newLo > newHi { return false }
                    if newLo != lo[e] || newHi != hi[e] {
                        sumLo += newLo - lo[e]
                        sumHi += newHi - hi[e]
                        lo[e] = newLo
                        hi[e] = newHi
                        changed = true
                    }
                }
            }
        }
        return true
    }

    // MARK: Level 1

    private func bridgeCount(_ island: Int, _ values: [Int]) -> Int {
        graph.incident[island].reduce(0) { $0 + values[$1] }
    }

    /// Islands reachable from `start` over edges with bridges in `values`.
    private func group(_ start: Int, _ values: [Int]) -> [Int] {
        var seen = [Bool](repeating: false, count: graph.islands.count)
        seen[start] = true
        var stack = [start], out = [start]
        while let i = stack.popLast() {
            for e in graph.incident[i] where values[e] > 0 {
                let j = graph.edges[e].a == i ? graph.edges[e].b : graph.edges[e].a
                if !seen[j] { seen[j] = true; stack.append(j); out.append(j) }
            }
        }
        return out
    }

    /// True if the group around `island` is complete (every island has all its bridges) but not everything.
    private func sealed(_ island: Int, _ values: [Int]) -> Bool {
        let g = group(island, values)
        guard g.count < graph.islands.count else { return false }
        return g.allSatisfy { bridgeCount($0, values) == graph.islands[$0].count }
    }

    private func sealedGroupExists(_ values: [Int]) -> Bool {
        (0..<graph.islands.count).contains { sealed($0, values) }
    }

    private func connected(_ values: [Int]) -> Bool {
        graph.islands.isEmpty || group(0, values).count == graph.islands.count
    }

    /// Tatham's stage 3: (1) an edge may not get so many bridges that its islands seal off a group;
    /// (2) if filling every other direction of an island would seal it off, this direction needs a bridge.
    private func isolationStep() -> Bool {
        for e in 0..<lo.count where hi[e] > lo[e] {
            var trial = lo
            for k in (lo[e] + 1)...hi[e] {
                trial[e] = k
                if sealed(graph.edges[e].a, trial) {
                    hi[e] = k - 1
                    return true
                }
            }
        }
        for (i, isl) in graph.islands.enumerated() where bridgeCount(i, lo) < isl.count {
            let inc = graph.incident[i]
            for e in inc where lo[e] == 0 && hi[e] > 0 {
                var trial = lo
                for f in inc where f != e { trial[f] = hi[f] }
                if bridgeCount(i, trial) == isl.count && sealed(i, trial) {
                    lo[e] = 1
                    return true
                }
            }
        }
        return false
    }

    // MARK: Level 2

    /// Rules out the lowest or highest value of an edge when assuming it leads to a contradiction.
    private func lookaheadStep() -> Bool {
        for e in 0..<lo.count where hi[e] > lo[e] {
            for v in [lo[e], hi[e]] {
                let probe = BridgesSolver(copying: self)
                probe.lo[e] = v
                probe.hi[e] = v
                if probe.solve(level: 1) == .impossible {
                    if v == lo[e] { lo[e] += 1 } else { hi[e] -= 1 }
                    return true
                }
            }
        }
        return false
    }

    private init(copying other: BridgesSolver) {
        graph = other.graph
        maxBridges = other.maxBridges
        lo = other.lo
        hi = other.hi
    }
}

enum BridgesGenerator {
    static func size(_ d: PuzzleDifficulty) -> (w: Int, h: Int) {
        switch d {
        case .easy: (7, 8)
        case .medium: (8, 10)
        case .hard, .expert: (9, 12)
        }
    }

    static func generate(difficulty: PuzzleDifficulty, seed: UInt64) -> BridgesPuzzle {
        let (w, h) = size(difficulty)
        let target = min(2, difficulty.level)
        var rng = PuzzleRNG(seed: seed, salt: 0xB41D &+ UInt64(difficulty.level) << 8)
        var fallback: BridgesPuzzle?
        for _ in 0..<400 {
            guard let (islands, bridges) = layout(w: w, h: h, rng: &rng) else { continue }
            let graph = BridgeGraph(w: w, h: h, islands: islands)
            // Too easy: solvable one level down. (Tatham's rule; tiny puzzles are exempt.)
            if target > 0 && islands.count > 3 && BridgesSolver(graph: graph).solve(level: target - 1) == .solved {
                if fallback == nil { fallback = puzzle(w, h, graph, bridges, grade: target - 1) }
                continue
            }
            let solver = BridgesSolver(graph: graph)
            guard solver.solve(level: target) == .solved else { continue }
            return puzzle(w, h, graph, bridges, grade: target)
        }
        // Rare: no puzzle needed exactly this level within the budget; use a solvable one from one level down.
        if let fallback { return fallback }
        while true {
            guard let (islands, bridges) = layout(w: w, h: h, rng: &rng) else { continue }
            let graph = BridgeGraph(w: w, h: h, islands: islands)
            if BridgesSolver(graph: graph).solve(level: 2) == .solved { return puzzle(w, h, graph, bridges, grade: 2) }
        }
    }

    private static func puzzle(_ w: Int, _ h: Int, _ graph: BridgeGraph, _ bridges: [Int: Int], grade: Int) -> BridgesPuzzle {
        let edges = graph.edges.map { e in
            BridgeEdge(a: e.a, b: e.b, bridges: bridges[min(e.a, e.b) * 10_000 + max(e.a, e.b)] ?? 0)
        }
        return BridgesPuzzle(w: w, h: h, islands: graph.islands, edges: edges, grade: grade)
    }

    /// Tatham's island growth. Returns islands and bridges keyed by `min * 10000 + max` island index.
    static func layout(w: Int, h: Int, rng: inout PuzzleRNG) -> ([BridgeIsland], [Int: Int])? {
        let islandsPercent = 30, expansion = 10, maxb = 2
        let required = max(islandsPercent * w * h / 100, 3)
        var at = [Int](repeating: -1, count: w * h)
        var line = [Bool](repeating: false, count: w * h)
        var pos: [(Int, Int)] = []
        var bridges: [Int: Int] = [:]

        func add(_ x: Int, _ y: Int) -> Int {
            at[y * w + x] = pos.count
            pos.append((x, y))
            return pos.count - 1
        }
        func join(_ i: Int, _ j: Int) {
            let n = rng.int(maxb) + 1
            bridges[min(i, j) * 10_000 + max(i, j)] = n
            let (x1, y1) = pos[i], (x2, y2) = pos[j]
            if x1 == x2 {
                for y in (min(y1, y2) + 1)..<max(y1, y2) { line[y * w + x1] = true }
            } else {
                for x in (min(x1, x2) + 1)..<max(x1, x2) { line[y1 * w + x] = true }
            }
        }
        func inGrid(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y < h }

        _ = add(rng.int(w), rng.int(h))
        // A failed extension counts as "bad"; 50 in a row ends the growth (MAX_NEWISLAND_TRIES).
        var bad = 0
        growth: while pos.count < required {
            let i = rng.int(pos.count)
            let (ix, iy) = pos[i]
            var dirs: [(Int, Int)] = []
            if ix > 0 { dirs.append((-1, 0)) }
            if ix < w - 1 { dirs.append((1, 0)) }
            if iy > 0 { dirs.append((0, -1)) }
            if iy < h - 1 { dirs.append((0, 1)) }
            let (dx, dy) = rng.pick(dirs)
            var placed = false
            repeat {
                if line[(iy + dy) * w + ix + dx] { break }
                let minX = ix + 2 * dx, minY = iy + 2 * dy
                var x = ix + dx, y = iy + dy
                var joinTo = -1
                var maxX = 0, maxY = 0
                while true {
                    if !inGrid(x, y) { maxX = x - dx; maxY = y - dy; break }
                    if at[y * w + x] >= 0 { joinTo = at[y * w + x]; maxX = x - 2 * dx; maxY = y - 2 * dy; break }
                    if line[y * w + x] { maxX = x - dx; maxY = y - dy; break }
                    x += dx
                    y += dy
                }
                if joinTo >= 0 && rng.int(100) < expansion {
                    join(i, joinTo)      // a loop; does not reset the bad counter
                    continue growth
                }
                let spanX = (maxX - minX) * dx, spanY = (maxY - minY) * dy
                if spanX < 0 || spanY < 0 { break }
                let nx: Int, ny: Int
                if rng.int(100) < expansion {
                    nx = maxX; ny = maxY
                } else {
                    let k = rng.int(max(spanX, spanY) + 1)
                    nx = minX + k * dx; ny = minY + k * dy
                }
                // Not right next to another island sideways.
                if (inGrid(nx + dy, ny + dx) && at[(ny + dx) * w + nx + dy] >= 0)
                    || (inGrid(nx - dy, ny - dx) && at[(ny - dx) * w + nx - dy] >= 0) { break }
                join(i, add(nx, ny))
                placed = true
            } while false
            if placed {
                bad = 0
            } else {
                bad += 1
                if bad > 50 { break }
            }
        }
        guard pos.count > 1 else { return nil }
        // At least one island on every edge of the grid.
        guard pos.contains(where: { $0.1 == 0 }), pos.contains(where: { $0.1 == h - 1 }),
              pos.contains(where: { $0.0 == 0 }), pos.contains(where: { $0.0 == w - 1 }) else { return nil }
        var counts = [Int](repeating: 0, count: pos.count)
        for (key, n) in bridges {
            counts[key / 10_000] += n
            counts[key % 10_000] += n
        }
        return (pos.enumerated().map { BridgeIsland(x: $0.element.0, y: $0.element.1, count: counts[$0.offset]) }, bridges)
    }
}

enum BridgesSheet {
    static func render(_ doc: PuzzleDoc, _ p: BridgesPuzzle, width: Int, solution: Bool) -> MonoBitmap {
        var sheet = SheetBuilder(width: width)
        let diff = doc.effectiveDifficulty
        if solution {
            sheet.header(title: "Solución", tag: "Puentes")
        } else {
            sheet.header(title: "Puentes", tag: diff.label(for: .bridges), level: diff.level, levels: 3)
            sheet.text("Uní las islas con puentes rectos: el número dice cuántos puentes salen de cada isla. Entre dos islas hay a lo sumo dos puentes, no se cruzan y todo queda conectado.")
        }
        sheet.add(board(p, sheet: sheet, solution: solution), gap: 14)
        sheet.footer(left: "Puentes (Hashi) \(p.w)×\(p.h) · \(diff.label(for: .bridges))", right: "#\(doc.seed)")
        return sheet.build()
    }

    private static func board(_ p: BridgesPuzzle, sheet: SheetBuilder, solution: Bool) -> Canvas {
        let cell = min(sheet.px(48), sheet.innerWidth / p.w)
        var canvas = Canvas(width: cell * p.w, height: cell * p.h)
        let radius = Double(cell) * 0.4
        let ring = max(2, Double(sheet.px(2)))
        func center(_ i: Int) -> (Double, Double) {
            (Double(p.islands[i].x * cell) + Double(cell) / 2, Double(p.islands[i].y * cell) + Double(cell) / 2)
        }
        if solution {
            let stroke = max(2, Double(sheet.px(2)))
            let offset = Double(cell) * 0.1
            for e in p.edges where e.bridges > 0 {
                let (ax, ay) = center(e.a), (bx, by) = center(e.b)
                let horizontal = ay == by
                let offsets = e.bridges == 1 ? [0.0] : [-offset, offset]
                for o in offsets {
                    if horizontal {
                        canvas.buttLine(ax + radius, ay + o, bx - radius, by + o, width: stroke)
                    } else {
                        canvas.buttLine(ax + o, ay + radius, bx + o, by - radius, width: stroke)
                    }
                }
            }
        }
        let glyphs = GlyphSet(PuzzleFont.bold(CGFloat(cell) * 0.46))
        for (i, isl) in p.islands.enumerated() {
            let (cx, cy) = center(i)
            canvas.disc(cx, cy, radius: radius, black: false)
            canvas.ring(cx, cy, radius: radius, width: ring)
            glyphs.draw(String(isl.count), on: &canvas, cx: cx, cy: cy)
        }
        return canvas
    }
}
