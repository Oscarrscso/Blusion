import Foundation

/// User preferences that affect which stream is picked and how it plays (PLAN M7 surfaces them in Settings).
public struct PlaybackSettings: Sendable, Equatable, Codable {
    /// Preferred vertical resolution (e.g. 1080). nil = best available.
    public var preferredResolution: Int?
    /// Default subtitle language as an ISO 639-2 or 639-1 code (`eng`, `en`). nil = subtitles off by default.
    public var subtitleLanguage: String?
    /// A Stremio-compatible streaming server (ADR-004). A URL can embed credentials, so it is stored as a secret.
    public var streamingServerURL: String?
    /// Lets the user turn the fallback engine off (it is also off when no engine is linked).
    public var fallbackEngineEnabled: Bool

    public init(preferredResolution: Int? = nil, subtitleLanguage: String? = nil, streamingServerURL: String? = nil, fallbackEngineEnabled: Bool = true) {
        self.preferredResolution = preferredResolution
        self.subtitleLanguage = subtitleLanguage
        self.streamingServerURL = streamingServerURL
        self.fallbackEngineEnabled = fallbackEngineEnabled
    }

    public var serverURL: URL? {
        guard let text = streamingServerURL?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return url
    }

    public var rankingPreferences: RankingPreferences { RankingPreferences(preferredResolution: preferredResolution) }

    public func policy(fallbackEngineLinked: Bool) -> PolicyConfiguration {
        PolicyConfiguration(fallbackEngineAvailable: fallbackEngineLinked && fallbackEngineEnabled, streamingServerURL: serverURL)
    }
}

public protocol SettingsStore: Sendable {
    func load() async -> PlaybackSettings
    func save(_ settings: PlaybackSettings) async
}

public actor InMemorySettingsStore: SettingsStore {
    private var settings: PlaybackSettings

    public init(_ settings: PlaybackSettings = PlaybackSettings()) {
        self.settings = settings
    }

    public func load() async -> PlaybackSettings { settings }

    public func save(_ settings: PlaybackSettings) async { self.settings = settings }
}
