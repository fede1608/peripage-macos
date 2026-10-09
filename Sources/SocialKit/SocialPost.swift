import CoreGraphics
import Foundation

public enum SocialPlatform: String, Codable, Sendable {
    case x, instagram, capture

    public var title: String {
        switch self {
        case .x: "X"
        case .instagram: "Instagram"
        case .capture: "Captura"
        }
    }
}

/// A fetched (or captured) post, ready to be laid out. Images are already decoded.
public struct SocialPost: Sendable {
    public var platform: SocialPlatform
    public var url: URL?
    public var authorName: String
    public var handle: String
    public var avatar: CGImage?
    public var text: String
    public var date: Date?
    public var images: [CGImage]
    public var likes: Int?
    public var replies: Int?
    public var reposts: Int?

    public init(platform: SocialPlatform, url: URL? = nil, authorName: String = "", handle: String = "", avatar: CGImage? = nil,
                text: String = "", date: Date? = nil, images: [CGImage] = [], likes: Int? = nil, replies: Int? = nil, reposts: Int? = nil) {
        self.platform = platform
        self.url = url
        self.authorName = authorName
        self.handle = handle
        self.avatar = avatar
        self.text = text
        self.date = date
        self.images = images
        self.likes = likes
        self.replies = replies
        self.reposts = reposts
    }

    /// Bold name shown in headers: the display name, or the handle when there is none (Instagram embeds only expose the username).
    var displayName: String {
        let name = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? handle : name
    }

    /// "@handle", or empty.
    var atHandle: String { handle.isEmpty ? "" : "@" + handle }

    func image(at index: Int) -> CGImage? {
        guard !images.isEmpty else { return nil }
        return images[min(max(0, index), images.count - 1)]
    }
}

/// What a parser extracts before any image is downloaded.
struct PostDraft {
    var post: SocialPost
    var imageURLs: [URL] = []
    var avatarURL: URL?
}
