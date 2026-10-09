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
    /// Choosing a season fills in its episode ratings from TMDb, when the addon sent none (see `loadEpisodeRatings`).
    public var selectedSeason: Int? {
        didSet { if selectedSeason != oldValue { Task { await loadEpisodeRatings() } } }
    }
    public private(set) var isInLibrary = false
    /// Seasons whose TMDb episode scores are already in `detail`, or on their way.
    private var episodeRatingSeasons: Set<Int> = []
    /// Identities (`type/id`) of watched movies and episodes shown on this screen.
    public private(set) var watchedIdentities: Set<String> = []
    /// Share of the runtime saved for the movie and episodes shown here, by identity (0...1). Only progress that playback can
    /// resume from is listed, so a bar or a "Resume" label always means the player starts at the saved position.
    public private(set) var progressFractions: [String: Double] = [:]
    /// Saved records for the movie and episodes shown here, by identity. `nextUp` reads their update times.
    private var savedProgress: [String: WatchProgress] = [:]

    private let services: AppServices
    public private(set) var tmdbArtwork: TMDbArtwork?

    public init(preview: MetaPreview, services: AppServices) {
        self.preview = preview
        self.detail = .fallback(from: preview)
        self.services = services
    }

    public func load() async {
        isLoading = true
        episodeRatingSeasons.removeAll()
        async let artwork: Void = loadArtwork()
        let result = await services.browse.detail(for: preview)
        detail = result.detail
        isFallback = result.isFallback
        isLoading = false
        await refreshUserState()
        // A series opens on the season of its next episode, so the list starts where the viewer left off.
        if selectedSeason == nil { selectedSeason = nextUp?.season ?? detail.seasons.first }
        await loadEpisodeRatings()
        await artwork
    }

    public func refresh() async {
        await services.posterRatings.refresh()
        await load()
    }

    private func loadArtwork() async {
        let settings = await services.settings.load()
        guard let token = settings.tmdbReadToken, !token.isEmpty else { return }
        let artwork = try? await TMDbRatings(client: services.client, readAccessToken: token).artwork(imdbID: preview.id, type: preview.type)
        guard !Task.isCancelled else { return }
        tmdbArtwork = artwork
    }

    private var seriesIMDbID: String? {
        if LetterboxdRatings.isIMDbID(detail.preview.id) { return detail.preview.id }
        return detail.videos.lazy.compactMap { Video.seriesIMDbID(fromVideoID: $0.id) }.first
    }

    private func loadEpisodeRatings() async {
        guard isSeries, let season = selectedSeason, !episodeRatingSeasons.contains(season),
              detail.episodes(inSeason: season).contains(where: { $0.rating == nil }), let seriesID = seriesIMDbID else { return }
        episodeRatingSeasons.insert(season)
        let scores = await services.posterRatings.episodeRatings(seriesIMDbID: seriesID, season: season)
        guard !Task.isCancelled else { return }
        if scores.isEmpty { episodeRatingSeasons.remove(season) }
        detail.fillEpisodeRatings(season: season, scores: scores, source: .tmdb)
    }

    /// Library membership, watched marks and saved progress, from the local stores.
    public func refreshUserState() async {
        isInLibrary = await services.library.contains(libraryIdentity)
        var watched = Set<String>()
        var saved: [String: WatchProgress] = [:]
        var fractions: [String: Double] = [:]
        for identity in [movieIdentity] + detail.videos.map({ episodeIdentity($0) }) {
            guard let record = await services.progress.progress(for: identity) else { continue }
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

    public func isWatched(_ video: Video) -> Bool { watchedIdentities.contains(episodeIdentity(video)) }

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

    // MARK: watched marks for a whole show

    /// Marks every aired episode of the show, specials aside, watched, or clears every one of those marks. Specials keep their own
    /// marks (the season menu and an episode's menu reach them): a show counts as watched without them.
    public func setSeriesWatched(_ watched: Bool) async {
        await setWatched(watched, episodes: detail.episodesCountingAsWatched())
    }

    /// The same for one season, specials included when that season is the specials.
    public func setSeasonWatched(_ watched: Bool, season: Int) async {
        await setWatched(watched, episodes: markableEpisodes(in: [season]))
    }

    /// True when the show has aired episodes and every one of them is marked. Specials do not count.
    public var isSeriesWatched: Bool {
        let episodes = detail.episodesCountingAsWatched()
        return !episodes.isEmpty && episodes.allSatisfy { watchedIdentities.contains(episodeIdentity($0)) }
    }

    /// True when the season has aired episodes and every one of them is marked.
    public func isSeasonWatched(_ season: Int) -> Bool {
        let episodes = markableEpisodes(in: [season])
        return !episodes.isEmpty && episodes.allSatisfy { watchedIdentities.contains(episodeIdentity($0)) }
    }

    private func markableEpisodes(in seasons: [Int], now: Date = Date()) -> [Video] {
        seasons.flatMap { detail.episodes(inSeason: $0) }.filter { $0.hasAired(by: now) }
    }

    private func setWatched(_ watched: Bool, episodes: [Video]) async {
        for video in episodes {
            let request = request(for: video)
            if watched {
                await services.progress.save(WatchProgress(id: request.identity, type: request.type, contentID: request.id, title: request.title,
                                                           poster: request.poster, position: 0, duration: 0, isWatched: true, updatedAt: Date(),
                                                           season: request.season, episode: request.episode))
            } else {
                await services.progress.remove(request.identity)
            }
        }
        await refreshUserState()
    }

    // MARK: episode scores

    /// An episode's score and where it came from: OMDb's IMDb score when there is one, else whatever the addon sent.
    public struct EpisodeScore: Equatable, Sendable {
        public let value: Double
        public let isIMDb: Bool
        public var text: String { value.formatted(.number.precision(.fractionLength(1))) }
    }

    /// OMDb's scores by season, then episode number. A season is here once it has been asked for, even when OMDb had none.
    public private(set) var omdbEpisodeScores: [Int: [Int: Double]] = [:]

    /// Changes when review credentials do, so the screen asks again for the season on show.
    public var reviewServicesRevision: Int { services.posterRatings.reviewServicesRevision }

    /// Asks OMDb for the season's episode scores. Nothing without an OMDb key; the screen calls it as seasons are picked.
    public func loadEpisodeScores(season: Int?) async {
        guard let season, isSeries, LetterboxdRatings.isIMDbID(detail.id) else { return }
        let scores = await services.posterRatings.episodeRatings(for: detail.id, season: season)
        guard !Task.isCancelled else { return }
        omdbEpisodeScores[season] = scores
    }

    public func score(for video: Video) -> EpisodeScore? {
        if let season = video.season, let episode = video.episode, let value = omdbEpisodeScores[season]?[episode] {
            return EpisodeScore(value: value, isIMDb: true)
        }
        return video.rating.map { EpisodeScore(value: $0, isIMDb: false) }
    }

    public var isSeries: Bool { detail.type == "series" || !detail.videos.isEmpty }
    public var seasons: [Int] { detail.seasons }
    public var episodes: [Video] { selectedSeason.map { detail.episodes(inSeason: $0) } ?? [] }

    /// What "Play" asks addons for: the movie itself.
    public var movieRequest: StreamRequest { StreamRequest(movie: detail.preview.type.isEmpty ? preview : detail.preview) }

    public func request(for video: Video) -> StreamRequest { StreamRequest(episode: video, of: detail) }

    /// Series: the episode to play next. The most recently updated unfinished episode, else the first unwatched one in watching
    /// order, else the first episode. Nil for movies and for series without episodes.
    public var nextUp: Video? {
        guard isSeries else { return nil }
        let ordered = watchingOrder
        let unfinished = ordered.filter { isUnfinished(episodeIdentity($0)) }
        if let latest = unfinished.max(by: { lastUpdate($0) < lastUpdate($1) }) { return latest }
        return ordered.first(where: { !watchedIdentities.contains(episodeIdentity($0)) }) ?? ordered.first
    }

    /// "Play", "Resume", "Play S1 · E1", "Resume S2 · E5". "Resume" only when playback starts from saved progress.
    public var primaryActionTitle: String {
        guard isSeries else { return progressFractions[movieIdentity] == nil ? "Play" : "Resume" }
        guard let next = nextUp else { return "Play" }
        let verb = progressFractions[episodeIdentity(next)] == nil ? "Play" : "Resume"
        guard let season = next.season, let episode = next.episode else { return verb }
        return "\(verb) S\(season) · E\(episode)"
    }

    /// Share of the movie that is saved and resumable (0...1). Nil when it has not started, is watched or cannot be resumed.
    public func progressFraction(for request: StreamRequest) -> Double? { progressFractions[request.identity] }

    /// The same for an episode of this series.
    public func progressFraction(for video: Video) -> Double? { progressFractions[episodeIdentity(video)] }

    /// Background artwork for the header, falling back to the poster.
    public var backdropURL: URL? { tmdbArtwork?.backdrop ?? detail.preview.background ?? detail.preview.poster }
    public var portraitArtworkURL: URL? { tmdbArtwork?.portrait ?? detail.preview.poster ?? detail.preview.background }

    /// The title's logo (a transparent image), when the addon or the catalog has one.
    public var logoURL: URL? { tmdbArtwork?.logo ?? detail.preview.logo }

    /// Year and runtime for a `MetaLine`: "2008", "152 min". Parts the addon left out are skipped. The rating is not here: the page
    /// shows it as a button under the title.
    public var metaParts: [String] {
        let meta = detail.preview
        var parts: [String] = []
        if let year = Self.nonEmpty(meta.releaseInfo) { parts.append(year) }
        if let runtime = Self.nonEmpty(meta.runtime) { parts.append(runtime) }
        return parts
    }

    /// The first trailer with a well-formed YouTube id, as a watch page.
    public var trailerURL: URL? {
        guard let id = detail.trailers.first(where: Self.isYouTubeID) else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")
    }

    public var subtitle: String {
        [detail.preview.releaseInfo, detail.preview.runtime, detail.preview.imdbRating.map { String(format: "★ %.1f", $0) }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// Episodes in watching order: regular seasons, then specials, then any episode the addon gave no season.
    private var watchingOrder: [Video] {
        detail.seasons.flatMap { detail.episodes(inSeason: $0) } + detail.videos.filter { $0.season == nil }
    }

    private var movieIdentity: String { movieRequest.identity }

    /// The identity `request(for:)` gives an episode. Built here so a loop over every episode does not look up each next episode.
    private func episodeIdentity(_ video: Video) -> String {
        "\(detail.type.isEmpty ? "series" : detail.type)/\(video.id)"
    }

    /// Started but not watched.
    private func isUnfinished(_ identity: String) -> Bool {
        guard let record = savedProgress[identity] else { return false }
        return !record.isWatched && record.position > 0
    }

    private func lastUpdate(_ video: Video) -> Date {
        savedProgress[episodeIdentity(video)]?.updatedAt ?? .distantPast
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// YouTube ids are short runs of letters, digits, `-` and `_`. Anything else an addon sends is never put into a URL.
    private static func isYouTubeID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}
