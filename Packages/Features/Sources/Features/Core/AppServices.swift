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
    public let makeEngine: EngineFactory
    /// True once a fallback engine (M6) is linked into the app.
    public let fallbackEngineLinked: Bool
    /// Streams handed to another player app, waiting for its callback to record where the viewer stopped.
    public let handoffs: any HandoffStore

    public init(registry: AddonRegistry, client: AddonClient, browse: BrowseService? = nil, streams: StreamService? = nil,
                subtitles: SubtitleService? = nil, settings: (any SettingsStore)? = nil, progress: (any ProgressStore)? = nil,
                library: (any LibraryStore)? = nil, makeEngine: EngineFactory? = nil, fallbackEngineLinked: Bool = false,
                widgets: (any WidgetStore)? = nil, widgetContent: WidgetContentService? = nil, posterRatings: PosterRatingsStore? = nil,
                handoffs: (any HandoffStore)? = nil) {
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
        self.widgetContent = widgetContent ?? WidgetContentService(registry: registry, client: client, settings: settings)
        self.posterRatings = posterRatings ?? PosterRatingsStore()
        self.handoffs = handoffs ?? InMemoryHandoffStore()
        self.makeEngine = makeEngine ?? { _ in nil }
        self.fallbackEngineLinked = fallbackEngineLinked
    }
}
