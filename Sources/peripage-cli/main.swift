import AppKit
import Foundation
import PeriPageKit

let usage = """
uso: peripage <comando> [opciones]

  list                         Impresoras PeriPage emparejadas
  scan                         Busca impresoras cercanas (10 s)
  info    [-a MAC]             Batería, estado, firmware y número de serie
  print   [-a MAC] <imagen>    Imprime una imagen
  preview <imagen> <salida.png> Genera la vista previa 1-bit sin imprimir
  raw     [-a MAC] <hex…>      Envía bytes crudos y muestra la respuesta

opciones de imagen:
  --model a6|a6plus|a6new|a6hd   (preview; al imprimir se detecta por nombre)
  --dither atkinson|floydSteinberg|stucki|bayer|halftone|threshold
  --brightness -1…1  --contrast 0…3  --gamma 0.3…3  --sharpen 0…3  --threshold 0…1
  --auto-levels  --invert  --rotate 0|90|180|270  --mirror
  --density low|normal|high  --copies N  --margin MM (margen inferior, def. 7)  --feed DOTS  --verbose
"""

struct Options {
    var address: String?
    var positional: [String] = []
    var values: [String: String] = [:]
    var flags: Set<String> = []

    init(_ args: ArraySlice<String>) {
        var it = args.makeIterator()
        let booleanFlags: Set<String> = ["--auto-levels", "--invert", "--mirror", "--verbose"]
        while let arg = it.next() {
            if arg == "-a" { address = it.next() }
            else if booleanFlags.contains(arg) { flags.insert(arg) }
            else if arg.hasPrefix("--") { values[arg] = it.next() }
            else { positional.append(arg) }
        }
    }

    func double(_ key: String) -> Double? { values[key].flatMap(Double.init) }
    func int(_ key: String) -> Int? { values[key].flatMap(Int.init) }

    var pipeline: ImagePipeline {
        var p = ImagePipeline.recommendedPhoto
        if let d = values["--dither"].flatMap(DitherAlgorithm.init(rawValue:)) { p.algorithm = d }
        if let v = double("--brightness") { p.adjustments.brightness = v }
        if let v = double("--contrast") { p.adjustments.contrast = v }
        if let v = double("--gamma") { p.adjustments.gamma = v }
        if let v = double("--sharpen") { p.adjustments.sharpen = v }
        if let v = double("--threshold") { p.adjustments.threshold = v }
        if flags.contains("--auto-levels") { p.adjustments.autoLevels = true }
        p.adjustments.invert = flags.contains("--invert")
        p.transform.mirrored = flags.contains("--mirror")
        if let deg = int("--rotate") { p.transform.rotation = ImageTransform.Rotation(rawValue: (deg / 90) % 4) ?? .none }
        return p
    }

    var model: PrinterModel {
        switch values["--model"] {
        case "a6plus": .a6Plus
        case "a6new": .a6New
        case "a6hd": .a6NewHD
        default: .a6
        }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func loadImage(_ path: String) -> CGImage {
    guard let image = NSImage(contentsOfFile: path),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fail("No pude abrir la imagen \(path)") }
    return cg
}

func savePNG(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { fail("No pude generar PNG") }
    do { try data.write(to: URL(fileURLWithPath: path)) } catch { fail("No pude escribir \(path): \(error)") }
}

@MainActor
func connectPrinter(_ opts: Options) async throws -> PeriPagePrinter {
    let target: BluetoothDeviceInfo
    if let address = opts.address {
        target = BluetoothDirectory.pairedPrinters().first { $0.address.caseInsensitiveCompare(address) == .orderedSame }
            ?? BluetoothDeviceInfo.placeholder(address: address)
    } else {
        guard let first = BluetoothDirectory.pairedPrinters().first else {
            fail("No hay impresoras PeriPage emparejadas. Emparejala en Ajustes → Bluetooth o usá -a MAC.")
        }
        target = first
    }
    // If the PeriPrint app holds the printer, ask it to let go first.
    DistributedNotificationCenter.default().postNotificationName(Notification.Name("app.periprint.releasePrinter"),
                                                                 object: nil, userInfo: nil, deliverImmediately: true)
    try? await Task.sleep(for: .milliseconds(800))
    let printer = try PeriPagePrinter(address: target.address, name: target.name)
    if opts.flags.contains("--verbose") { printer.onLog = { print("  [bt] \($0)") } }
    printer.onEvent = { print("  [evento] \($0.message)") }
    print("→ \(printer.name) (\(printer.address)) · modelo \(printer.model.family.rawValue), \(printer.model.widthDots) px")
    try await printer.connect()
    return printer
}

@MainActor
func run() async throws {
    let args = CommandLine.arguments
    guard args.count >= 2 else { print(usage); exit(0) }
    let opts = Options(args.dropFirst(2))
    if args[1] != "preview" {
        switch await BluetoothAuthorization().request() {
        case .allowed: break
        case .poweredOff: fail("Bluetooth está apagado")
        case .denied: fail("Sin permiso de Bluetooth para la Terminal (Ajustes → Privacidad y seguridad → Bluetooth)")
        case .unsupported: fail("Bluetooth no soportado")
        }
    }

    switch args[1] {
    case "list":
        let printers = BluetoothDirectory.pairedPrinters()
        if printers.isEmpty { print("No hay impresoras PeriPage emparejadas.") }
        for p in printers {
            print("\(p.address)  \(p.name)  \(p.model?.family.rawValue ?? "desconocido")\(p.isConnected ? "  (conectada)" : "")")
        }

    case "scan":
        print("Buscando 10 s…")
        let scanner = PrinterScanner()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            scanner.onUpdate = { list in if let last = list.last { print("  \(last.address)  \(last.name)") } }
            scanner.onFinish = { cont.resume() }
            scanner.start()
        }
        if scanner.found.isEmpty { print("No encontré impresoras. ¿Está prendida?") }

    case "info":
        let printer = try await connectPrinter(opts)
        defer { printer.disconnect() }
        if let v = try? await printer.batteryPercent() { print("Batería: \(v)%") }
        if let s = try? await printer.status() { print("Estado: \(s.descriptions.joined(separator: ", ")) (0x\(String(format: "%02X", s.raw)))") }
        if let v = try? await printer.firmwareVersion() { print("Firmware: \(v)") }
        if let v = try? await printer.serialNumber() { print("Serie: \(v)") }
        if let v = try? await printer.modelName() { print("Modelo reportado: \(v)") }

    case "preview":
        guard opts.positional.count >= 2 else { fail(usage) }
        let model = opts.model
        guard let bitmap = opts.pipeline.render(loadImage(opts.positional[0]), width: model.widthDots),
              let cg = bitmap.cgImage() else { fail("No pude procesar la imagen") }
        savePNG(cg, to: opts.positional[1])
        print("Vista previa \(bitmap.width)×\(bitmap.height) px (\(String(format: "%.1f", model.mm(forDots: bitmap.height))) mm) → \(opts.positional[1])")

    case "print":
        guard let path = opts.positional.first else { fail(usage) }
        let image = loadImage(path)
        let printer = try await connectPrinter(opts)
        defer { printer.disconnect() }
        guard let bitmap = opts.pipeline.render(image, width: printer.model.widthDots) else { fail("No pude procesar la imagen") }
        let density = opts.values["--density"].flatMap { ["low": Density.low, "normal": .normal, "high": .high][$0] } ?? .high
        let ok = try await printer.setDensity(density)
        print("Densidad \(density.label): \(ok ? "OK" : "sin confirmación")")
        var jobOptions = PrintJobOptions(copies: opts.int("--copies") ?? 1)
        jobOptions.trailingFeedDots = opts.int("--feed") ?? printer.model.feedDots(bottomMarginMM: opts.double("--margin") ?? printer.model.topMarginMM)
        var lastShown = -1
        try await printer.print(bitmap, options: jobOptions) { fraction in
            let pct = Int(fraction * 100)
            if pct / 10 != lastShown / 10 { print("  enviado \(pct)%"); lastShown = pct }
        }
        print("Listo: \(bitmap.height) filas (\(String(format: "%.1f", printer.model.mm(forDots: bitmap.height))) mm)")

    case "raw":
        let bytes = opts.positional.joined().replacingOccurrences(of: " ", with: "")
        guard bytes.count % 2 == 0, !bytes.isEmpty else { fail("hex inválido") }
        let data: [UInt8] = stride(from: 0, to: bytes.count, by: 2).compactMap {
            let s = bytes.index(bytes.startIndex, offsetBy: $0)
            return UInt8(bytes[s..<bytes.index(s, offsetBy: 2)], radix: 16)
        }
        let printer = try await connectPrinter(opts)
        defer { printer.disconnect() }
        let reply = try await printer.request(data, timeout: 1.5) { _ in false }
        print("← " + reply.map { String(format: "%02X", $0) }.joined(separator: " ") + "  \"\(ResponseText.clean(reply))\"")

    default:
        print(usage)
    }
}

extension BluetoothDeviceInfo {
    static func placeholder(address: String) -> BluetoothDeviceInfo {
        guard let info = BluetoothDirectory.device(address: address) else { fail("No encontré \(address)") }
        return info
    }
}

setvbuf(stdout, nil, _IOLBF, 0)
Task { @MainActor in
    do { try await run() } catch { fail("Error: \(error.localizedDescription)") }
    exit(0)
}
RunLoop.main.run()
