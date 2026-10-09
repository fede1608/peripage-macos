import AppKit
import PeriPageKit

public enum TextAlign: String, Codable, CaseIterable, Identifiable, Sendable {
    case left, center, right
    public var id: String { rawValue }
    public var icon: String {
        switch self {
        case .left: "text.alignleft"
        case .center: "text.aligncenter"
        case .right: "text.alignright"
        }
    }
}

public enum Formatters {
    public static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "d MMM yyyy · HH:mm"
        return f
    }()
}

/// Alpha channel of an image drawn at printer width (true = opaque).
public struct AlphaMask {
    public let width: Int
    public let height: Int
    public let mask: [Bool]

    public init?(cgImage image: CGImage, width: Int, transform: ImageTransform) {
        let rotated = transform.rotation.quarterTurns % 2 != 0
        let srcW = rotated ? image.height : image.width
        let srcH = rotated ? image.width : image.height
        let height = max(1, Int((Double(width) * Double(srcH) / Double(srcW)).rounded()))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        if transform.mirrored { ctx.scaleBy(x: -1, y: 1) }
        ctx.rotate(by: -CGFloat(transform.rotation.quarterTurns) * .pi / 2)
        let drawW = rotated ? CGFloat(height) : CGFloat(width)
        let drawH = rotated ? CGFloat(width) : CGFloat(height)
        ctx.draw(image, in: CGRect(x: -drawW / 2, y: -drawH / 2, width: drawW, height: drawH))
        guard let data = ctx.data else { return nil }
        let bpr = ctx.bytesPerRow
        let px = data.bindMemory(to: UInt8.self, capacity: bpr * height)
        var mask = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width { mask[y * width + x] = px[y * bpr + x] > 127 }
        }
        self.width = width
        self.height = height
        self.mask = mask
    }
}

public enum TextRenderer {
    public static func font(family: String, size: CGFloat, bold: Bool) -> NSFont {
        let traits: NSFontTraitMask = bold ? .boldFontMask : []
        return NSFontManager.shared.font(withFamily: family, traits: traits, weight: 5, size: size)
            ?? (bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size))
    }

    public static func attributed(_ text: String, font: NSFont, align: TextAlign, lineSpacing: CGFloat = 0, kern: CGFloat = 0) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = switch align {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        paragraph.lineSpacing = lineSpacing
        return NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraph, .kern: kern,
        ])
    }

    /// Renders wrapped text into a `width`-wide 1-bit block (antialiased, then thresholded).
    public static func render(_ text: String, font: NSFont, align: TextAlign, width: Int, lineSpacing: CGFloat = 0) -> MonoBitmap {
        guard !text.isEmpty, width > 0 else { return MonoBitmap(width: max(width, 1), height: 0) }
        let string = attributed(text, font: font, align: align, lineSpacing: lineSpacing)
        let bounds = string.boundingRect(with: CGSize(width: CGFloat(width), height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = max(1, Int(ceil(bounds.height)) + 2)
        return draw(width: width, height: height) {
            string.draw(with: CGRect(x: 0, y: 1, width: CGFloat(width), height: CGFloat(height)),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }

    /// Single unwrapped line, vertically centered in `height`.
    public static func renderLine(_ text: String, font: NSFont, kern: CGFloat, height: Int) -> MonoBitmap {
        let string = attributed(text.replacingOccurrences(of: "\n", with: " "), font: font, align: .left, kern: kern)
        let size = string.size()
        let width = max(1, Int(ceil(size.width)) + 4)
        let lineHeight = font.ascender - font.descender
        return draw(width: width, height: height) {
            string.draw(at: CGPoint(x: 2, y: (CGFloat(height) - lineHeight) / 2))
        }
    }

    /// Largest font size (≤ maxSize) whose longest line fits in `width`.
    public static func fittingFont(_ text: String, family: String, bold: Bool, width: Int, maxSize: CGFloat) -> NSFont {
        let longest = text.split(separator: "\n").map(String.init).max { $0.count < $1.count } ?? text
        var lo: CGFloat = 8, hi = maxSize
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            let w = attributed(longest, font: font(family: family, size: mid, bold: bold), align: .left).size().width
            if w <= CGFloat(width) { lo = mid } else { hi = mid }
        }
        return font(family: family, size: lo, bold: bold)
    }

    /// Runs AppKit drawing in a flipped white RGB bitmap and converts it to 1-bit:
    /// black text is thresholded (crisp edges) while colored glyphs such as emoji are dithered.
    public static func draw(width: Int, height: Int, _ body: () -> Void) -> MonoBitmap {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()

        let px = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var lum = [Float](repeating: 1, count: width * height)
        var colored = [Bool](repeating: false, count: width * height)
        var anyColor = false
        for i in 0..<(width * height) {
            let r = Float(px[i * 4]) / 255, g = Float(px[i * 4 + 1]) / 255, b = Float(px[i * 4 + 2]) / 255
            lum[i] = 0.299 * r + 0.587 * g + 0.114 * b
            if max(r, g, b) - min(r, g, b) > 0.12 { colored[i] = true; anyColor = true }
        }
        let gray = GrayImage(width: width, height: height, pixels: lum)
        var out = ImageProcessor.dither(gray, algorithm: .threshold, threshold: 0.55)
        guard anyColor else { return out }
        let darker = ImageProcessor.adjust(gray, ImageAdjustments(contrast: 1.2, gamma: 0.9))
        let dithered = ImageProcessor.dither(darker, algorithm: .atkinson)
        for i in colored.indices where colored[i] { out[i % width, i / width] = dithered[i % width, i / width] }
        return out
    }
}
