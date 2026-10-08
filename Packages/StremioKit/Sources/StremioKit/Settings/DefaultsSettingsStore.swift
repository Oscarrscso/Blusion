import Foundation

/// Persists `PlaybackSettings`: plain preferences in `UserDefaults`; the streaming server URL (it may embed credentials) and the
/// Trakt client ID live in a `SecretStore`.
public final class DefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    public enum Keys {
        public static let preferredResolution = "settings.preferredResolution"
        public static let subtitleLanguage = "settings.subtitleLanguage"
        public static let fallbackEngineEnabled = "settings.fallbackEngineEnabled"
        public static let playerPreference = "settings.playerPreference"
        public static let showsPosterRatings = "settings.showsPosterRatings"
        public static let autoPlayBestStream = "settings.autoPlayBestStream"
        public static let serverSecret = "settings.streamingServerURL"
        public static let traktClientSecret = "settings.traktClientID"
    }

    private let defaults: UserDefaults
    private let secrets: any SecretStore

    public init(defaults: UserDefaults = .standard, secrets: any SecretStore) {
        self.defaults = defaults
        self.secrets = secrets
    }

    public func load() async -> PlaybackSettings {
        let resolution = defaults.integer(forKey: Keys.preferredResolution)
        let language = defaults.string(forKey: Keys.subtitleLanguage)
        let fallback = defaults.object(forKey: Keys.fallbackEngineEnabled) as? Bool ?? true
        let server = try? await secrets.get(Keys.serverSecret)
        let traktClientID = try? await secrets.get(Keys.traktClientSecret)
        let player = defaults.string(forKey: Keys.playerPreference).flatMap(PlayerPreference.init(rawValue:)) ?? PlaybackSettings().playerPreference
        let posterRatings = defaults.object(forKey: Keys.showsPosterRatings) as? Bool ?? true
        return PlaybackSettings(preferredResolution: resolution > 0 ? resolution : nil, subtitleLanguage: language?.isEmpty == false ? language : nil,
                                streamingServerURL: server, fallbackEngineEnabled: fallback, traktClientID: traktClientID, playerPreference: player,
                                showsPosterRatings: posterRatings, autoPlayBestStream: defaults.bool(forKey: Keys.autoPlayBestStream))
    }

    public func save(_ settings: PlaybackSettings) async {
        if let resolution = settings.preferredResolution, resolution > 0 {
            defaults.set(resolution, forKey: Keys.preferredResolution)
        } else {
            defaults.removeObject(forKey: Keys.preferredResolution)
        }
        if let language = settings.subtitleLanguage, !language.isEmpty {
            defaults.set(language, forKey: Keys.subtitleLanguage)
        } else {
            defaults.removeObject(forKey: Keys.subtitleLanguage)
        }
        defaults.set(settings.fallbackEngineEnabled, forKey: Keys.fallbackEngineEnabled)
        defaults.set(settings.playerPreference.rawValue, forKey: Keys.playerPreference)
        defaults.set(settings.showsPosterRatings, forKey: Keys.showsPosterRatings)
        defaults.set(settings.autoPlayBestStream, forKey: Keys.autoPlayBestStream)
        if let server = settings.streamingServerURL?.trimmingCharacters(in: .whitespacesAndNewlines), !server.isEmpty {
            try? await secrets.set(server, for: Keys.serverSecret)
        } else {
            try? await secrets.remove(Keys.serverSecret)
        }
        if let traktClientID = settings.traktClientID?.trimmingCharacters(in: .whitespacesAndNewlines), !traktClientID.isEmpty {
            try? await secrets.set(traktClientID, for: Keys.traktClientSecret)
        } else {
            try? await secrets.remove(Keys.traktClientSecret)
        }
    }
}
