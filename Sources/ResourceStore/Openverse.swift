import Foundation

struct OpenverseImage: Decodable, Hashable, Sendable {
    var id: String
    var title: String?
    var url: String
    var thumbnail: String?
    var creator: String?
    var creatorURL: String?
    var license: String
    var licenseVersion: String?
    var licenseURL: String?
    var provider: String?
    var source: String?
    var landingURL: String?
    var width: Int?
    var height: Int?
    var filetype: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, url, thumbnail, creator, license, provider, source, width, height, filetype
        case creatorURL = "creator_url"
        case licenseVersion = "license_version"
        case licenseURL = "license_url"
        case landingURL = "foreign_landing_url"
    }
}

struct OpenverseSearchResult: Decodable, Sendable {
    var resultCount: Int
    var pageCount: Int
    var page: Int
    var results: [OpenverseImage]

    private enum CodingKeys: String, CodingKey {
        case results, page
        case resultCount = "result_count"
        case pageCount = "page_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = try c.decode([OpenverseImage].self, forKey: .results)
        resultCount = try c.decodeIfPresent(Int.self, forKey: .resultCount) ?? results.count
        pageCount = try c.decodeIfPresent(Int.self, forKey: .pageCount) ?? 1
        page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 1
    }
}

enum Openverse {
    /// Anonymous requests are limited to 20 results per page.
    static let pageSize = 20

    enum Category: String, CaseIterable, Identifiable, Sendable {
        case all = ""
        case photograph
        case illustration
        case digitizedArtwork = "digitized_artwork"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Todo"
            case .photograph: "Fotos"
            case .illustration: "Ilustraciones"
            case .digitizedArtwork: "Arte"
            }
        }
    }

    static func searchURL(query: String, page: Int, category: Category) -> URL {
        var components = URLComponents(string: "https://api.openverse.org/v1/images/")!
        var items = [URLQueryItem(name: "q", value: query),
                     URLQueryItem(name: "page_size", value: String(pageSize)),
                     URLQueryItem(name: "page", value: String(page))]
        if category != .all { items.append(URLQueryItem(name: "category", value: category.rawValue)) }
        components.queryItems = items
        return components.url!
    }

    static func parse(_ data: Data) throws -> OpenverseSearchResult {
        do { return try JSONDecoder().decode(OpenverseSearchResult.self, from: data) } catch { throw StoreError.badData }
    }

    /// "by" + "2.0" → "CC BY 2.0"; "cc0" → "CC0 1.0"; "pdm" → "Dominio público".
    static func licenseName(code: String, version: String?) -> String {
        let code = code.lowercased()
        switch code {
        case "cc0": return "CC0 \(version ?? "1.0")"
        case "pdm": return "Dominio público"
        default:
            let name = "CC " + code.uppercased()
            guard let version, !version.isEmpty else { return name }
            return "\(name) \(version)"
        }
    }

    static func providerName(_ provider: String?) -> String {
        guard let provider, !provider.isEmpty else { return "Openverse" }
        let known = ["flickr": "Flickr", "wikimedia": "Wikimedia Commons", "stocksnap": "StockSnap",
                     "rawpixel": "rawpixel", "nappy": "nappy", "smithsonian": "Smithsonian",
                     "met": "The Met", "clevelandmuseum": "Cleveland Museum of Art", "europeana": "Europeana",
                     "nasa": "NASA", "brooklynmuseum": "Brooklyn Museum", "sciencemuseum": "Science Museum"]
        if let name = known[provider.lowercased()] { return name }
        return provider.prefix(1).uppercased() + provider.dropFirst()
    }

    static func item(_ image: OpenverseImage) -> ResourceItem? {
        guard let full = URL(string: image.url) else { return nil }
        let thumb = image.thumbnail.flatMap(URL.init(string:))
            ?? URL(string: "https://api.openverse.org/v1/images/\(image.id)/thumb/")!
        let title = image.title?.trimmed.nilIfEmpty ?? "Sin título"
        let license = licenseName(code: image.license, version: image.licenseVersion)
        let creator = image.creator?.trimmed.nilIfEmpty
        var attribution = "“\(title)”"
        if let creator { attribution += " de \(creator)" }
        attribution += ", \(license)"
        if let landing = image.landingURL { attribution += " · \(landing)" }
        let info = ResourceInfo(name: title, source: "Openverse · \(providerName(image.source ?? image.provider))",
                                license: license, attribution: image.license.lowercased() == "pdm" ? nil : attribution)
        var size: CGSize?
        if let w = image.width, let h = image.height, w > 0, h > 0 { size = CGSize(width: w, height: h) }
        return ResourceItem(id: "openverse:\(image.id)", kind: .image, style: .photo, title: title,
                            source: .remote(thumbnail: thumb, full: full), info: info, pixelSize: size,
                            licenseURL: image.licenseURL.flatMap(URL.init(string:)),
                            pageURL: image.landingURL.flatMap(URL.init(string:)))
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
