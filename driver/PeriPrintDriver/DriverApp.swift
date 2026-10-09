import AppKit
import PeriPageKit

/// Menu bar app that keeps `ippeveprinter` running and lets the user tune the driver.
@MainActor
final class DriverAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var server: Process?
    private var serverLog = ""
    private var stopping = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "printer.dotmatrix", accessibilityDescription: "PeriPrint Driver")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        Task {
            // Ask for Bluetooth up front so the first print job doesn't stall on the permission prompt.
            _ = await BluetoothAuthorization().request()
        }
        startServer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopping = true
        server?.terminate()
    }

    // MARK: Server

    private func startServer() {
        guard let executable = Bundle.main.executablePath,
              let conf = Bundle.main.path(forResource: "peripage-a6", ofType: "conf") else {
            serverLog = "Falta el archivo de configuración en el bundle"
            return
        }
        let spool = FileManager.default.temporaryDirectory.appendingPathComponent("PeriPrintDriver", isDirectory: true)
        try? FileManager.default.createDirectory(at: spool, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ippeveprinter")
        // -a can't be combined with -f/-M/-m (legacy options) in CUPS 2.3; make, model and formats come from the conf.
        var args = ["-v", "-c", executable, "-a", conf, "-p", "\(DriverSettings.port)", "-d", spool.path, "-r", "_print"]
        if let icon = Bundle.main.path(forResource: "printer-icon", ofType: "png") { args += ["-i", icon] }
        args.append("PeriPage A6")
        p.arguments = args
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            Task { @MainActor in self?.appendLog(text) }
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.stopping else { return }
                self.appendLog("ippeveprinter terminó; reiniciando en 3 s\n")
                try? await Task.sleep(for: .seconds(3))
                self.startServer()
            }
        }
        do {
            try p.run()
            server = p
        } catch {
            serverLog = "No pude iniciar ippeveprinter: \(error.localizedDescription)"
        }
    }

    private func appendLog(_ text: String) {
        DriverLog.write(text)
        serverLog += text
        if serverLog.count > 20_000 { serverLog = String(serverLog.suffix(15_000)) }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let running = server?.isRunning == true
        menu.addItem(disabledItem(running ? "● PeriPage A6 lista para imprimir" : "○ Servidor detenido"))
        if let printer = DriverSettings.printerNameBT { menu.addItem(disabledItem("Impresora: \(printer)")) }
        if let last = DriverSettings.lastJob { menu.addItem(disabledItem("Último: \(last)")) }
        menu.addItem(.separator())

        let quality = NSMenuItem(title: "Calidad", action: nil, keyEquivalent: "")
        let qualityMenu = NSMenu()
        for q in DriverSettings.Quality.allCases {
            let item = NSMenuItem(title: q.title, action: #selector(setQuality(_:)), keyEquivalent: "")
            item.representedObject = q.rawValue
            item.state = DriverSettings.quality == q ? .on : .off
            item.target = self
            qualityMenu.addItem(item)
        }
        quality.submenu = qualityMenu
        menu.addItem(quality)

        let density = NSMenuItem(title: "Densidad", action: nil, keyEquivalent: "")
        let densityMenu = NSMenu()
        for d in Density.allCases {
            let item = NSMenuItem(title: d.label, action: #selector(setDensity(_:)), keyEquivalent: "")
            item.tag = d.rawValue
            item.state = DriverSettings.density == d ? .on : .off
            item.target = self
            densityMenu.addItem(item)
        }
        density.submenu = densityMenu
        menu.addItem(density)

        menu.addItem(toggleItem("Recortar espacio en blanco", on: DriverSettings.trimBlank, action: #selector(toggleTrim)))
        menu.addItem(toggleItem("Ajustar páginas anchas a 48 mm", on: DriverSettings.fitWidth, action: #selector(toggleFit)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Agregar la impresora a macOS…", #selector(addPrinter)))
        menu.addItem(actionItem("Imprimir página de prueba", #selector(printTestPage)))
        menu.addItem(actionItem("Ver registro", #selector(showLog)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Salir de PeriPrint Driver", #selector(quit), key: "q"))
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func toggleItem(_ title: String, on: Bool, action: Selector) -> NSMenuItem {
        let item = actionItem(title, action)
        item.state = on ? .on : .off
        return item
    }

    @objc private func setQuality(_ sender: NSMenuItem) {
        DriverSettings.quality = DriverSettings.Quality(rawValue: sender.representedObject as? String ?? "") ?? .auto
    }

    @objc private func setDensity(_ sender: NSMenuItem) { DriverSettings.density = Density(rawValue: sender.tag) ?? .high }
    @objc private func toggleTrim() { DriverSettings.trimBlank.toggle() }
    @objc private func toggleFit() { DriverSettings.fitWidth.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// Creates the CUPS queue with the driverless "everywhere" model (macOS builds the PPD from IPP).
    @objc private func addPrinter() {
        let uri = "ipp://localhost:\(DriverSettings.port)/ipp/print"
        let result = run("/usr/sbin/lpadmin", ["-p", DriverSettings.printerName, "-D", "PeriPage A6", "-L", "Bluetooth",
                                                "-E", "-v", uri, "-m", "everywhere"])
        _ = run("/usr/sbin/lpadmin", ["-p", DriverSettings.printerName, "-o", "printer-is-shared=false"])
        let alert = NSAlert()
        if result.status == 0 {
            alert.messageText = "Impresora agregada"
            alert.informativeText = "Ya podés elegir “PeriPage A6” en el diálogo de impresión de cualquier app. Elegí un tamaño de papel de 48 mm (por ejemplo 48 × 100 mm) o uno largo si el contenido es largo: el blanco sobrante se recorta solo."
        } else {
            alert.messageText = "No pude agregar la impresora"
            alert.informativeText = result.output + "\nPodés agregarla a mano en Ajustes del Sistema → Impresoras y escáneres → Agregar impresora: aparece como “PeriPage A6”."
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func printTestPage() {
        let pdf = TestPage.make()
        let result = run("/usr/bin/lp", ["-d", DriverSettings.printerName, "-o", "media=om_peripage-100_48x100mm", pdf.path])
        if result.status != 0 {
            let alert = NSAlert()
            alert.messageText = "No pude enviar la página de prueba"
            alert.informativeText = result.output + "\n¿Agregaste la impresora a macOS?"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func showLog() {
        NSWorkspace.shared.open(DriverLog.url)
    }

    private func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (1, error.localizedDescription) }
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}

/// A short PDF that exercises text, lines and a gradient.
enum TestPage {
    static func make() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PeriPrint-prueba.pdf")
        var box = CGRect(x: 0, y: 0, width: 48 / 25.4 * 72, height: 60 / 25.4 * 72)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return url }
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let title = NSAttributedString(string: "PeriPrint Driver ✓", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        title.draw(at: CGPoint(x: 6, y: box.height - 22))
        let body = NSAttributedString(string: "Impreso desde el diálogo de impresión de macOS.\n\(Date().formatted())",
                                      attributes: [.font: NSFont.systemFont(ofSize: 7.5)])
        body.draw(in: CGRect(x: 6, y: box.height - 60, width: box.width - 12, height: 34))
        let gradient = NSGradient(starting: .black, ending: .white)!
        gradient.draw(in: CGRect(x: 6, y: 40, width: box.width - 12, height: 30), angle: 0)
        ctx.setLineWidth(0.5)
        for i in 0..<9 {
            let x = 6 + CGFloat(i) * (box.width - 12) / 8
            ctx.move(to: CGPoint(x: x, y: 20))
            ctx.addLine(to: CGPoint(x: x, y: i % 2 == 0 ? 32 : 27))
        }
        ctx.strokePath()
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
        return url
    }
}
