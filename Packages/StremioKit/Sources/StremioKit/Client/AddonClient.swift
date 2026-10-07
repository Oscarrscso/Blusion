import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AddonClientConfiguration: Sendable, Equatable {
    /// Overall deadline for one request, retries included (PLAN M2: 8 s per addon).
    public var timeout: TimeInterval
    public var maxBytes: Int
    /// Retries after the first attempt, for idempotent GETs that failed transiently (timeouts, connection loss, 5xx, 429).
    public var maxRetries: Int
    /// First retry waits `retryBackoff`, the next `2 x retryBackoff`, and so on.
    public var retryBackoff: TimeInterval
    public var maxRedirects: Int
    public var userAgent: String

    public init(timeout: TimeInterval = 8, maxBytes: Int = 5 * 1024 * 1024, maxRetries: Int = 2, retryBackoff: TimeInterval = 0.25,
                maxRedirects: Int = 5, userAgent: String = StremioKitInfo.userAgent) {
        self.timeout = timeout
        self.maxBytes = maxBytes
        self.maxRetries = maxRetries
        self.retryBackoff = retryBackoff
        self.maxRedirects = maxRedirects
        self.userAgent = userAgent
    }

    public static let `default` = AddonClientConfiguration()
}

/// Talks to addons. Every failure is an `AddonError`; no error or log line ever contains an addon URL.
public final class AddonClient: Sendable {
    public let configuration: AddonClientConfiguration
    private let transport: any HTTPTransport
    private let logger: AddonLogger

    public init(configuration: AddonClientConfiguration = .default,
                transport: (any HTTPTransport)? = nil,
                logger: AddonLogger = .silent) {
        self.configuration = configuration
        self.transport = transport ?? URLSessionTransport()
        self.logger = logger
    }

    /// GET with a deadline, bounded retries and status mapping. 2xx returns; 404 is `notFound`; other statuses are `http`.
    public func get(_ url: URL, headers: [String: String] = [:], limits: FetchLimits? = nil) async throws -> HTTPResult {
        let limits = limits ?? FetchLimits(maxBytes: configuration.maxBytes, maxRedirects: configuration.maxRedirects)
        let started = Date()
        do {
            let result = try await withDeadline(seconds: configuration.timeout) { [self] in
                try await getWithRetries(url, headers: headers, limits: limits)
            }
            logger.log(.debug, "GET \(Redactor.redact(url)) -> \(result.response.statusCode) (\(result.data.count) B, \(Self.millis(since: started)) ms)")
            return result
        } catch {
            let mapped = AddonError.from(error)
            logger.log(.warning, "GET \(Redactor.redact(url)) failed: \(mapped.shortDescription) after \(Self.millis(since: started)) ms")
            throw mapped
        }
    }

    /// First bytes of a resource, for container sniffing. Asks for a range, and cuts the body short if the server ignores it.
    public func prefix(of url: URL, bytes: Int = 4096, headers: [String: String] = [:]) async throws -> (data: Data, contentType: String?) {
        var headers = headers
        headers["Range"] = "bytes=0-\(max(bytes, 1) - 1)"
        let result = try await get(url, headers: headers, limits: FetchLimits(maxBytes: bytes, truncateAtLimit: true, maxRedirects: configuration.maxRedirects))
        return (result.data, result.response.contentType)
    }

    private func getWithRetries(_ url: URL, headers: [String: String], limits: FetchLimits) async throws -> HTTPResult {
        var attempt = 0
        while true {
            do {
                return try await attemptOnce(url, headers: headers, limits: limits)
            } catch let error as AddonError {
                guard error.isRetryable, attempt < configuration.maxRetries else { throw error }
                logger.log(.debug, "retry \(attempt + 1)/\(configuration.maxRetries) for \(Redactor.redact(url)) after \(error.shortDescription)")
                try await Task.sleep(for: .seconds(configuration.retryBackoff * pow(2, Double(attempt))))
                attempt += 1
            }
        }
    }

    private func attemptOnce(_ url: URL, headers: [String: String], limits: FetchLimits) async throws -> HTTPResult {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { throw AddonError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.httpMethod = "GET"
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, */*;q=0.5", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let result: HTTPResult
        do {
            result = try await transport.send(request, limits: limits)
        } catch {
            throw AddonError.from(error)   // whatever a transport throws, retry decisions see an AddonError
        }
        switch result.response.statusCode {
        case 200...299: return result
        case 404: throw AddonError.notFound
        default: throw AddonError.http(status: result.response.statusCode)
        }
    }

    private static func millis(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }
}

// MARK: - Typed protocol requests

extension AddonClient {
    /// Fetches, decodes and validates a manifest. Uninstallable manifests throw `invalidManifest` with readable reasons.
    public func fetchManifest(at location: AddonLocation) async throws -> Manifest {
        let result = try await get(location.manifestURL)
        let manifest = try ResponseDecoder.manifest(from: result.data)
        let errors = manifest.validate().filter { $0.severity == .error }
        guard errors.isEmpty else { throw AddonError.invalidManifest(errors.map(\.message)) }
        return manifest
    }

    public func catalog(base: URL, type: String, id: String, extras: [ExtraParam] = []) async throws -> [MetaPreview] {
        let result = try await get(try url(base, .catalog, type, id, extras))
        return try ResponseDecoder.catalog(from: result.data, defaultType: type)
    }

    /// `notFound` when the addon answers without a usable `meta`.
    public func meta(base: URL, type: String, id: String) async throws -> MetaDetail {
        let result = try await get(try url(base, .meta, type, id))
        guard let detail = try ResponseDecoder.meta(from: result.data, defaultType: type) else { throw AddonError.notFound }
        return detail
    }

    public func streams(base: URL, type: String, id: String) async throws -> [AddonStream] {
        let result = try await get(try url(base, .stream, type, id))
        return try ResponseDecoder.streams(from: result.data)
    }

    public func subtitles(base: URL, type: String, id: String, extras: [ExtraParam] = []) async throws -> [SubtitleItem] {
        let result = try await get(try url(base, .subtitles, type, id, extras))
        return try ResponseDecoder.subtitles(from: result.data)
    }

    private func url(_ base: URL, _ resource: ResourceKind, _ type: String, _ id: String, _ extras: [ExtraParam] = []) throws -> URL {
        guard let url = AddonRequestBuilder.url(base: base, resource: resource, type: type, id: id, extras: extras) else { throw AddonError.invalidURL }
        return url
    }
}
