import CoreGraphics
import Foundation
import PeriPageKit
import Testing
@testable import SocialKit

@Suite struct RendererTests {
    /// Gradient test image with a dark disc, `w`×`h` pixels.
    static func image(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<w {
            let v = CGFloat(x) / CGFloat(max(1, w - 1))
            ctx.setFillColor(red: v, green: 0.5, blue: 1 - v, alpha: 1)
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: h))
        }
        ctx.setFillColor(gray: 0.1, alpha: 1)
        ctx.fillEllipse(in: CGRect(x: w / 4, y: h / 4, width: w / 2, height: h / 2))
        return ctx.makeImage()!
    }

    static let posts: [SocialPost] = [
        SocialPost(platform: .x, url: URL(string: "https://x.com/jack/status/20"), authorName: "jack", handle: "jack", avatar: image(400, 400),
                   text: "just setting up my twttr", date: Date(timeIntervalSince1970: 1_142_974_214), likes: 310_173, replies: 18_074),
        SocialPost(platform: .x, authorName: "NASA Administrator Jared Isaacman", handle: "NASAAdmin", avatar: image(400, 400),
                   text: String(repeating: "Texto largo con emoji 🚀 y acentos áéíóú. ", count: 60), date: .now,
                   images: [image(450, 300), image(300, 450), image(270, 480)], likes: 6671, replies: 77, reposts: 12),
        SocialPost(platform: .instagram, handle: "natgeo", avatar: image(100, 100), text: "In the Alaska Peninsula, a brown bear…\n\nSee more",
                   date: .now, images: [image(1080, 721)], likes: 111_768, replies: 199),
        SocialPost(platform: .instagram, handle: "sin_avatar_ni_fotos"),
        SocialPost(platform: .capture, images: [image(1200, 804)]),
        SocialPost(platform: .capture, images: [image(400, 1600)]),
    ]

    @Test(arguments: SocialLayout.allCases)
    func everyLayoutIsExactlyPrinterWide(_ layout: SocialLayout) throws {
        for model in [PrinterModel.a6, .a6Plus] {
            for post in Self.posts {
                var doc = SocialDoc()
                doc.layout = layout
                // Out-of-range indices are clamped.
                for index in post.images.count > 1 ? [0, 5] : [0] {
                    doc.imageIndex = index
                    let bmp = try #require(SocialRenderer.render(post, doc: doc, model: model))
                    #expect(bmp.width == model.widthDots)
                    #expect(bmp.height > 0)
                    #expect(bmp.blackDotCount > 0)
                }
            }
        }
    }

    @Test(arguments: [10.0, 12, 15, 20, 25, 40])
    func labelHeightIsExact(_ mm: Double) throws {
        for model in [PrinterModel.a6, .a6Plus] {
            for post in Self.posts {
                var doc = SocialDoc()
                doc.layout = .label
                doc.labelHeightMM = mm
                let bmp = try #require(SocialRenderer.render(post, doc: doc, model: model))
                #expect(bmp.width == model.widthDots)
                #expect(bmp.height == model.dots(forMM: mm))
            }
        }
    }

    @Test func fifteenMillimeterLabelKeepsTheSafeInset() throws {
        var doc = SocialDoc()
        doc.layout = .label
        #expect(doc.labelHeightMM == 15)
        #expect(PrinterModel.a6.dots(forMM: 15) == 120)
        for post in Self.posts {
            let bmp = try #require(SocialRenderer.render(post, doc: doc, model: .a6))
            #expect(bmp.height == 120)
            let inset = PrinterModel.a6.dots(forMM: 1)
            for y in Array(0..<inset) + Array((bmp.height - inset)..<bmp.height) {
                #expect((0..<bmp.width).allSatisfy { !bmp[$0, y] }, "row \(y) should be blank")
            }
        }
    }

    @Test func togglesChangeTheCard() throws {
        let post = Self.posts[0]
        var doc = SocialDoc()
        let full = try #require(SocialRenderer.render(post, doc: doc, model: .a6))
        doc.showText = false
        doc.showStats = false
        doc.showDate = false
        let bare = try #require(SocialRenderer.render(post, doc: doc, model: .a6))
        #expect(bare.height < full.height)
    }

    @Test func instagramCardShowsTheChosenCarouselPhoto() throws {
        let post = SocialPost(platform: .instagram, handle: "natgeo", avatar: Self.image(100, 100), text: "Pie de foto",
                              date: .now, images: [Self.image(1080, 1350), Self.image(1080, 566), Self.image(1080, 1080)],
                              likes: 171_856, replies: 269)
        var doc = SocialDoc()
        let heights = try (0..<3).map { index in
            doc.imageIndex = index
            let card = try #require(SocialRenderer.render(post, doc: doc, model: .a6))
            #expect(card.width == 384)
            return card.height
        }
        // 4:5 portrait > square > 1.91:1 landscape, each printed edge to edge.
        #expect(heights[0] > heights[2] && heights[2] > heights[1])
        #expect(abs(heights[0] - heights[2] - 96) <= 1)  // 480 vs 384 dots of photo

        doc.imageIndex = 99
        let clamped = try #require(SocialRenderer.render(post, doc: doc, model: .a6))
        doc.imageIndex = 2
        #expect(clamped == SocialRenderer.render(post, doc: doc, model: .a6))
    }

    @Test func instagramCropKeepsTheAppAspectLimits() {
        let tall = SocialRenderer.instagramCrop(Self.image(1000, 3000))
        #expect(abs(Double(tall.height) / Double(tall.width) - 1.25) < 0.01)
        let wide = SocialRenderer.instagramCrop(Self.image(3000, 1000))
        #expect(abs(Double(wide.width) / Double(wide.height) - 1.91) < 0.01)
        let square = SocialRenderer.instagramCrop(Self.image(800, 800))
        #expect(square.width == 800 && square.height == 800)
        #expect(SocialRenderer.spanishThousands(171_856) == "171.856")
    }

    @Test func compactNumbersInSpanish() {
        #expect(SocialRenderer.compactNumber(0) == "0")
        #expect(SocialRenderer.compactNumber(999) == "999")
        #expect(SocialRenderer.compactNumber(1234) == "1,2\u{00A0}k")
        #expect(SocialRenderer.compactNumber(18_074) == "18,1\u{00A0}k")
        #expect(SocialRenderer.compactNumber(9_983) == "10\u{00A0}k")
        #expect(SocialRenderer.compactNumber(310_173) == "310\u{00A0}k")
        #expect(SocialRenderer.compactNumber(999_950) == "1\u{00A0}M")
        #expect(SocialRenderer.compactNumber(60_279_707) == "60,3\u{00A0}M")
    }

    @Test func docDecodingToleratesMissingAndUnknownFields() throws {
        var doc = SocialDoc()
        doc.urlString = "https://x.com/jack/status/20"
        doc.layout = .label
        doc.labelHeightMM = 20
        let data = try JSONEncoder().encode(doc)
        #expect(try JSONDecoder().decode(SocialDoc.self, from: data) == doc)

        let partial = try JSONDecoder().decode(SocialDoc.self, from: Data(#"{"layout":"sticker","future":1}"#.utf8))
        #expect(partial.layout == .sticker)
        #expect(partial.pipeline == .recommendedPhoto)
        #expect(partial.labelHeightMM == 15)
        let unknownLayout = try JSONDecoder().decode(SocialDoc.self, from: Data(#"{"layout":"poster"}"#.utf8))
        #expect(unknownLayout.layout == .card)
    }
}
