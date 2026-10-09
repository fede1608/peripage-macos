import Foundation

/// One emoji of the OpenMoji catalog (data/openmoji.json).
struct OpenMojiEntry: Decodable, Hashable, Sendable {
    var emoji: String
    var hexcode: String
    var group: String
    var subgroup: String
    var annotation: String
    var tags: [String]
    var author: String?
    /// Skin-tone variants are hidden: the outline version looks the same.
    var isSkinToneVariant: Bool
    // Folded search fields, computed once.
    private(set) var searchAnnotation = ""
    private(set) var annotationWords: [String] = []
    private(set) var searchTags = ""
    private(set) var tagWords: [String] = []

    private enum CodingKeys: String, CodingKey {
        case emoji, hexcode, group, subgroups, annotation, tags
        case openmojiTags = "openmoji_tags"
        case author = "openmoji_author"
        case skintoneBase = "skintone_base_hexcode"
    }

    init(emoji: String, hexcode: String, group: String, subgroup: String = "", annotation: String,
         tags: [String] = [], author: String? = nil, isSkinToneVariant: Bool = false) {
        self.emoji = emoji
        self.hexcode = hexcode
        self.group = group
        self.subgroup = subgroup
        self.annotation = annotation
        self.tags = tags
        self.author = author
        self.isSkinToneVariant = isSkinToneVariant
        index()
    }

    private mutating func index() {
        searchAnnotation = annotation.folded
        annotationWords = SpanishKeywords.words(searchAnnotation)
        searchTags = tags.joined(separator: " ").folded
        tagWords = SpanishKeywords.words(searchTags)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Several fields are "" or a number depending on the row, so everything is read leniently.
        func string(_ key: CodingKeys) -> String {
            if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
            if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return String(i) }
            return ""
        }
        func list(_ key: CodingKeys) -> [String] {
            string(key).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        emoji = string(.emoji)
        hexcode = string(.hexcode)
        group = string(.group)
        subgroup = string(.subgroups)
        annotation = string(.annotation)
        tags = list(.tags) + list(.openmojiTags)
        let author = string(.author)
        self.author = author.isEmpty ? nil : author
        isSkinToneVariant = !string(.skintoneBase).isEmpty
        guard !hexcode.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .hexcode, in: c, debugDescription: "missing hexcode")
        }
        index()
    }
}

enum OpenMoji {
    static let version = "17.0.0"
    static let license = "CC BY-SA 4.0"
    static let licenseURL = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!
    static let attribution = "Emoji de OpenMoji, el proyecto de emojis de código abierto (openmoji.org). Licencia: CC BY-SA 4.0"

    static var cdn: URL { URL(string: "https://cdn.jsdelivr.net/npm/openmoji@\(version)")! }
    static var catalogURL: URL { cdn.appendingPathComponent("data/openmoji.json") }

    /// The black variant is outline-only line art, ideal for thermal paper.
    static func svgURL(hexcode: String, color: Bool) -> URL {
        cdn.appendingPathComponent("\(color ? "color" : "black")/svg/\(hexcode).svg")
    }

    static let groups: [(id: String, title: String)] = [
        ("smileys-emotion", "Caras"),
        ("people-body", "Personas"),
        ("animals-nature", "Animales y plantas"),
        ("food-drink", "Comida y bebida"),
        ("activities", "Actividades"),
        ("travel-places", "Viajes y lugares"),
        ("objects", "Objetos"),
        ("symbols", "Símbolos"),
        ("flags", "Banderas"),
        ("extras-openmoji", "Extras OpenMoji"),
        ("extras-unicode", "Extras Unicode"),
    ]

    /// Parses the catalog keeping only browsable emoji (no skin-tone variants or bare components).
    static func parseCatalog(_ data: Data) throws -> [OpenMojiEntry] {
        struct Lenient: Decodable {
            let entry: OpenMojiEntry?
            init(from decoder: Decoder) throws { entry = try? OpenMojiEntry(from: decoder) }
        }
        let rows: [Lenient]
        do { rows = try JSONDecoder().decode([Lenient].self, from: data) } catch { throw StoreError.badData }
        return rows.compactMap(\.entry).filter { !$0.isSkinToneVariant && $0.group != "component" }
    }

    /// Matches every query word (or its English translation) against annotation and tags, best first.
    static func search(_ entries: [OpenMojiEntry], query: String, group: String?) -> [OpenMojiEntry] {
        let pool = group.map { g in entries.filter { $0.group == g } } ?? entries
        let words = SpanishKeywords.words(query)
        guard !words.isEmpty else { return pool }
        let alternatives: [[String]] = words.map { word in
            var alts = [word]
            if let english = SpanishKeywords.translate(word: word) { alts.append(english) }
            return alts
        }
        var scored: [(entry: OpenMojiEntry, score: Int, order: Int)] = []
        for (order, entry) in pool.enumerated() {
            let annotation = entry.searchAnnotation, annotationWords = entry.annotationWords
            let tagText = entry.searchTags, tagWords = entry.tagWords
            var total = 0
            var matchedAll = true
            for alts in alternatives {
                var best = 0
                for alt in alts {
                    if annotation == alt {
                        best = max(best, 6)
                    } else if alt.contains(" ") {
                        if annotation.contains(alt) { best = max(best, 3) } else if tagText.contains(alt) { best = max(best, 1) }
                    } else if annotationWords.first == alt || annotationWords.last == alt {
                        best = max(best, 5)
                    } else if annotationWords.contains(alt) {
                        best = max(best, 4)
                    } else if annotationWords.contains(where: { $0.hasPrefix(alt) }) {
                        best = max(best, 2)
                    } else if tagWords.contains(where: { $0.hasPrefix(alt) }) {
                        best = max(best, 1)
                    }
                }
                if best == 0 { matchedAll = false; break }
                total += best
            }
            if matchedAll { scored.append((entry, total, order)) }
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }.map(\.entry)
    }

    static func item(_ entry: OpenMojiEntry, color: Bool) -> ResourceItem {
        let info = ResourceInfo(name: entry.annotation, source: "OpenMoji", license: license, attribution: attribution)
        return ResourceItem(id: "openmoji:\(entry.hexcode):\(color ? "color" : "black")", kind: .emoji,
                            style: color ? .colorArt : .lineArt, title: entry.annotation,
                            source: .svg(svgURL(hexcode: entry.hexcode, color: color)), info: info,
                            licenseURL: licenseURL, pageURL: URL(string: "https://openmoji.org/library/emoji-\(entry.hexcode)/"))
    }
}
