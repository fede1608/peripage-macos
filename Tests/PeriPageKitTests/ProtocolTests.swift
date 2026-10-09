import Testing
@testable import PeriPageKit

@Suite struct ModelDetectionTests {
    @Test func detectsClassicA6() {
        #expect(PrinterModel.detect(bluetoothName: "PeriPage_3F2A") == .a6)
        #expect(PrinterModel.detect(bluetoothName: "PeriPage_3F2A_BLE") == .a6)
    }

    @Test func detectsA6Plus() {
        #expect(PrinterModel.detect(bluetoothName: "PeriPage+3F2A") == .a6Plus)
    }

    @Test func detectsNewA6Variants() {
        #expect(PrinterModel.detect(bluetoothName: "PPG_A6_SD_1234") == .a6New)
        #expect(PrinterModel.detect(bluetoothName: "PPG_A6_HD_1234") == .a6NewHD)
        #expect(PrinterModel.detect(bluetoothName: "PPG_A6_UHD_1234") == .a6NewHD)
    }

    @Test func ignoresOtherModels() {
        #expect(PrinterModel.detect(bluetoothName: "PeriPage_A9s") == nil)
        #expect(PrinterModel.detect(bluetoothName: "PeriPage_A8_1234") == nil)
    }
}

@Suite struct EncodingTests {
    @Test func rasterHeaderIsLittleEndian() {
        let bmp = MonoBitmap(width: 384, height: 300)
        let bytes = PeriPageCommand.raster(bmp)
        #expect(Array(bytes.prefix(8)) == [0x1D, 0x76, 0x30, 0x00, 48, 0, 0x2C, 0x01])
        #expect(bytes.count == 8 + 48 * 300)
    }

    @Test func jobMatchesOfficialSequence() {
        var bmp = MonoBitmap(width: 384, height: 2)
        bmp[0, 0] = true
        bmp[383, 1] = true
        let job = PrintJobEncoder.encode(bmp, model: .a6)
        var expected: [UInt8] = [0x10, 0xFF, 0xFE, 0x01] + Array(repeating: 0, count: 12)
        expected += [0x1D, 0x76, 0x30, 0x00, 48, 0, 2, 0]
        var row0 = [UInt8](repeating: 0, count: 48); row0[0] = 0x80
        var row1 = [UInt8](repeating: 0, count: 48); row1[47] = 0x01
        expected += row0 + row1
        expected += [0x1B, 0x4A, 104]
        expected += [0x10, 0xFF, 0xFE, 0x45]
        #expect(job == expected)
    }

    @Test func bottomMarginAddsTearOffset() {
        // 6 mm margin + 6 mm head-to-tear-bar at 8 dots/mm.
        #expect(PrinterModel.a6.feedDots(bottomMarginMM: 6) == 96)
        #expect(PrinterModel.a6.feedDots(bottomMarginMM: 0) == 48)
        // Default: bottom margin equal to the measured 7 mm top margin → 13 mm feed.
        #expect(PrinterModel.a6.trailingFeedDots == 104)
    }

    @Test func longFeedIsSplit() {
        #expect(PeriPageCommand.feed(dots: 300) == [0x1B, 0x4A, 255, 0x1B, 0x4A, 45])
        #expect(PeriPageCommand.feed(dots: 0).isEmpty)
    }

    @Test func densityUsesModelScale() {
        #expect(PeriPageCommand.density(PrinterModel.a6NewHD.densityValues[2]) == [0x10, 0xFF, 0x10, 0x00, 4])
    }

    @Test func copiesRepeatRaster() {
        let bmp = MonoBitmap(width: 384, height: 1)
        let job = PrintJobEncoder.encode(bmp, model: .a6, options: .init(copies: 2, gapBetweenCopiesDots: 24))
        let rasterCount = job.indices.dropLast(3).filter { job[$0] == 0x1D && job[$0 + 1] == 0x76 && job[$0 + 2] == 0x30 }.count
        #expect(rasterCount == 2)
    }
}

@Suite struct EventParsingTests {
    @Test func parsesEvents() {
        #expect(PrinterEvent.parse([0xAA]) == .printFinished)
        #expect(PrinterEvent.parse([0xFF, 0x01]) == .outOfPaper)
        #expect(PrinterEvent.parse([0xFF, 0x03]) == .overheat)
        #expect(PrinterEvent.parse([0x4F, 0x4B]) == .ok)
        #expect(PrinterEvent.parse([0x00, 0x55]) == nil)
    }

    @Test func firmwareStringIsCleaned() {
        #expect(ResponseText.firmware(Array("V1.31_A6OK".utf8)) == "V1.31")
    }
}

@Suite struct ImageTests {
    @Test func packsMSBFirst() {
        var bmp = MonoBitmap(width: 10, height: 1)
        bmp[0, 0] = true
        bmp[9, 0] = true
        #expect(bmp.bytes == [0x80, 0x40])
        #expect(bmp[9, 0])
        #expect(!bmp[8, 0])
    }

    @Test func ditherKeepsAverageTone() {
        let gray = GrayImage(width: 64, height: 64, fill: 0.5)
        for algorithm in DitherAlgorithm.allCases where algorithm != .threshold {
            let bmp = ImageProcessor.dither(gray, algorithm: algorithm)
            let ratio = Double(bmp.blackDotCount) / Double(64 * 64)
            #expect(abs(ratio - 0.5) < 0.06, "\(algorithm) ratio \(ratio)")
        }
    }

    @Test func orderedMatricesArePermutations() {
        #expect(ImageProcessor.bayer8.sorted() == Array(0..<64))
        #expect(ImageProcessor.clusteredDot8.sorted() == Array(0..<64))
    }

    @Test func trimsBlankRows() {
        var bmp = MonoBitmap(width: 8, height: 5)
        bmp[3, 2] = true
        #expect(bmp.trimmedVertically().height == 1)
    }
}
