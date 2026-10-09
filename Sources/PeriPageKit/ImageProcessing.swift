import CoreGraphics
import Foundation

/// Grayscale image with luminance in 0...1 (0 = black, 1 = white).
public struct GrayImage: Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        precondition(pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: Float = 1) {
        self.init(width: width, height: height, pixels: Array(repeating: fill, count: width * height))
    }

    /// Draws `image` onto white, scaled to `width` (aspect preserved). Alpha is flattened over white.
    public init?(cgImage image: CGImage, width: Int, transform: ImageTransform = .init()) {
        let rotated = transform.rotation.quarterTurns % 2 != 0
        let srcW = rotated ? image.height : image.width
        let srcH = rotated ? image.width : image.height
        guard srcW > 0, srcH > 0, width > 0 else { return nil }
        let height = max(1, Int((Double(width) * Double(srcH) / Double(srcW)).rounded()))
        guard let ctx = GrayImage.makeContext(width: width, height: height) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        ctx.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        if transform.mirrored { ctx.scaleBy(x: -1, y: 1) }
        ctx.rotate(by: -CGFloat(transform.rotation.quarterTurns) * .pi / 2)
        let drawW = rotated ? CGFloat(height) : CGFloat(width)
        let drawH = rotated ? CGFloat(width) : CGFloat(height)
        ctx.draw(image, in: CGRect(x: -drawW / 2, y: -drawH / 2, width: drawW, height: drawH))
        self.init(context: ctx)
    }

    init?(context ctx: CGContext) {
        guard let data = ctx.data else { return nil }
        let w = ctx.width, h = ctx.height, bpr = ctx.bytesPerRow
        let src = data.bindMemory(to: UInt8.self, capacity: bpr * h)
        var px = [Float](repeating: 1, count: w * h)
        for y in 0..<h {
            for x in 0..<w { px[y * w + x] = Float(src[y * bpr + x]) / 255 }
        }
        self.init(width: w, height: h, pixels: px)
    }

    static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
    }

    public func cgImage() -> CGImage? {
        guard let ctx = GrayImage.makeContext(width: width, height: height), let data = ctx.data else { return nil }
        let bpr = ctx.bytesPerRow
        let dst = data.bindMemory(to: UInt8.self, capacity: bpr * height)
        for y in 0..<height {
            for x in 0..<width { dst[y * bpr + x] = UInt8(max(0, min(1, pixels[y * width + x])) * 255) }
        }
        return ctx.makeImage()
    }

    @inline(__always) public subscript(x: Int, y: Int) -> Float {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }
}

public struct ImageTransform: Codable, Equatable, Sendable {
    public enum Rotation: Int, Codable, CaseIterable, Sendable {
        case none = 0, right = 1, upsideDown = 2, left = 3
        public var quarterTurns: Int { rawValue }
        public func rotatedClockwise() -> Rotation { Rotation(rawValue: (rawValue + 1) % 4)! }
    }

    public var rotation: Rotation = .none
    public var mirrored = false

    public init(rotation: Rotation = .none, mirrored: Bool = false) {
        self.rotation = rotation
        self.mirrored = mirrored
    }
}

public enum DitherAlgorithm: String, CaseIterable, Codable, Sendable, Identifiable {
    case atkinson
    case floydSteinberg
    case stucki
    case bayer
    case halftone
    case threshold

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .atkinson: "Atkinson (fotos, alto contraste)"
        case .floydSteinberg: "Floyd–Steinberg (fotos, más detalle)"
        case .stucki: "Stucki (suave)"
        case .bayer: "Bayer (trama ordenada)"
        case .halftone: "Semitono (puntos de diario)"
        case .threshold: "Umbral (texto, logos)"
        }
    }
}

public struct ImageAdjustments: Codable, Equatable, Sendable {
    public static let recommendedPhoto = ImageAdjustments(contrast: 1.25, gamma: 1.3, sharpen: 0.6, autoLevels: true)

    /// Added to luminance, -1...1.
    public var brightness: Double = 0
    /// Multiplier around mid-gray, 0...3.
    public var contrast: Double = 1
    /// Applied as pow(x, 1/gamma); >1 lightens midtones (thermal paper prints dark).
    public var gamma: Double = 1
    /// Unsharp-mask amount, 0...3.
    public var sharpen: Double = 0
    /// Threshold used by `.threshold`, 0...1.
    public var threshold: Double = 0.5
    public var autoLevels = false
    public var invert = false

    public init(brightness: Double = 0, contrast: Double = 1, gamma: Double = 1, sharpen: Double = 0,
                threshold: Double = 0.5, autoLevels: Bool = false, invert: Bool = false) {
        self.brightness = brightness
        self.contrast = contrast
        self.gamma = gamma
        self.sharpen = sharpen
        self.threshold = threshold
        self.autoLevels = autoLevels
        self.invert = invert
    }
}

public enum ImageProcessor {
    public static func adjust(_ image: GrayImage, _ adj: ImageAdjustments) -> GrayImage {
        var img = image
        if adj.sharpen > 0 { img = sharpen(img, amount: Float(adj.sharpen)) }
        if adj.autoLevels { img = autoLevels(img) }
        let b = Float(adj.brightness), c = Float(adj.contrast), invGamma = Float(1 / max(0.05, adj.gamma))
        let applyGamma = abs(adj.gamma - 1) > 0.001
        for i in img.pixels.indices {
            var v = img.pixels[i]
            v = (v - 0.5) * c + 0.5 + b
            v = max(0, min(1, v))
            if applyGamma { v = powf(v, invGamma) }
            if adj.invert { v = 1 - v }
            img.pixels[i] = v
        }
        return img
    }

    public static func dither(_ image: GrayImage, algorithm: DitherAlgorithm, threshold: Double = 0.5) -> MonoBitmap {
        switch algorithm {
        case .threshold:
            let t = Float(threshold)
            return MonoBitmap(width: image.width, height: image.height, black: image.pixels.map { $0 < t })
        case .bayer:
            return ordered(image, matrix: bayer8, size: 8)
        case .halftone:
            return ordered(image, matrix: clusteredDot8, size: 8)
        case .floydSteinberg:
            return diffuse(image, kernel: [(1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1)], divisor: 16)
        case .atkinson:
            return diffuse(image, kernel: [(1, 0, 1), (2, 0, 1), (-1, 1, 1), (0, 1, 1), (1, 1, 1), (0, 2, 1)], divisor: 8)
        case .stucki:
            return diffuse(image, kernel: [
                (1, 0, 8), (2, 0, 4),
                (-2, 1, 2), (-1, 1, 4), (0, 1, 8), (1, 1, 4), (2, 1, 2),
                (-2, 2, 1), (-1, 2, 2), (0, 2, 4), (1, 2, 2), (2, 2, 1),
            ], divisor: 42)
        }
    }

    /// Error diffusion with serpentine scanning.
    static func diffuse(_ image: GrayImage, kernel: [(dx: Int, dy: Int, w: Float)], divisor: Float) -> MonoBitmap {
        let w = image.width, h = image.height
        var buf = image.pixels
        var black = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            let leftToRight = y % 2 == 0
            for i in 0..<w {
                let x = leftToRight ? i : w - 1 - i
                let idx = y * w + x
                let old = buf[idx]
                let new: Float = old < 0.5 ? 0 : 1
                black[idx] = new == 0
                let err = (old - new) / divisor
                for k in kernel {
                    let nx = x + (leftToRight ? k.dx : -k.dx), ny = y + k.dy
                    if nx >= 0, nx < w, ny < h { buf[ny * w + nx] += err * k.w }
                }
            }
        }
        return MonoBitmap(width: w, height: h, black: black)
    }

    static func ordered(_ image: GrayImage, matrix: [Int], size: Int) -> MonoBitmap {
        let n = Float(size * size)
        let w = image.width, h = image.height
        var black = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let t = (Float(matrix[(y % size) * size + (x % size)]) + 0.5) / n
                black[y * w + x] = image.pixels[y * w + x] < t
            }
        }
        return MonoBitmap(width: w, height: h, black: black)
    }

    static func sharpen(_ image: GrayImage, amount: Float) -> GrayImage {
        let w = image.width, h = image.height
        var out = image
        for y in 0..<h {
            for x in 0..<w {
                var sum: Float = 0
                for dy in -1...1 {
                    let yy = min(max(y + dy, 0), h - 1)
                    for dx in -1...1 {
                        let xx = min(max(x + dx, 0), w - 1)
                        sum += image.pixels[yy * w + xx]
                    }
                }
                let p = image.pixels[y * w + x]
                out.pixels[y * w + x] = max(0, min(1, p + amount * (p - sum / 9)))
            }
        }
        return out
    }

    static func autoLevels(_ image: GrayImage) -> GrayImage {
        guard !image.pixels.isEmpty else { return image }
        var hist = [Int](repeating: 0, count: 256)
        for p in image.pixels { hist[Int(max(0, min(1, p)) * 255)] += 1 }
        let total = image.pixels.count
        func percentile(_ q: Double) -> Float {
            var acc = 0
            for (i, c) in hist.enumerated() {
                acc += c
                if Double(acc) >= q * Double(total) { return Float(i) / 255 }
            }
            return 1
        }
        let lo = percentile(0.01), hi = percentile(0.99)
        guard hi - lo > 0.05 else { return image }
        var out = image
        for i in out.pixels.indices { out.pixels[i] = max(0, min(1, (out.pixels[i] - lo) / (hi - lo))) }
        return out
    }

    static let bayer8: [Int] = [
        0, 32, 8, 40, 2, 34, 10, 42,
        48, 16, 56, 24, 50, 18, 58, 26,
        12, 44, 4, 36, 14, 46, 6, 38,
        60, 28, 52, 20, 62, 30, 54, 22,
        3, 35, 11, 43, 1, 33, 9, 41,
        51, 19, 59, 27, 49, 17, 57, 25,
        15, 47, 7, 39, 13, 45, 5, 37,
        63, 31, 55, 23, 61, 29, 53, 21,
    ]

    /// Clustered-dot (spiral) matrix: dots grow from the cell center, like newspaper halftone.
    static let clusteredDot8: [Int] = [
        24, 10, 12, 26, 35, 47, 49, 37,
        8, 0, 2, 14, 45, 59, 61, 51,
        22, 6, 4, 16, 43, 57, 63, 53,
        30, 20, 18, 28, 33, 41, 55, 39,
        34, 46, 48, 36, 25, 11, 13, 27,
        44, 58, 60, 50, 9, 1, 3, 15,
        42, 56, 62, 52, 23, 7, 5, 17,
        32, 40, 54, 38, 31, 21, 19, 29,
    ]
}

/// Full pipeline: source image → printer-width grayscale → adjustments → 1-bit.
public struct ImagePipeline: Codable, Equatable, Sendable {
    public var adjustments = ImageAdjustments()
    public var algorithm: DitherAlgorithm = .atkinson
    public var transform = ImageTransform()

    /// Chosen from print tests on a PeriPage A6 (203 dpi) at high density: Stucki + tone "#6".
    public static let recommendedPhoto = ImagePipeline(adjustments: .recommendedPhoto, algorithm: .stucki)

    public init(adjustments: ImageAdjustments = .init(), algorithm: DitherAlgorithm = .atkinson, transform: ImageTransform = .init()) {
        self.adjustments = adjustments
        self.algorithm = algorithm
        self.transform = transform
    }

    public func render(_ image: CGImage, width: Int) -> MonoBitmap? {
        guard let gray = GrayImage(cgImage: image, width: width, transform: transform) else { return nil }
        return process(gray)
    }

    public func process(_ gray: GrayImage) -> MonoBitmap {
        ImageProcessor.dither(ImageProcessor.adjust(gray, adjustments), algorithm: algorithm, threshold: adjustments.threshold)
    }
}
