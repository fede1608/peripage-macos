// Mazes after Jamis Buck, "Mazes for Programmers" (Pragmatic Bookshelf, 2015): perfect mazes carved on a
// cell graph with the recursive backtracker or Wilson's loop-erased random walks, on a rectangular grid or
// on a polar ("theta") grid whose rings subdivide as they grow so cells stay roughly square.

import Foundation
import PeriPageKit

struct MazePuzzle: Sendable {
    enum Layout: Sendable {
        case rect(cols: Int, rows: Int)
        /// Cells per ring, from the center (ring 0 is a single cell) outwards.
        case polar(counts: [Int])
    }

    let layout: Layout
    /// Carved passages: adjacency list per cell.
    let links: [[Int]]
    let entrance: Int
    /// Exit cell (the center for circular mazes).
    let exit: Int
    /// Solution: cells from entrance to exit.
    let path: [Int]

    var cellCount: Int { links.count }

    func linked(_ a: Int, _ b: Int) -> Bool { links[a].contains(b) }
}

/// Cell graph for a polar grid: ids are assigned ring by ring.
struct PolarGrid {
    let counts: [Int]
    let offsets: [Int]

    init(rings: Int) {
        var counts = [1]
        for row in 1..<max(2, rings) {
            let radius = Double(row) / Double(rings)
            let circumference = 2 * Double.pi * radius
            let previous = counts[row - 1]
            let estimatedWidth = circumference / Double(previous)
            let ratio = max(1, Int((estimatedWidth / (1 / Double(rings))).rounded()))
            counts.append(previous * ratio)
        }
        self.counts = counts
        var offsets: [Int] = []
        var total = 0
        for c in counts { offsets.append(total); total += c }
        self.offsets = offsets
    }

    var cellCount: Int { offsets.last! + counts.last! }
    func id(_ ring: Int, _ col: Int) -> Int { offsets[ring] + (col % counts[ring] + counts[ring]) % counts[ring] }
    func ring(of id: Int) -> Int { offsets.lastIndex { $0 <= id }! }
    func col(of id: Int) -> Int { id - offsets[ring(of: id)] }

    /// The cell one ring inwards that this cell hangs from.
    func parent(_ ring: Int, _ col: Int) -> Int {
        ring == 0 ? -1 : id(ring - 1, col / (counts[ring] / counts[ring - 1]))
    }

    func neighbors() -> [[Int]] {
        var out = [[Int]](repeating: [], count: cellCount)
        for ring in 1..<counts.count {
            for col in 0..<counts[ring] {
                let me = id(ring, col)
                let cw = id(ring, col + 1)
                if cw != me, !out[me].contains(cw) {
                    out[me].append(cw)
                    out[cw].append(me)
                }
                let p = parent(ring, col)
                out[me].append(p)
                out[p].append(me)
            }
        }
        return out
    }
}

enum MazeGenerator {
    static func generate(shape: MazeShape, style: MazeStyle, difficulty: PuzzleDifficulty, seed: UInt64) -> MazePuzzle {
        var rng = PuzzleRNG(seed: seed, salt: 0x3A2E &+ UInt64(difficulty.level) << 8)
        switch shape {
        case .rectangular:
            let cols = rectColumns(difficulty)
            let rows = Int((Double(cols) * 1.25).rounded())
            let neighbors = rectNeighbors(cols: cols, rows: rows)
            let links = carve(neighbors, style: style, rng: &rng)
            // Entrance on the top row; exit on the bottom row as far as possible from it.
            let entrance = rng.int(cols)
            let dist = distances(from: entrance, links: links)
            let bottom = ((rows - 1) * cols)..<(rows * cols)
            let exit = bottom.max { dist[$0] < dist[$1] }!
            return MazePuzzle(layout: .rect(cols: cols, rows: rows), links: links, entrance: entrance, exit: exit,
                              path: path(from: entrance, to: exit, links: links))
        case .circular:
            let grid = PolarGrid(rings: polarRings(difficulty))
            let links = carve(grid.neighbors(), style: style, rng: &rng)
            // Goal in the center; entrance on the outer ring as far as possible from it.
            let dist = distances(from: 0, links: links)
            let outer = grid.offsets.last!..<grid.cellCount
            let entrance = outer.max { dist[$0] < dist[$1] }!
            return MazePuzzle(layout: .polar(counts: grid.counts), links: links, entrance: entrance, exit: 0,
                              path: path(from: entrance, to: 0, links: links))
        }
    }

    static func rectColumns(_ d: PuzzleDifficulty) -> Int { [12, 17, 23, 33][d.level] }
    static func polarRings(_ d: PuzzleDifficulty) -> Int { [6, 9, 13, 18][d.level] }

    static func rectNeighbors(cols: Int, rows: Int) -> [[Int]] {
        (0..<(cols * rows)).map { i in
            let r = i / cols, c = i % cols
            var n: [Int] = []
            if r > 0 { n.append(i - cols) }
            if c < cols - 1 { n.append(i + 1) }
            if r < rows - 1 { n.append(i + cols) }
            if c > 0 { n.append(i - 1) }
            return n
        }
    }

    static func carve(_ neighbors: [[Int]], style: MazeStyle, rng: inout PuzzleRNG) -> [[Int]] {
        switch style {
        case .winding: recursiveBacktracker(neighbors, rng: &rng)
        case .branchy: wilson(neighbors, rng: &rng)
        }
    }

    /// Depth-first search with an explicit stack: long, winding corridors.
    static func recursiveBacktracker(_ neighbors: [[Int]], rng: inout PuzzleRNG) -> [[Int]] {
        let n = neighbors.count
        var links = [[Int]](repeating: [], count: n)
        var visited = [Bool](repeating: false, count: n)
        var stack = [rng.int(n)]
        visited[stack[0]] = true
        while let current = stack.last {
            let fresh = neighbors[current].filter { !visited[$0] }
            if fresh.isEmpty {
                stack.removeLast()
            } else {
                let next = rng.pick(fresh)
                links[current].append(next)
                links[next].append(current)
                visited[next] = true
                stack.append(next)
            }
        }
        return links
    }

    /// Wilson's algorithm: loop-erased random walks give a uniformly random spanning tree.
    static func wilson(_ neighbors: [[Int]], rng: inout PuzzleRNG) -> [[Int]] {
        let n = neighbors.count
        var links = [[Int]](repeating: [], count: n)
        var inMaze = [Bool](repeating: false, count: n)
        var unvisited = Array(0..<n)
        let first = rng.int(n)
        inMaze[first] = true
        unvisited.removeAll { $0 == first }
        var positionInWalk = [Int](repeating: -1, count: n)
        while !unvisited.isEmpty {
            var cell = rng.pick(unvisited)
            var walk = [cell]
            positionInWalk[cell] = 0
            while !inMaze[cell] {
                cell = rng.pick(neighbors[cell])
                let seen = positionInWalk[cell]
                if seen >= 0 {
                    // Erase the loop.
                    for c in walk[(seen + 1)...] { positionInWalk[c] = -1 }
                    walk.removeSubrange((seen + 1)...)
                } else {
                    positionInWalk[cell] = walk.count
                    walk.append(cell)
                }
            }
            for i in 0..<(walk.count - 1) {
                links[walk[i]].append(walk[i + 1])
                links[walk[i + 1]].append(walk[i])
            }
            for c in walk {
                positionInWalk[c] = -1
                inMaze[c] = true
            }
            unvisited.removeAll { inMaze[$0] }
        }
        return links
    }

    static func distances(from start: Int, links: [[Int]]) -> [Int] {
        var dist = [Int](repeating: -1, count: links.count)
        dist[start] = 0
        var queue = [start]
        var head = 0
        while head < queue.count {
            let c = queue[head]
            head += 1
            for nb in links[c] where dist[nb] < 0 {
                dist[nb] = dist[c] + 1
                queue.append(nb)
            }
        }
        return dist
    }

    static func path(from a: Int, to b: Int, links: [[Int]]) -> [Int] {
        let dist = distances(from: b, links: links)
        guard dist[a] >= 0 else { return [] }
        var out = [a]
        var c = a
        while c != b {
            c = links[c].first { dist[$0] == dist[c] - 1 }!
            out.append(c)
        }
        return out
    }
}

enum MazeSheet {
    static func render(_ doc: PuzzleDoc, _ p: MazePuzzle, width: Int, solution: Bool) -> MonoBitmap {
        var sheet = SheetBuilder(width: width)
        let diff = doc.effectiveDifficulty
        if solution {
            sheet.header(title: "Solución", tag: "Laberinto")
        } else {
            sheet.header(title: "Laberinto", tag: diff.label(for: .maze), level: diff.level, levels: 4)
            switch p.layout {
            case .rect: sheet.text("Entrá por la flecha de arriba y encontrá el camino hasta la salida de abajo.")
            case .polar: sheet.text("Entrá por la flecha y llegá hasta el centro sin atravesar paredes.")
            }
        }
        switch p.layout {
        case .rect(let cols, let rows): sheet.add(rect(p, cols: cols, rows: rows, sheet: sheet, solution: solution), gap: 10)
        case .polar(let counts): sheet.add(polar(p, counts: counts, sheet: sheet, solution: solution), gap: 10)
        }
        let shape = doc.mazeShape == .circular ? "circular" : "rectangular"
        sheet.footer(left: "Laberinto \(shape) · \(diff.label(for: .maze))", right: "#\(doc.seed)")
        return sheet.build()
    }

    // MARK: Rectangular

    private static func rect(_ p: MazePuzzle, cols: Int, rows: Int, sheet: SheetBuilder, solution: Bool) -> Canvas {
        let cell = sheet.innerWidth / cols
        let t = cell >= 20 ? max(3, sheet.px(3)) : max(2, sheet.px(2))
        let arrow = max(sheet.px(14), cell * 2 / 3)
        let x0 = (sheet.innerWidth - cols * cell) / 2 + t, y0 = arrow + sheet.px(6)
        let w = sheet.innerWidth + 2 * t, h = y0 + rows * cell + arrow + sheet.px(8)
        var canvas = Canvas(width: w, height: h)
        let half = t / 2
        for r in 0..<rows {
            for c in 0..<cols {
                let i = r * cols + c
                let x = x0 + c * cell, y = y0 + r * cell
                // North and west walls of every cell; south/east only on the border.
                if r == 0 ? i != p.entrance : !p.linked(i, i - cols) {
                    canvas.fill(x: x - half, y: y - half, w: cell + t, h: t)
                }
                if c == 0 || !p.linked(i, i - 1) {
                    canvas.fill(x: x - half, y: y - half, w: t, h: cell + t)
                }
                if r == rows - 1 && i != p.exit {
                    canvas.fill(x: x - half, y: y + cell - half, w: cell + t, h: t)
                }
                if c == cols - 1 {
                    canvas.fill(x: x + cell - half, y: y - half, w: t, h: cell + t)
                }
            }
        }
        func center(_ i: Int) -> (Double, Double) {
            (Double(x0 + (i % cols) * cell) + Double(cell) / 2, Double(y0 + (i / cols) * cell) + Double(cell) / 2)
        }
        // Arrows into the entrance and out of the exit.
        let (ex, _) = center(p.entrance), (sx, _) = center(p.exit)
        let aw = Double(arrow) * 0.5
        canvas.polygon([(ex - aw, Double(y0 - arrow - t)), (ex + aw, Double(y0 - arrow - t)), (ex, Double(y0 - t - 2))])
        let by = Double(y0 + rows * cell + t + 2)
        canvas.polygon([(sx - aw, by), (sx + aw, by), (sx, by + Double(arrow))])
        if solution {
            var pts = p.path.map(center)
            pts.insert((ex, Double(y0) - Double(t)), at: 0)
            pts.append((sx, Double(y0 + rows * cell) + Double(t)))
            canvas.dottedPolyline(pts, spacing: max(5, Double(cell) * 0.36), radius: max(1.8, Double(cell) * 0.13))
        }
        return canvas
    }

    // MARK: Circular

    private static func polar(_ p: MazePuzzle, counts: [Int], sheet: SheetBuilder, solution: Bool) -> Canvas {
        let rings = counts.count
        let arrow = sheet.px(16)
        let size = sheet.innerWidth
        let radius = Double(size) / 2 - Double(arrow) - 4
        let ringH = radius / Double(rings)
        let t = ringH >= 18 ? Double(max(3, sheet.px(3))) : Double(max(2, sheet.px(2)))
        let cx = Double(size) / 2, cy = Double(size) / 2
        var canvas = Canvas(width: size, height: size)
        let grid = PolarGrid(rings: rings)
        let entranceCol = grid.col(of: p.entrance)
        let twoPi = 2 * Double.pi
        let entranceSpan = twoPi / Double(counts[rings - 1])

        // Classify every pixel: on a circular wall (between rings) or on a radial wall (inside a ring).
        let ht = t / 2
        for y in 0..<size {
            let dy = Double(y) + 0.5 - cy
            for x in 0..<size {
                let dx = Double(x) + 0.5 - cx
                let r = (dx * dx + dy * dy).squareRoot()
                guard r <= radius + ht else { continue }
                var theta = atan2(dy, dx)
                if theta < 0 { theta += twoPi }
                var wall = false
                let k = Int((r / ringH).rounded())
                if k >= 1 && abs(r - Double(k) * ringH) <= ht {
                    if k == rings {
                        let a = theta - Double(entranceCol) * entranceSpan
                        wall = !(a >= 0 && a < entranceSpan)
                    } else {
                        let col = min(counts[k] - 1, Int(theta / (twoPi / Double(counts[k]))))
                        let cell = grid.id(k, col)
                        wall = !p.linked(cell, grid.parent(k, col))
                    }
                }
                if !wall {
                    // Radial walls of the ring(s) this pixel touches (± half the stroke, for clean joints).
                    for ring in Set([Int((r - ht) / ringH), Int((r + ht) / ringH)]) where ring >= 1 && ring < rings {
                        guard r >= Double(ring) * ringH - ht, r <= Double(ring + 1) * ringH + ht else { continue }
                        let span = twoPi / Double(counts[ring])
                        let j = Int((theta / span).rounded())
                        var delta = theta - Double(j) * span
                        if delta > Double.pi { delta -= twoPi }
                        if r * abs(delta) <= ht {
                            let left = grid.id(ring, j - 1), right = grid.id(ring, j)
                            if !p.linked(left, right) { wall = true; break }
                        }
                    }
                }
                if wall { canvas.px[y * size + x] = 1 }
            }
        }

        func point(_ ring: Int, _ col: Double, radius rr: Double) -> (Double, Double) {
            let a = col * twoPi / Double(counts[ring])
            return (cx + rr * cos(a), cy + rr * sin(a))
        }
        // Arrow pointing into the entrance.
        let ea = (Double(entranceCol) + 0.5) * entranceSpan
        let tipR = radius + 2, baseR = radius + Double(arrow) + 2
        let perp = ea + Double.pi / 2, aw = Double(arrow) * 0.5
        canvas.polygon([
            (cx + baseR * cos(ea) + aw * cos(perp), cy + baseR * sin(ea) + aw * sin(perp)),
            (cx + baseR * cos(ea) - aw * cos(perp), cy + baseR * sin(ea) - aw * sin(perp)),
            (cx + tipR * cos(ea), cy + tipR * sin(ea)),
        ])
        // Goal: a small star in the center.
        let starR = min(ringH * 0.62, Double(sheet.px(14)))
        var star: [(Double, Double)] = []
        for i in 0..<10 {
            let a = -Double.pi / 2 + Double(i) * Double.pi / 5
            let rr = i % 2 == 0 ? starR : starR * 0.45
            star.append((cx + rr * cos(a), cy + rr * sin(a)))
        }
        canvas.polygon(star)

        if solution {
            var pts: [(Double, Double)] = [point(rings - 1, Double(entranceCol) + 0.5, radius: radius + ht)]
            func mid(_ id: Int) -> (ring: Int, col: Double) { (grid.ring(of: id), Double(grid.col(of: id)) + 0.5) }
            for (a, b) in zip(p.path, p.path.dropFirst()) {
                let ma = mid(a), mb = mid(b)
                if mb.ring == 0 {
                    pts.append(point(ma.ring, ma.col, radius: (Double(ma.ring) + 0.5) * ringH))
                    pts.append((cx, cy))
                    continue
                }
                // Inwards or along a ring: radially to b's ring, then an arc on it. Outwards: an arc on a's
                // ring first (a's center may sit on the wall between two children), then radially to b.
                let arcRing = mb.ring <= ma.ring ? mb.ring : ma.ring
                let rr = (Double(arcRing) + 0.5) * ringH
                let angleA = ma.col / Double(counts[ma.ring]) * twoPi
                var angleB = mb.col / Double(counts[mb.ring]) * twoPi
                if angleB - angleA > Double.pi { angleB -= twoPi }
                if angleA - angleB > Double.pi { angleB += twoPi }
                let steps = max(2, Int(abs(angleB - angleA) * rr / 3))
                for s in 0...steps {
                    let a = angleA + (angleB - angleA) * Double(s) / Double(steps)
                    pts.append((cx + rr * cos(a), cy + rr * sin(a)))
                }
                if mb.ring > ma.ring { pts.append(point(mb.ring, mb.col, radius: (Double(mb.ring) + 0.5) * ringH)) }
            }
            canvas.dottedPolyline(pts, spacing: max(5, ringH * 0.4), radius: max(1.8, ringH * 0.15))
        }
        return canvas
    }
}
