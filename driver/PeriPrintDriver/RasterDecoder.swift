import Foundation
import PeriPageKit

/// Decoders for the raster formats macOS sends to IPP Everywhere / AirPrint printers.
/// PWG Raster: PWG 5102.4 ("RaS2"); Apple Raster: "UNIRAST". Both use the same per-line PackBits variant.
enum RasterDecoder {
    struct Page {
        var width: Int
        var height: Int
        var dpi: Int
        var gray: [Float]   // 0 = black, 1 = white
    }

    static func decode(_ data: Data) -> [Page]? {
        if data.starts(with: Array("RaS2".utf8)) { return decodePWG(data) }
        if data.starts(with: Array("UNIRAST".utf8)) { return decodeURF(data) }
        return nil
    }

    // MARK: PWG

    private static func decodePWG(_ data: Data) -> [Page]? {
        var r = Reader(data: data, offset: 4)
        var pages: [Page] = []
        while r.remaining >= 1796 {
            let header = r.offset
            func u32(_ at: Int) -> Int { Int(r.u32(at: header + at)) }
            let dpi = u32(276)
            let width = u32(372), height = u32(376)
            let bitsPerColor = u32(384), bitsPerPixel = u32(388), bytesPerLine = u32(392)
            let colorSpace = u32(400)
            r.offset += 1796
            guard width > 0, height > 0, bytesPerLine > 0, width * height < 80_000_000 else { return pages.isEmpty ? nil : pages }
            let bpp = max(1, bitsPerPixel / 8)
            // Fill for "rest of line" codes: white for gray/RGB, 0 for black-ink spaces.
            let blackInk = colorSpace == 3 || colorSpace == 6 // K, CMYK
            let white: UInt8 = blackInk ? 0x00 : 0xFF
            guard let lines = decodeLines(&r, height: height, bytesPerLine: bytesPerLine, bytesPerPixel: bitsPerPixel < 8 ? 1 : bpp, fill: white) else {
                return pages.isEmpty ? nil : pages
            }
            pages.append(Page(width: width, height: height, dpi: dpi,
                              gray: toGray(lines, width: width, height: height, bytesPerLine: bytesPerLine,
                                           bitsPerColor: bitsPerColor, bitsPerPixel: bitsPerPixel, blackInk: blackInk)))
        }
        return pages
    }

    // MARK: URF

    private static func decodeURF(_ data: Data) -> [Page]? {
        var r = Reader(data: data, offset: 12)   // "UNIRAST\0" + page count
        var pages: [Page] = []
        while r.remaining >= 32 {
            let h = r.offset
            let bitsPerPixel = Int(r.byte(at: h))
            let colorSpace = Int(r.byte(at: h + 1))
            let width = Int(r.u32(at: h + 12)), height = Int(r.u32(at: h + 16)), dpi = Int(r.u32(at: h + 20))
            r.offset += 32
            guard width > 0, height > 0, width * height < 80_000_000 else { return pages.isEmpty ? nil : pages }
            let bpp = max(1, bitsPerPixel / 8)
            let bytesPerLine = width * bpp
            guard let lines = decodeLines(&r, height: height, bytesPerLine: bytesPerLine, bytesPerPixel: bpp, fill: 0xFF) else {
                return pages.isEmpty ? nil : pages
            }
            // URF gray is luminance (255 = white); color spaces 1+ are RGB variants.
            _ = colorSpace
            pages.append(Page(width: width, height: height, dpi: dpi,
                              gray: toGray(lines, width: width, height: height, bytesPerLine: bytesPerLine,
                                           bitsPerColor: 8, bitsPerPixel: bitsPerPixel, blackInk: false)))
        }
        return pages
    }

    // MARK: Shared

    /// Line repeat byte, then PackBits per pixel: 0…127 repeat next pixel n+1 times, 129…255 copy 257−n pixels,
    /// 128 fills the rest of the line with the fill color.
    private static func decodeLines(_ r: inout Reader, height: Int, bytesPerLine: Int, bytesPerPixel: Int, fill: UInt8) -> [UInt8]? {
        var out = [UInt8](repeating: fill, count: height * bytesPerLine)
        var y = 0
        while y < height {
            guard r.remaining >= 1 else { return out }
            let repeatCount = Int(r.next()) + 1
            var line = [UInt8](repeating: fill, count: bytesPerLine)
            var x = 0
            while x < bytesPerLine {
                guard r.remaining >= 1 else { break }
                let n = Int(r.next())
                if n == 128 {
                    break
                } else if n < 128 {
                    let count = (n + 1) * bytesPerPixel
                    guard r.remaining >= bytesPerPixel else { return nil }
                    let pixel = r.read(bytesPerPixel)
                    for i in 0..<count where x + i < bytesPerLine { line[x + i] = pixel[i % bytesPerPixel] }
                    x += count
                } else {
                    let count = (257 - n) * bytesPerPixel
                    guard r.remaining >= count else { return nil }
                    let bytes = r.read(count)
                    for i in 0..<count where x + i < bytesPerLine { line[x + i] = bytes[i] }
                    x += count
                }
            }
            for k in 0..<repeatCount where y + k < height {
                out.replaceSubrange((y + k) * bytesPerLine..<(y + k + 1) * bytesPerLine, with: line)
            }
            y += repeatCount
        }
        return out
    }

    private static func toGray(_ bytes: [UInt8], width: Int, height: Int, bytesPerLine: Int,
                               bitsPerColor: Int, bitsPerPixel: Int, blackInk: Bool) -> [Float] {
        var gray = [Float](repeating: 1, count: width * height)
        for y in 0..<height {
            let row = y * bytesPerLine
            for x in 0..<width {
                let v: Float
                switch bitsPerPixel {
                case 1:
                    let bit = bytes[row + x / 8] & (0x80 >> UInt8(x % 8)) != 0
                    v = bit == blackInk ? 0 : 1
                case 8:
                    let b = Float(bytes[row + x]) / 255
                    v = blackInk ? 1 - b : b
                case 16:
                    v = Float(bytes[row + x * 2]) / 255
                case 24, 32:
                    let i = row + x * (bitsPerPixel / 8)
                    v = (0.299 * Float(bytes[i]) + 0.587 * Float(bytes[i + 1]) + 0.114 * Float(bytes[i + 2])) / 255
                default:
                    v = 1
                }
                gray[y * width + x] = v
            }
        }
        return gray
    }

    private struct Reader {
        let data: Data
        var offset: Int
        var remaining: Int { data.count - offset }

        func byte(at i: Int) -> UInt8 { data[data.startIndex + i] }
        func u32(at i: Int) -> UInt32 {
            (UInt32(byte(at: i)) << 24) | (UInt32(byte(at: i + 1)) << 16) | (UInt32(byte(at: i + 2)) << 8) | UInt32(byte(at: i + 3))
        }
        mutating func next() -> UInt8 {
            defer { offset += 1 }
            return byte(at: offset)
        }
        mutating func read(_ n: Int) -> [UInt8] {
            defer { offset += n }
            return Array(data[(data.startIndex + offset)..<(data.startIndex + offset + n)])
        }
    }
}
