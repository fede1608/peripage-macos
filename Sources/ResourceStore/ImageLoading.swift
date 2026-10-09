import AppKit
import ImageIO
import PeriPageKit

/// SVG → CGImage with transparency. macOS 14+ renders SVG natively through NSImage, so no WebKit is needed.
enum SVGRasterizer {
    static func isSVG(_ data: Data) -> Bool {
        guard let head = String(data: data.prefix(1024), encoding: .utf8) else { return false }
        return head.range(of: "<svg", options: .caseInsensitive) != nil
    }

    /// Rasterizes so the longest side is `maxPixel` pixels (aspect preserved), on a transparent background.
    static func rasterize(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0, maxPixel > 0 else { return nil }
        let scale = CGFloat(maxPixel) / max(image.size.width, image.size.height)
        let width = max(1, Int((image.size.width * scale).rounded()))
        let height = max(1, Int((image.size.height * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}

enum ImageDecoder {
    /// Decodes PNG/JPEG/GIF/WebP/HEIC (or SVG), downscaled so the longest side is at most `maxPixel`.
    static func decode(_ data: Data, maxPixel: Int) -> CGImage? {
        if SVGRasterizer.isSVG(data) { return SVGRasterizer.rasterize(data, maxPixel: maxPixel) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        // Check a downscaled copy for actual transparent pixels.
        let side = 64
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let raw = ctx.data else { return true }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let alpha = raw.bindMemory(to: UInt8.self, capacity: side * side)
        for i in 0..<(side * side) where alpha[i] < 250 { return true }
        return false
    }
}

/// 1-bit rendering exactly as the printer would produce it, for the "Vista térmica" toggle.
enum ThermalPreview {
    static func pipeline(for style: ThermalStyle) -> ImagePipeline {
        switch style {
        case .lineArt: ImagePipeline(adjustments: ImageAdjustments(threshold: 0.5), algorithm: .threshold)
        case .colorArt: ImagePipeline(adjustments: ImageAdjustments(contrast: 1.15, gamma: 1.1), algorithm: .atkinson)
        case .photo: .recommendedPhoto
        }
    }

    static func bitmap(_ image: CGImage, style: ThermalStyle, width: Int) -> MonoBitmap? {
        pipeline(for: style).render(image, width: width)
    }

    static func image(_ image: CGImage, style: ThermalStyle, width: Int) -> CGImage? {
        bitmap(image, style: style, width: width)?.cgImage(paper: 255, ink: 28)
    }
}

/// Loads thumbnails, full-resolution images and their thermal previews, with an in-memory cache.
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader(http: .shared)

    /// Size of vector resources handed to the app.
    static let vectorPixels = 1536
    /// Photos are downscaled to this (the printer is 384 dots wide).
    static let photoPixels = 2400

    let http: StoreHTTP
    private let cache = NSCache<NSString, ImageBox>()

    private final class ImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    init(http: StoreHTTP) {
        self.http = http
        cache.totalCostLimit = 384 << 20
    }

    private func cached(_ key: String) -> CGImage? { cache.object(forKey: key as NSString)?.image }

    private func store(_ image: CGImage, _ key: String) {
        cache.setObject(ImageBox(image), forKey: key as NSString, cost: image.bytesPerRow * image.height)
    }

    private func decode(_ data: Data, maxPixel: Int) async throws -> CGImage {
        let image = await Task.detached(priority: .userInitiated) { ImageDecoder.decode(data, maxPixel: maxPixel) }.value
        guard let image else { throw StoreError.unsupportedImage }
        return image
    }

    func thumbnail(_ item: ResourceItem, maxPixel: Int = 256) async throws -> CGImage {
        let key = "thumb|\(item.id)|\(maxPixel)"
        if let image = cached(key) { return image }
        let image: CGImage
        switch item.source {
        case .svg(let url):
            image = try await decode(try await http.data(from: url, policy: .returnCacheDataElseLoad), maxPixel: maxPixel)
        case .remote(let thumbnail, _):
            image = try await decode(try await http.data(from: thumbnail, policy: .returnCacheDataElseLoad), maxPixel: maxPixel)
        case .file(let url):
            image = try await decode(try Data(contentsOf: url), maxPixel: maxPixel)
        }
        store(image, key)
        return image
    }

    /// High-resolution image with transparency preserved; photos fall back to the thumbnail if the original fails.
    func full(_ item: ResourceItem) async throws -> CGImage {
        let key = "full|\(item.id)"
        if let image = cached(key) { return image }
        let image: CGImage
        switch item.source {
        case .svg(let url):
            image = try await decode(try await http.data(from: url, policy: .returnCacheDataElseLoad), maxPixel: Self.vectorPixels)
        case .remote(let thumbnail, let full):
            do {
                let data = try await http.data(from: full, policy: .returnCacheDataElseLoad, timeout: 40)
                image = try await decode(data, maxPixel: Self.photoPixels)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let data = try await http.data(from: thumbnail, policy: .returnCacheDataElseLoad)
                image = try await decode(data, maxPixel: Self.photoPixels)
            }
        case .file(let url):
            image = try await decode(try Data(contentsOf: url), maxPixel: 8192)
        }
        store(image, key)
        return image
    }

    func thermal(_ item: ResourceItem, from image: CGImage, width: Int) async -> CGImage? {
        let key = "thermal|\(item.id)|\(width)|\(image.width)"
        if let cachedImage = cached(key) { return cachedImage }
        let style = item.style
        let result = await Task.detached(priority: .userInitiated) { ThermalPreview.image(image, style: style, width: width) }.value
        if let result { store(result, key) }
        return result
    }
}
