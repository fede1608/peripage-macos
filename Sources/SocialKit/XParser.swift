import Foundation

/// Parses `cdn.syndication.twimg.com/tweet-result` JSON.
enum XParser {
    final class Tweet: Decodable {
        var typename: String?
        var idStr: String?
        var text: String?
        var createdAt: String?
        var favoriteCount: Int?
        var conversationCount: Int?
        var replyCount: Int?
        var retweetCount: Int?
        var displayTextRange: [Int]?
        var entities: Entities?
        var user: User?
        var mediaDetails: [Media]?
        var video: Video?
        var quotedTweet: Tweet?
        var noteTweet: NoteTweet?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case idStr = "id_str"
            case text
            case createdAt = "created_at"
            case favoriteCount = "favorite_count"
            case conversationCount = "conversation_count"
            case replyCount = "reply_count"
            case retweetCount = "retweet_count"
            case displayTextRange = "display_text_range"
            case entities, user, mediaDetails, video
            case quotedTweet = "quoted_tweet"
            case noteTweet = "note_tweet"
        }
    }

    struct Entities: Decodable {
        var urls: [URLEntity]?
        var media: [URLEntity]?
    }

    struct URLEntity: Decodable {
        var url: String?
        var displayURL: String?
        var expandedURL: String?
        enum CodingKeys: String, CodingKey {
            case url
            case displayURL = "display_url"
            case expandedURL = "expanded_url"
        }
    }

    struct User: Decodable {
        var name: String?
        var screenName: String?
        var profileImageURL: String?
        enum CodingKeys: String, CodingKey {
            case name
            case screenName = "screen_name"
            case profileImageURL = "profile_image_url_https"
        }
    }

    struct Media: Decodable {
        var type: String?
        var url: String?
        var mediaURL: String?
        enum CodingKeys: String, CodingKey {
            case type, url
            case mediaURL = "media_url_https"
        }
    }

    struct Video: Decodable {
        var poster: String?
    }

    struct NoteTweet: Decodable {
        var id: String?
    }

    enum Outcome {
        case post(PostDraft)
        case tombstone
        case notFound
    }

    static func parse(_ data: Data) throws -> Outcome {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SocialError.unreadable(.x) }
        if object.isEmpty { return .notFound }
        let tweet: Tweet
        do { tweet = try JSONDecoder().decode(Tweet.self, from: data) } catch { throw SocialError.unreadable(.x) }
        if tweet.typename == "TweetTombstone" { return .tombstone }
        guard tweet.text != nil || tweet.user != nil else { return .notFound }
        return .post(draft(from: tweet))
    }

    static func draft(from tweet: Tweet) -> PostDraft {
        let handle = tweet.user?.screenName ?? ""
        var text = cleanText(tweet)
        var imageURLs = mediaURLs(tweet)
        if let quoted = tweet.quotedTweet {
            let quotedText = cleanText(quoted)
            let who = quoted.user?.screenName.map { "@" + $0 + ":" }
            if !quotedText.isEmpty {
                let quote = [who, "“" + quotedText + "”"].compactMap { $0 }.joined(separator: " ")
                text += (text.isEmpty ? "" : "\n\n") + quote
            }
            if imageURLs.isEmpty { imageURLs = mediaURLs(quoted) }
        }
        var url: URL?
        if let id = tweet.idStr { url = URL(string: "https://x.com/\(handle.isEmpty ? "i" : handle)/status/\(id)") }
        let post = SocialPost(
            platform: .x, url: url,
            authorName: tweet.user?.name.map(HTMLText.decodeEntities) ?? "",
            handle: handle,
            text: text,
            date: tweet.createdAt.flatMap(parseDate),
            likes: tweet.favoriteCount,
            replies: tweet.conversationCount ?? tweet.replyCount,
            reposts: tweet.retweetCount
        )
        return PostDraft(post: post, imageURLs: imageURLs, avatarURL: avatarURL(tweet.user?.profileImageURL))
    }

    /// Tweet text without the reply prefix and trailing media links, with t.co links shown as their display URL.
    static func cleanText(_ tweet: Tweet) -> String {
        guard var text = tweet.text else { return "" }
        // Leading "@user @other " of replies: display_text_range starts after them (indices are code points).
        if let start = tweet.displayTextRange?.first, start > 0, start <= text.unicodeScalars.count {
            let prefix = String(String.UnicodeScalarView(text.unicodeScalars.prefix(start)))
            if prefix.trimmingCharacters(in: .whitespaces).hasPrefix("@") {
                text = String(String.UnicodeScalarView(text.unicodeScalars.dropFirst(start)))
            }
        }
        let mediaLinks = Set((tweet.entities?.media ?? []).compactMap(\.url) + (tweet.mediaDetails ?? []).compactMap(\.url))
        for link in mediaLinks { text = text.replacingOccurrences(of: link, with: "") }
        for entity in tweet.entities?.urls ?? [] {
            guard let short = entity.url else { continue }
            text = text.replacingOccurrences(of: short, with: entity.displayURL ?? entity.expandedURL ?? short)
        }
        text = HTMLText.decodeEntities(text).trimmingCharacters(in: .whitespacesAndNewlines)
        // Long posts ("note tweets") arrive truncated.
        if tweet.noteTweet != nil, !text.isEmpty, !text.hasSuffix("…") { text += "…" }
        return text
    }

    /// Photos at 900×900 max (plenty for 384–576 dots); videos and GIFs give their poster frame.
    static func mediaURLs(_ tweet: Tweet) -> [URL] {
        var urls: [URL] = []
        for media in tweet.mediaDetails ?? [] {
            guard let raw = media.mediaURL, var components = URLComponents(string: raw) else { continue }
            if media.type == "photo", components.host == "pbs.twimg.com", components.path.hasPrefix("/media/") {
                let ext = (components.path as NSString).pathExtension
                components.path = (components.path as NSString).deletingPathExtension
                components.queryItems = [URLQueryItem(name: "format", value: ext.isEmpty ? "jpg" : ext),
                                         URLQueryItem(name: "name", value: "900x900")]
            }
            if let url = components.url { urls.append(url) }
        }
        if urls.isEmpty, let poster = tweet.video?.poster, let url = URL(string: poster) { urls.append(url) }
        return urls
    }

    static func avatarURL(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        return URL(string: raw.replacingOccurrences(of: "_normal.", with: "_400x400."))
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
