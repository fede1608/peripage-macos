import CoreGraphics
import Foundation
import Testing
@testable import ResourceStore

private let catSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 24 24"><path fill="currentColor" d="m12 8l-1.33.09C9.81 7.07 7.4 4.5 5 4.5c0 0-1.97 2.96-.04 6.91c-.55.83-.89 1.26-.96 2.25l-1.93.29l.21.98l1.76-.26l.14.71l-1.57.94l.47.89l1.45-.89C5.68 18.76 8.59 20 12 20s6.32-1.24 7.47-3.68l1.45.89l.47-.89l-1.57-.94l.14-.71l1.76.26l.21-.98l-1.93-.29c-.07-.99-.41-1.42-.96-2.25C20.97 7.46 19 4.5 19 4.5c-2.4 0-4.81 2.57-5.67 3.59z"/></svg>
"""

/// OpenMoji-style SVG: only a viewBox, stroked outline.
private let outlineSVG = """
<svg id="emoji" viewBox="0 0 72 36" xmlns="http://www.w3.org/2000/svg">
  <g id="line"><circle cx="18" cy="18" r="12" fill="none" stroke="#000" stroke-width="2"/><rect x="40" y="6" width="24" height="24" fill="#f4aa41"/></g>
</svg>
"""

/// Counts (opaque, transparent) pixels.
private func alphaCounts(_ image: CGImage) -> (opaque: Int, transparent: Int) {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h)
    var opaque = 0, transparent = 0
    for i in 0..<(w * h) {
        if px[i] > 200 { opaque += 1 } else if px[i] == 0 { transparent += 1 }
    }
    return (opaque, transparent)
}

@Test func svgRasterizationKeepsAlpha() throws {
    let data = Data(catSVG.utf8)
    #expect(SVGRasterizer.isSVG(data))
    let image = try #require(SVGRasterizer.rasterize(data, maxPixel: 1024))
    #expect(image.width == 1024 && image.height == 1024)
    #expect(image.alphaInfo == .premultipliedLast)
    let counts = alphaCounts(image)
    #expect(counts.opaque > 100_000)
    #expect(counts.transparent > 100_000)
    #expect(ImageDecoder.hasTransparency(image))
}

@Test func svgRasterizationUsesViewBoxAspect() throws {
    let image = try #require(ImageDecoder.decode(Data(outlineSVG.utf8), maxPixel: 1200))
    #expect(image.width == 1200)
    #expect(image.height == 600)
    let counts = alphaCounts(image)
    #expect(counts.opaque > 1000)
    #expect(counts.transparent > counts.opaque)
}

@Test func pngRoundTripKeepsTransparency() throws {
    let image = try #require(SVGRasterizer.rasterize(Data(catSVG.utf8), maxPixel: 256))
    let png = try #require(ImageDecoder.pngData(image))
    let decoded = try #require(ImageDecoder.decode(png, maxPixel: 4096))
    #expect(decoded.width == 256)
    #expect(ImageDecoder.hasTransparency(decoded))
    #expect(ImageDecoder.decode(Data("not an image".utf8), maxPixel: 100) == nil)
}

@Test func thermalPreviewIsPrinterWidth() throws {
    let image = try #require(SVGRasterizer.rasterize(Data(catSVG.utf8), maxPixel: 1024))
    let bitmap = try #require(ThermalPreview.bitmap(image, style: .lineArt, width: 384))
    #expect(bitmap.width == 384)
    #expect(bitmap.height == 384)
    // The cat covers roughly a third of the square; transparency prints as white paper.
    let coverage = Double(bitmap.blackDotCount) / Double(384 * 384)
    #expect(coverage > 0.2 && coverage < 0.5)
    #expect(!bitmap[0, 0])
    #expect(bitmap[192, 300])
}

@MainActor
@Test func libraryRoundTrip() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ResourceStoreTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let library = ResourceLibrary(directory: dir)
    #expect(library.resources.isEmpty)

    let image = try #require(SVGRasterizer.rasterize(Data(catSVG.utf8), maxPixel: 300))
    let info = ResourceInfo(name: "cat", source: "Iconify · Material Design Icons", license: "Apache 2.0")
    let item = ResourceItem(id: "iconify:mdi:cat", kind: .icon, style: .lineArt, title: "cat",
                            source: .svg(URL(string: "https://api.iconify.design/mdi/cat.svg")!), info: info)
    let saved = try library.save(image, for: item)
    #expect(library.contains("iconify:mdi:cat"))
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(saved.id).png").path))
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(saved.id).json").path))

    // A fresh instance reads it back from disk.
    let reopened = ResourceLibrary(directory: dir)
    #expect(reopened.resources.count == 1)
    let restored = reopened.item(reopened.resources[0])
    #expect(restored.info == info)
    #expect(restored.favoriteKey == "iconify:mdi:cat")
    #expect(restored.pixelSize == CGSize(width: 300, height: 300))

    reopened.remove(favoriteKey: "iconify:mdi:cat")
    #expect(reopened.resources.isEmpty)
    #expect(ResourceLibrary(directory: dir).resources.isEmpty)
}

@Test func destinationsMatchContract() {
    #expect(ResourceDestination.allCases.map(\.title) == ["Foto", "Sticker", "Etiqueta"])
    #expect(ResourceDestination.allCases.map(\.buttonTitle) == ["Usar en foto", "Usar en sticker", "Usar en etiqueta"])
}
