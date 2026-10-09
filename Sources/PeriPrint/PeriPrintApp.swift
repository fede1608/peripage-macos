import AppKit
import ResourceStore
import SwiftUI

@main
enum Main {
    static func main() {
        // `PeriPrint --render-presets <dir> [image]` writes every built-in preset as the PNG that would be printed,
        // without creating the app state (which touches Bluetooth).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-presets"), i + 1 < args.count {
            PresetExporter.run(outputDirectory: URL(fileURLWithPath: args[i + 1]),
                               imagePath: i + 2 < args.count ? args[i + 2] : nil)
            return
        }
        PeriPrintApp.main()
    }
}

struct PeriPrintApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("PeriPrint") {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowToolbarStyle(.unified)

        Window("Tienda", id: "store") {
            ResourceStoreView { image, info, destination in
                model.useResource(image, info: info, destination: destination)
            }
            .frame(minWidth: 860, minHeight: 600)
        }
        .defaultSize(width: 960, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Abrir imagen…") { NotificationCenter.default.post(name: .openImage, object: nil) }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .printItem) {
                Button("Imprimir") { Task { await model.print() } }
                    .keyboardShortcut("p")
                    .disabled(model.isPrinting)
            }
            CommandGroup(after: .newItem) {
                Button("Tienda…") { NotificationCenter.default.post(name: .openStore, object: nil) }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Button("Pegar imagen") { _ = model.pasteImage() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (swift run) instead of from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

extension Notification.Name {
    static let openImage = Notification.Name("PeriPrint.openImage")
    static let openStore = Notification.Name("PeriPrint.openStore")
}
