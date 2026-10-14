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
    /// Episode cards are as wide as the text above them, as chosen with the toggle beside the season name. The choice is saved, and read
    /// again when the details load.
    public private(set) var matchesEpisodeWidthToText = false
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
    /// The Play request whose stream lookup was started from this page.
    private var prefetchedStreamRequest: StreamRequest?
    public private(set) var tmdbArtwork: TMDbArtwork?
    public private(set) var isLoadingArtwork = true
    public private(set) var reviews: [TMDbReview] = []
    /// The YouTube trailers and teasers TMDb lists for the title. Empty until TMDb answers, or when no read token is saved.
    public private(set) var tmdbVideos: [TMDbVideo] = []
    /// The title's preview from Apple's iTunes store: a direct file the app plays. Nil until the search answers, or when the store has none.
    public private(set) var itunesTrailer: Trailer?
    /// The cast and crew with TMDb ids and photos. Nil until TMDb answers, or when no read token is saved.
    public private(set) var titleCredits: TMDbTitleCredits?
    /// Titles TMDb recommends for this one, for the shelf at the bottom of the page. Empty until TMDb answers.
    public private(set) var relatedTitles: [TMDbRelatedTitle] = []
    /// The US age rating ("R", "TV-MA") for the meta line. Nil until TMDb answers, or when it has none.
    public private(set) var certification: String?
    /// Set once the hero picture and logo have loaded (or five seconds have passed), so the page's other requests may start.
    public private(set) var hasSettledHero = false
    /// The title's trailer: its loading, the player in the page's panel, and a failure. The trailer button and the panel share it.
    public let trailer: TrailerLoader

    public init(preview: MetaPreview, services: AppServices, artwork: TMDbArtwork? = nil, artworkChecked: Bool = false,
                trailerPreparer: (any TrailerPreparing)? = nil) {
        self.preview = preview
        self.detail = .fallback(from: preview)
        self.services = services
        self.trailer = TrailerLoader(preparer: trailerPreparer ?? UnavailableTrailerPreparer())
        // An artwork handed over by Home, or one looked up earlier this session, is used at once: the page then has nothing to wait for.
        let known = artwork ?? services.posterRatings.cachedHeroArtwork(for: preview)
        self.tmdbArtwork = known
        self.isLoadingArtwork = known == nil && !artworkChecked
        // The age rating the spotlight already showed for this title is there from the first frame, so the line does not change on opening.
        self.certification = services.posterRatings.cachedCertification(for: preview)
    }

    /// Runs the hero's load, and gives up after five seconds, so a slow picture never holds the page.
    private func loadHero(_ hero: @escaping @MainActor @Sendable () async -> Void) async {
        let heroTask = Task { @MainActor in await hero() }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await heroTask.value }
            group.addTask { try? await Task.sleep(for: .seconds(5)) }
            await group.next()
            group.cancelAll()
        }
    }

    public func load(afterHero hero: (@MainActor @Sendable () async -> Void)? = nil) async {
        isLoading = true
        episodeRatingSeasons.removeAll()
        // The artwork lookup and then the hero picture and logo come first and alone: nothing else starts until they are loaded
        // (or five seconds have passed), so no other request can delay them.
        await loadArtwork()
        // A movie's picture comes first and alone. A show's episodes come first: its picture follows them, below, so the list is not held
        // up by the picture.
        if !isSeries, let hero, !hasSettledHero { await loadHero(hero) }
        guard !Task.isCancelled else { return }
        if !isSeries { hasSettledHero = true }
        async let playbackSettings = services.settings.load()
        let result = await services.browse.detail(for: preview)
        // A load that was cancelled must not overwrite what the newer load shows.
        guard !Task.isCancelled else { return }
        let settings = await playbackSettings
        matchesEpisodeWidthToText = settings.matchesEpisodeWidthToText
        detail = result.detail
        isFallback = result.isFallback
        if !result.isFallback { services.heroMeta.record(detail.preview, for: preview) }
        isLoading = false
        // A show's picture loads once its episodes are on the page; the rating row waits for it.
        if isSeries {
            if let hero, !hasSettledHero { await loadHero(hero) }
            hasSettledHero = true
        }
        await refreshUserState()
        // A series opens on the season of its next episode, so the list starts where the viewer left off.
        if selectedSeason == nil { selectedSeason = nextUp?.season ?? detail.seasons.first }
        // Reviews and cast photos are secondary: they start after the hero and the page above, and never hold up the page above.
        async let reviews: Void = loadReviews()
        async let credits: Void = loadTitleCredits()
        async let related: Void = loadRelatedTitles()
        async let rating: Void = loadCertification()
        async let videos: Void = loadVideos()
        async let previews: Void = loadPreview()
        await reviews
        await credits
        await related
        await rating
        await videos
        await previews
    }

    public func refresh() async {
        await services.posterRatings.refresh()
        await load()
    }

    private func loadArtwork() async {
        // An artwork handed over by Home, or a lookup that has answered, is never fetched again.
        guard tmdbArtwork == nil, isLoadingArtwork else { return }
        defer { isLoadingArtwork = false }
        // The store holds the TMDb client and keeps each answer for the session, so a title opened again asks TMDb nothing.
        let artwork = await services.posterRatings.heroArtwork(for: preview)
        guard !Task.isCancelled else { return }
        tmdbArtwork = artwork
    }

    private func loadTitleCredits() async {
        let settings = await services.settings.load()
        guard let token = settings.tmdbReadToken, !token.isEmpty else { titleCredits = nil; return }
        let loaded = try? await TMDbRatings(client: services.client, readAccessToken: token).titleCredits(imdbID: preview.id, type: preview.type)
        guard !Task.isCancelled else { return }
        titleCredits = loaded
    }

    /// The age rating comes from the same session cache the spotlight reads, so a title shown on Home is not asked for again. Without
    /// a saved TMDb read token none is asked for, as before.
    private func loadCertification() async {
        let settings = await services.settings.load()
        guard let token = settings.tmdbReadToken, !token.isEmpty else { certification = nil; return }
        let loaded = await services.posterRatings.certification(for: preview)
        guard !Task.isCancelled else { return }
        certification = loaded
    }

    private func loadRelatedTitles() async {
        let settings = await services.settings.load()
        guard let token = settings.tmdbReadToken, !token.isEmpty else { relatedTitles = []; return }
        let loaded = try? await TMDbRatings(client: services.client, readAccessToken: token).relatedTitles(imdbID: preview.id, type: preview.type)
        guard !Task.isCancelled else { return }
        relatedTitles = loaded ?? []
    }

    /// The first twenty cast members, then the key crew who are not already in that cast. Nil while TMDb's credits are unknown; empty
    /// when TMDb has none, so the screen falls back to the addon's plain names.
    public var castAndCrew: [TMDbTitlePerson]? {
        guard let titleCredits else { return nil }
        let cast = Array(titleCredits.cast.prefix(20))
        let castIDs = Set(cast.map(\.id))
        return cast + titleCredits.keyCrew.filter { !castIDs.contains($0.id) }
    }

    private func loadReviews() async {
        let settings = await services.settings.load()
        guard let token = settings.tmdbReadToken, !token.isEmpty else { reviews = []; return }
        let loaded = try? await TMDbRatings(client: services.client, readAccessToken: token).reviews(imdbID: preview.id, type: preview.type)
        guard !Task.isCancelled else { return }
        reviews = loaded ?? []
    }

    private func loadVideos() async {
        let settings = await services.settings.load()
        guard let token = settings.tmdbReadToken, !token.isEmpty else { tmdbVideos = []; return }
        let loaded = try? await TMDbRatings(client: services.client, readAccessToken: token).videos(imdbID: preview.id, type: preview.type)
        guard !Task.isCancelled else { return }
        tmdbVideos = loaded ?? []
    }

    /// The iTunes preview for the title, looked up by its name and release year. Needs no TMDb token.
    private func loadPreview() async {
        let loaded = try? await ITunesTrailers(client: services.client).preview(title: detail.preview.name,
                                                                                year: Self.releaseYear(detail.preview.releaseInfo),
                                                                                type: preview.type)
        guard !Task.isCancelled else { return }
        itunesTrailer = loaded
    }

    /// The first four-digit run in a release text such as "2010" or "2008-2013", as a year.
    private static func releaseYear(_ text: String?) -> Int? {
        guard let text, let run = text.range(of: #"\d{4}"#, options: .regularExpression) else { return nil }
        return Int(text[run])
    }

    private var seriesIMDbID: String? {
        if LetterboxdRatings.isIMDbID(detail.preview.id) { return detail.preview.id }
        return detail.videos.lazy.compactMap { Video.seriesIMDbID(fromVideoID: $0.id) }.first
    }

    /// TMDb scores for a season, for the episodes the addon sent none for. One request fills the season; it is made when the first
    /// card of the season comes on screen, and only when OMDb cannot give episode scores (no key, paused, or the day's allowance spent).
    private func loadEpisodeRatings(season: Int?) async {
        guard !services.posterRatings.omdbAllowsEpisodeRequests else { return }
        guard let season, isSeries, !episodeRatingSeasons.contains(season), let seriesID = seriesIMDbID,
              detail.episodes(inSeason: season).contains(where: { $0.rating == nil }) else { return }
        episodeRatingSeasons.insert(season)
        let scores = await services.posterRatings.episodeRatings(seriesIMDbID: seriesID, season: season)
        guard !Task.isCancelled else { episodeRatingSeasons.remove(season); return }
        if scores.isEmpty { episodeRatingSeasons.remove(season) }
        detail.fillEpisodeRatings(season: season, scores: scores, source: .tmdb)
    }

    /// Switches the episode cards between their fixed width and the width of the text above them. The cards change at once; the
    /// choice is then saved, so every title page opens the same way.
    public func setMatchesEpisodeWidthToText(_ value: Bool) async {
        matchesEpisodeWidthToText = value
        var settings = await services.settings.load()
        settings.matchesEpisodeWidthToText = value
        await services.settings.save(settings)
    }

    /// Library membership, watched marks and saved progress, from the local stores.
    public func refreshUserState() async {
        isInLibrary = await services.library.contains(libraryIdentity)
        var watched = Set<String>()
        var saved: [String: WatchProgress] = [:]
        var fractions: [String: Double] = [:]
        let identities = [movieIdentity] + detail.videos.map { episodeIdentity($0) }
        for record in await services.progress.progress(for: identities) {
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
        if watched {
            let type = detail.type.isEmpty ? "series" : detail.type
            let records = episodes.map { video in
                WatchProgress(id: episodeIdentity(video), type: type, contentID: video.id, title: "\(detail.name) · \(video.title)",
                              poster: detail.preview.poster, position: 0, duration: 0, isWatched: true, updatedAt: Date(),
                              season: video.season, episode: video.episode)
            }
            await services.progress.save(records)
        } else {
            await services.progress.remove(episodes.map { episodeIdentity($0) })
        }
        await refreshUserState()
    }

    // MARK: episode scores

    /// An episode's score and where it came from: OMDb's IMDb score when there is one, else whatever the addon sent.
    public struct EpisodeScore: Equatable, Sendable {
        public let value: Double
        public let isIMDb: Bool
        /// A whole number out of 100, never a decimal: the score is out of 10, so "8.9" is 89.
        public var text: String { String(Int((value * 10).rounded())) }
    }

    /// OMDb's scores by season, then episode number. A season is here once it has been asked for, even when OMDb had none.
    public private(set) var omdbEpisodeScores: [Int: [Int: Double]] = [:]
    @ObservationIgnored private var scoreTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var scoresRevision = 0

    /// Changes when review credentials do, so the cards ask again.
    public var reviewServicesRevision: Int { services.posterRatings.reviewServicesRevision }

    /// An episode card came on screen: ask OMDb for its season's scores (one request, once per season). Only when OMDb is unavailable
    /// (no key, paused after a 401 or 429, or today's limit reached) and the addon has no score for the episode is the season's TMDb
    /// score asked for. An empty OMDb answer does not bring TMDb in while OMDb is available. Seasons whose cards are never scrolled to
    /// are never asked for.
    public func episodeAppeared(_ video: Video) async {
        await loadEpisodeScores(season: video.season)
        guard !Task.isCancelled, score(for: video) == nil else { return }
        await loadEpisodeRatings(season: video.season)
    }

    /// Asks OMDb for a season's episode scores, once. Cards that appear while the request is running wait for it, so none of them acts
    /// on a score that has not arrived yet. Scrolling away does not cancel it: the answer is cached either way.
    public func loadEpisodeScores(season: Int?) async {
        guard let season, isSeries, let seriesID = seriesIMDbID else { return }
        let revision = reviewServicesRevision
        if scoresRevision != revision {
            scoresRevision = revision
            scoreTasks.removeAll()
            omdbEpisodeScores.removeAll()
        }
        if let running = scoreTasks[season] {
            await running.value
            return
        }
        let ratings = services.posterRatings
        let task = Task { [weak self] in
            let scores = await ratings.episodeRatings(for: seriesID, season: season)
            guard let self, scoresRevision == revision else { return }
            omdbEpisodeScores[season] = scores
        }
        scoreTasks[season] = task
        await task.value
    }

    /// OMDb's IMDb score, else the addon's own. A TMDb score (filled in earlier) is shown only while OMDb is unavailable, so it is hidden
    /// again once OMDb can answer.
    public func score(for video: Video) -> EpisodeScore? {
        if let season = video.season, let episode = video.episode, let value = omdbEpisodeScores[season]?[episode] {
            return EpisodeScore(value: value, isIMDb: true)
        }
        if video.ratingSource == .tmdb, services.posterRatings.omdbAllowsEpisodeRequests { return nil }
        return video.rating.map { EpisodeScore(value: $0, isIMDb: false) }
    }

    public var isSeries: Bool { detail.type == "series" || !detail.videos.isEmpty }
    public var seasons: [Int] { detail.seasons }
    public var episodes: [Video] { selectedSeason.map { detail.episodes(inSeason: $0) } ?? [] }

    /// What "Play" asks addons for: the movie itself.
    public var movieRequest: StreamRequest { StreamRequest(movie: detail.preview.type.isEmpty ? preview : detail.preview) }

    public func request(for video: Video) -> StreamRequest { StreamRequest(episode: video, of: detail) }

    /// Starts the stream lookup for the Play button's request, once per title. A new request (a series moving to its next episode) lets the previous lookup go.
    public func prefetchStreams(for request: StreamRequest?) {
        guard let request else { return }
        if let previous = prefetchedStreamRequest, previous.id == request.id, previous.type == request.type { return }
        if let previous = prefetchedStreamRequest { services.streams.releasePrefetch(previous) }
        prefetchedStreamRequest = request
        Task { await services.streams.prefetch(request) }
    }

    /// Leaving the page lets an unclaimed lookup go (after a short grace).
    public func releaseStreamPrefetch() {
        guard let request = prefetchedStreamRequest else { return }
        services.streams.releasePrefetch(request)
        prefetchedStreamRequest = nil
    }

    /// Series: the episode to play next. The most recently updated unfinished episode, else the first unwatched one in watching
    /// order, else the first episode. Nil for movies and for series without episodes.
    public var nextUp: Video? {
        guard isSeries else { return nil }
        let ordered = watchingOrder
        let unfinished = ordered.filter { isUnfinished(episodeIdentity($0)) }
        if let latest = unfinished.max(by: { lastUpdate($0) < lastUpdate($1) }) { return latest }
        return ordered.first(where: { !watchedIdentities.contains(episodeIdentity($0)) }) ?? ordered.first
    }

    /// "Play", "Resume", "Play S1 · E1", "Resume S2 · E5". "Resume" only when playback starts from saved progress. A next episode that has
    /// not aired yet gives its air date instead (see `unairedAirLabel`).
    public var primaryActionTitle: String {
        guard isSeries else { return progressFractions[movieIdentity] == nil ? "Play" : "Resume" }
        guard let next = nextUp else { return "Play" }
        if let airs = unairedAirLabel { return airs }
        let verb = progressFractions[episodeIdentity(next)] == nil ? "Play" : "Resume"
        guard let season = next.season, let episode = next.episode else { return verb }
        return "\(verb) S\(season) · E\(episode)"
    }

    /// What the main action plays: a movie itself, or a series' next episode once it has aired. Nil while a series' episodes are still
    /// arriving, and while the next episode has not aired: nothing is played then, and the button shows `unairedAirLabel` instead.
    public var primaryRequest: StreamRequest? {
        guard isSeries else { return movieRequest }
        guard let next = nextUp, next.hasAired() else { return nil }
        return request(for: next)
    }

    /// The main action's label while a series' next episode has not aired yet: its air date, e.g. "Airs Oct 20, 2026". Nil otherwise.
    public var unairedAirLabel: String? {
        guard let next = nextUp, !next.hasAired(), let airDate = next.airDate else { return nil }
        return "Airs \(airDate.formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: shuffle

    /// Whether Shuffle has an episode to pick: a series whose episodes have arrived, with at least one aired.
    public var canShuffle: Bool { isSeries && !detail.episodesCountingAsWatched().isEmpty }

    /// Shuffle's pick: a random episode that has aired, from the episodes "watched" covers, so specials stay out. An episode that has not
    /// aired is never picked, as it is never the next one. Nil for a movie and when `canShuffle` is false.
    public func shuffledRequest(now: Date = Date()) -> StreamRequest? {
        guard isSeries else { return nil }
        return detail.episodesCountingAsWatched(by: now).randomElement().map { request(for: $0) }
    }

    /// The episode's score as its card shows it ("89"), for the stream selector's heading. Nil for a film or an episode without a score.
    public func episodeScoreText(for request: StreamRequest) -> String? {
        guard isSeries, let season = request.season, let episode = request.episode,
              let video = detail.videos.first(where: { $0.season == season && $0.episode == episode }) else { return nil }
        return score(for: video)?.text
    }

    /// The episode Shuffle has picked, highlighted in the episode list. It is shown, not played: Play still starts a stream.
    public private(set) var highlightedEpisodeID: String?

    /// Shuffle: picks a random episode that has aired, opens its season and highlights its card. Nothing starts playing.
    public func shuffleEpisode(now: Date = Date()) {
        guard isSeries, let video = detail.episodesCountingAsWatched(by: now).randomElement() else { return }
        if let season = video.season { selectedSeason = season }
        highlightedEpisodeID = video.id
    }

    /// Share of the movie that is saved and resumable (0...1). Nil when it has not started, is watched or cannot be resumed.
    public func progressFraction(for request: StreamRequest) -> Double? { progressFractions[request.identity] }

    /// The same for an episode of this series.
    public func progressFraction(for video: Video) -> Double? { progressFractions[episodeIdentity(video)] }

    /// Separate landscape and portrait heroes. Keep the transition's poster until the artwork lookup finishes. Falls back to the
    /// preview this page was opened from, so Home and the title page use the same URL.
    public var backdropURL: URL? {
        tmdbArtwork?.backdrop ?? (isLoadingArtwork ? nil : preview.background ?? MetahubArtwork.background(imdbID: preview.id))
    }
    public var portraitArtworkURL: URL? {
        tmdbArtwork?.portrait ?? (isLoadingArtwork ? nil : preview.background ?? MetahubArtwork.background(imdbID: preview.id))
    }

    /// The title's logo (a transparent image), when the preview or the TMDb lookup has one.
    public var logoURL: URL? { preview.logo ?? tmdbArtwork?.logo }

    /// Whether the portrait picture already carries the title, so the separate logo is not shown in portrait.
    public var portraitHidesLogo: Bool { tmdbArtwork?.portraitHidesLogo ?? false }

    /// The metadata line both heroes show, for `MetaLine`: year, the first two genres, certification, runtime and the IMDb rating, in that
    /// order ("2008", "Drama", "Crime", "PG-13", "152 min", "★ 9.0"). Missing parts
    /// stay nil and `MetaLine` leaves them out. The score is IMDb's own when the caller has it (`imdbRating`), else the catalog's.
    nonisolated public static func heroMetaParts(for preview: MetaPreview, certification: String?, imdbRating: Double? = nil) -> [String?] {
        let rating = (imdbRating ?? preview.imdbRating).map { "★ \($0.formatted(.number.precision(.fractionLength(1))))" }
        let genres = DetailViewModel.heroMetaGenres(for: preview).map { Optional($0) }
        return [preview.releaseInfo] + genres + [certification, preview.runtime, rating]
    }

    /// The genres the metadata line shows: the first two. `MetaLine` drops these first when the line is too long for one line.
    nonisolated public static func heroMetaGenres(for preview: MetaPreview) -> [String] {
        Array(preview.genres.prefix(2))
    }

    /// The metadata line under the hero, built by the shared store exactly as Home's spotlight builds it (see `HeroMetaStore.parts`).
    public var heroMetaLine: [String?] {
        services.heroMeta.parts(for: preview, certification: certification, ratings: services.posterRatings)
    }

    /// The genres in the metadata line, the same ones `heroMetaLine` shows, for `MetaLine` to drop first when the line is too long.
    public var heroMetaGenres: [String] {
        services.heroMeta.genres(for: preview)
    }

    /// The title's trailers known without a tap, merged and ordered (see `TrailerCatalog`): the iTunes preview first when there is one,
    /// then the addon's direct links; YouTube trailers only when there is no direct file at all.
    public var trailers: [Trailer] {
        TrailerCatalog.merge(previews: itunesTrailer.map { [$0] } ?? [], addonYouTubeIDs: detail.trailers, addonURLs: detail.trailerURLs,
                             tmdb: tmdbVideos)
    }

    /// Whether the trailer button can do anything: a trailer is known.
    public var canPlayTrailer: Bool { !trailers.isEmpty }

    /// A rating's site, shown on the page under the ratings: its reviews for this title, or a search when the site has no page for it.
    public struct OpenedReviews: Equatable, Sendable {
        public let site: ReviewSite
        public let url: URL
        public let isSearch: Bool
    }

    /// The reviews opened from a rating, under the ratings. Nil when none are open.
    public private(set) var openedReviews: OpenedReviews?

    /// A rating's tap: shows its site's reviews under the ratings, or closes them when that site's are already open. Another site's reviews
    /// replace the ones open. The inline trailer stops when reviews open, since one player or page is shown on the page at a time.
    public func toggleReviews(_ site: ReviewSite, url: URL, isSearch: Bool) {
        if openedReviews?.site == site {
            closeReviews()
            return
        }
        trailer.cancel()
        openedReviews = OpenedReviews(site: site, url: url, isSearch: isSearch)
        reviewsLoading = true
        startReviewsTimeout()
    }

    /// Closes the reviews opened from a rating.
    public func closeReviews() {
        openedReviews = nil
        reviewsDidLoad()
    }

    /// True from a rating's tap until its page has loaded (or failed to), so the rating shows a spinner, and the reviews stay collapsed.
    public private(set) var reviewsLoading = false
    @ObservationIgnored private var reviewsLoadTimeout: Task<Void, Never>?

    /// The reviews' page has loaded, or failed to: the spinner stops and the reviews open.
    public func reviewsDidLoad() {
        reviewsLoadTimeout?.cancel()
        reviewsLoadTimeout = nil
        reviewsLoading = false
    }

    /// A page that never finishes must not hold the spinner forever, so the reviews open after this long regardless.
    private func startReviewsTimeout() {
        reviewsLoadTimeout?.cancel()
        reviewsLoadTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled else { return }
            self?.reviewsDidLoad()
        }
    }

    /// The trailer button's tap: loads the title's trailer into the page, or closes it while it plays. A YouTube video is checked
    /// with YouTube before it is tried in the page's embedded player. Reviews opened from a rating are closed first.
    public func toggleTrailer() {
        openedReviews = nil
        trailer.toggle(TrailerLoader.Source(
            plan: { [weak self] in
                guard let self else { return TrailerPlan(trailers: []) }
                return await self.trailerPlan()
            },
            embedCheck: { [weak self] videoID in
                guard let self else { return YouTubeEmbedCheck.Answer(allowsEmbedding: false) }
                return await YouTubeEmbedCheck(client: self.services.client).check(videoID: videoID)
            }))
    }

    /// The trailers to try, best first: the iTunes preview and the addon's direct links, then the best YouTube trailers (see
    /// `TrailerCatalog.playbackOrder`).
    public func trailerPlan() async -> TrailerPlan {
        TrailerPlan(trailers: TrailerCatalog.playbackOrder(previews: itunesTrailer.map { [$0] } ?? [], addonYouTubeIDs: detail.trailers,
                                                          addonURLs: detail.trailerURLs, tmdb: tmdbVideos))
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
}
