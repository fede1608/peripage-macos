#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: `PERIPRINT_SNAPSHOT=<dir> [PERIPRINT_SAMPLE_IMAGE=<img>] swift run PeriPrint`
/// captures the main window in every mode to PNG files and quits. Bluetooth is not touched.
enum DebugSnapshot {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["PERIPRINT_SNAPSHOT"].map { URL(fileURLWithPath: $0) }
    }

    @MainActor
    static func run(model: AppModel) async {
        guard let dir = directory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let path = ProcessInfo.processInfo.environment["PERIPRINT_SAMPLE_IMAGE"] {
            model.loadImage(from: URL(fileURLWithPath: path))
        }
        for mode in Mode.allCases {
            model.mode = mode
            try? await Task.sleep(for: .milliseconds(900))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("ui-\(mode.rawValue).png"))
        }
        NSApp.terminate(nil)
    }
}
#endif
