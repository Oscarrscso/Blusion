import Foundation
import Observation
import PlayerKit
import StremioKit

/// Detail: starts from the catalog preview, upgrades to the addon's full `meta` when it arrives.
@MainActor
@Observable
public final class DetailViewModel {
    public let preview: MetaPreview
    public private(set) var detail: MetaDetail
    public private(set) var isLoading = true
    /// True when no addon returned `meta` and Detail is built from the catalog preview alone.
    public private(set) var isFallback = false
    public var selectedSeason: Int?
    public private(set) var isInLibrary = false
    /// Identities (`type/id`) of watched movies and episodes shown on this screen.
    public private(set) var watchedIdentities: Set<String> = []

    private let services: AppServices

    public init(preview: MetaPreview, services: AppServices) {
        self.preview = preview
        self.detail = .fallback(from: preview)
        self.services = services
    }

    public func load() async {
        isLoading = true
        let result = await services.browse.detail(for: preview)
        detail = result.detail
        isFallback = result.isFallback
        if selectedSeason == nil { selectedSeason = detail.seasons.first }
        isLoading = false
        await refreshUserState()
    }

    /// Library membership and watched marks, from the local stores.
    public func refreshUserState() async {
        isInLibrary = await services.library.contains(libraryIdentity)
        var identities = Set<String>()
        for request in [movieRequest] + detail.videos.map({ request(for: $0) }) {
            if await services.progress.progress(for: request.identity)?.isWatched == true { identities.insert(request.identity) }
        }
        watchedIdentities = identities
    }

    private var libraryIdentity: String {
        LibraryItem.identity(type: detail.type.isEmpty ? (preview.type.isEmpty ? "movie" : preview.type) : detail.type, contentID: detail.id)
    }

    public func toggleLibrary() async {
        if isInLibrary {
            await services.library.remove(libraryIdentity)
        } else {
            await services.library.add(LibraryItem(preview: detail.preview, addedAt: Date()))
        }
        isInLibrary = await services.library.contains(libraryIdentity)
    }

    public func isWatched(_ request: StreamRequest) -> Bool { watchedIdentities.contains(request.identity) }

    /// Marks a movie or episode watched, or clears the mark (and any saved position).
    public func setWatched(_ watched: Bool, for request: StreamRequest) async {
        if watched {
            await services.progress.save(WatchProgress(id: request.identity, type: request.type, contentID: request.id, title: request.title,
                                                       poster: request.poster, position: 0, duration: 0, isWatched: true, updatedAt: Date(),
                                                       season: request.season, episode: request.episode))
        } else {
            await services.progress.remove(request.identity)
        }
        await refreshUserState()
    }

    public var isSeries: Bool { detail.type == "series" || !detail.videos.isEmpty }
    public var seasons: [Int] { detail.seasons }
    public var episodes: [Video] { selectedSeason.map { detail.episodes(inSeason: $0) } ?? [] }

    /// What "Play" asks addons for: the movie itself.
    public var movieRequest: StreamRequest { StreamRequest(movie: detail.preview.type.isEmpty ? preview : detail.preview) }

    public func request(for video: Video) -> StreamRequest { StreamRequest(episode: video, of: detail) }

    public var subtitle: String {
        [detail.preview.releaseInfo, detail.preview.runtime, detail.preview.imdbRating.map { String(format: "★ %.1f", $0) }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
