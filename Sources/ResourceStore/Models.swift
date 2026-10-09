import CoreGraphics
import Foundation

/// Where a resource from the store ends up in the app.
public enum ResourceDestination: String, CaseIterable, Sendable {
    case photo, sticker, label

    public var title: String {
        switch self {
        case .photo: "Foto"
        case .sticker: "Sticker"
        case .label: "Etiqueta"
        }
    }

    var buttonTitle: String { "Usar en \(title.lowercased())" }

    var icon: String {
        switch self {
        case .photo: "photo"
        case .sticker: "seal"
        case .label: "tag"
        }
    }
}

/// Name, origin and license of a resource handed to the app.
public struct ResourceInfo: Sendable, Equatable, Codable {
    public var name: String
    /// "Iconify · Material Design Icons", "OpenMoji", "Openverse · Flickr", …
    public var source: String
    public var license: String
    /// Credit line required by the license (CC BY, CC BY-SA), if any.
    public var attribution: String?

    public init(name: String, source: String, license: String, attribution: String? = nil) {
        self.name = name
        self.source = source
        self.license = license
        self.attribution = attribution
    }
}

enum ResourceKind: String, Codable, Sendable, CaseIterable {
    case icon, emoji, image

    var title: String {
        switch self {
        case .icon: "Íconos"
        case .emoji: "Emojis"
        case .image: "Imágenes"
        }
    }
}

/// How a resource is converted to 1 bit: line art is thresholded, everything else dithered.
enum ThermalStyle: String, Codable, Sendable {
    case lineArt, colorArt, photo
}

/// One browsable resource (icon, emoji, image or saved favorite).
struct ResourceItem: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        /// Vector image, rasterized locally at any size.
        case svg(URL)
        /// Bitmap with a small preview and the original file.
        case remote(thumbnail: URL, full: URL)
        /// Saved PNG in "Mis recursos".
        case file(URL)
    }

    var id: String
    /// Identity of the original resource, used to know whether it is a favorite.
    var favoriteKey: String
    var kind: ResourceKind
    var style: ThermalStyle
    var title: String
    var source: Source
    var info: ResourceInfo
    var pixelSize: CGSize?
    var licenseURL: URL?
    var pageURL: URL?

    init(id: String, favoriteKey: String? = nil, kind: ResourceKind, style: ThermalStyle, title: String, source: Source,
         info: ResourceInfo, pixelSize: CGSize? = nil, licenseURL: URL? = nil, pageURL: URL? = nil) {
        self.id = id
        self.favoriteKey = favoriteKey ?? id
        self.kind = kind
        self.style = style
        self.title = title
        self.source = source
        self.info = info
        self.pixelSize = pixelSize
        self.licenseURL = licenseURL
        self.pageURL = pageURL
    }

    static func == (a: ResourceItem, b: ResourceItem) -> Bool { a.id == b.id && a.source == b.source }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum LoadPhase: Equatable {
    case idle, loading, loaded
    case failed(String)
}

enum StoreError: LocalizedError, Equatable {
    case offline
    case timedOut
    case rateLimited
    case notFound
    case http(Int)
    case badData
    case unsupportedImage
    case fontUnavailable

    var errorDescription: String? {
        switch self {
        case .offline: "No hay conexión a internet. Revisá tu conexión y probá de nuevo."
        case .timedOut: "El servidor tardó demasiado en responder. Probá de nuevo en un rato."
        case .rateLimited: "El servicio recibió demasiadas búsquedas seguidas. Esperá un minuto y probá de nuevo."
        case .notFound: "No se encontró el recurso en el servidor."
        case .http(let code): "El servidor respondió con un error (\(code)). Probá de nuevo más tarde."
        case .badData: "La respuesta del servidor no tiene el formato esperado."
        case .unsupportedImage: "No se pudo abrir la imagen."
        case .fontUnavailable: "Esta fuente no está disponible para descargar."
        }
    }

    static func message(for error: Error) -> String {
        (error as? StoreError)?.errorDescription ?? error.localizedDescription
    }
}

/// On-disk locations (overridable for tests and the snapshot harness).
enum StorePaths {
    static var applicationSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PeriPrint", isDirectory: true)
    static var caches: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PeriPrint", isDirectory: true)

    static var fonts: URL { applicationSupport.appendingPathComponent("Fonts", isDirectory: true) }
    static var library: URL { applicationSupport.appendingPathComponent("Library", isDirectory: true) }
    static var urlCache: URL { caches.appendingPathComponent("ResourceStore", isDirectory: true) }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Lowercased, without accents ("Corazón" → "corazon").
    var folded: String { lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es")) }
}
