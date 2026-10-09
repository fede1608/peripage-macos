import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PeriPageKit
import PeriRender
import PuzzleKit
import SocialKit

/// Turns a mode document into the exact 1-bit image that will be printed.
enum Renderer {
    struct Input {
        var mode: Mode
        var photo: PhotoDoc
        var sticker: StickerDoc
        var text: TextDoc
        var banner: BannerDoc
        var qr: QRDoc
        var label: LabelDoc
        var collage: CollageDoc
        var collageImages: [CGImage]
        var puzzle: PuzzleDoc
        var social: SocialDoc
        var socialPost: SocialPost?
        var image: CGImage?
        var labelImage: CGImage?
        var history: MonoBitmap?
        var model: PrinterModel
    }

    static func render(_ input: Input) -> MonoBitmap? {
        switch input.mode {
        case .photo: photo(input.photo, image: input.image, model: input.model)
        case .collage: collage(input.collage, images: input.collageImages, model: input.model)
        case .sticker: sticker(input.sticker, image: input.image, model: input.model)
        case .label: labels(input.label, image: input.labelImage, model: input.model)
        case .text: text(input.text, model: input.model)
        case .banner: banner(input.banner, model: input.model)
        case .qr: qr(input.qr, model: input.model)
        case .games: PuzzleRenderer.render(input.puzzle, widthDots: input.model.widthDots)
        case .history: input.history
        case .social: social(input)
        }
    }

    // MARK: Photo

    static func photo(_ doc: PhotoDoc, image: CGImage?, model: PrinterModel) -> MonoBitmap? {
        guard let source = image.map({ crop($0, to: doc.crop) }) else { return nil }
        let W = model.widthDots
        let scale = Double(W) / 384

        if doc.frame == .polaroid {
            let side = Int(16 * scale), top = Int(16 * scale)
            let imageW = Int(Double(W - 2 * side) * doc.widthPercent / 100)
            guard let img = doc.pipeline.render(source, width: imageW) else { return nil }
            let caption = MonoBitmap.stack(captionBlocks(doc, width: W - 2 * side, model: model), width: W - 2 * side, spacing: Int(4 * scale))
            let bottom = max(Int(64 * scale), caption.height + Int(28 * scale))
            var card = MonoBitmap(width: W, height: top + img.height + bottom)
            card.blit(img, x: (W - img.width) / 2, y: top)
            card.blit(caption, x: side, y: top + img.height + (bottom - caption.height) / 2)
            card.strokeRect(x: 0, y: 0, width: W, height: card.height, thickness: 2)
            return card
        }

        let inner = doc.frame.contentWidth(for: W)
        let pad = doc.frame == .none ? 0 : Int(6 * scale)
        let imageW = Int(Double(inner - 2 * pad) * doc.widthPercent / 100)
        guard let img = doc.pipeline.render(source, width: imageW) else { return nil }
        let framed = doc.frame.apply(to: img.padded(top: pad, bottom: pad), width: W)
        return MonoBitmap.stack([framed] + captionBlocks(doc, width: W - Int(24 * scale), model: model), width: W, spacing: Int(10 * scale))
    }

    private static func captionBlocks(_ doc: PhotoDoc, width: Int, model: PrinterModel) -> [MonoBitmap] {
        let scale = CGFloat(model.widthDots) / 384
        var blocks: [MonoBitmap] = []
        if !doc.caption.isEmpty {
            let font = TextRenderer.font(family: "Helvetica Neue", size: doc.captionSize * scale, bold: false)
            blocks.append(TextRenderer.render(doc.caption, font: font, align: .center, width: width))
        }
        if doc.dateStamp {
            let font = TextRenderer.font(family: "Menlo", size: 16 * scale, bold: false)
            blocks.append(TextRenderer.render(Formatters.stamp.string(from: .now), font: font, align: .center, width: width))
        }
        return blocks
    }

    static func crop(_ image: CGImage, to aspect: CropAspect) -> CGImage {
        guard let ratio = aspect.ratio else { return image }
        let w = Double(image.width), h = Double(image.height)
        let rect: CGRect
        if w / h > ratio {
            let newW = h * ratio
            rect = CGRect(x: (w - newW) / 2, y: 0, width: newW, height: h)
        } else {
            let newH = w / ratio
            rect = CGRect(x: 0, y: (h - newH) / 2, width: w, height: newH)
        }
        return image.cropping(to: rect.integral) ?? image
    }

    // MARK: Collage

    static func collage(_ doc: CollageDoc, images: [CGImage], model: PrinterModel) -> MonoBitmap? {
        guard !images.isEmpty else { return nil }
        let W = model.widthDots
        let inner = doc.frame.contentWidth(for: W) - (doc.frame == .none ? 0 : 12)
        let gap = model.dots(forMM: doc.spacingMM)
        let cells: [MonoBitmap]
        let columns: Int
        switch doc.layout {
        case .strip:
            // Photo booth: square-ish frames stacked vertically.
            columns = 1
            cells = images.map { doc.pipeline.render(crop($0, to: .fourThree), width: inner) ?? MonoBitmap(width: inner, height: 1) }
        case .grid:
            columns = 2
            let w = (inner - gap) / 2
            cells = images.map { doc.pipeline.render(crop($0, to: .square), width: w) ?? MonoBitmap(width: w, height: 1) }
        case .pairs:
            columns = 2
            let w = (inner - gap) / 2
            cells = images.map { doc.pipeline.render(crop($0, to: .threeFour), width: w) ?? MonoBitmap(width: w, height: 1) }
        }
        var rows: [MonoBitmap] = []
        for start in stride(from: 0, to: cells.count, by: columns) {
            let rowCells = Array(cells[start..<min(start + columns, cells.count)])
            var row = MonoBitmap(width: inner, height: rowCells.map(\.height).max() ?? 0)
            var x = 0
            for cell in rowCells {
                row.blit(cell, x: x, y: 0)
                x += cell.width + gap
            }
            rows.append(row)
        }
        var blocks = [MonoBitmap.stack(rows, width: inner, spacing: gap)]
        let scale = CGFloat(W) / 384
        if !doc.caption.isEmpty {
            blocks.append(TextRenderer.render(doc.caption, font: TextRenderer.font(family: "Avenir Next", size: 22 * scale, bold: true),
                                              align: .center, width: inner))
        }
        if doc.dateStamp {
            blocks.append(TextRenderer.render(Formatters.stamp.string(from: .now), font: TextRenderer.font(family: "Menlo", size: 15 * scale, bold: false),
                                              align: .center, width: inner))
        }
        let body = MonoBitmap.stack(blocks, width: inner, spacing: Int(8 * scale))
        return doc.frame.apply(to: doc.frame == .none ? body : body.padded(top: 6, bottom: 6), width: W)
    }

    // MARK: Stickers

    static func sticker(_ doc: StickerDoc, image: CGImage?, model: PrinterModel) -> MonoBitmap? {
        guard let image else { return nil }
        let W = model.widthDots
        let gap = model.dots(forMM: doc.gapMM)
        let columns = max(1, doc.columns)
        let maxTile = (W - (columns - 1) * gap) / columns
        let tileW = max(24, min(model.dots(forMM: doc.widthMM), maxTile))
        guard let tile = stickerTile(doc, image: image, width: tileW) else { return nil }

        let count = max(1, doc.count)
        let rows = (count + columns - 1) / columns
        let rowWidth = columns * tile.width + (columns - 1) * gap
        let x0 = (W - rowWidth) / 2
        var sheet = MonoBitmap(width: W, height: rows * tile.height + (rows - 1) * gap)
        for i in 0..<count {
            let r = i / columns, c = i % columns
            sheet.blit(tile, x: x0 + c * (tile.width + gap), y: r * (tile.height + gap))
        }
        return sheet
    }

    private static func stickerTile(_ doc: StickerDoc, image: CGImage, width tileW: Int) -> MonoBitmap? {
        switch doc.outline {
        case .none:
            return decorated(doc, image: image, width: tileW)

        case .cutLine:
            let margin = 6
            guard let img = decorated(doc, image: image, width: tileW - 2 * margin) else { return nil }
            var tile = img.padded(top: margin, bottom: margin, left: margin, right: margin)
            tile.strokeRect(x: 0, y: 0, width: tile.width, height: tile.height, thickness: 1, radius: 10, dash: 6)
            return tile

        case .contour:
            let cw = Int(doc.contourWidth.rounded())
            let pad = cw + 4
            let innerW = tileW - 2 * pad
            guard innerW > 8,
                  let gray = GrayImage(cgImage: image, width: innerW, transform: doc.pipeline.transform),
                  let alpha = AlphaMask(cgImage: image, width: innerW, transform: doc.pipeline.transform) else { return nil }
            var content = doc.pipeline.process(gray)
            var mask = alpha.mask
            if doc.whiteIsTransparent {
                for i in mask.indices where gray.pixels[i] > 0.92 { mask[i] = false }
            }
            for y in 0..<content.height {
                for x in 0..<content.width where !mask[y * innerW + x] { content[x, y] = false }
            }
            let w = innerW + 2 * pad, h = content.height + 2 * pad
            var padded = [Bool](repeating: false, count: w * h)
            for y in 0..<content.height {
                for x in 0..<innerW where mask[y * innerW + x] { padded[(y + pad) * w + x + pad] = true }
            }
            let dist = distanceToMask(padded, width: w, height: h)
            var tile = content.padded(top: pad, bottom: pad, left: pad, right: pad)
            let ring = Float(cw)
            for i in dist.indices where dist[i] > ring && dist[i] <= ring + 2 {
                tile[i % w, i / w] = true
            }
            return tile
        }
    }

    /// Sticker image, optionally inside a decorative frame, exactly `width` wide.
    private static func decorated(_ doc: StickerDoc, image: CGImage, width: Int) -> MonoBitmap? {
        guard doc.decor != .none else { return doc.pipeline.render(image, width: width) }
        let inner = doc.decor.contentWidth(for: width) - 6
        guard inner > 8, let img = doc.pipeline.render(image, width: inner) else { return nil }
        return doc.decor.apply(to: img.padded(top: 3, bottom: 3), width: width)
    }

    // MARK: Labels

    /// Label position math for die-cut labels on a roll (see docs/PROTOCOL.md):
    /// a job starts `topMarginMM` past the previous tear and ends `tearIntoGapMM` into the next gap.
    enum LabelGeometry {
        static let tearIntoGapMM = 0.25
        static let safeInsetMM = 1.0

        static func startOffset(_ doc: LabelDoc, model: PrinterModel) -> Int {
            max(0, model.dots(forMM: doc.gapMM - tearIntoGapMM - model.topMarginMM + doc.adjustMM))
        }

        static func trailingFeed(model: PrinterModel) -> Int { model.feedDots(bottomMarginMM: tearIntoGapMM) }
    }

    static func labelEntries(_ doc: LabelDoc) -> [String] {
        let lines = doc.lines.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let base = lines.isEmpty ? [""] : lines
        return base.flatMap { Array(repeating: $0, count: max(1, doc.copies)) }
    }

    static func labels(_ doc: LabelDoc, image: CGImage?, model: PrinterModel) -> MonoBitmap? {
        let entries = labelEntries(doc)
        let bitmaps = entries.map { label($0, doc: doc, image: image, model: model) }
        return placeOnLabels(bitmaps, doc: doc, model: model)
    }

    /// Stacks label-height bitmaps at the roll's pitch, starting where the next label begins.
    static func placeOnLabels(_ items: [MonoBitmap], doc: LabelDoc, model: PrinterModel) -> MonoBitmap {
        let H = model.dots(forMM: doc.heightMM), gap = model.dots(forMM: doc.gapMM)
        let offset = LabelGeometry.startOffset(doc, model: model)
        var strip = MonoBitmap(width: model.widthDots, height: offset + items.count * H + max(0, items.count - 1) * gap)
        for (i, item) in items.enumerated() {
            strip.blit(item.rows(0..<min(item.height, H)), x: (model.widthDots - item.width) / 2, y: offset + i * (H + gap))
        }
        return strip
    }

    /// Row ranges of backing paper between labels, for preview shading.
    static func labelGaps(count: Int, doc: LabelDoc, model: PrinterModel) -> [Range<Int>] {
        let H = model.dots(forMM: doc.heightMM), gap = model.dots(forMM: doc.gapMM)
        let offset = LabelGeometry.startOffset(doc, model: model)
        var gaps: [Range<Int>] = offset > 0 ? [0..<offset] : []
        for i in 0..<max(0, count - 1) {
            let start = offset + (i + 1) * H + i * gap
            gaps.append(start..<(start + gap))
        }
        return gaps
    }

    /// One label, exactly `heightMM` tall and printer-width wide.
    static func label(_ text: String, doc: LabelDoc, image: CGImage?, model: PrinterModel) -> MonoBitmap {
        let W = model.widthDots, H = model.dots(forMM: doc.heightMM)
        let inset = model.dots(forMM: LabelGeometry.safeInsetMM)
        let frameMargin = doc.frame == .none ? 0 : max(4, doc.frame.margin(for: W) * 2 / 3)
        let innerW = doc.frame.contentWidth(for: W) - (doc.frame == .none ? 2 * inset : 8)
        let innerH = max(8, H - 2 * inset - 2 * frameMargin)
        let subtitle = [doc.subtitle, doc.dateStamp ? Formatters.labelDate.string(from: .now) : ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")

        var content: MonoBitmap
        switch doc.content {
        case .text:
            content = fitLines(text, subtitle, doc: doc, width: innerW, height: innerH)
        case .iconText, .qrText:
            let side = innerH
            let art: MonoBitmap?
            if doc.content == .qrText {
                art = qrBitmap(text.isEmpty ? subtitle : text, correction: "M", maxSize: side)
            } else {
                let icon = image ?? symbolImage(doc.symbol)
                art = icon.flatMap { fitImage($0, maxWidth: side, maxHeight: side, pipeline: doc.pipeline) }
            }
            let gapX = model.dots(forMM: 2)
            let artW = art?.width ?? 0
            let textBlock = fitLines(text, subtitle, doc: doc, width: innerW - artW - gapX, height: innerH)
            content = MonoBitmap(width: innerW, height: innerH)
            if let art { content.blit(art, x: 0, y: (innerH - art.height) / 2) }
            content.blit(textBlock, x: artW + gapX, y: 0)
        case .barcode:
            let caption = TextRenderer.render(text, font: TextRenderer.font(family: "Menlo", size: CGFloat(innerH) * 0.2, bold: false),
                                              align: .center, width: innerW).trimmedVertically()
            let barH = max(8, innerH - caption.height - 2)
            content = MonoBitmap(width: innerW, height: innerH)
            if let bars = barcodeBitmap(text, maxWidth: innerW, height: barH) {
                content.blit(bars, x: (innerW - bars.width) / 2, y: 0)
            }
            content.blit(caption, x: 0, y: innerH - caption.height)
        case .image:
            content = MonoBitmap(width: innerW, height: innerH)
            if let image, let art = fitImage(image, maxWidth: innerW, maxHeight: innerH, pipeline: doc.pipeline) {
                content.blit(art, x: (innerW - art.width) / 2, y: (innerH - art.height) / 2)
            }
        }

        var framed = doc.frame.apply(to: content, width: W, compact: true)
        if doc.invert { framed = framed.inverted() }
        var out = MonoBitmap(width: W, height: H)
        out.blit(framed, x: 0, y: (H - framed.height) / 2)
        return out
    }

    /// Main line (+ optional smaller subtitle) at the largest size that fits `width` × `height`, centered vertically.
    private static func fitLines(_ main: String, _ sub: String, doc: LabelDoc, width: Int, height: Int) -> MonoBitmap {
        var lo: CGFloat = 6, hi = CGFloat(height)
        func measure(_ size: CGFloat) -> CGSize {
            let mainFont = TextRenderer.font(family: doc.fontFamily, size: size, bold: doc.bold)
            var w = TextRenderer.attributed(main, font: mainFont, align: doc.align).size().width
            var h = mainFont.ascender - mainFont.descender
            if !sub.isEmpty {
                let subFont = TextRenderer.font(family: doc.fontFamily, size: size * 0.5, bold: false)
                w = max(w, TextRenderer.attributed(sub, font: subFont, align: doc.align).size().width)
                h += subFont.ascender - subFont.descender
            }
            return CGSize(width: w, height: h)
        }
        while hi - lo > 0.5 {
            let mid = (lo + hi) / 2
            let m = measure(mid)
            if m.width <= CGFloat(width) && m.height <= CGFloat(height) { lo = mid } else { hi = mid }
        }
        func line(_ text: String, _ font: NSFont) -> MonoBitmap {
            let rendered = TextRenderer.renderLine(text, font: font, kern: 0, height: Int(ceil(font.ascender - font.descender)))
            let trimmed = rendered.trimmedHorizontally()
            return trimmed.width > width ? trimmed.cropped(width: width) : trimmed
        }
        var trimmed = [line(main, TextRenderer.font(family: doc.fontFamily, size: lo, bold: doc.bold))]
        if !sub.isEmpty { trimmed.append(line(sub, TextRenderer.font(family: doc.fontFamily, size: lo * 0.5, bold: false))) }
        let stack = MonoBitmap.stack(trimmed.map { aligned($0, width: width, align: doc.align) }, width: width, spacing: 1)
        var out = MonoBitmap(width: width, height: height)
        out.blit(stack, x: 0, y: (height - stack.height) / 2)
        return out
    }

    private static func aligned(_ b: MonoBitmap, width: Int, align: TextAlign) -> MonoBitmap {
        switch align {
        case .left: b.placed(inWidth: width, .leading)
        case .center: b.placed(inWidth: width, .center)
        case .right: b.placed(inWidth: width, .trailing)
        }
    }

    static func fitImage(_ image: CGImage, maxWidth: Int, maxHeight: Int, pipeline: ImagePipeline) -> MonoBitmap? {
        let aspect = Double(image.width) / Double(max(1, image.height))
        let w = max(1, min(maxWidth, Int(Double(maxHeight) * aspect)))
        return pipeline.render(image, width: w)
    }

    /// SF Symbol drawn in black. Runs on the render thread, so it draws the symbol straight into our own
    /// context: an NSImage drawing handler would run later without a current context and trap in AppKit.
    static func symbolImage(_ name: String) -> CGImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 256, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.black]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config),
              symbol.size.width >= 1, symbol.size.height >= 1 else { return nil }
        let size = symbol.size
        let canvas = MonoCanvas(width: Int(ceil(size.width)), height: Int(ceil(size.height)))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas.context, flipped: true)
        symbol.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        return canvas.context.makeImage()
    }

    // MARK: Text

    static func text(_ doc: TextDoc, model: PrinterModel) -> MonoBitmap? {
        let W = model.widthDots
        let scale = CGFloat(W) / 384
        let framed = doc.frame != .none
        let pad = !framed && !doc.invert ? Int(4 * scale) : Int(10 * scale)
        let innerW = doc.frame.contentWidth(for: W) - 2 * pad
        let size = doc.fontSize * scale
        var blocks: [MonoBitmap] = []

        switch doc.template {
        case .free:
            blocks.append(TextRenderer.render(doc.body, font: TextRenderer.font(family: doc.fontFamily, size: size, bold: doc.bold),
                                              align: doc.align, width: innerW, lineSpacing: doc.lineSpacing))
        case .note, .checklist:
            if !doc.title.isEmpty {
                let titleFont = TextRenderer.font(family: doc.fontFamily, size: size * 1.35, bold: true)
                blocks.append(TextRenderer.render(doc.title, font: titleFont, align: doc.align, width: innerW))
                var rule = MonoBitmap(width: innerW, height: Int(3 * scale))
                rule.fillRect(x: 0, y: 0, width: innerW, height: rule.height)
                blocks.append(rule)
            }
            let body: String
            if doc.template == .checklist {
                body = doc.body.split(separator: "\n", omittingEmptySubsequences: true)
                    .map { "☐  " + $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            } else {
                body = doc.body
            }
            blocks.append(TextRenderer.render(body, font: TextRenderer.font(family: doc.fontFamily, size: size, bold: doc.bold),
                                              align: doc.template == .checklist ? .left : doc.align, width: innerW,
                                              lineSpacing: doc.lineSpacing + (doc.template == .checklist ? 6 * scale : 0)))
        case .label:
            let font = TextRenderer.fittingFont(doc.body, family: doc.fontFamily, bold: doc.bold, width: innerW - Int(8 * scale), maxSize: 140 * scale)
            blocks.append(TextRenderer.render(doc.body, font: font, align: doc.align, width: innerW, lineSpacing: doc.lineSpacing))
        }
        if doc.dateStamp {
            let font = TextRenderer.font(family: "Menlo", size: 15 * scale, bold: false)
            blocks.append(TextRenderer.render(Formatters.stamp.string(from: .now), font: font, align: .right, width: innerW))
        }

        var body = MonoBitmap.stack(blocks, width: innerW, spacing: Int(8 * scale)).trimmedVertically()
        body = body.padded(top: pad, bottom: pad, left: pad, right: pad)
        if doc.invert { body = body.inverted() }
        return doc.frame.apply(to: body, width: W)
    }

    // MARK: Banner

    static func banner(_ doc: BannerDoc, model: PrinterModel) -> MonoBitmap? {
        let text = doc.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let H = model.widthDots
        let reference = TextRenderer.font(family: doc.fontFamily, size: 100, bold: doc.bold)
        let lineHeight100 = reference.ascender - reference.descender
        let size = CGFloat(H) * doc.heightPercent / 100 / lineHeight100 * 100
        let font = TextRenderer.font(family: doc.fontFamily, size: size, bold: doc.bold)
        let line = TextRenderer.renderLine(text, font: font, kern: doc.letterSpacing * size / 100, height: H)
        var strip = line.padded(left: H / 6, right: H / 6)
        if doc.border {
            strip.strokeRect(x: 4, y: 4, width: strip.width - 8, height: strip.height - 8, thickness: max(3, H / 64), radius: H / 10)
        }
        if doc.invert { strip = strip.inverted() }
        return strip.rotatedClockwise()
    }

    // MARK: QR

    static func qr(_ doc: QRDoc, model: PrinterModel) -> MonoBitmap? {
        let W = model.widthDots
        guard let code = qrBitmap(doc.payload, correction: doc.correction, maxSize: Int(Double(W) * doc.sizePercent / 100)) else { return nil }
        let module = max(1, code.width / 25)
        var blocks = [code.padded(top: 2 * module, bottom: 2 * module)]
        if !doc.caption.isEmpty {
            let font = TextRenderer.font(family: "Helvetica Neue", size: 22 * CGFloat(W) / 384, bold: false)
            blocks.append(TextRenderer.render(doc.caption, font: font, align: .center, width: W - 16))
        }
        if doc.kind == .wifi, !doc.wifiSSID.isEmpty {
            let font = TextRenderer.font(family: "Menlo", size: 18 * CGFloat(W) / 384, bold: false)
            var details = "Red: \(doc.wifiSSID)"
            if !doc.wifiPassword.isEmpty { details += "\nClave: \(doc.wifiPassword)" }
            blocks.append(TextRenderer.render(details, font: font, align: .center, width: W - 16))
        }
        return MonoBitmap.stack(blocks, width: W, spacing: 10)
    }

    /// QR code scaled by an integer factor so modules stay crisp.
    static func qrBitmap(_ payload: String, correction: String, maxSize: Int) -> MonoBitmap? {
        guard !payload.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = correction
        return moduleBitmap(filter.outputImage, maxWidth: maxSize, maxHeight: maxSize)
    }

    static func barcodeBitmap(_ text: String, maxWidth: Int, height: Int) -> MonoBitmap? {
        guard !text.isEmpty, let data = text.data(using: .ascii, allowLossyConversion: true) else { return nil }
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = data
        filter.quietSpace = 0
        filter.barcodeHeight = 1
        guard let bars = moduleBitmap(filter.outputImage, maxWidth: maxWidth, maxHeight: 1, stretchHeight: height) else { return nil }
        return bars
    }

    /// Converts a 1-px-per-module CIImage into a MonoBitmap scaled by the largest integer factor that fits.
    private static func moduleBitmap(_ ci: CIImage?, maxWidth: Int, maxHeight: Int, stretchHeight: Int? = nil) -> MonoBitmap? {
        guard let ci, let cg = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(ci, from: ci.extent),
              let gray = GrayImage(cgImage: cg, width: cg.width) else { return nil }
        let scale = max(1, min(maxWidth / gray.width, stretchHeight == nil ? maxHeight / max(1, gray.height) : Int.max))
        let outH = stretchHeight ?? gray.height * scale
        var out = MonoBitmap(width: gray.width * scale, height: outH)
        for x in 0..<gray.width {
            if let stretchHeight {
                if gray[x, 0] < 0.5 { out.fillRect(x: x * scale, y: 0, width: scale, height: stretchHeight) }
            } else {
                for y in 0..<gray.height where gray[x, y] < 0.5 {
                    out.fillRect(x: x * scale, y: y * scale, width: scale, height: scale)
                }
            }
        }
        return out
    }

    // MARK: Social

    static func social(_ input: Input) -> MonoBitmap? {
        guard let post = input.socialPost else { return nil }
        var doc = input.social
        doc.labelHeightMM = input.label.heightMM
        guard let bitmap = SocialRenderer.render(post, doc: doc, model: input.model) else { return nil }
        return doc.layout == .label ? placeOnLabels([bitmap], doc: input.label, model: input.model) : bitmap
    }
}

extension Formatters {
    static let labelDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "dd/MM/yy"
        return f
    }()
}

extension MonoBitmap {
    /// Removes fully white columns at the left and right.
    func trimmedHorizontally() -> MonoBitmap {
        var minX = width, maxX = -1
        for y in 0..<height {
            for x in 0..<width where self[x, y] {
                minX = Swift.min(minX, x)
                maxX = Swift.max(maxX, x)
            }
        }
        guard maxX >= minX else { return MonoBitmap(width: 1, height: height) }
        var out = MonoBitmap(width: maxX - minX + 1, height: height)
        out.blit(self, x: -minX, y: 0)
        return out
    }

    func cropped(width w: Int) -> MonoBitmap {
        var out = MonoBitmap(width: w, height: height)
        out.blit(self, x: 0, y: 0)
        return out
    }
}
