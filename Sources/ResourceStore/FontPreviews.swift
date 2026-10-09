import AppKit
import CoreText

/// Downloads fonts just to preview them, without registering them.
final class FontPreviewLoader: @unchecked Sendable {
    static let shared = FontPreviewLoader(http: .shared)

    let http: StoreHTTP
    private let cache = NSCache<NSString, Box>()

    private final class Box {
        let descriptor: CTFontDescriptor
        init(_ descriptor: CTFontDescriptor) { self.descriptor = descriptor }
    }

    init(http: StoreHTTP) {
        self.http = http
        cache.countLimit = 400
    }

    /// A tiny subset with only the glyphs of `text` (a few KB), enough to draw a family's name in itself.
    func subset(_ family: GoogleFontFamily, text: String) async throws -> CTFontDescriptor {
        try await load(key: "subset|\(family.family)|\(text)",
                       css: GoogleFonts.cssURL(family: family.family, weights: [family.regularWeight ?? 400], text: text))
    }

    /// The full regular face, for the large preview and the thermal sample.
    func regular(_ family: GoogleFontFamily) async throws -> CTFontDescriptor {
        try await load(key: "regular|\(family.family)", css: GoogleFonts.cssURL(family: family.family, weights: [family.regularWeight ?? 400]))
    }

    private func load(key: String, css: URL) async throws -> CTFontDescriptor {
        if let box = cache.object(forKey: key as NSString) { return box.descriptor }
        let cssData = try await http.data(from: css, policy: .returnCacheDataElseLoad,
                                          headers: ["User-Agent": GoogleFonts.cssUserAgent])
        let faces = GoogleFonts.trueTypeFaces(GoogleFonts.parseCSS(String(decoding: cssData, as: UTF8.self)))
        guard let face = faces.first(where: { !$0.italic }) ?? faces.first else { throw StoreError.fontUnavailable }
        let data = try await http.data(from: face.url, policy: .returnCacheDataElseLoad, timeout: 60)
        guard let descriptor = CTFontManagerCreateFontDescriptorFromData(data as CFData) else { throw StoreError.fontUnavailable }
        cache.setObject(Box(descriptor), forKey: key as NSString)
        return descriptor
    }

    static func font(_ descriptor: CTFontDescriptor, size: CGFloat) -> NSFont {
        CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }
}
