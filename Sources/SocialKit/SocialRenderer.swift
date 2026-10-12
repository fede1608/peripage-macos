import AppKit
import PeriPageKit
import PeriRender

/// Lays out a post as the exact 1-bit image that will be printed.
public enum SocialRenderer {
    /// Exactly `model.widthDots` wide. For `.label` the height is exactly `model.dots(forMM: doc.labelHeightMM)`.
    public static func render(_ post: SocialPost, doc: SocialDoc, model: PrinterModel) -> MonoBitmap? {
        let m = Metrics(width: model.widthDots)
        guard m.W > 16 else { return nil }
        let out: MonoBitmap?
        switch doc.layout {
        case .card:
            switch post.platform {
            case .capture: out = captureCard(post, doc: doc, m)
            case .instagram: out = instagramCard(post, doc: doc, m)
            case .x: out = card(post, doc: doc, m)
            }
        case .photo: out = photo(post, doc: doc, m)
        case .sticker: out = sticker(post, doc: doc, m)
        case .label: out = label(post, doc: doc, model: model, m)
        }
        guard let out, out.height > 0 else { return nil }
        return out.width == m.W ? out : out.placed(inWidth: m.W)
    }

    struct Metrics {
        let W: Int
        let s: CGFloat

        init(width: Int) {
            W = width
            s = CGFloat(width) / 384
        }

        func d(_ v: CGFloat) -> Int { Int((v * s).rounded()) }
        func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: size * s, weight: weight) }
    }

    static let maxTextLength = 1000

    // MARK: Card

    static func card(_ post: SocialPost, doc: SocialDoc, _ m: Metrics) -> MonoBitmap {
        let pad = m.d(16), inner = m.W - 2 * pad
        var blocks: [(MonoBitmap, gapBefore: Int)] = [(header(post, width: inner, doc: doc, m), 0)]

        var textBlock: MonoBitmap?
        let text = truncated(post.text, to: maxTextLength)
        if doc.showText, !text.isEmpty {
            textBlock = TextRenderer.render(text, font: m.font(21), align: .left, width: inner, lineSpacing: 2 * m.s).trimmedVertically()
        }
        var photoBlock: MonoBitmap?
        if let image = post.image(at: doc.imageIndex), var photo = doc.pipeline.render(cropped(image, maxAspect: 1.25), width: inner) {
            roundCorners(&photo, radius: m.d(14))
            photoBlock = photo
        }
        // X shows the text above the media; Instagram the caption below the photo.
        let body = post.platform == .instagram ? [photoBlock, textBlock] : [textBlock, photoBlock]
        for block in body.compactMap({ $0 }) { blocks.append((block, m.d(14))) }
        let footer = footer(post, doc: doc, width: inner, m)
        if footer.height > 0 {
            var rule = MonoBitmap(width: inner, height: max(1, m.d(2)))
            rule.fillRect(x: 0, y: 0, width: inner, height: rule.height)
            blocks.append((rule, m.d(14)))
            blocks.append((footer, m.d(10)))
        }

        let contentHeight = blocks.reduce(0) { $0 + $1.0.height + $1.gapBefore }
        var out = MonoBitmap(width: m.W, height: contentHeight + 2 * pad)
        var y = pad
        for (block, gap) in blocks {
            y += gap
            out.blit(block, x: pad, y: y)
            y += block.height
        }
        out.strokeRect(x: 0, y: 0, width: m.W, height: out.height, thickness: max(1, m.d(2)), radius: m.d(22))
        return out
    }

    /// Avatar, bold name, @handle and the platform mark.
    static func header(_ post: SocialPost, width: Int, doc: SocialDoc, _ m: Metrics) -> MonoBitmap {
        let avatarSize = m.d(60), markSize = m.d(26), gap = m.d(12)
        let textX = avatarSize + gap
        let textW = width - textX - markSize - gap
        let name = line(post.displayName, font: m.font(23, .bold), maxWidth: textW)
        let sub = line(secondaryLine(post), font: m.font(18), maxWidth: textW)
        let textH = name.height + sub.height
        let h = max(avatarSize, textH)
        var out = MonoBitmap(width: width, height: h)
        out.blit(avatar(post.avatar, initial: post.displayName, diameter: avatarSize, pipeline: doc.pipeline), x: 0, y: (h - avatarSize) / 2)
        let ty = (h - textH) / 2
        out.blit(name, x: textX, y: ty)
        out.blit(sub, x: textX, y: ty + name.height)
        out.blit(platformMark(post.platform, size: markSize), x: width - markSize, y: max(0, (h - markSize) / 2))
        return out
    }

    /// Date and stats on one row when they fit, else on two.
    static func footer(_ post: SocialPost, doc: SocialDoc, width: Int, _ m: Metrics) -> MonoBitmap {
        let font = m.font(17)
        let stats = doc.showStats ? statsRow(post, font: font, m) : nil
        let date = doc.showDate ? post.date.map { line(Formatters.stamp.string(from: $0), font: font, maxWidth: width) } : nil
        switch (stats, date) {
        case (nil, nil): return MonoBitmap(width: width, height: 0)
        case (let s?, nil): return s.placed(inWidth: width, .leading)
        case (nil, let d?): return d.placed(inWidth: width, .leading)
        case (let s?, let d?):
            if s.width + d.width + m.d(16) <= width {
                var row = MonoBitmap(width: width, height: max(s.height, d.height))
                row.blit(s, x: 0, y: (row.height - s.height) / 2)
                row.blit(d, x: width - d.width, y: (row.height - d.height) / 2)
                return row
            }
            return MonoBitmap.stack([d.placed(inWidth: width, .leading), s.placed(inWidth: width, .leading)], width: width, spacing: m.d(6))
        }
    }

    static func statsRow(_ post: SocialPost, font: NSFont, _ m: Metrics) -> MonoBitmap? {
        var items: [(symbol: String, text: String)] = []
        // Same order as X: replies, reposts, likes.
        if let replies = post.replies { items.append(("bubble.right", compactNumber(replies))) }
        if let reposts = post.reposts { items.append(("arrow.2.squarepath", compactNumber(reposts))) }
        if let likes = post.likes { items.append(("heart", compactNumber(likes))) }
        guard !items.isEmpty else { return nil }
        let iconSize = font.pointSize * 1.05
        let iconGap = m.s * 5, itemGap = m.s * 18
        let strings = items.map { TextRenderer.attributed($0.text, font: font, align: .left) }
        let images = items.map { symbolImage($0.symbol, pointSize: iconSize) }
        let lineHeight = ceil(font.ascender - font.descender)
        var width: CGFloat = 0
        for (i, s) in strings.enumerated() {
            width += (images[i]?.size.width ?? 0) + iconGap + s.size().width + (i < strings.count - 1 ? itemGap : 0)
        }
        let h = Int(lineHeight) + 4
        return TextRenderer.draw(width: Int(ceil(width)) + 4, height: h) {
            var x: CGFloat = 1
            for (i, s) in strings.enumerated() {
                if let img = images[i] {
                    let rect = CGRect(x: x, y: (CGFloat(h) - img.size.height) / 2, width: img.size.width, height: img.size.height)
                    img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                    x += img.size.width + iconGap
                }
                s.draw(at: CGPoint(x: x, y: (CGFloat(h) - lineHeight) / 2))
                x += s.size().width + itemGap
            }
        }
    }

    // MARK: Photo

    static func photo(_ post: SocialPost, doc: SocialDoc, _ m: Metrics) -> MonoBitmap? {
        // Text-only posts have no photo to show: fall back to the card.
        guard let image = post.image(at: doc.imageIndex) else { return card(post, doc: doc, m) }
        guard let img = doc.pipeline.render(image, width: m.W) else { return nil }
        guard post.platform != .capture, let credit = creditLine(post, doc: doc, maxWidth: m.W - m.d(16), m) else { return img }
        return MonoBitmap.stack([img, credit.padded(top: m.d(10), bottom: m.d(2))], width: m.W)
    }

    /// Small "[mark] @handle · date" line under photos and stickers.
    static func creditLine(_ post: SocialPost, doc: SocialDoc, maxWidth: Int, bold: Bool = false, size: CGFloat = 17, _ m: Metrics) -> MonoBitmap? {
        let handle = doc.showText && !post.handle.isEmpty ? post.atHandle : nil
        let dates = doc.showDate ? post.date.map { [Formatters.stamp.string(from: $0), shortDate.string(from: $0)] } ?? [] : []
        let font = m.font(size, bold ? .bold : .medium)
        let markSize = m.d(size)
        let gap = m.d(7)
        let available = CGFloat(maxWidth - markSize - gap - 2)
        // Longest variant that fits: handle · date and time, handle · date, handle alone.
        let variants = dates.map { [handle, $0].compactMap { $0 }.joined(separator: "  ·  ") } + [handle].compactMap { $0 }
        guard let first = variants.first else { return nil }
        let chosen = variants.first { NSAttributedString(string: $0, attributes: [.font: font]).size().width <= available } ?? variants.last ?? first
        let text = line(chosen, font: font, maxWidth: maxWidth - markSize - gap)
        let mark = platformMark(post.platform, size: markSize)
        var out = MonoBitmap(width: markSize + gap + text.width, height: max(markSize, text.height))
        out.blit(mark, x: 0, y: (out.height - markSize) / 2)
        out.blit(text, x: markSize + gap, y: (out.height - text.height) / 2)
        return out
    }

    // MARK: Sticker

    static func sticker(_ post: SocialPost, doc: SocialDoc, _ m: Metrics) -> MonoBitmap? {
        let pad = m.d(18), inner = m.W - 2 * pad
        var blocks: [MonoBitmap] = []
        if let image = post.image(at: doc.imageIndex) {
            guard var img = doc.pipeline.render(image, width: inner) else { return nil }
            roundCorners(&img, radius: m.d(20))
            blocks.append(img)
            if post.platform != .capture, let credit = creditLine(post, doc: doc, maxWidth: inner, bold: true, size: 20, m) {
                blocks.append(credit)
            }
        } else {
            // Text-only post: header and text inside the cut line.
            blocks.append(header(post, width: inner, doc: doc, m))
            let text = truncated(post.text, to: maxTextLength)
            if !text.isEmpty {
                blocks.append(TextRenderer.render(text, font: m.font(21), align: .left, width: inner, lineSpacing: 2 * m.s).trimmedVertically())
            }
        }
        let content = MonoBitmap.stack(blocks, width: inner, spacing: m.d(12))
        var out = content.padded(top: pad, bottom: pad, left: pad, right: pad)
        let inset = max(1, m.d(3))
        out.strokeRect(x: inset, y: inset, width: out.width - 2 * inset, height: out.height - 2 * inset,
                       thickness: max(1, m.d(2)), radius: m.d(26), dash: m.d(8))
        return out
    }

    // MARK: Label

    /// A die-cut label: picture square on the left, auto-fitted name, @handle and one line of text on the right.
    static func label(_ post: SocialPost, doc: SocialDoc, model: PrinterModel, _ m: Metrics) -> MonoBitmap? {
        let H = model.dots(forMM: doc.labelHeightMM)
        guard H > 0 else { return nil }
        var out = MonoBitmap(width: m.W, height: H)
        let safe = model.dots(forMM: 1)
        let side = m.d(8)
        let boxH = H - 2 * safe
        guard boxH > 8 else { return out }

        if post.platform == .capture, let image = post.image(at: doc.imageIndex) {
            let boxW = m.W - 2 * side
            let aspect = Double(image.width) / Double(max(1, image.height))
            let w = min(boxW, Int(Double(boxH) * aspect))
            if let img = doc.pipeline.render(image, width: max(1, w)) {
                let clipped = img.height > boxH ? img.rows(((img.height - boxH) / 2)..<((img.height - boxH) / 2 + boxH)) : img
                out.blit(clipped, x: (m.W - clipped.width) / 2, y: safe + (boxH - clipped.height) / 2)
            }
            return out
        }

        let body = doc.showText ? post.text.components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ") : ""
        if !body.isEmpty {
            // The post text is the label: as big as fits, with a small signature underneath.
            let picture = post.platform == .instagram ? post.image(at: doc.imageIndex) : nil
            return textLabel(post, text: body, picture: picture, doc: doc, H: H, safe: safe, side: side, m)
        }

        // No text (photo-only posts): picture, name and handle.
        var textX = side
        let picture = post.image(at: doc.imageIndex) ?? post.avatar
        if let picture, let square = squareCropped(picture), let gray = GrayImage(cgImage: square, width: boxH) {
            var img = doc.pipeline.process(gray)
            roundCorners(&img, radius: max(2, boxH / 8))
            out.blit(img, x: side, y: safe)
            textX = side + boxH + m.d(12)
        }
        let textW = m.W - side - textX
        guard textW > 20 else { return out }
        let nameFont = fittingFont(post.displayName, weight: .bold, width: textW, maxSize: CGFloat(boxH) * 0.36, minSize: 10)
        let lines = [line(post.displayName, font: nameFont, maxWidth: textW),
                     line(secondaryLine(post), font: NSFont.systemFont(ofSize: max(9, CGFloat(boxH) * 0.2)), maxWidth: textW)]
        let total = lines.reduce(0) { $0 + $1.height }
        var y = safe + max(0, (boxH - total) / 2)
        for l in lines {
            out.blit(l, x: textX, y: y)
            y += l.height
        }
        return out
    }

    /// Label whose main content is the post text, wrapped at the largest size that fits,
    /// with a quote bar on the left (or the photo, for Instagram) and a one-line signature at the bottom.
    static func textLabel(_ post: SocialPost, text: String, picture: CGImage?, doc: SocialDoc,
                          H: Int, safe: Int, side: Int, _ m: Metrics) -> MonoBitmap {
        var out = MonoBitmap(width: m.W, height: H)
        let boxH = H - 2 * safe
        var x = side
        if let picture, let square = squareCropped(picture), let gray = GrayImage(cgImage: square, width: boxH) {
            var img = doc.pipeline.process(gray)
            roundCorners(&img, radius: max(2, boxH / 8))
            out.blit(img, x: x, y: safe)
            x += boxH + m.d(10)
        } else {
            out.fillRect(x: x, y: safe, width: max(2, m.d(3)), height: boxH)
            x += max(2, m.d(3)) + m.d(9)
        }
        let width = m.W - side - x

        // Signature: platform mark, @handle and date, small.
        let signatureSize = max(9, CGFloat(boxH) * 0.15)
        let mark = platformMark(post.platform, size: Int(signatureSize * 1.05))
        var signature = secondaryLine(post)
        if doc.showDate, let date = post.date { signature += " · " + shortDate.string(from: date) }
        let signatureLine = line(signature, font: NSFont.systemFont(ofSize: signatureSize, weight: .medium), maxWidth: width - mark.width - m.d(5))
        let signatureH = max(mark.height, signatureLine.height)
        let signatureY = safe + boxH - signatureH
        out.blit(mark, x: x, y: signatureY + (signatureH - mark.height) / 2)
        out.blit(signatureLine, x: x + mark.width + m.d(5), y: signatureY + (signatureH - signatureLine.height) / 2)

        // Text: largest size whose wrapped height fits above the signature; at the minimum, truncate.
        let areaH = signatureY - safe - m.d(3)
        guard areaH > 8, width > 20 else { return out }
        func height(_ font: NSFont) -> CGFloat {
            NSAttributedString(string: text, attributes: [.font: font])
                .boundingRect(with: CGSize(width: CGFloat(width - 2), height: .greatestFiniteMagnitude),
                              options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        }
        // Below ~12 pt thermal text stops being legible: long posts switch to a condensed face, then truncate.
        let minSize = max(11, 12 * m.s), comfortable = 15 * m.s
        let faces: [(CGFloat) -> NSFont] = [
            { NSFont.systemFont(ofSize: $0, weight: .semibold) },
            { NSFont(name: "AvenirNextCondensed-DemiBold", size: $0 * 1.08) ?? NSFont.systemFont(ofSize: $0, weight: .semibold) },
        ]
        var font = faces[0](minSize)
        for (i, face) in faces.enumerated() {
            var lo = minSize, hi = max(minSize, CGFloat(areaH) * 0.62)
            while hi - lo > 0.5 {
                let mid = (lo + hi) / 2
                if height(face(mid)) <= CGFloat(areaH) { lo = mid } else { hi = mid }
            }
            font = face(lo)
            if lo >= comfortable || i == faces.count - 1 { break }
        }
        // Short posts: one line reads better than two slightly bigger ones with an orphan word.
        let oneLine = NSAttributedString(string: text, attributes: [.font: font]).size().width
        if oneLine > CGFloat(width - 2) {
            let singleSize = font.pointSize * CGFloat(width - 2) / oneLine
            if singleSize >= font.pointSize * 0.72, singleSize >= minSize { font = font.withSize(floor(singleSize)) }
        }
        // Truncate only when even the smallest size doesn't fit.
        let fits = height(font) <= CGFloat(areaH)
        let maxLines = fits ? 50 : max(1, Int(CGFloat(areaH) / (font.ascender - font.descender + font.leading)))
        let body = wrapped(text, font: font, width: width, maxLines: maxLines).trimmedVertically()
        out.blit(body, x: x, y: safe + max(0, (areaH - body.height) / 2))
        return out
    }

    // MARK: Captures

    static func captureCard(_ post: SocialPost, doc: SocialDoc, _ m: Metrics) -> MonoBitmap? {
        guard let image = post.image(at: doc.imageIndex) else { return nil }
        let t = max(1, m.d(2)), pad = t + m.d(6)
        guard var img = doc.pipeline.render(image, width: m.W - 2 * pad) else { return nil }
        roundCorners(&img, radius: m.d(8))
        var out = img.padded(top: pad, bottom: pad, left: pad, right: pad)
        out.strokeRect(x: 0, y: 0, width: out.width, height: out.height, thickness: t, radius: m.d(14))
        return out
    }

    // MARK: Pieces

    /// One unwrapped line, truncated with "…" to `maxWidth`.
    static func line(_ text: String, font: NSFont, maxWidth: Int) -> MonoBitmap {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        guard !clean.isEmpty, maxWidth > 0 else { return MonoBitmap(width: max(1, maxWidth), height: 0) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let string = NSAttributedString(string: clean, attributes: [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraph])
        let width = min(maxWidth, Int(ceil(string.size().width)) + 2)
        let height = Int(ceil(font.ascender - font.descender)) + 2
        return TextRenderer.draw(width: width, height: height) {
            string.draw(with: CGRect(x: 0, y: 1, width: CGFloat(width), height: CGFloat(height)),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    /// Word-wrapped text limited to `maxLines`, the last one truncated with "…".
    static func wrapped(_ text: String, font: NSFont, width: Int, maxLines: Int) -> MonoBitmap {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let string = NSAttributedString(string: text.replacingOccurrences(of: "\n", with: " "),
                                        attributes: [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraph])
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let full = string.boundingRect(with: CGSize(width: CGFloat(width), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = Int(min(ceil(full.height), lineHeight * CGFloat(maxLines))) + 2
        return TextRenderer.draw(width: width, height: height) {
            string.draw(with: CGRect(x: 0, y: 1, width: CGFloat(width), height: CGFloat(height - 1)),
                        options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
        }.trimmedVertically()
    }

    static func fittingFont(_ text: String, weight: NSFont.Weight, width: Int, maxSize: CGFloat, minSize: CGFloat) -> NSFont {
        var size = maxSize
        while size > minSize {
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            if NSAttributedString(string: text, attributes: [.font: font]).size().width + 2 <= CGFloat(width) { return font }
            size -= 0.5
        }
        return .systemFont(ofSize: minSize, weight: weight)
    }

    /// Dithered circular avatar with a thin ring; a filled circle with the initial when there is no picture.
    static func avatar(_ image: CGImage?, initial: String, diameter d: Int, pipeline: ImagePipeline) -> MonoBitmap {
        var bmp: MonoBitmap
        if let image, let square = squareCropped(image), let gray = GrayImage(cgImage: square, width: d) {
            bmp = pipeline.process(gray)
        } else {
            let letter = initial.first.map { String($0).uppercased() } ?? "?"
            let font = NSFont.systemFont(ofSize: CGFloat(d) * 0.48, weight: .bold)
            let string = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: NSColor.white])
            bmp = TextRenderer.draw(width: d, height: d) {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: CGRect(x: 0, y: 0, width: d, height: d)).fill()
                let size = string.size()
                string.draw(at: CGPoint(x: (CGFloat(d) - size.width) / 2, y: (CGFloat(d) - size.height) / 2))
            }
        }
        let r = Double(d) / 2
        for y in 0..<d {
            for x in 0..<d {
                let dist = ((Double(x) + 0.5 - r) * (Double(x) + 0.5 - r) + (Double(y) + 0.5 - r) * (Double(y) + 0.5 - r)).squareRoot()
                if dist > r { bmp[x, y] = false } else if dist > r - 1.6 { bmp[x, y] = true }
            }
        }
        return bmp
    }

    /// Clears the pixels outside a rounded rectangle.
    static func roundCorners(_ bmp: inout MonoBitmap, radius: Int) {
        let r = min(radius, bmp.width / 2, bmp.height / 2)
        guard r > 0 else { return }
        let rd = Double(r)
        for y in 0..<bmp.height {
            let cy: Double
            if y < r { cy = rd } else if y >= bmp.height - r { cy = Double(bmp.height) - rd } else { continue }
            for x in 0..<bmp.width {
                let cx: Double
                if x < r { cx = rd } else if x >= bmp.width - r { cx = Double(bmp.width) - rd } else { continue }
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                if dx * dx + dy * dy > rd * rd { bmp[x, y] = false }
            }
        }
    }

    /// Small black X logo or Instagram glyph.
    static func platformMark(_ platform: SocialPlatform, size: Int) -> MonoBitmap {
        guard size > 4 else { return MonoBitmap(width: max(1, size), height: max(1, size)) }
        return TextRenderer.draw(width: size, height: size) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            let S = CGFloat(size)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            switch platform {
            case .x:
                // The X logo (viewBox 1200×1227), even-odd filled.
                let k = S / 1227, ox = (S - 1200 * k) / 2
                func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * k, y: y * k) }
                let outer: [(CGFloat, CGFloat)] = [(714.163, 519.284), (1160.89, 0), (1055.03, 0), (667.137, 450.887), (357.328, 0), (0, 0),
                                                   (468.492, 681.821), (0, 1226.37), (105.866, 1226.37), (515.491, 750.218),
                                                   (842.672, 1226.37), (1200, 1226.37)]
                let inner: [(CGFloat, CGFloat)] = [(569.165, 687.828), (521.697, 619.934), (144.011, 79.6944), (306.615, 79.6944),
                                                   (611.412, 515.685), (658.88, 583.579), (1055.08, 1150.3), (892.476, 1150.3)]
                let path = CGMutablePath()
                path.addLines(between: outer.map { p($0.0, $0.1) })
                path.closeSubpath()
                path.addLines(between: inner.map { p($0.0, $0.1) })
                path.closeSubpath()
                ctx.addPath(path)
                ctx.fillPath(using: .evenOdd)
            case .instagram:
                let lw = max(1.5, S * 0.1)
                let frame = CGRect(x: lw / 2, y: lw / 2, width: S - lw, height: S - lw)
                ctx.setLineWidth(lw)
                ctx.addPath(CGPath(roundedRect: frame, cornerWidth: S * 0.28, cornerHeight: S * 0.28, transform: nil))
                ctx.strokePath()
                ctx.strokeEllipse(in: CGRect(x: S * 0.5 - S * 0.21, y: S * 0.5 - S * 0.21, width: S * 0.42, height: S * 0.42))
                ctx.fillEllipse(in: CGRect(x: S * 0.74 - S * 0.065, y: S * 0.26 - S * 0.065, width: S * 0.13, height: S * 0.13))
            case .capture:
                break
            }
        }
    }

    static func symbolImage(_ name: String, pointSize: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    // MARK: Helpers

    /// "@handle" under the name; "Instagram" when the name already is the handle (embeds don't expose display names).
    static func secondaryLine(_ post: SocialPost) -> String {
        if post.handle.isEmpty { return post.platform.title }
        if post.platform == .instagram, post.authorName.isEmpty || post.authorName == post.handle { return post.platform.title }
        return post.atHandle
    }

    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    /// 1234 → "1,2 k", 310173 → "310 k", 60279707 → "60,3 M" (Spanish decimal comma).
    static func compactNumber(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        var value = Double(n) / 1000
        var suffix = "k"
        func round(_ v: Double) -> Double { v < 100 ? (v * 10).rounded() / 10 : v.rounded() }
        if round(value) >= 1000 {
            value = Double(n) / 1_000_000
            suffix = "M"
        }
        let r = round(value)
        let formatted = r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",")
        return formatted + "\u{00A0}" + suffix
    }

    static func truncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        let end = cut.lastIndex(where: { $0 == " " || $0 == "\n" }) ?? cut.endIndex
        return String(cut[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func squareCropped(_ image: CGImage) -> CGImage? {
        let side = min(image.width, image.height)
        guard side > 0 else { return nil }
        return image.cropping(to: CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)) ?? image
    }

    /// Center-crops portraits taller than `maxAspect` (height / width).
    static func cropped(_ image: CGImage, maxAspect: Double) -> CGImage {
        let w = Double(image.width), h = Double(image.height)
        guard w > 0, h / w > maxAspect else { return image }
        let newH = w * maxAspect
        return image.cropping(to: CGRect(x: 0, y: ((h - newH) / 2).rounded(), width: w, height: newH.rounded())) ?? image
    }
}
