import Foundation

/// A pasted link (or bare tweet id) classified by what it points to.
enum SocialLink: Equatable {
    case tweet(id: String)
    case instagramPost(shortcode: String)
    case instagramStory(user: String, id: String?)
    case instagramProfile(user: String)
    case xProfile(user: String)
    /// t.co or instagram.com/share/… links: they must be followed to know the real post.
    case redirect(URL)

    static let xHosts: Set<String> = ["x.com", "twitter.com", "fxtwitter.com", "vxtwitter.com", "fixupx.com", "fixvx.com", "nitter.net"]
    static let instagramHosts: Set<String> = ["instagram.com", "instagr.am", "ddinstagram.com"]
    private static let instagramReserved: Set<String> = ["explore", "accounts", "direct", "about", "developer", "legal", "web", "reels"]

    var isFetchable: Bool {
        switch self {
        case .tweet, .instagramPost, .instagramStory, .redirect: true
        case .instagramProfile, .xProfile: false
        }
    }

    static func parse(_ raw: String) -> SocialLink? {
        var string = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "<>\"'")))
        guard !string.isEmpty else { return nil }
        if string.count <= 20, string.allSatisfy(\.isASCII), string.allSatisfy(\.isNumber) { return .tweet(id: string) }
        if !string.contains("://") { string = "https://" + string }
        guard let url = URL(string: string), let rawHost = url.host?.lowercased() else { return nil }
        var host = rawHost
        for prefix in ["www.", "mobile.", "m."] where host.hasPrefix(prefix) { host.removeFirst(prefix.count) }
        let parts = url.path.split(separator: "/").map(String.init)

        if host == "t.co", parts.count == 1 { return .redirect(url) }

        if xHosts.contains(host) {
            if let i = parts.firstIndex(where: { $0 == "status" || $0 == "statuses" }), i + 1 < parts.count {
                let id = String(parts[i + 1].prefix { $0.isASCII && $0.isNumber })
                return id.isEmpty || id.count > 20 ? nil : .tweet(id: id)
            }
            if parts.count == 1, parts[0].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), parts[0] != "home" {
                return .xProfile(user: parts[0])
            }
            return nil
        }

        if instagramHosts.contains(host) {
            if parts.first == "share" { return .redirect(url) }
            if parts.first == "stories", parts.count >= 2 {
                let id = parts.count >= 3 && parts[2].allSatisfy(\.isNumber) ? parts[2] : nil
                return .instagramStory(user: parts[1], id: id)
            }
            if let i = parts.firstIndex(where: { ["p", "reel", "reels", "tv"].contains($0) }), i + 1 < parts.count {
                let code = parts[i + 1]
                guard !code.isEmpty, code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { return nil }
                return .instagramPost(shortcode: code)
            }
            if parts.count == 1, !instagramReserved.contains(parts[0]) { return .instagramProfile(user: parts[0]) }
            return nil
        }
        return nil
    }
}

enum InstagramID {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    /// Instagram's epoch (ms) for the 41-bit timestamp in media ids.
    private static let epochMS: UInt64 = 1_314_220_021_721

    /// Media id encoded by a public shortcode (base-64 with Instagram's alphabet). Private-post shortcodes are longer and carry no id.
    static func mediaID(shortcode: String) -> UInt64? {
        guard !shortcode.isEmpty, shortcode.count <= 11 else { return nil }
        var n: UInt64 = 0
        for ch in shortcode {
            guard let v = alphabet.firstIndex(of: ch) else { return nil }
            let (shifted, overflow) = n.multipliedReportingOverflow(by: 64)
            guard !overflow else { return nil }
            n = shifted + UInt64(v)
        }
        return n
    }

    /// Publication date encoded in the media id (upper bits are milliseconds since Instagram's epoch).
    static func date(shortcode: String) -> Date? {
        guard let id = mediaID(shortcode: shortcode) else { return nil }
        let ms = (id >> 23) + epochMS
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        // Sanity check: Instagram launched in 2010; anything outside that range is not a real id.
        guard date > Date(timeIntervalSince1970: 1_262_304_000), date < Date().addingTimeInterval(86_400 * 2) else { return nil }
        return date
    }
}
