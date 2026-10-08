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
    /// The Trakt API client ID the user supplies, needed to read Trakt lists. Stored as a secret, never shipped with the app.
    public var traktClientID: String?
    /// Optional TMDb credential (a v4 Read Access Token, or a v3 API key), stored in the Keychain.
    public var tmdbReadToken: String?
    /// Whether streams play in Blusion or are handed to another player app (Infuse).
    public var playerPreference: PlayerPreference
    /// IMDb and Letterboxd ratings on posters.
    public var showsPosterRatings: Bool
    /// Play starts the best stream at once instead of showing the list of streams first.
    public var autoPlayBestStream: Bool

    public init(preferredResolution: Int? = nil, subtitleLanguage: String? = nil, streamingServerURL: String? = nil, fallbackEngineEnabled: Bool = true,
                traktClientID: String? = nil, playerPreference: PlayerPreference = .infuseWhenNeeded, showsPosterRatings: Bool = true,
                autoPlayBestStream: Bool = false, tmdbReadToken: String? = nil) {
        self.preferredResolution = preferredResolution
        self.subtitleLanguage = subtitleLanguage
        self.streamingServerURL = streamingServerURL
        self.fallbackEngineEnabled = fallbackEngineEnabled
        self.traktClientID = traktClientID
        self.playerPreference = playerPreference
        self.showsPosterRatings = showsPosterRatings
        self.autoPlayBestStream = autoPlayBestStream
        self.tmdbReadToken = tmdbReadToken
    }

    public var serverURL: URL? {
        guard let text = streamingServerURL?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return url
    }

    /// Why `streamingServerURL` can't be used, or nil when it is empty or fine. Shown in Settings as the user types.
    public static func validationMessage(forServerURL text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), url.host != nil else {
            return "Enter a full address such as http://192.168.1.10:11470"
        }
        guard scheme == "http" || scheme == "https" else { return "The address must start with http:// or https://" }
        return nil
    }

    public var rankingPreferences: RankingPreferences { RankingPreferences(preferredResolution: preferredResolution) }

    public func policy(fallbackEngineLinked: Bool) -> PolicyConfiguration {
        PolicyConfiguration(fallbackEngineAvailable: fallbackEngineLinked && fallbackEngineEnabled, streamingServerURL: serverURL,
                            playerPreference: playerPreference)
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
