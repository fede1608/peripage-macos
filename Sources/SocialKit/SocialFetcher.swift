import CoreGraphics
import Foundation
import ImageIO

public enum SocialError: LocalizedError, Equatable {
    case unsupportedLink
    case profileLink
    case instagramStory
    case notFound
    case tweetUnavailable
    case instagramUnavailable
    case instagramLogin
    case rateLimited(SocialPlatform)
    case httpStatus(SocialPlatform, Int)
    case unreadable(SocialPlatform)
    case imageDownload
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedLink:
            "No reconozco ese link. Pegá el link de un posteo de X (x.com/usuario/status/…) o de Instagram (instagram.com/p/…)."
        case .profileLink:
            "Ese link es de un perfil. Pegá el link de un posteo puntual (en el posteo: Compartir → Copiar link)."
        case .instagramStory:
            "Las historias de Instagram no se pueden traer con el link: abrila en el Navegador, iniciá sesión y usá Capturar."
        case .notFound:
            "No encontré ese posteo. Fijate que el link esté completo; puede que lo hayan borrado."
        case .tweetUnavailable:
            "X no deja mostrar ese posteo: puede ser de una cuenta protegida, estar borrado o tener restricción de edad. Probá abrirlo en el Navegador y capturarlo."
        case .instagramUnavailable:
            "Instagram no muestra ese posteo fuera de la app: puede ser de una cuenta privada, estar borrado o tener restricción de edad. Probá abrirlo en el Navegador y capturarlo."
        case .instagramLogin:
            "Instagram pide iniciar sesión para ver ese posteo. Abrilo en el Navegador, iniciá sesión y capturalo."
        case .rateLimited(let platform):
            "\(platform.title) está limitando las consultas. Esperá unos minutos y volvé a probar."
        case .httpStatus(let platform, let code):
            "\(platform.title) respondió con un error (\(code)). Probá de nuevo en un rato."
        case .unreadable(let platform):
            "No pude leer la respuesta de \(platform.title); puede que hayan cambiado el formato. Mientras tanto, usá el Navegador para capturarlo."
        case .imageDownload:
            "Encontré el posteo pero no pude descargar sus imágenes. Revisá la conexión y probá de nuevo."
        case .network(let message):
            "No me pude conectar: \(message)"
        }
    }
}

public enum SocialFetcher {
    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
    static let maxImages = 10

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": safariUserAgent]
        return URLSession(configuration: config)
    }()

    /// True for X/Instagram post links (and bare tweet ids) that `fetch` can try.
    public static func canHandle(_ string: String) -> Bool {
        SocialLink.parse(string)?.isFetchable ?? false
    }

    public static func fetch(_ urlString: String) async throws -> SocialPost {
        guard var link = SocialLink.parse(urlString) else { throw SocialError.unsupportedLink }
        if case .redirect(let url) = link {
            let resolved = try await resolveRedirect(url)
            guard let next = SocialLink.parse(resolved.absoluteString), next != link else { throw SocialError.unsupportedLink }
            link = next
        }
        let draft: PostDraft
        switch link {
        case .tweet(let id): draft = try await tweetDraft(id: id)
        case .instagramPost(let code): draft = try await instagramDraft(shortcode: code)
        case .instagramStory: throw SocialError.instagramStory
        case .instagramProfile, .xProfile: throw SocialError.profileLink
        case .redirect: throw SocialError.unsupportedLink
        }
        return try await complete(draft)
    }

    // MARK: Platforms

    static func tweetDraft(id: String) async throws -> PostDraft {
        // FxTwitter in parallel: it has the repost count and full long-post text that syndication omits.
        async let extras = fxTwitterExtras(id: id)
        var request = URLRequest(url: XSyndication.url(for: id))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await load(request)
        switch response.statusCode {
        case 200: break
        case 400, 404: throw SocialError.notFound
        case 429: throw SocialError.rateLimited(.x)
        default: throw SocialError.httpStatus(.x, response.statusCode)
        }
        switch try XParser.parse(data) {
        case .post(var draft):
            FxTwitter.merge(await extras, into: &draft)
            return draft
        case .tombstone: throw SocialError.tweetUnavailable
        case .notFound: throw SocialError.notFound
        }
    }

    private static func fxTwitterExtras(id: String) async -> FxTwitter.Extras? {
        var request = URLRequest(url: FxTwitter.url(for: id))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8
        guard let (data, response) = try? await load(request), response.statusCode == 200 else { return nil }
        return FxTwitter.parse(data)
    }

    static func instagramDraft(shortcode: String) async throws -> PostDraft {
        var request = URLRequest(url: URL(string: "https://www.instagram.com/p/\(shortcode)/embed/captioned/")!)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await load(request)
        if response.url?.path.contains("/accounts/login") == true { throw SocialError.instagramLogin }
        switch response.statusCode {
        case 200: break
        case 404: throw SocialError.notFound
        case 429: throw SocialError.rateLimited(.instagram)
        case 401, 403: throw SocialError.instagramLogin
        default: throw SocialError.httpStatus(.instagram, response.statusCode)
        }
        let html = String(decoding: data, as: UTF8.self)
        return try InstagramParser.parse(html: html, shortcode: shortcode)
    }

    // MARK: Networking

    private static func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SocialError.network("respuesta inválida") }
            return (data, http)
        } catch let error as SocialError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SocialError.network(error.localizedDescription)
        }
    }

    private static func resolveRedirect(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await load(request)
        if let final = response.url, final != url { return final }
        // t.co answers some clients with an HTML/JS redirect instead of a 301.
        let html = String(decoding: data.prefix(20_000), as: UTF8.self)
        if let r = html.range(of: #"https?://[^"'<> ]+"#, options: .regularExpression), let found = URL(string: String(html[r])),
           SocialLink.parse(found.absoluteString)?.isFetchable == true {
            return found
        }
        throw SocialError.unsupportedLink
    }

    /// Downloads avatar and images in parallel. Avatar failures are ignored; failing every image is an error.
    static func complete(_ draft: PostDraft) async throws -> SocialPost {
        var post = draft.post
        let urls = Array(draft.imageURLs.prefix(maxImages))
        let avatarURL = draft.avatarURL
        async let avatar: CGImage? = {
            guard let avatarURL else { return nil }
            return try? await downloadImage(avatarURL, maxPixels: 400)
        }()
        let images = await withTaskGroup(of: (Int, CGImage?).self) { group in
            for (i, url) in urls.enumerated() {
                group.addTask { (i, try? await downloadImage(url, maxPixels: 1600)) }
            }
            var out = [CGImage?](repeating: nil, count: urls.count)
            for await (i, image) in group { out[i] = image }
            return out.compactMap { $0 }
        }
        try Task.checkCancellation()
        if !urls.isEmpty, images.isEmpty { throw SocialError.imageDownload }
        post.images = images
        post.avatar = await avatar
        return post
    }

    static func downloadImage(_ url: URL, maxPixels: Int) async throws -> CGImage {
        var request = URLRequest(url: url)
        request.setValue("image/jpeg,image/png,image/webp,image/*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await load(request)
        guard response.statusCode == 200, let image = decodeImage(data, maxPixels: maxPixels) else { throw SocialError.imageDownload }
        return image
    }

    /// Decodes with ImageIO, applying EXIF orientation and capping the longest side.
    static func decodeImage(_ data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
