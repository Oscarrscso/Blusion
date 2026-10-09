import Foundation
import PlayerKit
import StremioKit

/// Creates the engine for a candidate: AVPlayer for `.native`, the fallback engine for `.fallback` (when linked), nil when none fits.
public typealias EngineFactory = @MainActor @Sendable (PlaybackCandidate) -> (any PlaybackEngine)?

/// The app's long-lived services, handed to view models. Built once at launch (App/) and in tests (with stubs or the mock).
public struct AppServices: Sendable {
    public let registry: AddonRegistry
    public let client: AddonClient
    public let browse: BrowseService
    public let streams: StreamService
    public let subtitles: SubtitleService
    public let settings: any SettingsStore
    public let progress: any ProgressStore
    public let library: any LibraryStore
    /// The user's Home layout (nil inside means "automatic").
    public let widgets: any WidgetStore
    /// Loads the items of Home widgets, with an in-memory cache.
    public let widgetContent: WidgetContentService
    /// IMDb and Letterboxd ratings for poster badges.
    public let posterRatings: PosterRatingsStore
    /// Finds a film's best Blu-ray edition on bestblurays.com while its streams are loading.
    public let bestBlurays: BestBluraysClient
    public let makeEngine: EngineFactory
    /// True once a fallback engine (M6) is linked into the app.
    public let fallbackEngineLinked: Bool
    /// Streams handed to another player app, waiting for its callback to record where the viewer stopped.
    public let handoffs: any HandoffStore
    public let searchHistory: any SearchHistoryStore
    public let traktAccount: TraktAccount
    /// The one Trakt client: public reads with the client ID, signed-in reads through `traktAccount`, browse pages cached.
    public let trakt: TraktClient
    /// False in a Mac build that the system keeps away from the Keychain: addon links and credentials are then in a private file.
    public let secretsInKeychain: Bool

    public init(registry: AddonRegistry, client: AddonClient, browse: BrowseService? = nil, streams: StreamService? = nil,
                subtitles: SubtitleService? = nil, settings: (any SettingsStore)? = nil, progress: (any ProgressStore)? = nil,
                library: (any LibraryStore)? = nil, makeEngine: EngineFactory? = nil, fallbackEngineLinked: Bool = false,
                widgets: (any WidgetStore)? = nil, widgetContent: WidgetContentService? = nil, posterRatings: PosterRatingsStore? = nil,
                handoffs: (any HandoffStore)? = nil, searchHistory: (any SearchHistoryStore)? = nil, traktAccount: TraktAccount? = nil,
                trakt: TraktClient? = nil, secretsInKeychain: Bool = true, bestBlurays: BestBluraysClient? = nil) {
        self.registry = registry
        self.client = client
        self.browse = browse ?? BrowseService(registry: registry, client: client)
        self.streams = streams ?? StreamService(registry: registry, client: client)
        self.subtitles = subtitles ?? SubtitleService(registry: registry, client: client)
        let settings = settings ?? InMemorySettingsStore()
        self.settings = settings
        self.progress = progress ?? InMemoryProgressStore()
        self.library = library ?? InMemoryLibraryStore()
        self.widgets = widgets ?? InMemoryWidgetStore()
        let traktAccount = traktAccount ?? TraktAccount(settings: settings, secrets: InMemorySecretStore())
        let trakt = trakt ?? TraktClient(client: client, account: traktAccount, cache: TraktBrowseCache())
        self.widgetContent = widgetContent ?? WidgetContentService(registry: registry, client: client, settings: settings, trakt: trakt,
                                                                   account: traktAccount)
        self.posterRatings = posterRatings ?? PosterRatingsStore()
        self.bestBlurays = bestBlurays ?? BestBluraysClient(client: client)
        self.handoffs = handoffs ?? InMemoryHandoffStore()
        self.searchHistory = searchHistory ?? InMemorySearchHistoryStore()
        self.traktAccount = traktAccount
        self.trakt = trakt
        self.makeEngine = makeEngine ?? { _ in nil }
        self.fallbackEngineLinked = fallbackEngineLinked
        self.secretsInKeychain = secretsInKeychain
    }
}
