import Foundation

/// One family from fonts.google.com/metadata/fonts.
struct GoogleFontFamily: Decodable, Hashable, Identifiable, Sendable {
    var family: String
    var category: String
    var popularity: Int
    var subsets: [String]
    var designers: [String]
    /// "400", "400i", "700", …
    var styles: [String]

    var id: String { family }

    private struct Ignored: Decodable, Hashable {}
    private enum CodingKeys: String, CodingKey { case family, category, popularity, subsets, designers, fonts }

    init(family: String, category: String, popularity: Int = 0, subsets: [String] = ["latin"],
         designers: [String] = [], styles: [String] = ["400"]) {
        self.family = family
        self.category = category
        self.popularity = popularity
        self.subsets = subsets
        self.designers = designers
        self.styles = styles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        family = try c.decode(String.self, forKey: .family)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        popularity = try c.decodeIfPresent(Int.self, forKey: .popularity) ?? Int.max
        subsets = try c.decodeIfPresent([String].self, forKey: .subsets) ?? []
        designers = try c.decodeIfPresent([String].self, forKey: .designers) ?? []
        let fonts = try c.decodeIfPresent([String: Ignored].self, forKey: .fonts) ?? [:]
        styles = fonts.keys.sorted()
    }

    var uprightWeights: [Int] { styles.compactMap { Int($0) }.sorted() }

    /// 400, or the closest upright weight.
    var regularWeight: Int? { uprightWeights.min { abs($0 - 400) < abs($1 - 400) } }

    /// 700 if the family has it (and it is not the regular weight).
    var boldWeight: Int? { uprightWeights.contains(700) && regularWeight != 700 ? 700 : nil }

    var categoryTitle: String { GoogleFonts.Category(rawValue: category)?.title ?? category }
}

enum GoogleFonts {
    static let metadataURL = URL(string: "https://fonts.google.com/metadata/fonts")!
    static let license = "Licencia libre (SIL OFL / Apache 2.0)"
    /// Old browsers get TrueType files instead of WOFF2.
    static let cssUserAgent = "Mozilla/5.0 (Linux; U; Android 2.2; en-us) AppleWebKit/533.1 (KHTML, like Gecko) Version/4.0 Mobile Safari/533.1"

    enum Category: String, CaseIterable, Identifiable, Sendable {
        case all = ""
        case sansSerif = "Sans Serif"
        case serif = "Serif"
        case display = "Display"
        case handwriting = "Handwriting"
        case monospace = "Monospace"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Todas"
            case .sansSerif: "Sans serif"
            case .serif: "Serif"
            case .display: "Decorativas"
            case .handwriting: "Manuscritas"
            case .monospace: "Monoespaciadas"
            }
        }
    }

    struct FontFace: Equatable, Sendable {
        var family: String
        var weight: Int
        var italic: Bool
        var url: URL
        var format: String?
    }

    /// Families with Latin glyphs, most popular first. Accepts the `)]}'` anti-JSON-hijacking prefix.
    static func parseMetadata(_ data: Data) throws -> [GoogleFontFamily] {
        struct Metadata: Decodable { var familyMetadataList: [GoogleFontFamily] }
        var body = data
        if let text = String(data: data.prefix(16), encoding: .utf8), text.hasPrefix(")]}'"),
           let start = data.firstIndex(where: { $0 == UInt8(ascii: "{") || $0 == UInt8(ascii: "[") }) {
            body = data[start...]
        }
        do {
            let metadata = try JSONDecoder().decode(Metadata.self, from: body)
            return metadata.familyMetadataList
                .filter { $0.subsets.contains("latin") && $0.regularWeight != nil }
                .sorted { $0.popularity < $1.popularity }
        } catch {
            throw StoreError.badData
        }
    }

    /// css2 URL for the given upright weights; `text` asks for a tiny subset with just those characters.
    static func cssURL(family: String, weights: [Int], text: String? = nil) -> URL {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let name = family.split(separator: " ").map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
            .joined(separator: "+")
        var query = "family=\(name)"
        let weights = Array(Set(weights)).sorted()
        if !weights.isEmpty, weights != [400] { query += ":wght@" + weights.map(String.init).joined(separator: ";") }
        if let text, !text.isEmpty {
            query += "&text=" + (text.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }
        return URL(string: "https://fonts.googleapis.com/css2?\(query)")!
    }

    static func parseCSS(_ css: String) -> [FontFace] {
        let block = try! NSRegularExpression(pattern: #"@font-face\s*\{([^}]*)\}"#)
        let family = try! NSRegularExpression(pattern: #"font-family:\s*['"]?([^;'"]+)['"]?\s*;"#)
        let style = try! NSRegularExpression(pattern: #"font-style:\s*(\w+)"#)
        let weight = try! NSRegularExpression(pattern: #"font-weight:\s*(\d+)"#)
        let src = try! NSRegularExpression(pattern: #"url\(\s*['"]?([^)'"]+)['"]?\s*\)(?:\s*format\(\s*['"]?([^)'"]+)['"]?\s*\))?"#)
        func first(_ regex: NSRegularExpression, in text: String, group: Int = 1) -> String? {
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > group,
                  let r = Range(match.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
        let range = NSRange(css.startIndex..., in: css)
        return block.matches(in: css, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: css) else { return nil }
            let body = String(css[r])
            guard let urlString = first(src, in: body), let url = URL(string: urlString) else { return nil }
            return FontFace(family: first(family, in: body)?.trimmed ?? "",
                            weight: first(weight, in: body).flatMap { Int($0) } ?? 400,
                            italic: first(style, in: body) == "italic",
                            url: url,
                            format: first(src, in: body, group: 2))
        }
    }

    /// Faces that CoreText can register directly.
    static func trueTypeFaces(_ faces: [FontFace]) -> [FontFace] {
        faces.filter { face in
            let format = face.format?.lowercased()
            let ext = face.url.pathExtension.lowercased()
            return format == "truetype" || format == "opentype" || ext == "ttf" || ext == "otf"
        }
    }
}
