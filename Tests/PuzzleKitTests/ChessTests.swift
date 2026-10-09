import AppKit
import Foundation
import Testing
@testable import PuzzleKit

@Suite struct ChessTests {
    @Test func allPuzzlesParseAndPlay() throws {
        #expect(ChessLibrary.entries.count == 2000)
        for entry in ChessLibrary.entries {
            let puzzle = try #require(ChessLibrary.puzzle(from: entry), "puzzle \(entry.id)")
            #expect(puzzle.solution.count == entry.mateIn * 2 - 1, "puzzle \(entry.id)")
            // The solver moves their own pieces.
            #expect(puzzle.solution[0].piece.color == puzzle.position.sideToMove, "puzzle \(entry.id)")
        }
    }

    @Test func appliesSpecialMoves() throws {
        var castle = try #require(ChessPosition(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq -"))
        let shortMove = castle.apply(uci: "e1g1")
        let short = try #require(shortMove)
        #expect(short.castle == 1 && castle.squares[5]?.kind == "r" && castle.squares[7] == nil)
        var ep = try #require(ChessPosition(fen: "8/8/8/3pP3/8/8/8/k6K w - d6"))
        let captureMove = ep.apply(uci: "e5d6")
        let capture = try #require(captureMove)
        #expect(capture.capture && ep.squares[4 * 8 + 3] == nil)
        var promo = try #require(ChessPosition(fen: "8/4P3/8/8/8/8/8/k6K w - -"))
        let queenMove = promo.apply(uci: "e7e8q")
        let queen = try #require(queenMove)
        #expect(queen.notation(mate: true) == "e7-e8=D#" && promo.squares[63 - 3]?.kind == "q")
    }

    @Test func pickIsDeterministic() {
        let a = ChessLibrary.pick(mateIn: 2, difficulty: .hard, count: 3, seed: 99).map(\.id)
        let b = ChessLibrary.pick(mateIn: 2, difficulty: .hard, count: 3, seed: 99).map(\.id)
        #expect(a == b && Set(a).count == 3)
    }

    @Test func rendersSheets() {
        var doc = PuzzleDoc(kind: .chess, difficulty: .medium, seed: 7)
        for mate in [1, 2] {
            doc.chessMateIn = mate
            #expect(PuzzleRenderer.render(doc, widthDots: 384).width == 384)
            #expect(PuzzleRenderer.renderSolution(doc, widthDots: 384)?.width == 384)
        }
    }

    /// Writes a board with every piece when PERIPRINT_DEBUG_DIR is set (visual check).
    @Test func debugBoard() throws {
        guard let dir = ProcessInfo.processInfo.environment["PERIPRINT_DEBUG_DIR"] else { return }
        var position = try #require(ChessPosition(fen: "kqrbnp2/8/8/8/8/8/8/KQRBNP2 w - -"))
        let lastMove = position.apply(uci: "a1a2")
        let last = try #require(lastMove)
        let puzzle = ChessPuzzle(id: "debug", mateIn: 1, rating: 0, position: position, lastMove: last, solution: [last])
        let canvas = ChessSheet.board(puzzle, sheet: SheetBuilder(width: 384), highlight: nil, size: 1)
        let cg = try #require(canvas.bitmap().cgImage())
        try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("chess-pieces.png"))
    }
}
