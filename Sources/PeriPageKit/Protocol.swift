import Foundation

/// Byte-level commands understood by PeriPage A6-class printers. See docs/PROTOCOL.md.
public enum PeriPageCommand {
    public static let startJob: [UInt8] = [0x10, 0xFF, 0xFE, 0x01]
    public static let endJob: [UInt8] = [0x10, 0xFF, 0xFE, 0x45]
    public static let padding: [UInt8] = Array(repeating: 0, count: 12)
    public static let nextLabel: [UInt8] = [0x1D, 0x0C]

    public static let queryStatus: [UInt8] = [0x10, 0xFF, 0x40]
    public static let queryBattery: [UInt8] = [0x10, 0xFF, 0x50, 0xF1]
    public static let queryModel: [UInt8] = [0x10, 0xFF, 0x20, 0xF0]
    public static let queryFirmware: [UInt8] = [0x10, 0xFF, 0x20, 0xF1]
    public static let querySerial: [UInt8] = [0x10, 0xFF, 0x20, 0xF2]
    public static let queryBluetoothFirmware: [UInt8] = [0x10, 0xFF, 0x30, 0x10]
    public static let queryInfo: [UInt8] = [0x10, 0xFF, 0x70]

    public static func density(_ raw: UInt8) -> [UInt8] { [0x10, 0xFF, 0x10, 0x00, raw] }
    public static func paperType(_ type: PaperType) -> [UInt8] { [0x10, 0xFF, 0x10, 0x03, UInt8(type.rawValue)] }
    public static func autoPowerOff(minutes: Int) -> [UInt8] {
        let m = max(0, min(minutes, 0xFFFF))
        return [0x10, 0xFF, 0x12, UInt8(m >> 8), UInt8(m & 0xFF)]
    }

    /// `ESC J n`. Feeds are split because a single command carries at most 255 dots.
    public static func feed(dots: Int) -> [UInt8] {
        var out: [UInt8] = []
        var remaining = max(0, dots)
        while remaining > 0 {
            let n = min(remaining, 255)
            out += [0x1B, 0x4A, UInt8(n)]
            remaining -= n
        }
        return out
    }

    /// `GS v 0` raster header followed by the packed rows.
    public static func raster(_ bitmap: MonoBitmap) -> [UInt8] {
        let w = bitmap.bytesPerRow
        let h = bitmap.height
        precondition(h <= 0xFFFF, "raster too tall for a single GS v 0 block")
        return [0x1D, 0x76, 0x30, 0x00, UInt8(w & 0xFF), UInt8(w >> 8), UInt8(h & 0xFF), UInt8(h >> 8)] + bitmap.bytes
    }
}

public struct PrintJobOptions: Sendable, Equatable {
    public var copies: Int = 1
    /// Dots fed after the last copy. `nil` uses the model default.
    public var trailingFeedDots: Int? = nil
    /// Dots fed between copies.
    public var gapBetweenCopiesDots: Int = 0
    /// Send `GS FF` after each copy (label paper with gaps / black marks).
    public var advanceToNextLabel: Bool = false

    public init(copies: Int = 1, trailingFeedDots: Int? = nil, gapBetweenCopiesDots: Int = 0, advanceToNextLabel: Bool = false) {
        self.copies = copies
        self.trailingFeedDots = trailingFeedDots
        self.gapBetweenCopiesDots = gapBetweenCopiesDots
        self.advanceToNextLabel = advanceToNextLabel
    }
}

public enum PrintJobEncoder {
    /// The official app sends the whole image as one `GS v 0` block; only the 16-bit height field forces a split.
    public static let maxRowsPerBlock = 0xFFFF

    /// Builds the full byte stream for a print job, following the sequence used by the official app.
    public static func encode(_ bitmap: MonoBitmap, model: PrinterModel, options: PrintJobOptions = .init()) -> [UInt8] {
        var out = PeriPageCommand.startJob + PeriPageCommand.padding
        let copies = max(1, options.copies)
        for copy in 0..<copies {
            for block in bitmap.split(maxRows: maxRowsPerBlock) {
                out += PeriPageCommand.raster(block)
            }
            if options.advanceToNextLabel {
                out += PeriPageCommand.nextLabel
            } else if copy < copies - 1 {
                out += PeriPageCommand.feed(dots: options.gapBetweenCopiesDots)
            }
        }
        if !options.advanceToNextLabel {
            out += PeriPageCommand.feed(dots: options.trailingFeedDots ?? model.trailingFeedDots)
        }
        out += PeriPageCommand.endJob
        return out
    }
}

/// Asynchronous notifications the printer pushes on its own.
public enum PrinterEvent: Equatable, Sendable {
    case printFinished
    case ok
    case outOfPaper
    case coverOpen
    case coverClosed
    case overheat
    case lowBattery
    case paperError(UInt8)
    case abortSending
    case resumeSending
    case busy
    case idle

    public var message: String {
        switch self {
        case .printFinished: "Impresión terminada"
        case .ok: "OK"
        case .outOfPaper: "Sin papel"
        case .coverOpen: "Tapa abierta"
        case .coverClosed: "Tapa cerrada"
        case .overheat: "Impresora sobrecalentada"
        case .lowBattery: "Batería baja"
        case .paperError(let code): String(format: "Error de papel (0x%02X)", code)
        case .abortSending: "La impresora canceló el envío"
        case .resumeSending: "La impresora pidió continuar"
        case .busy: "Impresora ocupada"
        case .idle: "Impresora libre"
        }
    }

    public var isProblem: Bool {
        switch self {
        case .outOfPaper, .coverOpen, .overheat, .lowBattery, .paperError, .abortSending: true
        default: false
        }
    }

    /// Mirrors `y0.e.l(byte[])`: two-byte packets whose first byte is 0xFF/0xFE/0xFD are events.
    public static func parse(_ bytes: [UInt8]) -> PrinterEvent? {
        if bytes.first == 0xAA || bytes.last == 0xAA { return .printFinished }
        guard bytes.count == 2 else { return nil }
        switch (bytes[0], bytes[1]) {
        case (0x4F, 0x4B): return .ok
        case (0xFF, 0x01): return .outOfPaper
        case (0xFF, 0x02): return .coverOpen
        case (0xFF, 0x03): return .overheat
        case (0xFF, 0x04): return .lowBattery
        case (0xFF, 0x05): return .coverClosed
        case (0xFE, let code): return .paperError(code)
        case (0xFD, 0x01): return .abortSending
        case (0xFD, 0x02): return .resumeSending
        case (0xFD, 0x03): return .busy
        case (0xFD, 0x04): return .idle
        default: return nil
        }
    }
}

public struct PrinterStatus: Equatable, Sendable {
    public let raw: UInt8
    public init(raw: UInt8) { self.raw = raw }

    public var isReady: Bool { raw == 0 }
    public var descriptions: [String] {
        if raw == 0 { return ["Lista"] }
        var out: [String] = []
        if raw & 0x01 != 0 { out.append("Ocupada") }
        if raw & 0x04 != 0 { out.append("Sin papel") }
        if raw & 0x08 != 0 { out.append("Batería baja") }
        if raw & 0x10 != 0 { out.append("Sobrecalentada") }
        if out.isEmpty { out.append(String(format: "Estado 0x%02X", raw)) }
        return out
    }
}

public enum ResponseText {
    /// Firmware strings come back like `V1.2.3_xxOK`; the app strips `OK` and anything after `_`.
    public static func firmware(_ bytes: [UInt8]) -> String {
        var s = clean(bytes).replacingOccurrences(of: "OK", with: "")
        if let underscore = s.firstIndex(of: "_") { s = String(s[..<underscore]) }
        return s
    }

    public static func clean(_ bytes: [UInt8]) -> String {
        let s = String(decoding: bytes, as: UTF8.self)
        return s.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    }
}
