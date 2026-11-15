import Foundation
import Observation
import PlayerKit
import StremioKit

/// A title's logos, best first. The catalogue logo, then TMDb, then its alternates, then Metahub once the artwork lookup has finished.
enum HeroLogos {
    static func candidates(preview: URL?, artwork: TMDbArtwork?, imdbID: String, artworkReady: Bool) -> [URL] {
        var urls: [URL] = []
        func add(_ url: URL?) {
            guard let url, !urls.contains(url) else { return }
            urls.append(url)
        }
        add(preview)
        add(artwork?.logo)
        for url in artwork?.alternateLogos ?? [] { add(url) }
        if artworkReady { add(MetahubArtwork.logo(imdbID: imdbID)) }
        return urls
    }
}

/// Detail: starts from the catalog preview, upgrades to the addon's full `meta` when it arrives.
@MainActor
@Observable
final class DetailViewModel {
    let preview: MetaPreview
    var detail: MetaDetail
    var isLoading = true
    /// True when no addon returned `meta` and Detail is built from the catalog preview alone.
    var isFallback = false
    var selectedSeason: Int?
    var isInLibrary = false
    /// Goes up each time the page reads in what it shows (the details, library membership, watched marks) rather than the user changing it
    /// here. The Save and Watched buttons tick only for a change that comes without it, so a page that opens on a saved or watched title is
    /// silent.
    var loadRevision = 0
    /// Episode cards are as wide as the text above them, as chosen with the toggle beside the season name. The choice is saved, and read
    /// again when the details load.
    var matchesEpisodeWidthToText = false
    /// Seasons whose TMDb episode scores are already in `detail`, or on their way.
    var episodeRatingSeasons: Set<Int> = []
    /// How long each episode runs, in minutes, by episode id, from TMDb's season data. Filled a season at a time as its cards appear.
    var episodeRuntimes: [String: Int] = [:]
    /// Seasons TMDb has answered for, even with no runtimes, so they are not asked again on this page. A failed lookup is asked again.
    @ObservationIgnored var runtimeSeasons: Set<Int> = []
    /// Bumped by each read of the watched and saved state, so a read that returns after a later one can't put back older state.
    @ObservationIgnored var userStateGeneration = 0
    /// The season lookups on their way. The page owns them: a card that scrolls away does not call its season's lookup off.
    @ObservationIgnored var runtimeTasks: [Int: Task<Void, Never>] = [:]
    /// Identities (`type/id`) of watched movies and episodes shown on this screen.
    var watchedIdentities: Set<String> = []
    /// Share of the runtime saved for the movie and episodes shown here, by identity (0...1). Only progress that playback can
    /// resume from is listed, so a bar or a "Resume" label always means the player starts at the saved position.
    var progressFractions: [String: Double] = [:]
    /// Saved records for the movie and episodes shown here, by identity. `nextUp` reads their update times.
    var savedProgress: [String: WatchProgress] = [:]
    /// Recomputed when details or progress change, rather than sorting every episode during SwiftUI redraws.
    var nextUp: Video?
    /// An untouched next episode is still a continuation once earlier episodes are watched.
    /// Cached with progress so the Play button does not scan the episode list on every redraw.
    var continuesSeries = false
    /// A show's watched button must not reparse every episode's air date on each view update.
    var isSeriesWatched = false

    let services: AppServices
    /// The Play request whose stream lookup was started from this page.
    var prefetchedStreamRequest: StreamRequest?
    /// A card's request includes its next episode; compute that once rather than sorting every season during redraws.
    @ObservationIgnored var episodeRequests: [String: StreamRequest] = [:]
    var tmdbArtwork: TMDbArtwork?
    var isLoadingArtwork = true
    // Separate from metadata: these requests start after hero and stream priority work.
    var isLoadingReviews = true
    var isLoadingCredits = true
    var isLoadingRelated = true
    var isLoadingFacts = true
    var reviews: [TMDbReview] = []
    /// What the TMDb reviews praise and complain about, from their complete text, by the on-device model.
    var reviewConsensus: String?
    var isSummarizingReviews = false
    var reviewSummaryError: String?
    var reviewedCount = 0
    @ObservationIgnored var reviewSummaryRequest = UUID()
    /// The YouTube trailers and teasers TMDb lists for the title. Empty until TMDb answers, or when no read token is saved.
    var tmdbVideos: [TMDbVideo] = []
    /// The title's preview from Apple's iTunes store: a direct file the app plays. Nil until the search answers, or when the store has none.
    var itunesTrailer: Trailer?
    /// The lookups of the trailers beyond the addon's (TMDb's videos and the iTunes preview), shared by the page's load and a trailer tap
    /// that comes before it gets to them.
    var trailerSourcesTask: Task<Void, Never>?
    /// Set once every place a trailer can come from has answered, so a title with none dims its trailer button only then.
    var hasCheckedTrailerSources = false
    /// The cast and crew with TMDb ids and photos. Nil until TMDb answers, or when no read token is saved.
    var titleCredits: TMDbTitleCredits?
    /// Titles TMDb recommends for this one, for the shelf at the bottom of the page. Empty until TMDb answers.
    var relatedTitles: [TMDbRelatedTitle] = []
    /// The other films of the movie's franchise (its TMDb collection), for the shelf above More Like This. Nil until TMDb answers, for a
    /// series, and for a movie in no franchise.
    var franchise: TMDbFranchise?
    /// Where the title can be watched in the viewer's region, for the Watch Anywhere section. Nil until loaded, and only asked for while
    /// that section is on.
    var titleWatch: TMDbTitleWatch?
    /// What the stores ask to rent and buy the title in the viewer's region, for Information and the line under Play. Nil until JustWatch
    /// answers, or when no store there rents or sells it.
    var titlePrices: TitlePrices?
    /// What TMDb knows beyond the addon's details (studios, countries, language, budget, a series' network and run), for Information. Nil
    /// until TMDb answers, or when no read token is saved.
    var titleFacts: TMDbTitleFacts?
    /// The US age rating ("R", "TV-MA") for the meta line. Nil until TMDb answers, or when it has none.
    var certification: String?
    /// Set after the hero picture/logo and the first stream prefetch have been prioritised, so secondary page work may start.
    var hasSettledHero = false
    /// The title's trailer: its loading, the player in the page's panel, and a failure. The trailer button and the panel share it.
    let trailer: TrailerLoader
    /// Goes up when the trailer is closed by a control that gave its own haptic (the full-screen trailer's X), so the Trailer button does not
    /// tick a second time.
    var trailerQuietCloses = 0
    /// The title's Play colour as "rrggbb" ("" for the plain button), or nil while it is not decided. Read when the page opens; a title whose
    /// colour was not decided yet (a dull poster whose logo had not loaded, or no card that showed it) takes it once, as soon as the page's
    /// own read decides it, rather than on the next opening. It never changes after that.
    private(set) var playColourHex: String?

    init(preview: MetaPreview, services: AppServices, artwork: TMDbArtwork? = nil, artworkChecked: Bool = false,
                trailerPreparer: (any TrailerPreparing)? = nil) {
        self.preview = preview
        self.detail = .fallback(from: preview)
        self.services = services
        // The title's Play colour from its poster, when the poster is already in the image cache, so the page is coloured from its first frame.
        #if canImport(UIKit)
        PlayColourStore.shared.readNow(identity: preview.identity, pictures: PlayColourStore.pictures(for: preview),
                                       logos: PlayColourStore.logos(for: preview))
        playColourHex = PlayColourStore.shared.hex(for: preview.identity)
        PlayColourStore.shared.logPageColour(identity: preview.identity)
        #else
        playColourHex = nil
        #endif
        self.trailer = TrailerLoader(preparer: trailerPreparer ?? UnavailableTrailerPreparer())
        // An artwork handed over by Home, or one looked up earlier this session, is used at once: the page then has nothing to wait for.
        let known = artwork ?? services.posterRatings.cachedHeroArtwork(for: preview)
        self.tmdbArtwork = known
        self.isLoadingArtwork = known == nil && !artworkChecked
        // The age rating the spotlight already showed for this title is there from the first frame, so the line does not change on opening.
        self.certification = services.posterRatings.cachedCertification(for: preview)
        #if canImport(UIKit)
        if playColourHex == nil {
            // The page's own stand-in picture, so a picture fetched for the colour is the stand-in's own download: the Mac's stands in with a
            // backdrop.
            #if targetEnvironment(macCatalyst)
            let standIn = HeroPicture.standInURL(for: preview, backdropOnly: true)
            #else
            let standIn = HeroPicture.standInURL(for: preview)
            #endif
            let identity = preview.identity
            let pictures = PlayColourStore.pictures(for: preview), logos = PlayColourStore.logos(for: preview)
            Task { [weak self] in
                let hex = await PlayColourStore.shared.readForPage(identity: identity, standIn: standIn, pictures: pictures, logos: logos)
                guard let self, let hex, self.playColourHex == nil else { return }
                self.playColourHex = hex
            }
        }
        #endif
    }

    /// The part of the cast and crew picked from its menu: the cast until another is picked.
    var creditGroup: TitleCreditGroup = .cast

    /// The parts of the cast and crew the menu offers: the cast, then each crew department TMDb lists anyone in.
    var creditGroups: [TitleCreditGroup] { titleCredits?.groups ?? [] }

    /// The part the section shows: the one picked, or the first there is when nobody is in it. Nil while TMDb's credits are unknown or
    /// list nobody.
    var shownCreditGroup: TitleCreditGroup? { titleCredits?.group(showing: creditGroup) }

    /// The people of the part shown, the cast's first twenty. Nil while TMDb's credits are unknown; empty when TMDb has none, so the
    /// screen falls back to the addon's plain names.
    var shownCredits: [TMDbTitlePerson]? {
        guard let titleCredits else { return nil }
        guard let group = shownCreditGroup else { return [] }
        let people = titleCredits.people(in: group)
        return group == .cast ? Array(people.prefix(20)) : people
    }

    /// Resolved IMDb scores by season, then episode number. An empty entry means IMDb has been checked for that season.
    var omdbEpisodeScores: [Int: [Int: Double]] = [:]
    @ObservationIgnored var scoreTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored var scoresRevision = 0

    /// Changes when review credentials do, so the cards ask again.
    func download(_ request: StreamRequest) async { await services.downloads?.enqueueBest(request) }
    var downloadManager: DownloadManager? { services.downloads }

    var reviewServicesRevision: Int { services.posterRatings.reviewServicesRevision }

    var isSeries: Bool { detail.type == "series" || !detail.videos.isEmpty }

    var seasons: [Int] { detail.seasons }
    var episodes: [Video] { selectedSeason.map { detail.episodes(inSeason: $0) } ?? [] }

    /// What "Play" asks addons for: the movie itself.
    var movieRequest: StreamRequest { StreamRequest(movie: detail.preview.type.isEmpty ? preview : detail.preview) }

    func request(for video: Video) -> StreamRequest {
        var request = episodeRequests[video.id] ?? StreamRequest(episode: video, of: detail)
        episodeRequests[video.id] = request
        if let minutes = episodeRuntimes[video.id] { request.expectedDuration = TimeInterval(minutes) * 60 }
        return request
    }

    /// The episodes the stream picker's switcher steps to from `request`'s: the one before and the one after in watching order, as their
    /// cards would open them. Each is nil when there is none or it has not aired, and both are nil for a film.
    func neighbouringEpisodes(of request: StreamRequest) -> (previous: StreamRequest?, next: StreamRequest?) {
        // By its id first, so a series listing two videos with the same numbers still steps on from the one shown.
        guard isSeries, let season = request.season, let episode = request.episode,
              let video = detail.videos.first(where: { $0.id == request.id })
                ?? detail.videos.first(where: { $0.season == season && $0.episode == episode }) else { return (nil, nil) }
        let neighbours = detail.neighbouringEpisodes(of: video)
        return (neighbours.previous.map(self.request(for:)), neighbours.next.map(self.request(for:)))
    }

    /// Starts the stream lookup for the Play button's request, once per title. A new request (a series moving to its next episode) lets the previous lookup go.
    func prefetchStreams(for request: StreamRequest?) async {
        guard let request, !Task.isCancelled, OptimisationSettings.prefetchesStreams() else { return }
        if let previous = prefetchedStreamRequest, previous.id == request.id, previous.type == request.type { return }
        if let previous = prefetchedStreamRequest { services.streams.releasePrefetch(previous) }
        prefetchedStreamRequest = request
        // Register with the prefetch cache before lower-priority network work starts.
        await services.streams.prefetch(request)
    }

    /// Stop page-owned lookups after leaving the details screen. Individual cards may disappear
    /// while scrolling without cancelling their shared season requests; page departure is different.
    func cancelOffscreenWork() {
        trailerSourcesTask?.cancel()
        trailerSourcesTask = nil
        for task in runtimeTasks.values { task.cancel() }
        runtimeTasks.removeAll()
        for task in scoreTasks.values { task.cancel() }
        scoreTasks.removeAll()
        // The reviews' timeout is kept: it is the only thing that clears their spinner when the page never reports.
    }

    /// Leaving the page lets an unclaimed lookup go (after a short grace), Shuffle's included.
    func releaseStreamPrefetch() {
        shuffleLookup?.cancel()
        shuffleLookup = nil
        if let shuffle = prefetchedShuffleRequest {
            services.streams.releasePrefetch(shuffle)
            prefetchedShuffleRequest = nil
        }
        guard let request = prefetchedStreamRequest else { return }
        services.streams.releasePrefetch(request)
        prefetchedStreamRequest = nil
    }

    // MARK: Shuffle

    /// The episode Shuffle plays next, picked ahead so the button can name it. The first one's streams are looked up as the page opens.
    var shuffleNext: Video?
    /// The lookup started for the first `shuffleNext`, let go when the page is left.
    var prefetchedShuffleRequest: StreamRequest?
    /// Waits for the Play button's lookup to finish, then starts Shuffle's.
    var shuffleLookup: Task<Void, Never>?
    /// True once Shuffle has been tapped: later picks are not looked up ahead.
    var hasTakenShuffle = false

    /// Share of the movie that is saved and resumable (0...1). Nil when it has not started, is watched or cannot be resumed.
    func progressFraction(for request: StreamRequest) -> Double? { progressFractions[request.identity] }

    /// The same for an episode of this series.
    func progressFraction(for video: Video) -> Double? { progressFractions[episodeIdentity(video)] }

    /// Separate landscape and portrait heroes. Keep the transition's poster until the artwork lookup finishes. Falls back to the
    /// preview this page was opened from, so Home and the title page use the same URL.
    var backdropURL: URL? {
        tmdbArtwork?.backdrop ?? (isLoadingArtwork ? nil : preview.background ?? MetahubArtwork.background(imdbID: preview.id))
    }
    var portraitArtworkURL: URL? {
        tmdbArtwork?.portrait ?? (isLoadingArtwork ? nil : preview.background ?? MetahubArtwork.background(imdbID: preview.id))
    }

    /// The title's logos, best first. Metahub is included once the TMDb lookup has finished.
    var logoCandidates: [URL] {
        HeroLogos.candidates(preview: preview.logo, artwork: tmdbArtwork, imdbID: preview.id, artworkReady: !isLoadingArtwork)
    }

    /// The title's logo (a transparent image), when the preview or the TMDb lookup has one. A later candidate stands in when this one fails.
    var logoURL: URL? { logoCandidates.first }

    /// Whether the portrait picture already carries the title, so the separate logo is not shown in portrait.
    var portraitHidesLogo: Bool { tmdbArtwork?.portraitHidesLogo ?? false }

    /// The metadata line both heroes show, for `MetaLine`: year, the first two genres, certification, runtime and the IMDb rating, in that
    /// order ("2008", "Drama", "Crime", "PG-13", "152 min", "★ 90"). Missing parts
    /// stay nil and `MetaLine` leaves them out. The score is IMDb's own when the caller has it (`imdbRating`), else the catalog's.
    nonisolated static func heroMetaParts(for preview: MetaPreview, certification: String?, imdbRating: Double? = nil) -> [String?] {
        let rating = (imdbRating ?? preview.imdbRating).map { "★ \(ScoreText.wholeScore($0))" }
        let genres = DetailViewModel.heroMetaGenres(for: preview).map { Optional($0) }
        return [preview.releaseInfo] + genres + [certification, preview.runtime, rating]
    }

    /// The genres the metadata line shows: the first two. `MetaLine` drops these first when the line is too long for one line.
    nonisolated static func heroMetaGenres(for preview: MetaPreview) -> [String] {
        Array(preview.genres.prefix(2))
    }

    /// The metadata line under the hero, built by the shared store exactly as Home's spotlight builds it (see `HeroMetaStore.parts`).
    var heroMetaLine: [String?] {
        services.heroMeta.parts(for: preview, certification: certification, ratings: services.posterRatings)
    }

    /// The genres in the metadata line, the same ones `heroMetaLine` shows, for `MetaLine` to drop first when the line is too long.
    var heroMetaGenres: [String] {
        services.heroMeta.genres(for: preview)
    }

    /// The reviews opened from a rating, under the ratings. Nil when none are open.
    var openedReviews: OpenedReviews?
    /// The site that stays on screen while another rating's site loads in its place. Nil once the new one shows, or when none was open.
    var shownReviews: OpenedReviews?

    /// True from a rating's tap until its page has loaded (or failed to), so the rating shows a spinner, and the reviews stay collapsed.
    var reviewsLoading = false
    @ObservationIgnored var reviewsLoadTimeout: Task<Void, Never>?

    var subtitle: String {
        [detail.preview.releaseInfo, detail.preview.runtime, detail.preview.imdbRating.map { "★ \(ScoreText.wholeScore($0))" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// Episodes in watching order: regular seasons, then specials, then any episode the addon gave no season.
    var watchingOrder: [Video] {
        detail.seasons.flatMap { detail.episodes(inSeason: $0) } + detail.videos.filter { $0.season == nil }
    }

    var movieIdentity: String { movieRequest.identity }

    /// The identity `request(for:)` gives an episode. Built here so a loop over every episode does not look up each next episode.
    func episodeIdentity(_ video: Video) -> String {
        "\(detail.type.isEmpty ? "series" : detail.type)/\(video.id)"
    }

    /// Started or queued to continue, but not watched.
    func isUnfinished(_ identity: String) -> Bool {
        guard let record = savedProgress[identity] else { return false }
        return !record.isWatched && (record.isQueuedForContinue == true || record.position > 0)
    }

    func lastUpdate(_ video: Video) -> Date {
        savedProgress[episodeIdentity(video)]?.updatedAt ?? .distantPast
    }
}

/// Resumes a continuation once, for whichever of several racing tasks finishes first.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }

    func resume() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }
}
