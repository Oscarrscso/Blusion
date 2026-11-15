import Foundation
import Observation
import PlayerKit
import StremioKit

extension DetailViewModel {
    private var seriesIMDbID: String? {
        if LetterboxdRatings.isIMDbID(detail.preview.id) { return detail.preview.id }
        return detail.videos.lazy.compactMap { Video.seriesIMDbID(fromVideoID: $0.id) }.first
    }

    /// One TMDb lookup fills the season's remaining gaps after checking IMDb and the addon.
    private func loadEpisodeRatings(season: Int?) async {
        // Called only for an episode the IMDb lookup has no score for, whether or not OMDb is available.
        guard let season, isSeries, !episodeRatingSeasons.contains(season), let seriesID = seriesIMDbID,
              detail.episodes(inSeason: season).contains(where: { $0.rating == nil }) else { return }
        episodeRatingSeasons.insert(season)
        let scores = await services.posterRatings.episodeRatings(seriesIMDbID: seriesID, season: season)
        guard !Task.isCancelled else { episodeRatingSeasons.remove(season); return }
        if scores.isEmpty { episodeRatingSeasons.remove(season) }
        detail.fillEpisodeRatings(season: season, scores: scores, source: .tmdb)
    }

    /// How long `video` runs, in minutes. Nil until TMDb's season data is in, or when TMDb has none.
    func runtimeMinutes(for video: Video) -> Int? {
        episodeRuntimes[video.id]
    }

    /// Minutes as a card writes them: "45m", "1h", "1h 2m".
    nonisolated static func runtimeText(minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// One TMDb lookup gives the runtimes of a season's episodes, shared by the season's cards. Without a TMDb read token nothing is asked.
    private func loadEpisodeRuntimes(season: Int?) async {
        guard let season, isSeries, !runtimeSeasons.contains(season), let seriesID = seriesIMDbID else { return }
        if let pending = runtimeTasks[season] { return await pending.value }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetchEpisodeRuntimes(season: season, seriesID: seriesID)
        }
        runtimeTasks[season] = task
        await task.value
        if runtimeTasks[season] == task { runtimeTasks[season] = nil }
    }

    private func fetchEpisodeRuntimes(season: Int, seriesID: String) async {
        let settings = await services.settings.load()
        guard let token = settings.tmdbReadToken, !token.isEmpty else { return }
        guard let episodes = try? await TMDbRatings(client: services.client, readAccessToken: token)
            .seasonEpisodes(seriesIMDbID: seriesID, season: season) else { return }
        guard !Task.isCancelled else { return }
        runtimeSeasons.insert(season)
        var updatedRuntimes = episodeRuntimes
        for video in detail.episodes(inSeason: season) {
            if let episode = video.episode, let runtime = episodes.runtimes[episode] { updatedRuntimes[video.id] = runtime }
        }
        // One observed assignment per season, rather than one invalidation per episode card.
        if updatedRuntimes != episodeRuntimes { episodeRuntimes = updatedRuntimes }
        // Some addons send no episode synopses at all (Cinemeta for Friends or Seinfeld), so TMDb's fill the gaps.
        var filled = detail
        filled.fillEpisodeOverviews(season: season, overviews: episodes.overviews)
        if filled != detail { detail = filled }
    }

    /// Switches the episode cards between their fixed width and the width of the text above them. The cards change at once; the
    /// choice is then saved, so every title page opens the same way.
    func setMatchesEpisodeWidthToText(_ value: Bool) async {
        matchesEpisodeWidthToText = value
        _ = await services.settings.update { $0.matchesEpisodeWidthToText = value }
    }

    // MARK: episode scores

    /// An episode's score and where it came from: IMDb's local dataset/OMDb first, then the addon or TMDb.
    struct EpisodeScore: Equatable, Sendable {
        let value: Double
        let isIMDb: Bool
        /// A whole number out of 100, never a decimal: the score is out of 10, so "8.9" is 89.
        var text: String { String(Int((value * 10).rounded())) }
    }

    /// Load the displayed season once for the shelf; TMDb fills gaps after IMDb.
    func loadEpisodeSeason(_ season: Int?) async {
        async let runtimes: Void = loadEpisodeRuntimes(season: season)
        await loadEpisodeScores(season: season)
        if !Task.isCancelled, let season,
           detail.episodes(inSeason: season).contains(where: { score(for: $0) == nil }) {
            await loadEpisodeRatings(season: season)
        }
        await runtimes
    }

    /// Cards appearing together share the season lookup. Completed tasks are released so scrolling back can retry after a failure
    /// or cache expiry. Scrolling away does not cancel it: the answer is cached either way.
    func loadEpisodeScores(season: Int?) async {
        guard let season, isSeries, let seriesID = seriesIMDbID else { return }
        let revision = reviewServicesRevision
        if scoresRevision != revision {
            scoresRevision = revision
            scoreTasks.removeAll()
        }
        if let running = scoreTasks[season] {
            await running.value
            return
        }
        let ratings = services.posterRatings
        let expected = Set(detail.episodes(inSeason: season).filter { $0.hasAired() }.compactMap(\.episode))
        let task = Task { [weak self] in
            let scores = await ratings.episodeRatings(for: seriesID, season: season, expectedEpisodes: expected)
            guard let self, scoresRevision == revision else { return }
            if omdbEpisodeScores[season] != scores { omdbEpisodeScores[season] = scores }
        }
        scoreTasks[season] = task
        await task.value
        if scoreTasks[season] == task { scoreTasks[season] = nil }
    }

    /// IMDb's resolved score wins. TMDb can fill a gap once the season's IMDb lookup has finished.
    func score(for video: Video) -> EpisodeScore? {
        if let season = video.season, let episode = video.episode, let value = omdbEpisodeScores[season]?[episode] {
            return EpisodeScore(value: value, isIMDb: true)
        }
        // A TMDb score waits only while OMDb is usable and has not yet answered for this season; once it has, TMDb fills its gaps.
        let omdbAnswered = video.season.map { omdbEpisodeScores[$0] != nil } ?? false
        if video.ratingSource == .tmdb, services.posterRatings.omdbAllowsEpisodeRequests, !omdbAnswered { return nil }
        return video.rating.map { EpisodeScore(value: $0, isIMDb: false) }
    }

    /// The episode's score as its card shows it ("89"), for the stream selector's heading. Nil for a film or an episode without a score.
    func episodeScore(for request: StreamRequest) -> EpisodeScore? {
        guard isSeries, let season = request.season, let episode = request.episode,
              let video = detail.videos.first(where: { $0.season == season && $0.episode == episode }) else { return nil }
        return score(for: video)
    }

    /// The stream picker's episode asks for its season's scores the same way its card would, so its heading gets the score even when
    /// the card never came on screen (Play on a season the list is not showing).
    func prepareEpisodeScore(for request: StreamRequest) async {
        guard isSeries, let season = request.season, let episode = request.episode,
              let video = detail.videos.first(where: { $0.season == season && $0.episode == episode }) else { return }
        await loadEpisodeSeason(video.season)
    }
}
