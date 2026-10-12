import Foundation

/// Reads private posts and stories with the user's own session (see `SocialSession`): Instagram through the
/// JSON endpoints its web app uses, requested from inside an instagram.com page; X by reading the rendered
/// post. Both are unofficial and may need updating if the sites change.
@MainActor
enum AuthenticatedFetcher {
    // MARK: Instagram

    /// Instagram's public web app id, sent by instagram.com itself on these requests.
    static let instagramAppID = "936619743392459"

    static func instagramPost(shortcode: String) async throws -> PostDraft {
        guard let mediaID = InstagramIDs.mediaID(shortcode: shortcode) else { throw SocialError.notFound }
        let page = try await openInstagram()
        defer { page.close() }
        let data = try await instagramJSON(page, path: "/api/v1/media/\(mediaID)/info/")
        guard let item = try InstagramAPI.decode(InstagramAPI.MediaInfo.self, data).items?.first else { throw SocialError.notFound }
        return InstagramAPI.draft(from: item, url: URL(string: "https://www.instagram.com/p/\(shortcode)/"))
    }

    static func instagramStory(user: String, id: String?) async throws -> PostDraft {
        let page = try await openInstagram()
        defer { page.close() }
        let profile = try InstagramAPI.decode(InstagramAPI.ProfileInfo.self,
                                              try await instagramJSON(page, path: "/api/v1/users/web_profile_info/?username=\(user)"))
        guard let userID = profile.data?.user?.id?.value else { throw SocialError.notFound }
        let reels = try InstagramAPI.decode(InstagramAPI.ReelsMedia.self,
                                            try await instagramJSON(page, path: "/api/v1/feed/reels_media/?reel_ids=\(userID)"))
        let items = reels.reelsMedia?.first?.items ?? reels.reels?[userID]?.items ?? []
        let item = id.flatMap { wanted in items.first { $0.pk?.value == wanted || $0.id?.value.hasPrefix(wanted + "_") == true } }
            ?? (id == nil ? items.first : nil)
        guard var found = item else { throw SocialError.storyExpired }
        if found.user == nil { found.user = reels.reelsMedia?.first?.user ?? reels.reels?[userID]?.user }
        let url = URL(string: "https://www.instagram.com/stories/\(user)/\(found.pk?.value ?? "")/")
        return InstagramAPI.draft(from: found, url: url)
    }

    private static func openInstagram() async throws -> HiddenPage {
        let page = HiddenPage()
        do {
            try await page.load(URL(string: "https://www.instagram.com/")!)
        } catch {
            page.close()
            throw error
        }
        return page
    }

    /// GET from inside the page: same origin, so the session cookies go along (and never pass through us).
    private static func instagramJSON(_ page: HiddenPage, path: String) async throws -> Data {
        let script = """
        const r = await fetch(path, { credentials: 'include', headers: {
            'X-IG-App-ID': appID, 'X-Requested-With': 'XMLHttpRequest', 'Accept': 'application/json' } });
        return JSON.stringify({ status: r.status, url: r.url, body: await r.text() });
        """
        let raw = try await page.run(script, arguments: ["path": path, "appID": instagramAppID])
        struct Envelope: Decodable { let status: Int; let url: String; let body: String }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(raw.utf8)) else { throw SocialError.unreadable(.instagram) }
        let body = envelope.body
        if envelope.url.contains("/accounts/login") || body.contains("login_required") || envelope.status == 401 {
            throw SocialError.instagramLogin
        }
        switch envelope.status {
        case 200: return Data(body.utf8)
        case 404: throw SocialError.notFound
        case 429: throw SocialError.rateLimited(.instagram)
        case 400, 403:
            // "Media not found or unavailable": private account the user doesn't follow, or deleted.
            throw SocialError.privateNotFollowed(.instagram)
        default: throw SocialError.httpStatus(.instagram, envelope.status)
        }
    }

    // MARK: X

    static func tweet(id: String) async throws -> PostDraft {
        let page = HiddenPage()
        defer { page.close() }
        try await page.load(URL(string: "https://x.com/i/status/\(id)")!)
        let raw = try await page.run(XPageScript.source, arguments: ["id": id])
        guard let data = raw.data(using: .utf8),
              let found = try? JSONDecoder().decode(XPageScript.Result.self, from: data) else { throw SocialError.unreadable(.x) }
        if found.missing == true { throw found.loginWall == true ? SocialError.xLogin : SocialError.privateNotFollowed(.x) }
        let handle = found.handle ?? ""
        let post = SocialPost(
            platform: .x, url: URL(string: "https://x.com/\(handle.isEmpty ? "i" : handle)/status/\(id)"),
            authorName: found.name ?? handle, handle: handle,
            text: found.text ?? "",
            date: found.time.flatMap { ISO8601DateFormatter.withFractions.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
                ?? found.timestamp.map { Date(timeIntervalSince1970: $0 / 1000) },
            likes: XPageScript.count(found.likes), replies: XPageScript.count(found.replies), reposts: XPageScript.count(found.reposts)
        )
        let images = (found.photos ?? []).map(XPageScript.largePhoto) + (found.posters ?? [])
        return PostDraft(post: post, imageURLs: images.compactMap(URL.init(string:)),
                         avatarURL: found.avatar.flatMap { URL(string: $0.replacingOccurrences(of: "_normal.", with: "_400x400.")) })
    }
}

/// Instagram shortcodes are the media id in a URL-safe base64 alphabet (only the first 11 characters for
/// private-post links, which append extra characters).
enum InstagramIDs {
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    static func mediaID(shortcode: String) -> String? {
        let code = shortcode.count > 11 ? String(shortcode.prefix(11)) : shortcode
        var value: UInt64 = 0
        for ch in code {
            guard let digit = alphabet.firstIndex(of: ch) else { return nil }
            let (shifted, o1) = value.multipliedReportingOverflow(by: 64)
            let (sum, o2) = shifted.addingReportingOverflow(UInt64(digit))
            if o1 || o2 { return nil }
            value = sum
        }
        return String(value)
    }
}

enum InstagramAPI {
    /// Ids arrive as strings or numbers depending on the endpoint.
    struct FlexibleID: Decodable {
        let value: String
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { value = s } else if let i = try? c.decode(Int64.self) { value = String(i) } else {
                value = String(format: "%.0f", try c.decode(Double.self))
            }
        }
    }

    struct User: Decodable {
        var username: String?
        var fullName: String?
        var profilePicURL: String?
        enum CodingKeys: String, CodingKey {
            case username
            case fullName = "full_name"
            case profilePicURL = "profile_pic_url"
        }
    }

    struct Candidate: Decodable { var url: String; var width: Int? }
    struct Images: Decodable { var candidates: [Candidate]? }
    struct Caption: Decodable { var text: String? }

    struct Item: Decodable {
        var pk: FlexibleID?
        var id: FlexibleID?
        var takenAt: Double?
        var user: User?
        var caption: Caption?
        var likeCount: Int?
        var commentCount: Int?
        var imageVersions2: Images?
        var carouselMedia: [Item]?
        enum CodingKeys: String, CodingKey {
            case pk, id, user, caption
            case takenAt = "taken_at"
            case likeCount = "like_count"
            case commentCount = "comment_count"
            case imageVersions2 = "image_versions2"
            case carouselMedia = "carousel_media"
        }

        var bestImageURL: URL? {
            imageVersions2?.candidates?.max { ($0.width ?? 0) < ($1.width ?? 0) }.flatMap { URL(string: $0.url) }
        }
    }

    struct MediaInfo: Decodable { var items: [Item]? }

    struct ProfileInfo: Decodable {
        struct DataBlock: Decodable {
            struct ProfileUser: Decodable { var id: FlexibleID? }
            var user: ProfileUser?
        }
        var data: DataBlock?
    }

    struct Reel: Decodable { var items: [Item]?; var user: User? }
    struct ReelsMedia: Decodable {
        var reels: [String: Reel]?
        var reelsMedia: [Reel]?
        enum CodingKeys: String, CodingKey {
            case reels
            case reelsMedia = "reels_media"
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw SocialError.unreadable(.instagram) }
    }

    static func draft(from item: Item, url: URL?) -> PostDraft {
        let user = item.user
        let post = SocialPost(
            platform: .instagram, url: url,
            authorName: user?.fullName ?? "", handle: user?.username ?? "",
            text: item.caption?.text ?? "",
            date: item.takenAt.map { Date(timeIntervalSince1970: $0) },
            likes: item.likeCount, replies: item.commentCount
        )
        let images = (item.carouselMedia?.isEmpty == false ? item.carouselMedia!.compactMap(\.bestImageURL) : [item.bestImageURL].compactMap { $0 })
        return PostDraft(post: post, imageURLs: images, avatarURL: user?.profilePicURL.flatMap(URL.init(string:)))
    }
}

/// Reads a rendered post on x.com. Handles both the classic web app (`data-testid` attributes) and the
/// newer server-rendered design (`data-engagement-action`, abbreviated localized counts).
enum XPageScript {
    struct Result: Decodable {
        var missing: Bool?
        var loginWall: Bool?
        var text: String?
        var name: String?
        var handle: String?
        var avatar: String?
        var photos: [String]?
        var posters: [String]?
        var time: String?
        var timestamp: Double?
        var replies: String?
        var reposts: String?
        var likes: String?
    }

    static let source = """
    const deadline = Date.now() + 15000;
    const statusLink = a => [...a.querySelectorAll('a[href*="/status/"]')]
      .find(l => /\\/status\\/\\d+$/.test(l.getAttribute('href')) && l.getAttribute('href').endsWith('/status/' + id));
    let art = null;
    while (Date.now() < deadline) {
      art = [...document.querySelectorAll('article')].find(a => statusLink(a));
      if (art) break;
      await new Promise(r => setTimeout(r, 300));
    }
    if (!art) {
      const loginWall = !!document.querySelector('a[href="/login"], a[href="/i/flow/login"], [data-testid="loginButton"]');
      return JSON.stringify({ missing: true, loginWall });
    }
    const q = s => art.querySelector(s);
    const handle = (statusLink(art).getAttribute('href').split('/')[1] || '');
    const name = [...art.querySelectorAll('a[href="/' + handle + '"]')].map(l => l.innerText.trim())
      .find(t => t && !t.startsWith('@')) || handle;
    const textEl = q('[data-testid="tweetText"]')
      || [...art.querySelectorAll('div[dir="auto"], div[lang]')].find(d => !d.closest('button') && d.innerText.trim());
    const count = action => {
      const old = q('[data-testid="' + action + '"]') || (action === 'retweet' ? q('[data-testid="unretweet"]') : null)
        || (action === 'like' ? q('[data-testid="unlike"]') : null);
      if (old && /\\d/.test(old.getAttribute('aria-label') || '')) return old.getAttribute('aria-label');
      const neu = q('[data-engagement-action="' + action + '"]');
      return neu ? neu.innerText.replace(/\\u00a0/g, ' ').trim() : null;
    };
    const stamp = (art.innerHTML.match(/"timestamp":(\\d{10,})/) || [])[1];
    return JSON.stringify({
      text: textEl ? textEl.innerText.trim() : '',
      name, handle,
      avatar: q('img[src*="profile_images"]')?.src ?? null,
      photos: [...art.querySelectorAll('img[src*="pbs.twimg.com/media"]')].map(i => i.src),
      posters: [...art.querySelectorAll('video')].map(v => v.poster).filter(Boolean)
        .concat([...art.querySelectorAll('img[src*="video_thumb"]')].map(i => i.src)),
      time: q('time')?.getAttribute('datetime') ?? null,
      timestamp: stamp ? Number(stamp) : null,
      replies: count('reply'), reposts: count('retweet'), likes: count('like'),
    });
    """

    /// pbs.twimg.com photos come at the rendered size; ask for the large variant.
    static func largePhoto(_ url: String) -> String {
        guard var c = URLComponents(string: url) else { return url }
        var items = (c.queryItems ?? []).filter { $0.name != "name" }
        items.append(URLQueryItem(name: "name", value: "large"))
        c.queryItems = items
        return c.string ?? url
    }

    /// "1234 Replies", "1.234", "158 mil", "2 M", "1,9 M", "12.5K" → integer (abbreviations are approximate).
    static func count(_ raw: String?) -> Int? {
        guard let raw, let match = raw.firstMatch(of: #/(\d[\d.,]*)\s*(mil\s*M|mil|k|K|M|B|mill)?/#) else { return nil }
        let digits = String(match.1)
        guard let suffix = match.2.map({ String($0).lowercased().replacingOccurrences(of: " ", with: "") }) else {
            return Int(digits.filter(\.isNumber))
        }
        let multiplier: Double = switch suffix {
        case "k", "mil": 1_000
        case "m", "mill": 1_000_000
        case "b", "milm": 1_000_000_000
        default: 1
        }
        // With a suffix, "," or "." is a decimal separator ("1,9 M", "12.5K").
        guard let value = Double(digits.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return Int((value * multiplier).rounded())
    }
}

extension ISO8601DateFormatter {
    static let withFractions: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
