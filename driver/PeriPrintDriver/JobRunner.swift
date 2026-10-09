import AppKit
import CoreGraphics
import ImageIO
import PeriPageKit

/// Prints one spooled document. Messages on stderr use ippeveprinter's protocol (INFO:/ERROR:/STATE:).
@MainActor
enum JobRunner {
    static func run(path: String, contentType: String) async -> Int32 {
        let model = PrinterModel.detect(bluetoothName: DriverSettings.printerNameBT ?? "") ?? .a6
        let copies = max(1, Int(ProcessInfo.processInfo.environment["IPP_COPIES"] ?? "") ?? 1)
        let jobName = ProcessInfo.processInfo.environment["IPP_JOB_NAME"] ?? URL(fileURLWithPath: path).lastPathComponent

        info("Preparando \(jobName)")
        guard let pages = Rasterizer.pages(path: path, contentType: contentType, model: model), !pages.isEmpty else {
            error("No pude leer el documento (\(contentType))")
            return 1
        }
        let bitmap = MonoBitmap.stack(pages, width: model.widthDots, spacing: model.dots(forMM: 4))
        guard bitmap.height > 0 else {
            info("El documento está en blanco; no hay nada para imprimir")
            return 0
        }
        // Development aid: write the strip as PNG instead of printing.
        if let dir = ProcessInfo.processInfo.environment["PERIPRINT_DRIVER_DRYRUN"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("job-\(Int(Date().timeIntervalSince1970)).png")
            if let cg = bitmap.cgImage() { try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url) }
            info("Simulado: \(url.path) (\(bitmap.width)×\(bitmap.height))")
            return 0
        }
        if bitmap.height > model.dots(forMM: 3000) {
            error("El documento mide más de 3 m impreso; cancelado para no gastar el rollo")
            return 1
        }

        guard let address = DriverSettings.printerAddress else {
            error("No hay impresora configurada: abrí PeriPrint y conectate una vez")
            return 1
        }
        info("Pidiendo permiso de Bluetooth…")
        switch await authorization(timeout: 20) {
        case .allowed?: info("Bluetooth: permiso OK")
        case .poweredOff?:
            error("Bluetooth está apagado")
            return 1
        case nil:
            error("macOS no respondió el permiso de Bluetooth. Abrí Ajustes → Privacidad y seguridad → Bluetooth y activá PeriPrint Driver.")
            return 1
        default:
            error("PeriPrint Driver no tiene permiso de Bluetooth (Ajustes → Privacidad y seguridad → Bluetooth)")
            return 1
        }

        info("Impresora: \(DriverSettings.printerNameBT ?? "?") [\(address)]")
        // Ask the PeriPrint app to let go of the printer, then connect.
        DistributedNotificationCenter.default().postNotificationName(PrinterHandoff.releaseRequest, object: nil, userInfo: nil, deliverImmediately: true)
        try? await Task.sleep(for: .milliseconds(800))
        do {
            let printer = try PeriPagePrinter(address: address, name: DriverSettings.printerNameBT, model: model)
            info("Conectando a \(printer.name)…")
            try await printer.connect(attempts: 3)
            defer {
                printer.disconnect()
                DistributedNotificationCenter.default().postNotificationName(PrinterHandoff.released, object: nil, userInfo: nil, deliverImmediately: true)
            }
            if let status = try? await printer.status(), status.raw & 0x04 != 0 {
                state("+media-empty-error")
                error("La impresora no tiene papel")
                return 1
            }
            state("-media-empty-error")
            try await printer.setDensity(DriverSettings.density)
            let options = PrintJobOptions(copies: copies, trailingFeedDots: model.feedDots(bottomMarginMM: DriverSettings.bottomMarginMM),
                                          gapBetweenCopiesDots: model.dots(forMM: 4))
            var lastShown = -1
            try await printer.print(bitmap, options: options) { fraction in
                let pct = Int(fraction * 100)
                if pct / 20 != lastShown / 20 {
                    lastShown = pct
                    info("Imprimiendo \(pct)%")
                }
            }
            if let battery = try? await printer.batteryPercent() {
                attr("marker-levels=\(battery) marker-names=Batería marker-types=other marker-colors=#000000")
            }
            let mm = Int(model.mm(forDots: bitmap.height * copies))
            DriverSettings.lastJob = "\(jobName) · \(mm) mm · \(Date().formatted(date: .omitted, time: .shortened))"
            info("Listo: \(mm) mm")
            return 0
        } catch let err {
            error(err.localizedDescription)
            return 1
        }
    }

    /// Bluetooth authorization with a deadline, so a job never hangs waiting on a prompt nobody answers.
    private static func authorization(timeout: TimeInterval) async -> BluetoothAuthorization.Result? {
        await withTaskGroup(of: BluetoothAuthorization.Result?.self) { group in
            group.addTask { await BluetoothAuthorization().request() }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    static func info(_ s: String) { FileHandle.standardError.write("INFO: \(s)\n".data(using: .utf8)!) }
    static func error(_ s: String) { FileHandle.standardError.write("ERROR: \(s)\n".data(using: .utf8)!) }
    static func state(_ s: String) { FileHandle.standardError.write("STATE: \(s)\n".data(using: .utf8)!) }
    static func attr(_ s: String) { FileHandle.standardError.write("ATTR: \(s)\n".data(using: .utf8)!) }
}

/// Turns PDFs and images into 1-bit strips for the print head.
enum Rasterizer {
    static func pages(path: String, contentType: String, model: PrinterModel) -> [MonoBitmap]? {
        let url = URL(fileURLWithPath: path)
        if contentType.contains("pwg-raster") || contentType.contains("urf") {
            guard let data = try? Data(contentsOf: url), let pages = RasterDecoder.decode(data) else { return nil }
            return pages.compactMap { raster in
                var gray = GrayImage(width: raster.width, height: raster.height, pixels: raster.gray)
                if raster.width > model.widthDots, let cg = gray.cgImage(), let scaled = GrayImage(cgImage: cg, width: model.widthDots) {
                    gray = scaled
                }
                return finish(gray, model: model)
            }
        }
        if contentType.contains("pdf") || url.pathExtension.lowercased() == "pdf" {
            guard let doc = CGPDFDocument(url as CFURL), doc.numberOfPages > 0 else { return nil }
            return (1...doc.numberOfPages).compactMap { doc.page(at: $0) }.compactMap { page(pdf: $0, model: model) }
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldAllowFloat: false] as CFDictionary),
              let gray = GrayImage(cgImage: image, width: model.widthDots) else { return nil }
        return [finish(gray, model: model)]
    }

    /// Renders at the printer's physical resolution; wide pages get their margins cropped and shrink to 48 mm.
    static func page(pdf page: CGPDFPage, model: PrinterModel) -> MonoBitmap? {
        let box = page.getBoxRect(.cropBox)
        let rotated = page.rotationAngle % 180 != 0
        let widthPt = rotated ? box.height : box.width, heightPt = rotated ? box.width : box.height
        let pxPerPt = Double(model.dpi) / 72
        let w = max(1, Int((widthPt * pxPerPt).rounded())), h = max(1, Int((heightPt * pxPerPt).rounded()))
        guard w * h < 60_000_000,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: w, height: h), rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        guard var image = ctx.makeImage() else { return nil }

        if w > model.widthDots, DriverSettings.fitWidth, let bounds = contentBounds(of: image), let cropped = image.cropping(to: bounds) {
            image = cropped
        }
        let targetWidth = min(model.widthDots, image.width)
        guard let gray = GrayImage(cgImage: image, width: targetWidth) else { return nil }
        return finish(gray, model: model)
    }

    private static func finish(_ gray: GrayImage, model: PrinterModel) -> MonoBitmap {
        let quality: DriverSettings.Quality = DriverSettings.quality == .auto ? (looksPhotographic(gray) ? .photo : .text) : DriverSettings.quality
        var bitmap = quality == .photo
            ? ImagePipeline.recommendedPhoto.process(gray)
            : ImageProcessor.dither(gray, algorithm: .threshold, threshold: 0.6)
        bitmap = bitmap.placed(inWidth: model.widthDots)
        return DriverSettings.trimBlank ? bitmap.trimmedVertically() : bitmap
    }

    /// Pages with a lot of mid-gray are treated as photos; text and line art stay crisp with a threshold.
    static func looksPhotographic(_ gray: GrayImage) -> Bool {
        var mid = 0, inked = 0
        for v in gray.pixels where v < 0.97 {
            inked += 1
            if v > 0.12 && v < 0.85 { mid += 1 }
        }
        return inked > 0 && Double(mid) / Double(inked) > 0.45 && Double(inked) / Double(gray.pixels.count) > 0.05
    }

    /// Bounding box of non-white pixels, padded a little.
    static func contentBounds(of image: CGImage) -> CGRect? {
        guard let gray = GrayImage(cgImage: image, width: image.width) else { return nil }
        var minX = gray.width, maxX = -1, minY = gray.height, maxY = -1
        for y in 0..<gray.height {
            for x in 0..<gray.width where gray[x, y] < 0.9 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return nil }
        let pad = 8
        return CGRect(x: max(0, minX - pad), y: max(0, minY - pad),
                      width: min(gray.width, maxX + pad) - max(0, minX - pad), height: min(gray.height, maxY + pad) - max(0, minY - pad))
    }
}
