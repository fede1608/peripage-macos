import AppKit
import PeriPageKit
import PeriRender
import PuzzleKit
import SocialKit

/// Debug helper: renders each built-in preset to PNG without touching the printer.
enum PresetExporter {
    static func run(outputDirectory: URL, imagePath: String?) {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        exportFrames(to: outputDirectory)
        exportChess(to: outputDirectory)
        exportLabelsOffMain(to: outputDirectory)
        let image = imagePath.flatMap { NSImage(contentsOfFile: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        for preset in Preset.builtIns {
            let input = Renderer.Input(
                mode: preset.mode,
                photo: preset.photo ?? PhotoDoc(),
                sticker: preset.sticker ?? StickerDoc(),
                text: preset.text ?? TextDoc(),
                banner: preset.banner ?? BannerDoc(),
                qr: { var q = preset.qr ?? QRDoc(); if q.kind == .wifi { q.wifiSSID = "MiCasa"; q.wifiPassword = "clave123" } else { q.content = "https://example.com" }; return q }(),
                label: preset.label ?? LabelDoc(),
                collage: CollageDoc(),
                collageImages: image.map { [$0, $0, $0] } ?? [],
                puzzle: PuzzleDoc(),
                social: SocialDoc(),
                socialPost: nil,
                image: image,
                labelImage: image,
                history: nil,
                model: .a6
            )
            let start = Date()
            guard let bitmap = Renderer.render(input), let cg = bitmap.cgImage() else {
                print("✗ \(preset.name): sin resultado")
                continue
            }
            let file = outputDirectory.appendingPathComponent("\(preset.mode.rawValue)-\(preset.name).png")
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: file)
            print(String(format: "✓ %@ %d×%d (%.0f ms)", preset.name, bitmap.width, bitmap.height, Date().timeIntervalSince(start) * 1000))
        }
    }

    static func exportFrames(to dir: URL) {
        var tiles: [MonoBitmap] = []
        for frame in DecorativeFrame.allCases where frame != .none {
            let inner = frame.contentWidth(for: 384)
            let text = TextRenderer.render(frame.title, font: TextRenderer.font(family: "Georgia", size: 26, bold: true), align: .center, width: inner)
                .padded(top: 16, bottom: 16)
            tiles.append(frame.apply(to: text, width: 384))
        }
        let sheet = MonoBitmap.stack(tiles, width: 384, spacing: 12)
        if let cg = sheet.cgImage() {
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("frames.png"))
            print("✓ frames.png \(sheet.height) px")
        }
    }

    static func exportChess(to dir: URL) {
        for mate in [1, 2] {
            for diff in [PuzzleDifficulty.easy, .expert] {
                var doc = PuzzleDoc(kind: .chess, difficulty: diff, seed: 424242)
                doc.chessMateIn = mate
                let sheets = [("", PuzzleRenderer.render(doc, widthDots: 384)), ("-sol", PuzzleRenderer.renderSolution(doc, widthDots: 384))]
                for (suffix, bitmap) in sheets {
                    guard let cg = bitmap?.cgImage() else { continue }
                    let url = dir.appendingPathComponent("chess-m\(mate)-\(diff.rawValue)\(suffix).png")
                    try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
                }
            }
        }
        print("✓ chess sheets")
    }

    /// Label presets rendered the way the app does it: off the main thread and without a picked image,
    /// so SF Symbol icons are exercised.
    static func exportLabelsOffMain(to dir: URL) {
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            for preset in Preset.builtIns where preset.mode == .label {
                let doc = preset.label ?? LabelDoc()
                guard let bitmap = Renderer.labels(doc, image: nil, model: .a6), let cg = bitmap.cgImage() else { continue }
                let url = dir.appendingPathComponent("label-noimage-\(preset.name).png")
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
            }
            done.signal()
        }
        done.wait()
        print("✓ label presets off main")
    }
}
