import Foundation

struct IconifyLicense: Codable, Hashable, Sendable {
    var title: String
    var spdx: String?
    var url: String?
}

struct IconifyAuthor: Codable, Hashable, Sendable {
    var name: String
    var url: String?
}

/// Icon set metadata, from /collections or the `collections` field of a search.
struct IconifyCollection: Codable, Hashable, Sendable {
    var name: String
    var total: Int?
    var author: IconifyAuthor?
    var license: IconifyLicense?
    var category: String?
    var palette: Bool?
    var hidden: Bool?
    var samples: [String]?

    var isMonochrome: Bool { palette != true }
}

struct IconifySearchResult: Decodable, Sendable {
    var icons: [String]
    var total: Int
    var collections: [String: IconifyCollection]

    private enum CodingKeys: String, CodingKey { case icons, total, collections }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        icons = try c.decode([String].self, forKey: .icons)
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? icons.count
        collections = try c.decodeIfPresent([String: IconifyCollection].self, forKey: .collections) ?? [:]
    }
}

/// Icon names of one set, from /collection?prefix=…
struct IconifyCollectionListing: Decodable, Sendable {
    var prefix: String
    var uncategorized: [String]?
    var categories: [String: [String]]?
    var hidden: [String]?

    var allIcons: [String] {
        var seen = Set<String>()
        let ordered = (categories ?? [:]).sorted { $0.key < $1.key }.flatMap(\.value) + (uncategorized ?? [])
        let hiddenSet = Set(hidden ?? [])
        return ordered.filter { !hiddenSet.contains($0) && seen.insert($0).inserted }
    }
}

enum Iconify {
    static let api = URL(string: "https://api.iconify.design")!

    /// Monochrome sets that print well, in display order.
    static let recommended = ["mdi", "material-symbols", "ph", "tabler", "lucide", "mingcute", "solar", "ri",
                              "bi", "fa6-solid", "game-icons", "healthicons", "fluent-emoji-high-contrast",
                              "emojione-monotone", "icon-park-outline", "streamline"]

    /// Shown when the search field is empty and no set is selected.
    static let featured = ["heart", "star", "cat", "dog", "paw", "flower", "leaf", "white-balance-sunny",
                           "moon-waning-crescent", "cloud", "umbrella", "coffee", "cake-variant", "gift",
                           "party-popper", "balloon", "music", "camera", "home", "bike", "car", "airplane",
                           "rocket-launch", "book-open-variant", "pencil", "content-cut", "lightbulb", "key",
                           "lock", "email", "phone", "clock-outline", "calendar", "map-marker", "crown",
                           "diamond-stone", "trophy", "pizza", "ice-cream", "cactus", "pine-tree", "mushroom",
                           "ghost", "skull", "fire", "lightning-bolt", "anchor", "emoticon-happy-outline",
                           "bee", "butterfly", "rabbit", "owl", "teddy-bear", "baby-carriage"].map { "mdi:\($0)" }

    static func searchURL(query: String, limit: Int, prefix: String?, colorful: Bool) -> URL {
        var components = URLComponents(url: api.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        // `palette:false` inside the query keeps only monochrome sets.
        var items = [URLQueryItem(name: "query", value: "\(query) palette:\(colorful)"),
                     URLQueryItem(name: "limit", value: String(max(32, min(999, limit))))]
        if let prefix { items.append(URLQueryItem(name: "prefix", value: prefix)) }
        components.queryItems = items
        return components.url!
    }

    static var collectionsURL: URL { api.appendingPathComponent("collections") }

    static func collectionURL(prefix: String) -> URL {
        var components = URLComponents(url: api.appendingPathComponent("collection"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "prefix", value: prefix)]
        return components.url!
    }

    /// Monochrome icons use `currentColor`; `color` makes it pure black.
    static func svgURL(prefix: String, name: String) -> URL {
        var components = URLComponents(url: api.appendingPathComponent(prefix).appendingPathComponent("\(name).svg"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "height", value: "1024"), URLQueryItem(name: "color", value: "#000000")]
        return components.url!
    }

    static func parseSearch(_ data: Data) throws -> IconifySearchResult {
        do { return try JSONDecoder().decode(IconifySearchResult.self, from: data) } catch { throw StoreError.badData }
    }

    static func parseCollections(_ data: Data) throws -> [String: IconifyCollection] {
        do { return try JSONDecoder().decode([String: IconifyCollection].self, from: data) } catch { throw StoreError.badData }
    }

    static func parseListing(_ data: Data) throws -> IconifyCollectionListing {
        do { return try JSONDecoder().decode(IconifyCollectionListing.self, from: data) } catch { throw StoreError.badData }
    }

    /// "mdi:cat-outline" → ("mdi", "cat-outline").
    static func split(_ id: String) -> (prefix: String, name: String)? {
        guard let colon = id.firstIndex(of: ":") else { return nil }
        let prefix = String(id[..<colon]), name = String(id[id.index(after: colon)...])
        guard !prefix.isEmpty, !name.isEmpty else { return nil }
        return (prefix, name)
    }

    static func requiresAttribution(_ license: IconifyLicense?) -> Bool {
        guard let license else { return true }
        let tag = (license.spdx ?? license.title).uppercased()
        return tag.hasPrefix("CC-BY") || tag.hasPrefix("CC BY")
    }

    static func item(id: String, collection: IconifyCollection?) -> ResourceItem? {
        guard let (prefix, name) = split(id) else { return nil }
        let setName = collection?.name ?? prefix
        let title = name.replacingOccurrences(of: "-", with: " ")
        let license = collection?.license?.title ?? "Ver licencia de la colección"
        var attribution: String?
        if requiresAttribution(collection?.license) {
            let author = collection?.author?.name.trimmed
            attribution = "Ícono “\(title)” de \(setName)\(author.map { " por \($0)" } ?? ""), \(license)"
        }
        let info = ResourceInfo(name: title, source: "Iconify · \(setName)", license: license, attribution: attribution)
        return ResourceItem(id: "iconify:\(id)", kind: .icon, style: (collection?.palette == true) ? .colorArt : .lineArt,
                            title: title, source: .svg(svgURL(prefix: prefix, name: name)), info: info,
                            licenseURL: collection?.license?.url.flatMap(URL.init(string:)),
                            pageURL: URL(string: "https://icon-sets.iconify.design/\(prefix)/?icon-filter=\(name)"))
    }
}
