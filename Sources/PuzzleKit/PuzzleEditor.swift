import SwiftUI

/// Puzzle controls as Form sections, to embed in the app's `Form { … }.formStyle(.grouped)`.
public struct PuzzleEditor: View {
    @Binding private var doc: PuzzleDoc

    public init(doc: Binding<PuzzleDoc>) {
        _doc = doc
    }

    public var body: some View {
        Section("Juego") {
            Picker("Juego", selection: $doc.kind) {
                ForEach(PuzzleKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.icon).tag(kind)
                }
            }
            Text(doc.kind.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Section(doc.kind.difficultyTitle) {
            Picker(doc.kind.difficultyTitle, selection: difficulty) {
                ForEach(doc.availableDifficulties) { Text($0.label(for: doc.kind)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let detail = sizeDetail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }

        options

        if doc.kind.usesSeed {
            Section("Número de juego") {
                HStack {
                    TextField("Número", value: $doc.seed, format: .number.grouping(.never))
                        .monospacedDigit()
                        .help("El mismo número vuelve a generar el mismo juego (va impreso al pie como #número)")
                    Button {
                        doc.reroll()
                    } label: {
                        Label("Nuevo", systemImage: "dice")
                    }
                    .help("Generar otro juego")
                }
                Text("Probá con «Nuevo» hasta que te guste; la solución sale con el mismo número.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var difficulty: Binding<PuzzleDifficulty> {
        Binding(get: { doc.effectiveDifficulty }, set: { doc.difficulty = $0 })
    }

    @ViewBuilder private var options: some View {
        switch doc.kind {
        case .sudoku:
            Section("Opciones") {
                Picker("Tamaño", selection: $doc.sudokuSize) {
                    ForEach(SudokuSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        case .wordSearch:
            Section("Palabras") {
                Picker("Tema", selection: $doc.wordTheme) {
                    ForEach(WordTheme.allCases) { Text($0.label).tag($0) }
                }
                if doc.wordTheme == .custom {
                    TextField("Tus palabras", text: $doc.customWords,
                              prompt: Text("perro, gato, ñandú…"), axis: .vertical)
                        .lineLimit(3...8)
                    Text("Separalas con comas o una por renglón. Las tildes se ignoran en la grilla; la Ñ se respeta.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .maze:
            Section("Opciones") {
                Picker("Forma", selection: $doc.mazeShape) {
                    ForEach(MazeShape.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Estilo", selection: $doc.mazeStyle) {
                    ForEach(MazeStyle.allCases) { Text($0.label).tag($0) }
                }
            }
        case .futoshiki:
            Section("Opciones") {
                Stepper("Tamaño: \(doc.clampedFutoshikiSize)×\(doc.clampedFutoshikiSize)",
                        value: $doc.futoshikiSize, in: 4...7)
            }
        case .battleship:
            Section {
                Text("Imprimí una copia para cada jugador.").foregroundStyle(.secondary)
            }
        case .chess:
            Section("Opciones") {
                Picker("Mate en", selection: $doc.chessMateIn) {
                    Text("1 jugada").tag(1)
                    Text("2 jugadas").tag(2)
                }
                .pickerStyle(.segmented)
                Stepper("Posiciones por hoja: \(doc.clampedChessCount)", value: $doc.chessCount, in: 1...3)
                Text("Puzzles de partidas reales de la base abierta de Lichess (CC0).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }

    private var sizeDetail: String? {
        let d = doc.effectiveDifficulty
        switch doc.kind {
        case .nonogram:
            let s = NonogramGenerator.size(d)
            return "Grilla de \(s.cols)×\(s.rows)."
        case .bridges:
            let s = BridgesGenerator.size(d)
            return "Tablero de \(s.w)×\(s.h)."
        case .wordSearch:
            let c = WordSearchGenerator.config(d)
            return "Grilla de \(c.size)×\(c.size). \(c.hint)"
        case .sudoku:
            return doc.sudokuSize == .classic
                ? ["Solo hace falta descartar.", "Hace falta cruzar cajas con filas y columnas.",
                   "Hace falta encontrar grupos (pares, tríos…).", "Hace falta razonar en cadena."][d.level]
                : nil
        case .chess:
            return ["Rating Lichess hasta ~1100 (mate en 1) / ~1200 (mate en 2).", "Rating ~1150–1400.",
                    "Rating ~1250–1600.", "Rating alto: 1400–2400."][d.level]
        case .battleship:
            let f = PaperGameSheet.fleet(d)
            return "Tableros de \(f.grid)×\(f.grid), \(f.ships.reduce(0) { $0 + $1.count }) barcos."
        default:
            return nil
        }
    }
}
