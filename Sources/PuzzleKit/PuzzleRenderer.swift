import Foundation
import PeriPageKit

public enum PuzzleRenderer {
    /// Puzzle sheet exactly `widthDots` wide: title, short instructions, the puzzle, footer with an id (#seed) to reproduce it.
    public static func render(_ doc: PuzzleDoc, widthDots: Int) -> MonoBitmap {
        // AppKit text drawing autoreleases; drain per sheet since callers run on background threads.
        autoreleasepool { renderSheet(doc, width: max(200, widthDots)) }
    }

    /// Solution sheet (same id), or nil for games without a solution.
    public static func renderSolution(_ doc: PuzzleDoc, widthDots: Int) -> MonoBitmap? {
        autoreleasepool { renderSolutionSheet(doc, width: max(200, widthDots)) }
    }

    private static func renderSheet(_ doc: PuzzleDoc, width: Int) -> MonoBitmap {
        switch generated(doc) {
        case .sudoku(let p): return SudokuSheet.render(doc, p, width: width, solution: false)
        case .wordSearch(let p): return WordSearchSheet.render(doc, p, width: width, solution: false)
        case .maze(let p): return MazeSheet.render(doc, p, width: width, solution: false)
        case .nonogram(let p): return NonogramSheet.render(doc, p, width: width, solution: false)
        case .futoshiki(let p): return FutoshikiSheet.render(doc, p, width: width, solution: false)
        case .bridges(let p): return BridgesSheet.render(doc, p, width: width, solution: false)
        case .chess(let p): return ChessSheet.render(doc, p, width: width, solution: false)
        case .paperGame: return PaperGameSheet.render(doc, width: width)
        }
    }

    private static func renderSolutionSheet(_ doc: PuzzleDoc, width: Int) -> MonoBitmap? {
        switch generated(doc) {
        case .sudoku(let p): return SudokuSheet.render(doc, p, width: width, solution: true)
        case .wordSearch(let p): return WordSearchSheet.render(doc, p, width: width, solution: true)
        case .maze(let p): return MazeSheet.render(doc, p, width: width, solution: true)
        case .nonogram(let p): return NonogramSheet.render(doc, p, width: width, solution: true)
        case .futoshiki(let p): return FutoshikiSheet.render(doc, p, width: width, solution: true)
        case .bridges(let p): return BridgesSheet.render(doc, p, width: width, solution: true)
        case .chess(let p): return ChessSheet.render(doc, p, width: width, solution: true)
        case .paperGame: return nil
        }
    }

    /// The generated puzzle for `doc`, from the cache when possible.
    static func generated(_ doc: PuzzleDoc) -> GeneratedPuzzle {
        PuzzleCache.shared.value(for: doc.generationKey) { generate(doc) }
    }

    static func generate(_ doc: PuzzleDoc) -> GeneratedPuzzle {
        let diff = doc.effectiveDifficulty
        switch doc.kind {
        case .sudoku:
            return .sudoku(SudokuGenerator.generate(size: doc.sudokuSize, difficulty: diff, seed: doc.seed))
        case .wordSearch:
            return .wordSearch(WordSearchGenerator.generate(theme: doc.wordTheme, customWords: doc.customWords,
                                                            difficulty: diff, seed: doc.seed))
        case .maze:
            return .maze(MazeGenerator.generate(shape: doc.mazeShape, style: doc.mazeStyle, difficulty: diff, seed: doc.seed))
        case .nonogram:
            return .nonogram(NonogramGenerator.generate(difficulty: diff, seed: doc.seed))
        case .futoshiki:
            return .futoshiki(FutoshikiGenerator.generate(size: doc.clampedFutoshikiSize, difficulty: diff, seed: doc.seed))
        case .bridges:
            return .bridges(BridgesGenerator.generate(difficulty: diff, seed: doc.seed))
        case .chess:
            return .chess(ChessLibrary.pick(mateIn: doc.clampedChessMateIn, difficulty: diff, count: doc.clampedChessCount, seed: doc.seed))
        case .battleship, .dotsAndBoxes, .ticTacToe:
            return .paperGame
        }
    }
}

enum GeneratedPuzzle: Sendable {
    case sudoku(SudokuPuzzle)
    case wordSearch(WordSearchPuzzle)
    case maze(MazePuzzle)
    case nonogram(NonogramPuzzle)
    case futoshiki(FutoshikiPuzzle)
    case bridges(BridgesPuzzle)
    case chess([ChessPuzzle])
    case paperGame
}

/// Small thread-safe cache of generated puzzles keyed by the generation-relevant fields.
/// Generation runs outside the lock; two threads asking for the same new key may both generate it
/// (the results are identical, generation is deterministic).
final class PuzzleCache: @unchecked Sendable {
    static let shared = PuzzleCache()

    private let lock = NSLock()
    private var entries: [GenerationKey: GeneratedPuzzle] = [:]
    private var order: [GenerationKey] = []
    private let capacity = 40

    func value(for key: GenerationKey, make: () -> GeneratedPuzzle) -> GeneratedPuzzle {
        lock.lock()
        if let hit = entries[key] {
            if let i = order.firstIndex(of: key) { order.remove(at: i) }
            order.append(key)
            lock.unlock()
            return hit
        }
        lock.unlock()

        let made = make()

        lock.lock()
        defer { lock.unlock() }
        if entries[key] == nil {
            entries[key] = made
            order.append(key)
            while order.count > capacity { entries[order.removeFirst()] = nil }
        }
        return made
    }

    func removeAll() {
        lock.lock()
        entries.removeAll()
        order.removeAll()
        lock.unlock()
    }
}
