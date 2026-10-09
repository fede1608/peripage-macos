import CoreGraphics
import Foundation

/// 1-bit image in the printer's native layout: rows of MSB-first bytes, bit set = black dot.
public struct MonoBitmap: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var bytes: [UInt8]

    public var bytesPerRow: Int { (width + 7) / 8 }

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.bytes = Array(repeating: 0, count: ((width + 7) / 8) * height)
    }

    public init(width: Int, height: Int, bytes: [UInt8]) {
        precondition(bytes.count == ((width + 7) / 8) * height)
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// Packs a row-major black mask (true = black).
    public init(width: Int, height: Int, black: [Bool]) {
        precondition(black.count == width * height)
        self.init(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width where black[y * width + x] {
                bytes[y * bytesPerRow + x / 8] |= 0x80 >> UInt8(x % 8)
            }
        }
    }

    public subscript(x: Int, y: Int) -> Bool {
        get { bytes[y * bytesPerRow + x / 8] & (0x80 >> UInt8(x % 8)) != 0 }
        set {
            let i = y * bytesPerRow + x / 8
            let mask: UInt8 = 0x80 >> UInt8(x % 8)
            if newValue { bytes[i] |= mask } else { bytes[i] &= ~mask }
        }
    }

    public func rows(_ range: Range<Int>) -> MonoBitmap {
        let start = range.lowerBound * bytesPerRow
        let end = range.upperBound * bytesPerRow
        return MonoBitmap(width: width, height: range.count, bytes: Array(bytes[start..<end]))
    }

    public func split(maxRows: Int) -> [MonoBitmap] {
        guard height > maxRows else { return [self] }
        return stride(from: 0, to: height, by: maxRows).map { rows($0..<min($0 + maxRows, height)) }
    }

    /// Removes fully white rows at the top and bottom.
    public func trimmedVertically() -> MonoBitmap {
        let bpr = bytesPerRow
        func blank(_ y: Int) -> Bool { bytes[(y * bpr)..<((y + 1) * bpr)].allSatisfy { $0 == 0 } }
        var top = 0
        while top < height && blank(top) { top += 1 }
        guard top < height else { return MonoBitmap(width: width, height: 0) }
        var bottom = height
        while bottom > top && blank(bottom - 1) { bottom -= 1 }
        return rows(top..<bottom)
    }

    public var blackDotCount: Int { bytes.reduce(0) { $0 + $1.nonzeroBitCount } }

    /// Renders to a CGImage (black on white, or on a paper tint) for previews.
    public func cgImage(paper: UInt8 = 255, ink: UInt8 = 0) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: paper, count: width * height)
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width where bytes[rowStart + x / 8] & (0x80 >> UInt8(x % 8)) != 0 {
                pixels[y * width + x] = ink
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
