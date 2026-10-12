import AppKit
import PeriPageKit
import PeriRender

/// Instagram post in the app's classic layout: header with avatar and username, edge-to-edge photo,
/// action icons, likes, "username caption", comments link and date.
extension SocialRenderer {
    static func instagramCard(_ post: SocialPost, doc: SocialDoc, _ m: SocialRenderer.Metrics) -> MonoBitmap {
        let side = m.d(12)
        let inner = m.W - 2 * side
        var blocks: [(bitmap: MonoBitmap, x: Int, gap: Int)] = []

        // Header: avatar · username ··· ellipsis.
        let avatarSize = m.d(36)
        let name = line(post.handle.isEmpty ? post.displayName : post.handle, font: m.font(17, .semibold),
                        maxWidth: inner - avatarSize - m.d(44))
        let headerH = max(avatarSize, name.height) + m.d(4)
        var header = MonoBitmap(width: inner, height: headerH)
        header.blit(avatar(post.avatar, initial: post.displayName, diameter: avatarSize, pipeline: doc.pipeline), x: 0, y: (headerH - avatarSize) / 2)
        header.blit(name, x: avatarSize + m.d(10), y: (headerH - name.height) / 2)
        if let dots = icon("ellipsis", size: m.s * 20, m) {
            header.blit(dots, x: inner - dots.width, y: (headerH - dots.height) / 2)
        }
        blocks.append((header, side, m.d(10)))

        // Photo, full bleed, cropped like Instagram (between 4:5 portrait and 1.91:1 landscape).
        let index = min(max(0, doc.imageIndex), max(0, post.images.count - 1))
        if let image = post.image(at: index), var photo = doc.pipeline.render(instagramCrop(image), width: m.W) {
            if post.images.count > 1 {
                // White outline first, so the black pill also reads over dark photos.
                let badge = counterBadge("\(index + 1)/\(post.images.count)", m)
                let halo = max(1, m.d(2))
                let outline = pill(width: badge.width + 2 * halo, height: badge.height + 2 * halo)
                let bx = m.W - badge.width - m.d(10), by = m.d(10)
                for y in 0..<outline.height {
                    for x in 0..<outline.width where outline[x, y] {
                        let px = bx - halo + x, py = by - halo + y
                        if px >= 0, px < photo.width, py >= 0, py < photo.height { photo[px, py] = false }
                    }
                }
                photo.blit(badge, x: bx, y: by)
            }
            blocks.append((photo, 0, m.d(8)))
        }

        // Actions: ♡ 💬 ✈ ··· 🔖, with carousel dots in the middle.
        let iconSize = m.s * 25
        let actions = ["heart", "message", "paperplane"].compactMap { icon($0, size: iconSize, m) }
        let rowH = (actions.map(\.height).max() ?? m.d(26)) + m.d(4)
        var row = MonoBitmap(width: inner, height: rowH)
        var x = 0
        for a in actions {
            row.blit(a, x: x, y: (rowH - a.height) / 2)
            x += a.width + m.d(16)
        }
        if let bookmark = icon("bookmark", size: iconSize, m) {
            row.blit(bookmark, x: inner - bookmark.width, y: (rowH - bookmark.height) / 2)
        }
        if post.images.count > 1 {
            let dots = carouselDots(count: post.images.count, selected: index, m)
            row.blit(dots, x: (inner - dots.width) / 2, y: (rowH - dots.height) / 2)
        }
        blocks.append((row, side, m.d(8)))

        if doc.showStats, let likes = post.likes, likes > 0 {
            blocks.append((line("\(spanishThousands(likes)) Me gusta", font: m.font(17, .semibold), maxWidth: inner), side, m.d(6)))
        }
        let text = truncated(post.text, to: maxTextLength)
        if doc.showText, !text.isEmpty {
            blocks.append((caption(user: post.handle, text: text, width: inner, m), side, m.d(4)))
        }
        if doc.showStats, let comments = post.replies, comments > 0 {
            let label = comments == 1 ? "Ver 1 comentario" : "Ver los \(spanishThousands(comments)) comentarios"
            blocks.append((line(label, font: m.font(16), maxWidth: inner), side, m.d(4)))
        }
        if doc.showDate, let date = post.date {
            blocks.append((line(instagramDate.string(from: date).uppercased(), font: m.font(12, .medium), maxWidth: inner), side, m.d(6)))
        }

        let height = blocks.reduce(0) { $0 + $1.bitmap.height + $1.gap } + m.d(12)
        var out = MonoBitmap(width: m.W, height: height)
        var y = 0
        for block in blocks {
            y += block.gap
            out.blit(block.bitmap, x: block.x, y: y)
            y += block.bitmap.height
        }
        return out
    }

    static func instagramCrop(_ image: CGImage) -> CGImage {
        let w = Double(image.width), h = Double(image.height)
        guard w > 0, h > 0 else { return image }
        if h / w > 1.25 { return cropped(image, maxAspect: 1.25) }
        if w / h > 1.91 {
            let newW = h * 1.91
            return image.cropping(to: CGRect(x: ((w - newW) / 2).rounded(), y: 0, width: newW.rounded(), height: h)) ?? image
        }
        return image
    }

    /// "username caption…" with the username in bold, wrapped.
    static func caption(user: String, text: String, width: Int, _ m: SocialRenderer.Metrics) -> MonoBitmap {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2 * m.s
        let string = NSMutableAttributedString()
        if !user.isEmpty {
            string.append(NSAttributedString(string: user + " ", attributes: [.font: m.font(17, .semibold), .paragraphStyle: paragraph]))
        }
        string.append(NSAttributedString(string: text, attributes: [.font: m.font(17), .paragraphStyle: paragraph]))
        string.addAttribute(.foregroundColor, value: NSColor.black, range: NSRange(location: 0, length: string.length))
        let bounds = string.boundingRect(with: CGSize(width: CGFloat(width), height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = Int(ceil(bounds.height)) + 2
        return TextRenderer.draw(width: width, height: height) {
            string.draw(with: CGRect(x: 0, y: 1, width: CGFloat(width), height: CGFloat(height)), options: [.usesLineFragmentOrigin, .usesFontLeading])
        }.trimmedVertically()
    }

    /// Black SF Symbol trimmed to its ink.
    static func icon(_ name: String, size: CGFloat, _ m: SocialRenderer.Metrics) -> MonoBitmap? {
        guard let image = symbolImage(name, pointSize: size) else { return nil }
        let w = Int(ceil(image.size.width)) + 4, h = Int(ceil(image.size.height)) + 4
        let bitmap = TextRenderer.draw(width: w, height: h) {
            image.draw(in: CGRect(x: 2, y: 2, width: image.size.width, height: image.size.height), from: .zero,
                       operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        return bitmap.trimmedVertically()
    }

    /// "2/5" in white on a black rounded pill, like Instagram's carousel counter.
    static func counterBadge(_ text: String, _ m: SocialRenderer.Metrics) -> MonoBitmap {
        let label = line(text, font: m.font(13, .semibold), maxWidth: m.d(80)).trimmedVertically()
        let padX = m.d(8), padY = m.d(4)
        var badge = pill(width: label.width + 2 * padX, height: label.height + 2 * padY)
        for y in 0..<label.height {
            for x in 0..<label.width where label[x, y] { badge[x + padX, y + padY] = false }
        }
        return badge
    }

    /// A filled capsule (fully rounded ends).
    static func pill(width: Int, height: Int) -> MonoBitmap {
        var out = MonoBitmap(width: width, height: height)
        let radius = Double(height) / 2
        for y in 0..<height {
            for x in 0..<width {
                let cx = min(max(Double(x) + 0.5, radius), Double(width) - radius)
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - radius
                if dx * dx + dy * dy <= radius * radius { out[x, y] = true }
            }
        }
        return out
    }

    /// Carousel position: the selected dot filled, the others as rings.
    static func carouselDots(count: Int, selected: Int, _ m: SocialRenderer.Metrics) -> MonoBitmap {
        let shown = min(count, 7)
        let r = max(2, m.d(3)), gap = m.d(5)
        let canvas = MonoCanvas(width: shown * 2 * r + (shown - 1) * gap + 2, height: 2 * r + 2)
        for i in 0..<shown {
            let rect = CGRect(x: 1 + i * (2 * r + gap), y: 1, width: 2 * r, height: 2 * r)
            if i == min(selected, shown - 1) {
                canvas.context.fillEllipse(in: rect)
            } else {
                canvas.context.setLineWidth(1.2)
                canvas.context.strokeEllipse(in: rect.insetBy(dx: 0.6, dy: 0.6))
            }
        }
        return canvas.makeBitmap()
    }

    /// 1234 → "1.234" (Instagram writes exact counts with a dot as thousands separator).
    static func spanishThousands(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    static let instagramDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "d 'de' MMMM 'de' yyyy"
        return f
    }()
}
