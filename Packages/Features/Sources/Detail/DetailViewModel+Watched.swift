import Foundation
import Observation
import PlayerKit
import StremioKit

extension DetailViewModel {
    /// Library membership, watched marks and saved progress, from the local stores. `afterUserChange` is for a change the user just made
    /// on this page, which the Save and Watched buttons tick for; any other read moves `loadRevision` along with the state, so they stay silent.
    func refreshUserState(afterUserChange: Bool = false) async {
        userStateGeneration += 1
        let generation = userStateGeneration
        let identities = [movieIdentity] + detail.videos.map { episodeIdentity($0) }
        async let membership = services.library.contains(libraryIdentity)
        async let progress = services.progress.progress(for: identities)
        let records = await progress
        let isSaved = await membership
        guard !Task.isCancelled, generation == userStateGeneration else { return }
        // A quiet revision must precede state changes, so loading watched/save state cannot tick a button.
        if !afterUserChange { loadRevision += 1 }
        isInLibrary = isSaved
        var watched = Set<String>()
        var saved: [String: WatchProgress] = [:]
        var fractions: [String: Double] = [:]
        for record in records {
            let identity = record.id
            saved[identity] = record
            if record.isWatched {
                watched.insert(identity)
            } else if ProgressRecorder.resumePosition(for: record) > 0 {
                fractions[identity] = record.fraction
            }
        }
        watchedIdentities = watched
        savedProgress = saved
        progressFractions = fractions
        nextUp = findNextUp()
        if let nextUp {
            continuesSeries = watchingOrder.prefix(while: { $0.id != nextUp.id })
                .contains { watched.contains(episodeIdentity($0)) }
        } else {
            continuesSeries = false
        }
        let airedEpisodes = detail.episodesCountingAsWatched()
        isSeriesWatched = !airedEpisodes.isEmpty && airedEpisodes.allSatisfy { watched.contains(episodeIdentity($0)) }
    }

    private var libraryIdentity: String {
        LibraryItem.identity(type: detail.type.isEmpty ? (preview.type.isEmpty ? "movie" : preview.type) : detail.type, contentID: detail.id)
    }

    func toggleLibrary() async {
        if isInLibrary {
            await services.library.remove(libraryIdentity)
        } else {
            await services.library.add(LibraryItem(preview: detail.preview, addedAt: Date()))
        }
        isInLibrary = await services.library.contains(libraryIdentity)
    }

    func isWatched(_ request: StreamRequest) -> Bool { watchedIdentities.contains(request.identity) }

    func isWatched(_ video: Video) -> Bool { watchedIdentities.contains(episodeIdentity(video)) }

    /// Marks a movie or episode watched, or clears the mark (and any saved position).
    func setWatched(_ watched: Bool, for request: StreamRequest) async {
        if watched {
            await services.progress.save(WatchProgress(id: request.identity, type: request.type, contentID: request.id, title: request.title,
                                                       poster: request.poster, position: 0, duration: 0, isWatched: true, updatedAt: Date(),
                                                       season: request.season, episode: request.episode))
            await services.queueNextContinueEpisode(after: request)
        } else {
            await services.progress.remove(request.identity)
        }
        await refreshUserState(afterUserChange: true)
    }

    // MARK: watched marks for a whole show

    /// Marks every aired episode of the show, specials aside, watched, or clears every one of those marks. Specials keep their own
    /// marks (the season menu and an episode's menu reach them): a show counts as watched without them.
    func setSeriesWatched(_ watched: Bool) async {
        await setWatched(watched, episodes: detail.episodesCountingAsWatched())
    }

    /// The same for one season, specials included when that season is the specials.
    func setSeasonWatched(_ watched: Bool, season: Int) async {
        await setWatched(watched, episodes: markableEpisodes(in: [season]))
    }

    /// Mark every aired episode through the selected one, inclusive, in season/episode order.
    /// Specials have their own order and never mark the regular seasons (or vice versa).
    func markEpisodesWatched(through selected: Video) async {
        let remaining = episodesThrough(selected).filter { $0.hasAired() && !isWatched($0) }
        guard !remaining.isEmpty else { return }
        await setWatched(true, episodes: remaining)
    }

    /// True when the aired episodes through the selected one, inclusive, are all marked. The episode's menu fills its mark-through action then.
    func isWatchedThrough(_ selected: Video) -> Bool {
        let aired = episodesThrough(selected).filter { $0.hasAired() }
        return !aired.isEmpty && aired.allSatisfy { isWatched($0) }
    }

    /// The episodes through the selected one, inclusive, in season/episode order: none when the selected episode is not listed.
    private func episodesThrough(_ selected: Video) -> [Video] {
        guard let season = selected.season else { return [] }
        let seasons = season == 0 ? [0] : detail.seasons.filter { $0 > 0 && $0 <= season }
        let ordered = seasons.flatMap { detail.episodes(inSeason: $0) }
        guard let index = ordered.firstIndex(where: { $0.id == selected.id }) else { return [] }
        return Array(ordered.prefix(through: index))
    }

    /// True when the season has aired episodes and every one of them is marked.
    func isSeasonWatched(_ season: Int) -> Bool {
        let episodes = markableEpisodes(in: [season])
        return !episodes.isEmpty && episodes.allSatisfy { watchedIdentities.contains(episodeIdentity($0)) }
    }

    private func markableEpisodes(in seasons: [Int], now: Date = Date()) -> [Video] {
        seasons.flatMap { detail.episodes(inSeason: $0) }.filter { $0.hasAired(by: now) }
    }

    private func setWatched(_ watched: Bool, episodes: [Video]) async {
        if watched {
            let type = detail.type.isEmpty ? "series" : detail.type
            let records = episodes.map { video in
                WatchProgress(id: episodeIdentity(video), type: type, contentID: video.id, title: "\(detail.name) · \(video.title)",
                              poster: detail.preview.poster, position: 0, duration: 0, isWatched: true, updatedAt: Date(),
                              season: video.season, episode: video.episode)
            }
            await services.progress.save(records)
            if let last = episodes.last {
                await services.queueNextContinueEpisode(after: request(for: last))
            }
        } else {
            await services.progress.remove(episodes.map { episodeIdentity($0) })
        }
        await refreshUserState(afterUserChange: true)
    }
}
