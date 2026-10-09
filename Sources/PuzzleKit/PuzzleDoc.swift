import Foundation

public enum PuzzleKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case sudoku, wordSearch, maze, nonogram, futoshiki, bridges, chess, battleship, dotsAndBoxes, ticTacToe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sudoku: "Sudoku"
        case .wordSearch: "Sopa de letras"
        case .maze: "Laberinto"
        case .nonogram: "Nonograma"
        case .futoshiki: "Futoshiki"
        case .bridges: "Puentes (Hashi)"
        case .chess: "Ajedrez: mate en 1 o 2"
        case .battleship: "Batalla naval"
        case .dotsAndBoxes: "Timbiriche"
        case .ticTacToe: "Ta-te-ti"
        }
    }

    public var icon: String {
        switch self {
        case .sudoku: "square.grid.3x3"
        case .wordSearch: "character.magnify"
        case .maze: "point.topleft.down.to.point.bottomright.curvepath"
        case .nonogram: "square.grid.4x3.fill"
        case .futoshiki: "lessthan.square"
        case .bridges: "point.3.connected.trianglepath.dotted"
        case .chess: "crown"
        case .battleship: "scope"
        case .dotsAndBoxes: "circle.grid.3x3"
        case .ticTacToe: "number"
        }
    }

    public var summary: String {
        switch self {
        case .sudoku: "Números del 1 al 9 sin repetir en filas, columnas ni cajas."
        case .wordSearch: "Encontrá las palabras escondidas en la grilla."
        case .maze: "Llegá de la entrada a la salida sin cruzar paredes."
        case .nonogram: "Pintá las casillas según los números y aparece un dibujo."
        case .futoshiki: "Un latino con signos de mayor y menor entre casillas."
        case .bridges: "Uní las islas con puentes según el número de cada una."
        case .chess: "Posiciones de partidas reales (Lichess): encontrá el mate."
        case .battleship: "Para dos: escondé tu flota y hundí la del rival."
        case .dotsAndBoxes: "Para dos: uní puntos y cerrá más cuadrados que el otro."
        case .ticTacToe: "Para dos: tableros de ta-te-ti listos para jugar."
        }
    }

    /// True for the two-player paper games, which have no solution sheet.
    public var isPaperGame: Bool { self == .battleship || self == .dotsAndBoxes || self == .ticTacToe }

    /// True when the seed changes the output (paper games are fixed layouts).
    public var usesSeed: Bool { !isPaperGame }

    public var difficulties: [PuzzleDifficulty] {
        switch self {
        case .sudoku, .maze, .chess: PuzzleDifficulty.allCases
        default: [.easy, .medium, .hard]
        }
    }

    /// Label for the difficulty control: paper games use it as a size.
    public var difficultyTitle: String { isPaperGame ? "Tamaño" : "Dificultad" }
}

public enum PuzzleDifficulty: String, CaseIterable, Codable, Identifiable, Sendable {
    case easy, medium, hard, expert
    public var id: String { rawValue }

    public var level: Int {
        switch self {
        case .easy: 0
        case .medium: 1
        case .hard: 2
        case .expert: 3
        }
    }

    public func label(for kind: PuzzleKind) -> String {
        if kind.isPaperGame {
            switch self {
            case .easy: return "Chico"
            case .medium: return "Mediano"
            case .hard, .expert: return "Grande"
            }
        }
        switch self {
        case .easy: return "Fácil"
        case .medium: return "Medio"
        case .hard: return "Difícil"
        case .expert: return "Experto"
        }
    }
}

public enum SudokuSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case classic, mini
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .classic: "9×9"
        case .mini: "6×6 (chicos)"
        }
    }
}

public enum MazeShape: String, CaseIterable, Codable, Identifiable, Sendable {
    case rectangular, circular
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .rectangular: "Rectangular"
        case .circular: "Circular"
        }
    }
}

public enum MazeStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Recursive backtracker: long winding corridors, few dead ends.
    case winding
    /// Wilson's algorithm: uniform spanning tree, many short dead ends.
    case branchy
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .winding: "Pasillos largos"
        case .branchy: "Muchas ramas"
        }
    }
}

public struct PuzzleDoc: Codable, Equatable, Sendable {
    public var kind: PuzzleKind = .sudoku
    /// Reproduces the puzzle; printed in the footer as "#seed".
    public var seed: UInt64
    public var difficulty: PuzzleDifficulty = .medium
    public var sudokuSize: SudokuSize = .classic
    public var wordTheme: WordTheme = .animals
    /// Words for `WordTheme.custom`, separated by commas, spaces or new lines.
    public var customWords: String = ""
    public var mazeShape: MazeShape = .rectangular
    public var mazeStyle: MazeStyle = .winding
    /// Futoshiki side, 4...7.
    public var futoshikiSize: Int = 5
    /// Chess: mate in 1 or 2 moves.
    public var chessMateIn: Int = 1
    /// Chess: positions per sheet, 1...3.
    public var chessCount: Int = 1

    public init() {
        seed = PuzzleDoc.randomSeed()
    }

    public init(kind: PuzzleKind, difficulty: PuzzleDifficulty = .medium, seed: UInt64) {
        self.kind = kind
        self.difficulty = difficulty
        self.seed = seed
    }

    /// New random seed (short, so the printed id is easy to type back).
    public mutating func reroll() {
        var next = PuzzleDoc.randomSeed()
        while next == seed { next = PuzzleDoc.randomSeed() }
        seed = next
    }

    static func randomSeed() -> UInt64 { UInt64.random(in: 100_000...999_999) }

    /// Difficulty levels offered for the current kind and options.
    public var availableDifficulties: [PuzzleDifficulty] {
        if kind == .sudoku && sudokuSize == .mini { return [.easy, .medium, .hard] }
        return kind.difficulties
    }

    /// Difficulty clamped to the levels the current kind offers.
    public var effectiveDifficulty: PuzzleDifficulty {
        let options = availableDifficulties
        if options.contains(difficulty) { return difficulty }
        return options.last { $0.level <= difficulty.level } ?? options[0]
    }

    /// Tolerates fields added or removed between versions, so saved documents keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PuzzleDoc(kind: .sudoku, seed: 1)
        kind = (try? c.decodeIfPresent(PuzzleKind.self, forKey: .kind)) ?? d.kind
        seed = (try? c.decodeIfPresent(UInt64.self, forKey: .seed)) ?? PuzzleDoc.randomSeed()
        difficulty = (try? c.decodeIfPresent(PuzzleDifficulty.self, forKey: .difficulty)) ?? d.difficulty
        sudokuSize = (try? c.decodeIfPresent(SudokuSize.self, forKey: .sudokuSize)) ?? d.sudokuSize
        wordTheme = (try? c.decodeIfPresent(WordTheme.self, forKey: .wordTheme)) ?? d.wordTheme
        customWords = (try? c.decodeIfPresent(String.self, forKey: .customWords)) ?? d.customWords
        mazeShape = (try? c.decodeIfPresent(MazeShape.self, forKey: .mazeShape)) ?? d.mazeShape
        mazeStyle = (try? c.decodeIfPresent(MazeStyle.self, forKey: .mazeStyle)) ?? d.mazeStyle
        futoshikiSize = (try? c.decodeIfPresent(Int.self, forKey: .futoshikiSize)) ?? d.futoshikiSize
        chessMateIn = (try? c.decodeIfPresent(Int.self, forKey: .chessMateIn)) ?? d.chessMateIn
        chessCount = (try? c.decodeIfPresent(Int.self, forKey: .chessCount)) ?? d.chessCount
    }

    /// Fields that affect generation for the current kind (the cache key).
    var generationKey: GenerationKey {
        let diff = effectiveDifficulty
        var options = ""
        switch kind {
        case .sudoku: options = sudokuSize.rawValue
        case .wordSearch: options = wordTheme == .custom ? "custom:" + customWords : wordTheme.rawValue
        case .maze: options = mazeShape.rawValue + "/" + mazeStyle.rawValue
        case .futoshiki: options = String(clampedFutoshikiSize)
        case .chess: options = "m\(clampedChessMateIn)x\(clampedChessCount)"
        default: break
        }
        return GenerationKey(kind: kind, seed: kind.usesSeed ? seed : 0, difficulty: diff, options: options)
    }

    var clampedFutoshikiSize: Int { min(7, max(4, futoshikiSize)) }
    var clampedChessMateIn: Int { min(2, max(1, chessMateIn)) }
    var clampedChessCount: Int { min(3, max(1, chessCount)) }
}

struct GenerationKey: Hashable, Sendable {
    let kind: PuzzleKind
    let seed: UInt64
    let difficulty: PuzzleDifficulty
    let options: String
}
