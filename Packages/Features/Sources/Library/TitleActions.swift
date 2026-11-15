import Foundation
import Observation
import PlayerKit
import StremioKit

/// Library membership and watched marks for any title, kept current so menus and badges can read them without waiting.
@MainActor
@Observable
final class TitleActions {
    /// `type/id` of every saved title.
    private(set) var savedIdentities: Set<String> = []
    /// `type/id` of every watched movie. A series is not in here: it is watched by its episodes (`seriesWithWatchedEpisodes`).
    private(set) var watchedIdentities: Set<String> = []
    /// `type/id` of every series with at least one episode marked watched.
    private(set) var seriesWithWatchedEpisodes: Set<String> = []
    /// `type/id` of every series in progress, with what Play resumes there: "S2E4 | 23m left", or the episode alone before it is started.
    private(set) var resumeLines: [String: String] = [:]

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    /// Reads the library and the watch history again. Call when a screen appears, since other screens change them too.
    func refresh(progress: [WatchProgress]? = nil) async {
        savedIdentities = Set(await services.library.all().map(\.id))
        let records: [WatchProgress]
        if let progress { records = progress } else { records = await services.progress.all() }
        let watched = records.filter(\.isWatched)
        watchedIdentities = Set(watched.filter { $0.type == "movie" }.map(\.id))
        seriesWithWatchedEpisodes = Set(watched.compactMap(Self.showID(of:)).map { LibraryItem.identity(type: "series", contentID: $0) })
        resumeLines = Self.resumeLines(from: records)
    }

    /// The episode a series resumes at and the time left on it, as Play's second line gives them on the title's page.
    func resumeLine(for item: MetaPreview) -> String? {
        resumeLines[Self.identity(of: item)]
    }

    /// Each series' most recent unfinished episode: one partly played, or the next one queued after a completion.
    static func resumeLines(from records: [WatchProgress]) -> [String: String] {
        var latest: [String: WatchProgress] = [:]
        for record in records where !record.isWatched {
            let isStarted = record.duration > 0 && record.position > 0
            guard isStarted || record.isQueuedForContinue, record.season != nil, record.episode != nil,
                  let show = showID(of: record) else { continue }
            let key = LibraryItem.identity(type: "series", contentID: show)
            if let current = latest[key], current.updatedAt >= record.updatedAt { continue }
            latest[key] = record
        }
        return latest.compactMapValues { record in
            guard let season = record.season, let episode = record.episode else { return nil }
            let code = "S\(season)E\(episode)"
            guard record.duration > 0, record.position > 0, record.position.isFinite, record.duration.isFinite else { return code }
            let minutes = max(1, ((record.duration - record.position) / 60).rounded(.up))
            return "\(code) | \(minutes.formatted(.number.precision(.fractionLength(0))))m left"
        }
    }

    /// The show an episode record belongs to. An episode's id is its show's id plus `:season:episode`, whatever the addon's id scheme
    /// (`ContentID` only understands IMDb ones), so the suffix comes off by what the record says it is.
    private static func showID(of record: WatchProgress) -> String? {
        guard record.type == "series" else { return nil }
        if let season = record.season, let episode = record.episode {
            let suffix = ":\(season):\(episode)"
            if record.contentID.hasSuffix(suffix), record.contentID.count > suffix.count { return String(record.contentID.dropLast(suffix.count)) }
        }
        return record.seriesID
    }

    /// True when some episode of the series is marked watched, which is when "mark as unwatched" has something to clear.
    func hasWatchedEpisodes(_ item: MetaPreview) -> Bool {
        seriesWithWatchedEpisodes.contains(Self.identity(of: item))
    }

    /// Series: marks every aired episode watched, or clears the mark from every episode. The episode list comes from the addons, so
    /// this waits for them; a show they cannot describe is left alone.
    func setSeriesWatched(_ watched: Bool, for item: MetaPreview) async {
        guard Self.itemType(of: item) == "series" else { return }
        let detail = await services.browse.detail(for: item).detail
        // The same episodes both ways, as the title page marks them: specials keep their own marks.
        let videos = detail.episodesCountingAsWatched()
        let type = detail.type.isEmpty ? "series" : detail.type
        if watched {
            await services.progress.save(videos.map { video in
                WatchProgress(id: "\(type)/\(video.id)", type: type, contentID: video.id, title: "\(detail.name) · \(video.title)",
                              poster: detail.preview.poster, position: 0, duration: 0, isWatched: true, updatedAt: Date(),
                              season: video.season, episode: video.episode)
            })
        } else {
            await services.progress.remove(videos.map { "\(type)/\($0.id)" })
        }
        await refresh()
    }

    func isSaved(_ item: MetaPreview) -> Bool {
        savedIdentities.contains(Self.identity(of: item))
    }

    func isWatched(_ item: MetaPreview) -> Bool {
        watchedIdentities.contains(Self.identity(of: item))
    }

    /// Saves the title, or removes it. Decides from the store rather than the cached set, so a stale menu cannot save twice.
    func toggleSaved(_ item: MetaPreview) async {
        let identity = Self.identity(of: item)
        if await services.library.contains(identity) {
            await services.library.remove(identity)
        } else {
            await services.library.add(LibraryItem(preview: item, addedAt: Date()))
        }
        await refresh()
    }

    /// Movies only: marks watched or removes the mark, as Detail does. Does nothing for other types.
    func setWatched(_ watched: Bool, for item: MetaPreview) async {
        guard Self.itemType(of: item) == "movie" else { return }
        let identity = Self.identity(of: item)
        if watched {
            await services.progress.save(WatchProgress(id: identity, type: "movie", contentID: item.id, title: item.name, poster: item.poster,
                                                       position: 0, duration: 0, isWatched: true, updatedAt: Date()))
        } else {
            await services.progress.remove(identity)
        }
        await refresh()
    }

    /// A title with no type is a movie, as in `LibraryItem` and `StreamRequest`, so it is keyed the same way everywhere.
    private static func itemType(of item: MetaPreview) -> String {
        item.type.isEmpty ? "movie" : item.type
    }

    private static func identity(of item: MetaPreview) -> String {
        LibraryItem.identity(type: itemType(of: item), contentID: item.id)
    }
}
