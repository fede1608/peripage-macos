import Foundation
import PeriPageKit

/// Settings shared by the menu bar app and job processes (same bundle → same defaults domain).
enum DriverSettings {
    enum Quality: String, CaseIterable {
        case auto, text, photo
        var title: String {
            switch self {
            case .auto: "Automática"
            case .text: "Texto (nítido)"
            case .photo: "Fotos (trama)"
            }
        }
    }

    static let defaults = UserDefaults.standard
    /// The PeriPrint app remembers the printer; the driver reuses it.
    static let appDefaults = UserDefaults(suiteName: "app.periprint.PeriPrint")

    static let printerName = "PeriPage_A6"
    static let port = 8631

    static var quality: Quality {
        get { Quality(rawValue: defaults.string(forKey: "quality") ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "quality") }
    }

    static var density: Density {
        get { Density(rawValue: defaults.object(forKey: "density") as? Int ?? Density.high.rawValue) ?? .high }
        set { defaults.set(newValue.rawValue, forKey: "density") }
    }

    /// Removes blank space above and below the content of each page.
    static var trimBlank: Bool {
        get { defaults.object(forKey: "trimBlank") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "trimBlank") }
    }

    /// Crops side margins of wide pages (A4, Letter) so the content uses the full 48 mm.
    static var fitWidth: Bool {
        get { defaults.object(forKey: "fitWidth") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fitWidth") }
    }

    static var bottomMarginMM: Double {
        get { defaults.object(forKey: "bottomMarginMM") as? Double ?? 7 }
        set { defaults.set(newValue, forKey: "bottomMarginMM") }
    }

    static var printerAddress: String? {
        defaults.string(forKey: "printerAddress") ?? appDefaults?.string(forKey: "printer.address")
    }

    static var printerNameBT: String? {
        defaults.string(forKey: "printerBTName") ?? appDefaults?.string(forKey: "printer.name")
    }

    static var lastJob: String? {
        get { defaults.string(forKey: "lastJob") }
        set { defaults.set(newValue, forKey: "lastJob") }
    }
}

/// Persistent log at ~/Library/Logs/PeriPrint Driver.log (server output and every job's messages).
enum DriverLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/PeriPrint Driver.log")

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { "\(stamp.string(from: .now))  \($0)\n" }.joined()
        guard let data = lines.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
        trimIfNeeded()
    }

    /// Keeps the file under ~1 MB.
    private static func trimIfNeeded() {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000,
              let data = try? Data(contentsOf: url) else { return }
        try? data.suffix(500_000).write(to: url)
    }
}

/// Coordination with the PeriPrint app, which keeps the RFCOMM link open while it runs.
enum PrinterHandoff {
    static let releaseRequest = Notification.Name("app.periprint.releasePrinter")
    static let released = Notification.Name("app.periprint.printerReleased")
}
