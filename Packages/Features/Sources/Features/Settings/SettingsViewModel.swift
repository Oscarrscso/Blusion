import Foundation
import Observation
import PlayerKit
import StremioKit

/// Settings: default subtitle language, preferred quality, streaming server, clear data.
@MainActor
@Observable
public final class SettingsViewModel {
    public struct Option<Value: Hashable>: Hashable, Identifiable {
        public let label: String
        public let value: Value
        public var id: String { label }
    }

    public static let resolutionOptions: [Option<Int?>] = [
        .init(label: "Best available", value: nil), .init(label: "4K (2160p)", value: 2160), .init(label: "1080p", value: 1080),
        .init(label: "720p", value: 720), .init(label: "480p", value: 480),
    ]

    public static var languageOptions: [Option<String?>] {
        [.init(label: "Off", value: nil)] + LanguageCodes.all.map { .init(label: $0.name, value: $0.code) }
    }

    public private(set) var settings = PlaybackSettings()
    public var serverURLText = ""
    /// The Trakt client ID as typed. `commitTraktClientID()` saves it.
    public var traktClientIDText = ""
    public var omdbAPIKeyText = ""
    public var tmdbReadTokenText = ""
    /// Every installed addon, disabled ones included.
    public private(set) var installedAddonCount = 0
    public private(set) var lastMessage: String?

    private let services: AppServices
    private let reset: DataResetService

    public init(services: AppServices) {
        self.services = services
        self.reset = DataResetService(services: services)
    }

    public var fallbackEngineLinked: Bool { services.fallbackEngineLinked }
    public var serverURLMessage: String? { PlaybackSettings.validationMessage(forServerURL: serverURLText) }

    public func load() async {
        settings = await services.settings.load()
        serverURLText = settings.streamingServerURL ?? ""
        traktClientIDText = settings.traktClientID ?? ""
        omdbAPIKeyText = settings.omdbAPIKey ?? ""
        tmdbReadTokenText = settings.tmdbReadToken ?? ""
        services.posterRatings.isEnabled = settings.showsPosterRatings
        installedAddonCount = await services.registry.addons.count
    }

    public func setPreferredResolution(_ value: Int?) async {
        settings = await services.settings.load()
        settings.preferredResolution = value
        await services.settings.save(settings)
    }

    public func setSubtitleLanguage(_ code: String?) async {
        settings = await services.settings.load()
        settings.subtitleLanguage = code
        await services.settings.save(settings)
    }

    public func setFallbackEngineEnabled(_ enabled: Bool) async {
        settings = await services.settings.load()
        settings.fallbackEngineEnabled = enabled
        await services.settings.save(settings)
    }

    public func setPlayerPreference(_ value: PlayerPreference) async {
        settings = await services.settings.load()
        settings.playerPreference = value
        await services.settings.save(settings)
    }

    public func setAutoPlayBestStream(_ value: Bool) async {
        settings = await services.settings.load()
        settings.autoPlayBestStream = value
        await services.settings.save(settings)
    }

    /// Also switches the poster ratings in the store the posters read.
    public func setShowsPosterRatings(_ value: Bool) async {
        settings = await services.settings.load()
        settings.showsPosterRatings = value
        services.posterRatings.isEnabled = value
        await services.settings.save(settings)
    }

    /// Saves the Trakt client ID as typed, without surrounding spaces. A blank field removes it.
    public func commitTraktClientID() async {
        settings = await services.settings.load()
        let trimmed = traktClientIDText.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.traktClientID = trimmed.isEmpty ? nil : trimmed
        await services.settings.save(settings)
    }

    public func commitReviewCredentials() async {
        settings = await services.settings.load()
        let omdb = omdbAPIKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tmdb = tmdbReadTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.omdbAPIKey = omdb.isEmpty ? nil : omdb
        settings.tmdbReadToken = tmdb.isEmpty ? nil : tmdb
        await services.settings.save(settings)
        await services.posterRatings.setReviewServices(
            omdb: settings.omdbAPIKey.map { OMDbRatings(client: services.client, apiKey: $0) },
            tmdb: settings.tmdbReadToken.map { TMDbRatings(client: services.client, readAccessToken: $0) })
        lastMessage = "Review services saved."
    }

    /// Saves the streaming server field if it is empty or valid; otherwise leaves the stored value alone.
    public func commitServerURL() async {
        guard serverURLMessage == nil else { return }
        settings = await services.settings.load()
        let trimmed = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.streamingServerURL = trimmed.isEmpty ? nil : trimmed
        await services.settings.save(settings)
    }

    public func clear(_ scope: DataResetService.Scope) async {
        lastMessage = await reset.clear(scope)
        if scope == .settings || scope == .everything { await load() }
    }

    public static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
