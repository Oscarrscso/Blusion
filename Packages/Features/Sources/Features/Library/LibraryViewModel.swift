import Foundation
import Observation
import PlayerKit
import StremioKit

/// Library: continue watching, saved titles, and what has been watched.
@MainActor
@Observable
public final class LibraryViewModel {
    public private(set) var continueWatching: [WatchProgress] = []
    public private(set) var saved: [LibraryItem] = []
    public private(set) var watched: [WatchProgress] = []
    public private(set) var hasLoaded = false

    private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public var isEmpty: Bool { continueWatching.isEmpty && saved.isEmpty && watched.isEmpty }

    public func load() async {
        let all = await services.progress.all()
        continueWatching = Self.continueWatching(from: all)
        watched = all.filter(\.isWatched)
        saved = await services.library.all()
        hasLoaded = true
    }

    /// In-progress items worth resuming, newest first, one per series (the latest episode).
    public static func continueWatching(from all: [WatchProgress]) -> [WatchProgress] {
        var seenSeries = Set<String>()
        return all.filter { !$0.isWatched && ProgressRecorder.resumePosition(for: $0) > 0 }
            .filter { item in
                guard let series = item.seriesID else { return true }
                return seenSeries.insert(series).inserted
            }
    }

    public func removeFromContinueWatching(_ item: WatchProgress) async {
        await services.progress.remove(item.id)
        await load()
    }

    public func markWatched(_ item: WatchProgress) async {
        var updated = item
        updated.isWatched = true
        updated.updatedAt = Date()
        await services.progress.save(updated)
        await load()
    }

    public func markUnwatched(_ item: WatchProgress) async {
        await services.progress.remove(item.id)
        await load()
    }

    public func removeSaved(_ item: LibraryItem) async {
        await services.library.remove(item.id)
        await load()
    }

    /// What tapping an in-progress item plays; the player resumes from the saved position.
    public static func request(for progress: WatchProgress) -> StreamRequest {
        StreamRequest(type: progress.type, id: progress.contentID, title: progress.title, poster: progress.poster,
                      season: progress.season, episode: progress.episode)
    }
}
