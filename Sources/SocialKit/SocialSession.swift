import AppKit
import WebKit

/// The login the user made in the in-app browser (WebKit's default, persistent data store), reused to read
/// private posts and stories. PeriPrint never sees the password: sign-in happens on instagram.com / x.com
/// inside the browser, and here we only look for the session cookie and load pages with it.
@MainActor
public enum SocialSession {
    /// Session cookies that only exist while logged in.
    static func sessionCookie(_ platform: SocialPlatform) -> (name: String, domains: [String])? {
        switch platform {
        case .instagram: ("sessionid", ["instagram.com"])
        case .x: ("auth_token", ["x.com", "twitter.com"])
        case .capture: nil
        }
    }

    public static func isLoggedIn(_ platform: SocialPlatform) async -> Bool {
        guard let wanted = sessionCookie(platform) else { return false }
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return cookies.contains { cookie in
            cookie.name == wanted.name && !cookie.value.isEmpty && wanted.domains.contains { cookie.domain.hasSuffix($0) }
                && (cookie.expiresDate.map { $0 > .now } ?? true)
        }
    }

    /// Deletes everything WebKit stored for the platform (cookies, storage, cache): a full sign-out.
    public static func logOut(_ platform: SocialPlatform) async {
        let sites: [String] = switch platform {
        case .instagram: ["instagram.com", "cdninstagram.com", "facebook.com"]
        case .x: ["x.com", "twitter.com", "twimg.com"]
        case .capture: []
        }
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let matching = records.filter { record in sites.contains { record.displayName.hasSuffix($0) } }
        await store.removeData(ofTypes: types, for: matching)
    }

    public static func loginURL(_ platform: SocialPlatform) -> URL {
        platform == .x ? URL(string: "https://x.com/i/flow/login")! : URL(string: "https://www.instagram.com/accounts/login/")!
    }
}

/// An off-screen WKWebView sharing the browser's data store: it loads a page with the user's session and
/// runs a script there (same-origin requests carry the session cookies; nothing is read from them here).
@MainActor
final class HiddenPage: NSObject, WKNavigationDelegate {
    private let window: NSWindow
    let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Error>?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1100, height: 1400), configuration: config)
        webView.customUserAgent = SocialFetcher.safariUserAgent
        // A real (but invisible) window keeps WebKit rendering and running timers at full speed.
        window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 1100, height: 1400),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.contentView = webView
        super.init()
        webView.navigationDelegate = self
        window.orderBack(nil)
    }

    func close() {
        webView.stopLoading()
        window.orderOut(nil)
        window.contentView = nil
    }

    func load(_ url: URL, timeout: TimeInterval = 25) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    self.loadContinuation = cont
                    self.webView.load(URLRequest(url: url))
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw SocialError.network("la página tardó demasiado en cargar")
            }
            try await group.next()
            group.cancelAll()
        }
    }

    /// Runs an async JavaScript function body in the page and returns its (JSON string) result.
    func run(_ body: String, arguments: [String: Any] = [:]) async throws -> String {
        let result = try await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
        guard let string = result as? String else { throw SocialError.unreadable(.instagram) }
        return string
    }

    /// Resolves as soon as the page is committed: scripts then wait for the content they need,
    /// and sites that keep connections open (x.com) may never report "finished".
    nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        MainActor.assumeIsolated { finish(nil) }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { finish(nil) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finish(error) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finish(error) }
    }

    private func finish(_ error: Error?) {
        guard let cont = loadContinuation else { return }
        loadContinuation = nil
        if let error { cont.resume(throwing: SocialError.network(error.localizedDescription)) } else { cont.resume() }
    }
}
