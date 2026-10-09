import Foundation

/// URLSession with a disk cache in ~/Library/Caches/PeriPrint, Spanish errors and an offline fallback
/// to whatever was cached before.
final class StoreHTTP: @unchecked Sendable {
    static let shared = StoreHTTP()

    static let userAgent = "PeriPrint/1.0 (macOS; thermal printer app)"

    let session: URLSession
    let cache: URLCache

    init(cacheDirectory: URL = StorePaths.urlCache, configure: (URLSessionConfiguration) -> Void = { _ in }) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        cache = URLCache(memoryCapacity: 48 << 20, diskCapacity: 512 << 20, directory: cacheDirectory)
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 25
        config.httpMaximumConnectionsPerHost = 8
        config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        configure(config)
        session = URLSession(configuration: config)
    }

    /// `.returnCacheDataElseLoad` suits immutable files (versioned CDN paths, SVGs, fonts).
    func data(from url: URL, policy: URLRequest.CachePolicy = .useProtocolCachePolicy,
              headers: [String: String] = [:], timeout: TimeInterval? = nil) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: policy)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let timeout { request.timeoutInterval = timeout }
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 200..<300: break
                case 404, 410: throw StoreError.notFound
                case 429: throw StoreError.rateLimited
                default: throw StoreError.http(http.statusCode)
                }
            }
            return data
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            try Task.checkCancellation()
            if let cached = cache.cachedResponse(for: request), !cached.data.isEmpty { return cached.data }
            switch error.code {
            case .timedOut: throw StoreError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
                throw StoreError.offline
            default: throw error
            }
        }
    }
}
