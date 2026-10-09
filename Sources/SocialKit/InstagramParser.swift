import Foundation

/// Parses Instagram's public embed page (`/p/<shortcode>/embed/captioned/`).
/// Carousels and videos carry a `contextJSON` blob with the full media data; single photos only have the HTML.
enum InstagramParser {
    struct Media: Decodable {
        var shortcode: String?
        var isVideo: Bool?
        var displayURL: String?
        var displayResources: [Resource]?
        var caption: Edges<TextNode>?
        var comments: Count?
        var likedBy: Count?
        var previewLikes: Count?
        var owner: Owner?
        var children: Edges<Media>?
        var takenAt: Double?

        enum CodingKeys: String, CodingKey {
            case shortcode
            case isVideo = "is_video"
            case displayURL = "display_url"
            case displayResources = "display_resources"
            case caption = "edge_media_to_caption"
            case comments = "edge_media_to_comment"
            case likedBy = "edge_liked_by"
            case previewLikes = "edge_media_preview_like"
            case owner
            case children = "edge_sidecar_to_children"
            case takenAt = "taken_at_timestamp"
        }

        /// The rendition closest to 1080 px wide (or the display URL).
        var bestImageURL: URL? {
            let resources = displayResources ?? []
            let pick = resources.filter { ($0.width ?? 0) >= 1000 }.min { ($0.width ?? 0) < ($1.width ?? 0) }
                ?? resources.max { ($0.width ?? 0) < ($1.width ?? 0) }
            return (pick?.src ?? displayURL).flatMap(URL.init(string:))
        }
    }

    struct Resource: Decodable {
        var src: String?
        var width: Int?
        enum CodingKeys: String, CodingKey {
            case src
            case width = "config_width"
        }
    }

    final class Edges<Node: Decodable>: Decodable {
        var edges: [Edge]?
        struct Edge: Decodable { var node: Node? }
        var nodes: [Node] { (edges ?? []).compactMap(\.node) }
    }

    struct TextNode: Decodable { var text: String? }
    struct Count: Decodable { var count: Int? }

    struct Owner: Decodable {
        var username: String?
        var fullName: String?
        var profilePicURL: String?
        enum CodingKeys: String, CodingKey {
            case username
            case fullName = "full_name"
            case profilePicURL = "profile_pic_url"
        }
    }

    private struct Context: Decodable {
        var gqlData: GQL?
        enum CodingKeys: String, CodingKey { case gqlData = "gql_data" }
        struct GQL: Decodable {
            var media: Media?
            enum CodingKeys: String, CodingKey { case media = "shortcode_media" }
        }
    }

    static func parse(html: String, shortcode: String) throws -> PostDraft {
        if html.contains("EmbedBrokenMedia") { throw SocialError.instagramUnavailable }
        let hasEmbed = html.contains("EmbeddedMedia") || html.contains("contextJSON\":\"")
        if !hasEmbed {
            if html.contains("/accounts/login") || html.contains("loginForm") { throw SocialError.instagramLogin }
            throw SocialError.unreadable(.instagram)
        }

        let media = contextMedia(in: html)
        let username = media?.owner?.username
            ?? HTMLText.element(withClass: "UsernameText", in: html).map { HTMLText.plainText(String($0)) }
            ?? HTMLText.element(withClass: "CaptionUsername", in: html).map { HTMLText.plainText(String($0)) }
            ?? ""

        var imageURLs: [URL] = []
        if let media {
            let children = media.children?.nodes ?? []
            imageURLs = (children.isEmpty ? [media] : children).compactMap(\.bestImageURL)
        }
        if imageURLs.isEmpty, let img = HTMLText.tag(withClass: "EmbeddedMediaImage", in: html) {
            let src = HTMLText.attribute("srcset", in: img).flatMap { HTMLText.bestSource(srcset: $0, target: 1000) }
                ?? HTMLText.attribute("src", in: img)
            if let src, let url = URL(string: src) { imageURLs = [url] }
        }

        var avatar = media?.owner?.profilePicURL
        if avatar == nil, let container = HTMLText.element(withClass: "AvatarContainer", in: html),
           let img = container.range(of: "<img").map({ container[$0.lowerBound...].prefix { $0 != ">" } }) {
            avatar = HTMLText.attribute("src", in: img + ">")
        }

        let text = media?.caption?.nodes.first?.text.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? htmlCaption(html)
        let likes = media?.likedBy?.count ?? media?.previewLikes?.count
            ?? HTMLText.element(withClass: "SocialProof", in: html).flatMap { HTMLText.integer(in: HTMLText.plainText(String($0))) }
        let comments = media?.comments?.count
            ?? HTMLText.element(withClass: "CaptionCommentsExpand", in: html).flatMap { HTMLText.integer(in: HTMLText.plainText(String($0))) }
        let date = media?.takenAt.map { Date(timeIntervalSince1970: $0) } ?? InstagramID.date(shortcode: shortcode)

        guard !imageURLs.isEmpty || !username.isEmpty else { throw SocialError.unreadable(.instagram) }
        let post = SocialPost(
            platform: .instagram,
            url: URL(string: "https://www.instagram.com/p/\(shortcode)/"),
            authorName: media?.owner?.fullName ?? "",
            handle: username,
            text: text,
            date: date,
            likes: likes,
            replies: comments
        )
        return PostDraft(post: post, imageURLs: imageURLs, avatarURL: avatar.flatMap(URL.init(string:)))
    }

    /// Decodes `"contextJSON":"{…}"` (a JSON document inside a JSON string) when present.
    static func contextMedia(in html: String) -> Media? {
        let marker = "\"contextJSON\":\""
        guard let start = html.range(of: marker) else { return nil }
        // Find the closing quote of the string literal, skipping escaped characters.
        var i = start.upperBound
        var escaped = false
        while i < html.endIndex {
            let c = html[i]
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { break }
            i = html.index(after: i)
        }
        guard i < html.endIndex else { return nil }
        let literal = "\"" + html[start.upperBound..<i] + "\""
        guard let inner = try? JSONSerialization.jsonObject(with: Data(literal.utf8), options: .fragmentsAllowed) as? String,
              let context = try? JSONDecoder().decode(Context.self, from: Data(inner.utf8)) else { return nil }
        return context.gqlData?.media
    }

    /// Caption text from the HTML: what follows the username link inside `.Caption`, minus the comments link.
    static func htmlCaption(_ html: String) -> String {
        guard var caption = HTMLText.element(withClass: "Caption", in: html).map(String.init) else { return "" }
        if let comments = caption.range(of: "<div class=\"CaptionComments\"") { caption = String(caption[..<comments.lowerBound]) }
        if let userEnd = caption.range(of: "</a>"), caption.hasPrefix("<a class=\"CaptionUsername\"") {
            caption = String(caption[userEnd.upperBound...])
        }
        return HTMLText.plainText(caption)
    }
}
