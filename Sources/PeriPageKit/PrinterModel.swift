import Foundation

/// Physical characteristics of a PeriPage model, derived from the official app (see docs/PROTOCOL.md).
public struct PrinterModel: Equatable, Hashable, Sendable {
    public enum Family: String, Sendable {
        case a6 = "A6"
        case a6Plus = "A6+"
        case a6New = "A6 (PPG)"
        case a6NewHD = "A6 HD (PPG)"
    }

    public let family: Family
    /// Printable width in dots.
    public let widthDots: Int
    public let dpi: Int
    /// Distance from the print head to the tear bar: the extra feed needed to clear it (measured on a PeriPage A6).
    public let tearOffsetMM: Double
    /// Blank paper before the first printed line after tearing (tear offset + the printer's own ~1 mm
    /// advance at job start). Measured on a PeriPage A6; it cannot be reduced from the host.
    public let topMarginMM: Double
    /// Raw density values sent for (low, normal, high).
    public let densityValues: [UInt8]

    public var bytesPerRow: Int { (widthDots + 7) / 8 }
    public var dotsPerMM: Double { Double(dpi) / 25.4 }
    public var widthMM: Double { Double(widthDots) / dotsPerMM }

    public func dots(forMM mm: Double) -> Int { Int((mm * dotsPerMM).rounded()) }

    /// Feed after the last line so that `bottomMarginMM` of blank paper remains before the tear bar.
    public func feedDots(bottomMarginMM: Double) -> Int { dots(forMM: max(0, bottomMarginMM) + tearOffsetMM) }

    /// Default feed: a bottom margin equal to the top one, so the strip is symmetric after tearing.
    public var trailingFeedDots: Int { feedDots(bottomMarginMM: topMarginMM) }
    public func mm(forDots dots: Int) -> Double { Double(dots) / dotsPerMM }

    public static let a6 = PrinterModel(family: .a6, widthDots: 384, dpi: 203, tearOffsetMM: 6, topMarginMM: 7, densityValues: [0, 1, 2])
    public static let a6Plus = PrinterModel(family: .a6Plus, widthDots: 576, dpi: 300, tearOffsetMM: 6, topMarginMM: 7, densityValues: [0, 1, 2])
    public static let a6New = PrinterModel(family: .a6New, widthDots: 384, dpi: 203, tearOffsetMM: 6, topMarginMM: 7, densityValues: [0, 1, 2])
    public static let a6NewHD = PrinterModel(family: .a6NewHD, widthDots: 384, dpi: 203, tearOffsetMM: 6, topMarginMM: 7, densityValues: [0, 2, 4])

    public static let all: [PrinterModel] = [.a6, .a6Plus, .a6New, .a6NewHD]

    /// Detects the model from the Bluetooth name, mirroring the checks in the official app.
    public static func detect(bluetoothName name: String) -> PrinterModel? {
        if name.hasPrefix("PPG_A6_UHD") || name.hasPrefix("PPG_A6_UD") || name.hasPrefix("PPG_A6_HD") { return .a6NewHD }
        if name.hasPrefix("PPG_A6") { return .a6New }
        if name.hasPrefix("PeriPage+") { return .a6Plus }
        if name.wholeMatch(of: #/PeriPage_[0-9A-Fa-f]{4}(_BLE)?/#) != nil { return .a6 }
        return nil
    }

    /// True for names that look like a PeriPage device of any family.
    public static func looksLikePeriPage(_ name: String) -> Bool {
        name.hasPrefix("PeriPage") || name.hasPrefix("PPG_")
    }
}

public enum Density: Int, CaseIterable, Codable, Sendable, Identifiable {
    case low = 0, normal = 1, high = 2
    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .low: "Baja"
        case .normal: "Normal"
        case .high: "Alta"
        }
    }
}

public enum PaperType: Int, CaseIterable, Codable, Sendable, Identifiable {
    case continuous = 0
    case blackMark = 1
    case gapLabel = 2
    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .continuous: "Rollo continuo"
        case .blackMark: "Marca negra"
        case .gapLabel: "Etiquetas con gap"
        }
    }
}
