import Foundation

/// Asks YouTube, before a player is made, whether a video may be played in an embedded player. It reads YouTube's public oEmbed answer for
/// the video, which needs no key.
public struct YouTubeEmbedCheck: Sendable {
    let client: AddonClient

    public init(client: AddonClient) { self.client = client }

    /// False only when YouTube says the video cannot be embedded or is not there: 400, 401, 403 or 404. True when it can be embedded,
    /// and also when no answer could be had (offline, a timeout, any other failure), so the player itself decides.
    public func allowsEmbedding(videoID: String) async -> Bool {
        guard let url = Self.url(videoID: videoID) else { return false }
        do {
            _ = try await client.get(url, headers: [:], limits: FetchLimits(maxBytes: 64 * 1024, maxRedirects: 2), timeout: 5)
            return true
        } catch {
            guard let addonError = error as? AddonError else { return true }
            switch addonError {
            case .notFound: return false
            case .http(let status): return ![400, 401, 403, 404].contains(status)
            default: return true
            }
        }
    }

    /// The oEmbed address for a video, or nil unless `videoID` is a well-formed YouTube id (`Trailer.isYouTubeID`):
    /// `https://www.youtube.com/oembed?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3D<id>&format=json`.
    static func url(videoID: String) -> URL? {
        guard Trailer.isYouTubeID(videoID) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/oembed"
        // The watch address goes in as one percent-encoded value. The id is already known to hold only plain characters.
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "url", value: "https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3D\(videoID)"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url
    }
}
