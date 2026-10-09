import Foundation
import PeriPageKit
import PeriRender

enum Mode: String, CaseIterable, Codable, Identifiable {
    case photo, collage, sticker, label, text, banner, qr, social, games, history

    var id: String { rawValue }
    var title: String {
        switch self {
        case .photo: "Foto"
        case .collage: "Collage y fotomatón"
        case .sticker: "Stickers"
        case .label: "Etiquetas 15 mm"
        case .text: "Texto y notas"
        case .banner: "Banner"
        case .qr: "Código QR"
        case .social: "Instagram y X"
        case .games: "Juegos"
        case .history: "Historial"
        }
    }
    var icon: String {
        switch self {
        case .photo: "photo"
        case .collage: "square.grid.2x2"
        case .sticker: "seal"
        case .label: "tag"
        case .text: "text.alignleft"
        case .banner: "textformat.size.larger"
        case .qr: "qrcode"
        case .social: "bubble.left.and.text.bubble.right"
        case .games: "puzzlepiece"
        case .history: "clock.arrow.circlepath"
        }
    }
    var usesImage: Bool { self == .photo || self == .sticker }
    /// Modes that have presets (the others have their own pickers).
    var hasPresets: Bool { ![.collage, .social, .games, .history].contains(self) }

    static let sections: [(title: String, modes: [Mode])] = [
        ("Crear", [.photo, .collage, .sticker, .label, .text, .banner, .qr]),
        ("Más", [.social, .games, .history]),
    ]
}

struct PrintSettings: Codable, Equatable {
    var density: Density = .high
    var copies = 1
    /// Blank paper left between the last printed line and the tear bar (the top margin is ~7 mm).
    var bottomMarginMM: Double = 7
    var gapBetweenCopiesMM: Double = 3
    var paper: PaperType = .continuous

    init(density: Density = .high, copies: Int = 1, bottomMarginMM: Double = 7, gapBetweenCopiesMM: Double = 3,
         paper: PaperType = .continuous) {
        self.density = density
        self.copies = copies
        self.bottomMarginMM = bottomMarginMM
        self.gapBetweenCopiesMM = gapBetweenCopiesMM
        self.paper = paper
    }

    /// Tolerates fields added or removed between versions, so saved state and presets keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PrintSettings()
        density = try c.decodeIfPresent(Density.self, forKey: .density) ?? d.density
        copies = try c.decodeIfPresent(Int.self, forKey: .copies) ?? d.copies
        bottomMarginMM = try c.decodeIfPresent(Double.self, forKey: .bottomMarginMM) ?? d.bottomMarginMM
        gapBetweenCopiesMM = try c.decodeIfPresent(Double.self, forKey: .gapBetweenCopiesMM) ?? d.gapBetweenCopiesMM
        paper = try c.decodeIfPresent(PaperType.self, forKey: .paper) ?? d.paper
    }
}

enum CropAspect: String, Codable, CaseIterable, Identifiable {
    case original, square, fourThree, threeFour, sixteenNine, nineSixteen
    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: "Original"
        case .square: "1:1"
        case .fourThree: "4:3"
        case .threeFour: "3:4"
        case .sixteenNine: "16:9"
        case .nineSixteen: "9:16"
        }
    }
    /// width / height
    var ratio: Double? {
        switch self {
        case .original: nil
        case .square: 1
        case .fourThree: 4.0 / 3
        case .threeFour: 3.0 / 4
        case .sixteenNine: 16.0 / 9
        case .nineSixteen: 9.0 / 16
        }
    }
}

struct PhotoDoc: Codable, Equatable {
    var pipeline = ImagePipeline.recommendedPhoto
    var crop: CropAspect = .original
    var widthPercent: Double = 100
    var frame: DecorativeFrame = .none
    var caption = ""
    var captionSize: Double = 24
    var dateStamp = false
}

enum StickerOutline: String, Codable, CaseIterable, Identifiable {
    case none, cutLine, contour
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Ninguno"
        case .cutLine: "Línea de corte"
        case .contour: "Contorno (PNG sin fondo)"
        }
    }
}

struct StickerDoc: Codable, Equatable {
    var pipeline = ImagePipeline.recommendedPhoto
    var widthMM: Double = 40
    var columns = 1
    var count = 1
    var gapMM: Double = 3
    var outline: StickerOutline = .cutLine
    var contourWidth: Double = 6
    /// Treat near-white pixels as transparent when building the contour.
    var whiteIsTransparent = false
    /// Decorative frame around each sticker (inside the cut line).
    var decor: DecorativeFrame = .none
}

enum TextTemplate: String, Codable, CaseIterable, Identifiable {
    case free, note, checklist, label
    var id: String { rawValue }
    var label: String {
        switch self {
        case .free: "Libre"
        case .note: "Nota"
        case .checklist: "Lista de tareas"
        case .label: "Etiqueta"
        }
    }
}

struct TextDoc: Codable, Equatable {
    var template: TextTemplate = .free
    var title = ""
    var body = "Hola 👋"
    var fontFamily = "Helvetica Neue"
    var fontSize: Double = 32
    var bold = false
    var align: TextAlign = .left
    var invert = false
    var frame: DecorativeFrame = .none
    var dateStamp = false
    var lineSpacing: Double = 0
}

enum CollageLayout: String, Codable, CaseIterable, Identifiable {
    case strip, grid, pairs
    var id: String { rawValue }
    var title: String {
        switch self {
        case .strip: "Tira de fotomatón"
        case .grid: "Grilla 2 columnas"
        case .pairs: "De a dos, apaisadas"
        }
    }
}

struct CollageDoc: Codable, Equatable {
    var layout: CollageLayout = .strip
    var pipeline = ImagePipeline.recommendedPhoto
    var spacingMM: Double = 2
    var frame: DecorativeFrame = .thin
    var caption = ""
    var dateStamp = true
}

enum LabelContent: String, Codable, CaseIterable, Identifiable {
    case text, iconText, qrText, barcode, image
    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: "Texto"
        case .iconText: "Ícono + texto"
        case .qrText: "QR + texto"
        case .barcode: "Código de barras"
        case .image: "Imagen"
        }
    }
}

/// Die-cut labels: `heightMM` tall, separated by `gapMM` of backing paper.
struct LabelDoc: Codable, Equatable {
    var content: LabelContent = .text
    /// One label per non-empty line.
    var lines = "Azúcar\nCafé\nYerba"
    /// Second, smaller line printed on every label.
    var subtitle = ""
    var dateStamp = false
    var fontFamily = "Avenir Next"
    var bold = true
    var align: TextAlign = .center
    var frame: DecorativeFrame = .rounded
    var invert = false
    var copies = 1
    /// SF Symbol used by `.iconText` when no image was picked from the store.
    var symbol = "leaf.fill"
    var pipeline = ImagePipeline(adjustments: .init(threshold: 0.55), algorithm: .threshold)
    var heightMM: Double = 15
    var gapMM: Double = 7.5
    /// Fine position adjustment; positive moves the print further into the label.
    var adjustMM: Double = 0
}

struct BannerDoc: Codable, Equatable {
    var text = "FELIZ CUMPLE"
    var fontFamily = "Helvetica Neue"
    var bold = true
    var heightPercent: Double = 90
    var letterSpacing: Double = 0
    var invert = false
    var border = false
}

enum QRKind: String, Codable, CaseIterable, Identifiable {
    case text, wifi
    var id: String { rawValue }
    var label: String { self == .text ? "Texto / URL" : "Wi-Fi" }
}

struct QRDoc: Codable, Equatable {
    var kind: QRKind = .text
    var content = "https://"
    var wifiSSID = ""
    var wifiPassword = ""
    var caption = ""
    var sizePercent: Double = 80
    var correction = "M"

    var payload: String {
        switch kind {
        case .text: return content
        case .wifi:
            func esc(_ s: String) -> String {
                s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
                    .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: ":", with: "\\:")
            }
            let security = wifiPassword.isEmpty ? "nopass" : "WPA"
            return "WIFI:T:\(security);S:\(esc(wifiSSID));P:\(esc(wifiPassword));;"
        }
    }
}

struct Preset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var mode: Mode
    var builtIn = false
    var settings = PrintSettings()
    var photo: PhotoDoc?
    var sticker: StickerDoc?
    var text: TextDoc?
    var banner: BannerDoc?
    var qr: QRDoc?
    var label: LabelDoc?
}

extension Preset {
    static let builtIns: [Preset] = {
        var list: [Preset] = []
        func add(_ name: String, _ mode: Mode, settings: PrintSettings = .init(), configure: (inout Preset) -> Void) {
            var p = Preset(name: name, mode: mode, builtIn: true, settings: settings)
            configure(&p)
            list.append(p)
        }

        add("Foto", .photo) { $0.photo = PhotoDoc() }
        add("Foto con más detalle (F–S)", .photo) {
            var d = PhotoDoc()
            d.pipeline = ImagePipeline(adjustments: .recommendedPhoto, algorithm: .floydSteinberg)
            $0.photo = d
        }
        add("Polaroid", .photo) {
            var d = PhotoDoc()
            d.crop = .square
            d.frame = .polaroid
            d.dateStamp = true
            $0.photo = d
        }
        add("Retro (semitono)", .photo) {
            var d = PhotoDoc()
            d.pipeline = ImagePipeline(adjustments: .init(contrast: 1.2, gamma: 1.1, autoLevels: true), algorithm: .halftone)
            $0.photo = d
        }
        add("Logo / dibujo", .photo) {
            var d = PhotoDoc()
            d.pipeline = ImagePipeline(adjustments: .init(threshold: 0.55), algorithm: .threshold)
            d.widthPercent = 80
            $0.photo = d
        }

        add("Sticker 4 cm", .sticker) { $0.sticker = StickerDoc() }
        add("Mini stickers ×9", .sticker) {
            var d = StickerDoc()
            d.widthMM = 14
            d.columns = 3
            d.count = 9
            d.gapMM = 2
            $0.sticker = d
        }
        add("Sticker con contorno", .sticker) {
            var d = StickerDoc()
            d.outline = .contour
            d.widthMM = 45
            $0.sticker = d
        }
        add("Transparente (espejado)", .sticker) {
            var d = StickerDoc()
            d.pipeline.transform.mirrored = true
            d.outline = .none
            $0.sticker = d
        }

        add("Frascos de cocina", .label) { $0.label = LabelDoc() }
        add("Con ícono", .label) {
            var d = LabelDoc()
            d.content = .iconText
            d.frame = .thin
            d.align = .left
            $0.label = d
        }
        add("Fecha de elaboración", .label) {
            var d = LabelDoc()
            d.subtitle = "Elaborado"
            d.dateStamp = true
            d.frame = .double
            $0.label = d
        }
        add("QR + texto", .label) {
            var d = LabelDoc()
            d.content = .qrText
            d.frame = .none
            d.align = .left
            $0.label = d
        }
        add("Código de barras", .label) {
            var d = LabelDoc()
            d.content = .barcode
            d.frame = .none
            $0.label = d
        }
        add("Invertida", .label) {
            var d = LabelDoc()
            d.invert = true
            d.frame = .none
            d.fontFamily = "Futura"
            $0.label = d
        }
        add("Decorada", .label) {
            var d = LabelDoc()
            d.frame = .stars
            d.fontFamily = "Snell Roundhand"
            $0.label = d
        }

        add("Nota rápida", .text) {
            var d = TextDoc()
            d.template = .note
            d.title = "Nota"
            d.body = "Escribí acá…"
            d.fontSize = 26
            d.dateStamp = true
            $0.text = d
        }
        add("Lista de tareas", .text) {
            var d = TextDoc()
            d.template = .checklist
            d.title = "Para hoy"
            d.body = "Comprar café\nLlamar a mamá\nRegar las plantas"
            d.fontSize = 26
            $0.text = d
        }
        add("Etiqueta grande", .text) {
            var d = TextDoc()
            d.template = .label
            d.body = "CONDIMENTOS"
            d.bold = true
            d.align = .center
            d.frame = .rounded
            $0.text = d
        }
        add("Ticket invertido", .text) {
            var d = TextDoc()
            d.body = "¡GRACIAS!"
            d.fontSize = 56
            d.bold = true
            d.align = .center
            d.invert = true
            $0.text = d
        }

        add("Banner", .banner) { $0.banner = BannerDoc() }
        add("Banner con borde", .banner) {
            var d = BannerDoc()
            d.border = true
            d.heightPercent = 75
            $0.banner = d
        }

        add("QR", .qr) { $0.qr = QRDoc() }
        add("Wi-Fi para invitados", .qr) {
            var d = QRDoc()
            d.kind = .wifi
            d.caption = "Escaneá para conectarte al Wi-Fi"
            $0.qr = d
        }
        return list
    }()
}
