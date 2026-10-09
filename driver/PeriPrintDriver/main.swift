import AppKit
import PeriPageKit

// PeriPrint Driver has two roles, chosen by how it is launched:
// - App mode (no arguments): a menu bar helper that runs `ippeveprinter` as a child process so macOS sees an
//   IPP Everywhere printer. Children inherit this app's Bluetooth permission, which a launchd/CUPS process lacks.
// - Job mode (`ippeveprinter -c` calls it with the spooled document path and CONTENT_TYPE set): rasterizes the
//   document for the 48 mm head and prints it over Bluetooth.

let arguments = CommandLine.arguments
let environment = ProcessInfo.processInfo.environment

if arguments.count >= 2, environment["CONTENT_TYPE"] != nil || arguments[1] == "--job" {
    let path = arguments[1] == "--job" ? arguments[2] : arguments[1]
    let contentType = environment["CONTENT_TYPE"] ?? "application/pdf"
    setvbuf(stderr, nil, _IONBF, 0)
    Task { @MainActor in
        let code = await JobRunner.run(path: path, contentType: contentType)
        exit(code)
    }
    RunLoop.main.run()
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = DriverAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
