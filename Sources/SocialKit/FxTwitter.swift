import Foundation

/// FxTwitter's public API (https://github.com/FxEmbed/FxEmbed), used to complete what X's syndication
/// endpoint leaves out: the repost count and the full text of long posts. It is optional: any failure is ignored.
enum FxTwitter {
    struct Extras: Equatable {
        var reposts: Int?
        var likes: Int?
        var replies: Int?
        /// Full text, only for long posts ("note tweets") that syndication truncates.
        var fullText: String?
    }

    static func url(for id: String) -> URL { URL(string: "https://api.fxtwitter.com/status/\(id)")! }

    static func parse(_ data: Data) -> Extras? {
        struct Response: Decodable {
            struct Tweet: Decodable {
                var text: String?
                var retweets: Int?
                var likes: Int?
                var replies: Int?
                var isNoteTweet: Bool?
                enum CodingKeys: String, CodingKey {
                    case text, retweets, likes, replies
                    case isNoteTweet = "is_note_tweet"
                }
            }
            var code: Int?
            var tweet: Tweet?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data), response.code == 200,
              let tweet = response.tweet else { return nil }
        let text = tweet.isNoteTweet == true ? tweet.text.map { HTMLText.decodeEntities($0).trimmingCharacters(in: .whitespacesAndNewlines) } : nil
        return Extras(reposts: tweet.retweets, likes: tweet.likes, replies: tweet.replies, fullText: text?.isEmpty == true ? nil : text)
    }

    /// Fills missing counts and swaps in the full text of long posts; syndication data wins otherwise.
    static func merge(_ extras: Extras?, into draft: inout PostDraft) {
        guard let extras else { return }
        draft.post.reposts = draft.post.reposts ?? extras.reposts
        draft.post.likes = draft.post.likes ?? extras.likes
        draft.post.replies = draft.post.replies ?? extras.replies
        // XParser marks truncated long posts with "…"; anything after it (a quoted tweet) is kept.
        if let full = extras.fullText, let cut = draft.post.text.range(of: "…") {
            draft.post.text = full + draft.post.text[cut.upperBound...]
        }
    }
}
