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
    public let makeEngine: EngineFactory
    /// True once a fallback engine (M6) is linked into the app.
    public let fallbackEngineLinked: Bool

    public init(registry: AddonRegistry, client: AddonClient, browse: BrowseService? = nil, streams: StreamService? = nil,
                subtitles: SubtitleService? = nil, settings: (any SettingsStore)? = nil, progress: (any ProgressStore)? = nil,
                library: (any LibraryStore)? = nil, makeEngine: EngineFactory? = nil, fallbackEngineLinked: Bool = false) {
        self.registry = registry
        self.client = client
        self.browse = browse ?? BrowseService(registry: registry, client: client)
        self.streams = streams ?? StreamService(registry: registry, client: client)
        self.subtitles = subtitles ?? SubtitleService(registry: registry, client: client)
        self.settings = settings ?? InMemorySettingsStore()
        self.progress = progress ?? InMemoryProgressStore()
        self.library = library ?? InMemoryLibraryStore()
        self.makeEngine = makeEngine ?? { _ in nil }
        self.fallbackEngineLinked = fallbackEngineLinked
    }
}
