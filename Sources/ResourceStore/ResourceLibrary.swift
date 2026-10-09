import CoreGraphics
import Foundation
import Observation

/// A favorite saved for offline use: `<id>.png` + `<id>.json` in ~/Library/Application Support/PeriPrint/Library/.
struct SavedResource: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var favoriteKey: String
    var kind: ResourceKind
    var style: ThermalStyle
    var info: ResourceInfo
    var savedAt: Date
    var pixelWidth: Int
    var pixelHeight: Int
    var licenseURL: URL?
    var pageURL: URL?

    static func == (a: SavedResource, b: SavedResource) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@Observable
@MainActor
final class ResourceLibrary {
    let directory: URL
    private(set) var resources: [SavedResource] = []

    init(directory: URL = StorePaths.library) {
        self.directory = directory
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        resources = files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(SavedResource.self, from: Data(contentsOf: $0)) }
            .filter { FileManager.default.fileExists(atPath: imageURL($0).path) }
            .sorted { $0.savedAt > $1.savedAt }
    }

    func imageURL(_ resource: SavedResource) -> URL { directory.appendingPathComponent("\(resource.id).png") }

    func contains(_ favoriteKey: String) -> Bool { resources.contains { $0.favoriteKey == favoriteKey } }

    @discardableResult
    func save(_ image: CGImage, for item: ResourceItem) throws -> SavedResource {
        if let existing = resources.first(where: { $0.favoriteKey == item.favoriteKey }) { return existing }
        guard let png = ImageDecoder.pngData(image) else { throw StoreError.unsupportedImage }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let resource = SavedResource(id: UUID().uuidString, favoriteKey: item.favoriteKey, kind: item.kind, style: item.style,
                                     info: item.info, savedAt: Date(), pixelWidth: image.width, pixelHeight: image.height,
                                     licenseURL: item.licenseURL, pageURL: item.pageURL)
        try png.write(to: imageURL(resource), options: .atomic)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(resource).write(to: directory.appendingPathComponent("\(resource.id).json"), options: .atomic)
        resources.insert(resource, at: 0)
        return resource
    }

    func remove(favoriteKey: String) {
        for resource in resources where resource.favoriteKey == favoriteKey {
            try? FileManager.default.removeItem(at: imageURL(resource))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(resource.id).json"))
        }
        resources.removeAll { $0.favoriteKey == favoriteKey }
    }

    func item(_ resource: SavedResource) -> ResourceItem {
        ResourceItem(id: "saved:\(resource.id)", favoriteKey: resource.favoriteKey, kind: resource.kind, style: resource.style,
                     title: resource.info.name, source: .file(imageURL(resource)), info: resource.info,
                     pixelSize: CGSize(width: resource.pixelWidth, height: resource.pixelHeight),
                     licenseURL: resource.licenseURL, pageURL: resource.pageURL)
    }
}
