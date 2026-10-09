import Foundation
import Testing
@testable import PeriPrintDriver

@Suite struct RasterDecoderTests {
    private func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }

    @Test func decodesAppleRasterGray() throws {
        var data: [UInt8] = Array("UNIRAST".utf8) + [0] + be32(1)
        var header = [UInt8](repeating: 0, count: 32)
        header[0] = 8   // bits per pixel
        header.replaceSubrange(12..<16, with: be32(4))
        header.replaceSubrange(16..<20, with: be32(3))
        header.replaceSubrange(20..<24, with: be32(203))
        data += header as [UInt8]
        // Two identical lines: 2 black pixels then 2 white (literal run of 4).
        data += [1, 253, 0, 0, 255, 255] as [UInt8]
        // Third line: one black pixel, then "fill the rest with white".
        data += [0, 0, 0, 128] as [UInt8]
        let pages = try #require(RasterDecoder.decode(Data(data)))
        #expect(pages.count == 1)
        #expect(pages[0].width == 4 && pages[0].height == 3 && pages[0].dpi == 203)
        #expect(pages[0].gray == [0, 0, 1, 1, 0, 0, 1, 1, 0, 1, 1, 1])
    }

    @Test func decodesPWGBlackBitmap() throws {
        var header = [UInt8](repeating: 0, count: 1796)
        func put(_ offset: Int, _ v: Int) { header.replaceSubrange(offset..<(offset + 4), with: be32(v)) }
        put(276, 203); put(280, 203)
        put(372, 16); put(376, 1)        // width, height
        put(384, 1); put(388, 1); put(392, 2)  // 1 bit per color/pixel, 2 bytes per line
        put(400, 3)                      // CUPS_CSPACE_K: 1 = black
        let data: [UInt8] = Array("RaS2".utf8) + header + [0, 255, 0xF0, 0x0F]
        let pages = try #require(RasterDecoder.decode(Data(data)))
        let row = pages[0].gray
        #expect(row.prefix(4).allSatisfy { $0 == 0 })
        #expect(row[4..<12].allSatisfy { $0 == 1 })
        #expect(row.suffix(4).allSatisfy { $0 == 0 })
    }
}
