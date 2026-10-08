import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TraktDeviceCode: Sendable, Decodable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURL: URL
    public let expiresIn: Int
    public let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code", userCode = "user_code", verificationURL = "verification_url", expiresIn = "expires_in", interval
    }
}

public enum TraktAuthorizationResult: Sendable, Equatable {
    case pending, slowDown, signedIn
}

public enum TraktAccountError: Error, Sendable, Equatable {
    case needsCredentials, needsSignIn, expiredCode, denied, invalidCode, credentialsChanged, invalidResponse
    case needsRedirectURI, invalidCallback, needsClientSecret
    case network(AddonError)

    public var message: String {
        switch self {
        case .needsCredentials: return "Enter your Trakt API Client ID first."
        case .needsRedirectURI: return "Enter the exact Redirect URI registered for your Trakt API app."
        case .invalidCallback: return "The Trakt sign-in callback did not match this sign-in. Start again."
        case .needsClientSecret: return "Device-code sign-in needs a Client Secret. Use PKCE sign-in instead."
        case .needsSignIn: return "Sign in to Trakt before syncing."
        case .expiredCode: return "The sign-in code expired. Start again for a new code."
        case .denied: return "Trakt sign-in was declined."
        case .invalidCode: return "This sign-in code is no longer valid. Start again."
        case .credentialsChanged: return "Your Trakt API credentials changed. Sign in again."
        case .invalidResponse: return "Trakt returned an unreadable response. Try again."
        case .network(.http(status: 401)): return "Trakt rejected the credentials. Check them and sign in again."
        case .network(.http(status: 420)): return "Your Trakt watchlist is full. Check your account limits on Trakt."
        case .network(.http(status: 429)): return "Trakt is busy. Wait a little before trying again."
        case .network: return "Couldn’t reach Trakt. Check your connection and try again."
        }
    }
}

/// A watched movie or episode. IMDb identities match the addon metadata and local progress stores.
public struct TraktWatchedItem: Sendable, Equatable {
    public let preview: MetaPreview
    public let watchedAt: Date
    public let season: Int?
    public let episode: Int?

    public init(preview: MetaPreview, watchedAt: Date, season: Int? = nil, episode: Int? = nil) {
        self.preview = preview
        self.watchedAt = watchedAt
        self.season = season
        self.episode = episode
    }

    public var contentID: String {
        if let season, let episode { return "\(preview.id):\(season):\(episode)" }
        return preview.id
    }

    public var identity: String { LibraryItem.identity(type: preview.type, contentID: contentID) }
}

/// OAuth credentials live only in the supplied SecretStore. Sync adds items; it never removes items from either account.
public actor TraktAccount {
    public static let defaultClientID = "uWo0Ywaz_S4_-uH6KDVh6G8bahxb2bD_pIUz2DgIDno"

    public enum Keys {
        public static let clientSecret = "trakt.account.clientSecret"
        public static let token = "trakt.account.token"
        public static let redirectURI = "trakt.account.redirectURI"
    }

    private struct Token: Codable, Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let createdAt: Int
        var clientID: String?
        var redirectURI: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in", createdAt = "created_at", clientID, redirectURI
        }

        var expiresAt: Date { Date(timeIntervalSince1970: Double(createdAt) + Double(expiresIn)) }
    }

    private let settings: any SettingsStore
    private let secrets: any SecretStore
    private let transport: any HTTPTransport
    private let baseURL: URL
    private let now: @Sendable () -> Date
    private var credentialsRevision = 0
    private var pendingPKCE: (clientID: String, redirectURI: String, verifier: String, state: String, revision: Int)?

    public init(settings: any SettingsStore, secrets: any SecretStore, transport: (any HTTPTransport)? = nil,
                baseURL: URL = TraktClient.defaultBaseURL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.settings = settings
        self.secrets = secrets
        self.transport = transport ?? URLSessionTransport()
        self.baseURL = baseURL
        self.now = now
    }

    public func clientSecret() async -> String { (try? await secrets.get(Keys.clientSecret)) ?? "" }

    public func redirectURI() async -> String { (try? await secrets.get(Keys.redirectURI)) ?? "" }

    public func saveRedirectURI(_ value: String) async throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != (try await secrets.get(Keys.redirectURI) ?? "") else { return }
        credentialsRevision += 1
        pendingPKCE = nil
        try await secrets.remove(Keys.token)
        if value.isEmpty { try await secrets.remove(Keys.redirectURI) } else { try await secrets.set(value, for: Keys.redirectURI) }
    }

    /// The verifier stays in memory for one browser sign-in; only tokens are saved.
    public func beginPKCESignIn(redirectURI: String, codeVerifier: String, codeChallenge: String) async throws -> URL {
        let (clientID, _) = try await credentials()
        guard let redirect = URL(string: redirectURI), let scheme = redirect.scheme,
              (scheme == "https" && redirect.host != nil) || scheme == "blusion" || redirectURI == "urn:ietf:wg:oauth:2.0:oob",
              redirect.fragment == nil, redirect.query == nil, redirect.user == nil, redirect.password == nil else {
            throw TraktAccountError.needsRedirectURI
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard (43...128).contains(codeVerifier.count), codeVerifier.unicodeScalars.allSatisfy(allowed.contains),
              codeChallenge.count == 43 else { throw TraktAccountError.invalidCode }
        let state = UUID().uuidString
        pendingPKCE = (clientID, redirectURI, codeVerifier, state, credentialsRevision)
        var url = URLComponents(string: "https://auth.trakt.tv/oauth/authorize")!
        url.queryItems = [URLQueryItem(name: "client_id", value: clientID), URLQueryItem(name: "redirect_uri", value: redirectURI),
                         URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "state", value: state),
                         URLQueryItem(name: "code_challenge", value: codeChallenge), URLQueryItem(name: "code_challenge_method", value: "S256")]
        return url.url!
    }

    public func finishPKCESignIn(callbackURL: URL) async throws {
        guard let pending = pendingPKCE, let redirect = URL(string: pending.redirectURI),
              callbackURL.scheme == redirect.scheme, callbackURL.host == redirect.host, callbackURL.port == redirect.port,
              callbackURL.path == redirect.path, callbackURL.fragment == nil,
              let query = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
              query.filter({ $0.name == "state" }).count == 1,
              query.first(where: { $0.name == "state" })?.value == pending.state else { throw TraktAccountError.invalidCallback }
        if query.contains(where: { $0.name == "error" }) { throw TraktAccountError.denied }
        guard query.filter({ $0.name == "code" }).count == 1,
              let code = query.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw TraktAccountError.invalidCode }
        try await exchangePKCECode(code, pending: pending)
    }

    /// For Trakt apps already registered with the legacy out-of-band callback.
    public func finishPKCESignIn(code: String) async throws {
        guard let pending = pendingPKCE, pending.redirectURI == "urn:ietf:wg:oauth:2.0:oob" else { throw TraktAccountError.invalidCallback }
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw TraktAccountError.invalidCode }
        try await exchangePKCECode(code, pending: pending)
    }

    public func cancelPKCESignIn() { pendingPKCE = nil }

    private func exchangePKCECode(_ code: String, pending: (clientID: String, redirectURI: String, verifier: String, state: String, revision: Int)) async throws {
        let currentClientID = await settings.load().traktClientID
        guard pendingPKCE?.state == pending.state, pending.revision == credentialsRevision,
              currentClientID == pending.clientID else { throw TraktAccountError.credentialsChanged }
        let result = try await request(path: "oauth/token", clientID: pending.clientID,
                                      body: ["code": code, "client_id": pending.clientID, "redirect_uri": pending.redirectURI,
                                             "code_verifier": pending.verifier, "grant_type": "authorization_code"])
        try checkStatus(result)
        var token = try token(from: result.data)
        token.clientID = pending.clientID
        token.redirectURI = pending.redirectURI
        try Task.checkCancellation()
        let savedClientID = await settings.load().traktClientID
        guard pendingPKCE?.state == pending.state, pending.revision == credentialsRevision,
              savedClientID == pending.clientID else { throw TraktAccountError.credentialsChanged }
        pendingPKCE = nil
        try await save(token)
    }

    public func saveClientSecret(_ value: String) async throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != (try await secrets.get(Keys.clientSecret) ?? "") else { return }
        credentialsRevision += 1
        try await secrets.remove(Keys.token)
        if value.isEmpty { try await secrets.remove(Keys.clientSecret) } else { try await secrets.set(value, for: Keys.clientSecret) }
    }

    public func isSignedIn() async -> Bool {
        guard let token = try? await loadToken(), let clientID = await settings.load().traktClientID else { return false }
        return token.clientID == clientID
    }

    public func beginSignIn() async throws -> TraktDeviceCode {
        let (clientID, clientSecret) = try await credentials()
        guard !clientSecret.isEmpty else { throw TraktAccountError.needsClientSecret }
        return try await decode(TraktDeviceCode.self, path: "oauth/device/code", body: ["client_id": clientID])
    }

    public func checkAuthorization(_ code: TraktDeviceCode) async throws -> TraktAuthorizationResult {
        let revision = credentialsRevision
        let (clientID, clientSecret) = try await credentials()
        guard !clientSecret.isEmpty else { throw TraktAccountError.needsClientSecret }
        let result = try await request(path: "oauth/device/token", clientID: clientID,
                                       body: ["code": code.deviceCode, "client_id": clientID, "client_secret": clientSecret])
        switch result.response.statusCode {
        case 400: return .pending
        case 429: return .slowDown
        case 404, 409: throw TraktAccountError.invalidCode
        case 410: throw TraktAccountError.expiredCode
        case 418: throw TraktAccountError.denied
        case 200:
            var token = try token(from: result.data)
            token.clientID = clientID
            try Task.checkCancellation()
            guard revision == credentialsRevision else { throw TraktAccountError.credentialsChanged }
            try await save(token)
            return .signedIn
        default: throw TraktAccountError.network(.http(status: result.response.statusCode))
        }
    }

    /// Removes the local token immediately, then best-effort revokes the remote token.
    public func signOut() async {
        let token = try? await loadToken()
        let credentials = try? await credentials()
        credentialsRevision += 1
        pendingPKCE = nil
        try? await secrets.remove(Keys.token)
        if let token, let (clientID, clientSecret) = credentials {
            var body = ["token": token.accessToken, "client_id": clientID]
            if token.redirectURI == nil { body["client_secret"] = clientSecret }
            _ = try? await request(path: "oauth/revoke", clientID: clientID,
                                   body: body)
        }
    }

    public func clearCredentials() async {
        credentialsRevision += 1
        pendingPKCE = nil
        try? await secrets.remove(Keys.token)
        try? await secrets.remove(Keys.clientSecret)
        try? await secrets.remove(Keys.redirectURI)
    }

    public func watchlist() async throws -> [MetaPreview] {
        var items: [MetaPreview] = []
        var page = 1
        while true {
            let result = try await authorizedRequest(path: "sync/watchlist?page=\(page)&limit=100&extended=full")
            let entries = try decodeEntries(result.data)
            items += entries.compactMap(\.watchlistPreview)
            let pageCount = result.response.headers["x-pagination-page-count"].flatMap(Int.init) ?? 1
            guard page < pageCount else { return items }
            page += 1
        }
    }

    /// Collected movies and shows map to saved titles; collection membership does not mark them watched.
    public func collection() async throws -> [MetaPreview] {
        var items: [MetaPreview] = []
        var page = 1
        while true {
            let result = try await authorizedRequest(path: "sync/collection/movies?page=\(page)&limit=100&extended=full")
            items += try decodeEntries(result.data).compactMap(\.watchlistPreview)
            let pageCount = result.response.headers["x-pagination-page-count"].flatMap(Int.init) ?? 1
            guard page < pageCount else { break }
            page += 1
        }
        let shows = try await authorizedRequest(path: "sync/collection/shows?extended=full")
        return items + (try decodeEntries(shows.data).compactMap(\.watchlistPreview))
    }

    public func watched() async throws -> [TraktWatchedItem] {
        let movies = try await authorizedRequest(path: "sync/watched/movies?extended=full")
        let shows = try await authorizedRequest(path: "sync/watched/shows?extended=full")
        return try (decodeEntries(movies.data) + decodeEntries(shows.data)).flatMap(\.watchedItems)
    }

    public func addToWatchlist(_ items: [MetaPreview]) async throws -> Int {
        let payload = Self.watchlistPayload(items)
        guard !payload.isEmpty else { return 0 }
        let result = try await authorizedRequest(path: "sync/watchlist", body: payload)
        return try addedCount(result.data)
    }

    /// Call with records missing on Trakt to avoid sending duplicate watches.
    public func addToHistory(_ items: [TraktWatchedItem]) async throws -> Int {
        let payload = Self.historyPayload(items)
        guard !payload.isEmpty else { return 0 }
        let result = try await authorizedRequest(path: "sync/history", body: payload)
        return try addedCount(result.data)
    }

    private func credentials() async throws -> (String, String) {
        let clientID = (await settings.load().traktClientID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = try await secrets.get(Keys.clientSecret) ?? ""
        guard !clientID.isEmpty else { throw TraktAccountError.needsCredentials }
        return (clientID, clientSecret)
    }

    private func loadToken() async throws -> Token? {
        guard let text = try await secrets.get(Keys.token) else { return nil }
        return try? JSONDecoder().decode(Token.self, from: Data(text.utf8))
    }

    private func save(_ token: Token) async throws {
        let data = try JSONEncoder().encode(token)
        try await secrets.set(String(decoding: data, as: UTF8.self), for: Keys.token)
    }

    private func token(from data: Data) throws -> Token {
        guard let token = try? JSONDecoder().decode(Token.self, from: data), !token.accessToken.isEmpty,
              !token.refreshToken.isEmpty, token.expiresIn > 0 else { throw TraktAccountError.invalidResponse }
        return token
    }

    private func refreshed(_ old: Token, clientID: String, clientSecret: String) async throws -> Token {
        let revision = credentialsRevision
        var body = ["refresh_token": old.refreshToken, "client_id": clientID,
                    "redirect_uri": old.redirectURI ?? "urn:ietf:wg:oauth:2.0:oob", "grant_type": "refresh_token"]
        if old.redirectURI == nil { body["client_secret"] = clientSecret }
        let result = try await request(path: "oauth/token", clientID: clientID, body: body)
        try checkStatus(result)
        var token = try token(from: result.data)
        token.clientID = clientID
        token.redirectURI = old.redirectURI
        try Task.checkCancellation()
        guard revision == credentialsRevision else { throw TraktAccountError.credentialsChanged }
        try await save(token)
        return token
    }

    private func authorizedRequest(path: String, body: [String: Any]? = nil) async throws -> HTTPResult {
        let (clientID, clientSecret) = try await credentials()
        guard var token = try await loadToken() else { throw TraktAccountError.needsSignIn }
        guard token.clientID == clientID else { throw TraktAccountError.credentialsChanged }
        if token.expiresAt <= now().addingTimeInterval(60) {
            token = try await refreshed(token, clientID: clientID, clientSecret: clientSecret)
        }
        var result = try await request(path: path, clientID: clientID, accessToken: token.accessToken, body: body)
        if result.response.statusCode == 401 {
            token = try await refreshed(token, clientID: clientID, clientSecret: clientSecret)
            result = try await request(path: path, clientID: clientID, accessToken: token.accessToken, body: body)
        }
        try checkStatus(result)
        return result
    }

    private func decode<T: Decodable>(_ type: T.Type, path: String, body: [String: Any]) async throws -> T {
        let result = try await request(path: path, body: body)
        try checkStatus(result)
        guard let value = try? JSONDecoder().decode(type, from: result.data) else { throw TraktAccountError.invalidResponse }
        return value
    }

    private func request(path: String, clientID: String? = nil, accessToken: String? = nil, body: [String: Any]? = nil) async throws -> HTTPResult {
        guard let url = URL(string: path, relativeTo: baseURL.appendingPathComponent("/"))?.absoluteURL,
              url.scheme == "https" || url.scheme == "http" else { throw TraktAccountError.network(.invalidURL) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Blusion/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        if let clientID { request.setValue(clientID, forHTTPHeaderField: "trakt-api-key") }
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        do {
            return try await withDeadline(seconds: 20) { [request, transport] in
                try await transport.send(request, limits: FetchLimits(maxRedirects: 0))
            }
        } catch {
            throw TraktAccountError.network(AddonError.from(error))
        }
    }

    private func checkStatus(_ result: HTTPResult) throws {
        guard (200...299).contains(result.response.statusCode) else {
            throw TraktAccountError.network(.http(status: result.response.statusCode))
        }
    }

    private func decodeEntries(_ data: Data) throws -> [TraktSyncEntry] {
        guard let entries = try? JSONDecoder().decode([TraktSyncEntry].self, from: data) else { throw TraktAccountError.invalidResponse }
        return entries
    }

    private func addedCount(_ data: Data) throws -> Int {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let added = body["added"] as? [String: Int] else {
            throw TraktAccountError.invalidResponse
        }
        return added.values.reduce(0, +)
    }

    private static func watchlistPayload(_ items: [MetaPreview]) -> [String: Any] {
        let movies = items.filter { $0.type == "movie" && isIMDb($0.id) }.map { ["ids": ["imdb": $0.id]] }
        let shows = items.filter { $0.type == "series" && isIMDb($0.id) }.map { ["ids": ["imdb": $0.id]] }
        var payload: [String: Any] = [:]
        if !movies.isEmpty { payload["movies"] = movies }
        if !shows.isEmpty { payload["shows"] = shows }
        return payload
    }

    private static func historyPayload(_ items: [TraktWatchedItem]) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        let movies: [[String: Any]] = items.filter { $0.preview.type == "movie" && isIMDb($0.preview.id) }.map {
            ["ids": ["imdb": $0.preview.id], "watched_at": formatter.string(from: $0.watchedAt)]
        }
        let episodes = items.filter { $0.preview.type == "series" && isIMDb($0.preview.id) && $0.season != nil && $0.episode != nil }
        let shows: [[String: Any]] = Dictionary(grouping: episodes, by: { $0.preview.id }).sorted { $0.key < $1.key }.map { id, records in
            let seasons: [[String: Any]] = Dictionary(grouping: records, by: { $0.season ?? 0 }).sorted { $0.key < $1.key }.map { season, records in
                let episodes: [[String: Any]] = records.map { ["number": $0.episode ?? 0, "watched_at": formatter.string(from: $0.watchedAt)] }
                return ["number": season, "episodes": episodes]
            }
            return ["ids": ["imdb": id], "seasons": seasons]
        }
        var payload: [String: Any] = [:]
        if !movies.isEmpty { payload["movies"] = movies }
        if !shows.isEmpty { payload["shows"] = shows }
        return payload
    }

    public static func isIMDb(_ id: String) -> Bool {
        id.hasPrefix("tt") && id.count > 2 && id.dropFirst(2).allSatisfy(\.isNumber)
    }
}

private struct TraktSyncEntry: Decodable {
    struct Media: Decodable {
        struct IDs: Decodable { let imdb: String? }
        let title: String?
        let year: Int?
        let ids: IDs?

        func preview(type: String) -> MetaPreview? {
            guard let id = ids?.imdb, TraktAccount.isIMDb(id) else { return nil }
            return MetaPreview(id: id, type: type, name: title, poster: MetahubArtwork.poster(imdbID: id),
                               releaseInfo: year.map(String.init))
        }
    }

    struct Season: Decodable {
        struct Episode: Decodable {
            let number: Int
            let lastWatchedAt: String?
            enum CodingKeys: String, CodingKey { case number, lastWatchedAt = "last_watched_at" }
        }
        let number: Int
        let episodes: [Episode]
    }

    let movie: Media?
    let show: Media?
    let lastWatchedAt: String?
    let seasons: [Season]?
    enum CodingKeys: String, CodingKey { case movie, show, seasons, lastWatchedAt = "last_watched_at" }

    var watchlistPreview: MetaPreview? { movie?.preview(type: "movie") ?? show?.preview(type: "series") }

    var watchedItems: [TraktWatchedItem] {
        if let preview = movie?.preview(type: "movie"), let date = Self.date(lastWatchedAt) {
            return [TraktWatchedItem(preview: preview, watchedAt: date)]
        }
        guard let preview = show?.preview(type: "series") else { return [] }
        return (seasons ?? []).flatMap { season in
            season.episodes.compactMap { episode in
                guard let date = Self.date(episode.lastWatchedAt) else { return nil }
                return TraktWatchedItem(preview: preview, watchedAt: date, season: season.number, episode: episode.number)
            }
        }
    }

    private static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
