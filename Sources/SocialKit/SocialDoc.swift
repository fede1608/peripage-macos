import Foundation
import PeriPageKit

public enum SocialLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case card, photo, sticker, label

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .card: "Tarjeta"
        case .photo: "Foto"
        case .sticker: "Sticker"
        case .label: "Etiqueta"
        }
    }
}

/// Settings of the social mode. The fetched post itself is not persisted (images are not Codable).
public struct SocialDoc: Codable, Equatable, Sendable {
    public var urlString = ""
    public var layout: SocialLayout = .card
    public var showText = true
    public var showStats = true
    public var showDate = true
    public var imageIndex = 0
    public var pipeline: ImagePipeline = .recommendedPhoto
    /// Height of the die-cut labels used by `.label`.
    public var labelHeightMM: Double = 15

    public init() {}

    /// Tolerates fields added or removed between versions, so saved state keeps loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SocialDoc()
        urlString = try c.decodeIfPresent(String.self, forKey: .urlString) ?? d.urlString
        layout = (try? c.decodeIfPresent(SocialLayout.self, forKey: .layout)) ?? d.layout
        showText = try c.decodeIfPresent(Bool.self, forKey: .showText) ?? d.showText
        showStats = try c.decodeIfPresent(Bool.self, forKey: .showStats) ?? d.showStats
        showDate = try c.decodeIfPresent(Bool.self, forKey: .showDate) ?? d.showDate
        imageIndex = try c.decodeIfPresent(Int.self, forKey: .imageIndex) ?? d.imageIndex
        pipeline = (try? c.decodeIfPresent(ImagePipeline.self, forKey: .pipeline)) ?? d.pipeline
        labelHeightMM = try c.decodeIfPresent(Double.self, forKey: .labelHeightMM) ?? d.labelHeightMM
    }
}
