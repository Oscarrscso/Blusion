import Foundation
import Observation
import StremioKit

/// Lazy, bounded lookups. Cached scores stay visible while expired answers are refreshed.
@MainActor
@Observable
public final class PosterRatingsStore {
    /// Makes visible posters, review rows and episodes ask again after saving credentials or refreshing.
    var reviewServicesRevision = 0
    var omdbError: String?
    var reviewServiceIssue: String?
    var isEnabled: Bool {
        didSet { if isEnabled { Task { startLookups() } } }
    }
    /// Read by the rating logos: their brand colours when on, the text colour when off. Mirrors the saved setting.
    var showsColouredLogos = false
    /// Posters show the film's best disc beside the ratings, looked up on bestblurays.com, or else the service the title streams on, from
    /// TMDb. Mirrors the saved setting.
    var showsBestDisc = false {
        didSet { if showsBestDisc, !oldValue { Task { startLookups() } } }
    }
    /// Where posters put that mark. Mirrors the saved setting.
    var markPlacement = PosterMarkPlacement.topTrailing

    /// Copies the poster switches from the saved look, the one place they are read from. Launch, a reset and every change to the look call
    /// it, so a preset or an imported look reaches the posters as well as the switches in Settings.
    public func apply(_ look: AppearancePreferences) {
        isEnabled = look.showsPosterRatings
        showsColouredLogos = look.showsColouredRatingLogos
        showsBestDisc = look.showsBestDiscOnPosters
        markPlacement = look.posterMarkPlacement
    }
    /// True when ratings or a mark sit along a poster's bottom edge, so a logo drawn over the poster keeps clear of them.
    var occupiesPosterBottom: Bool {
        isEnabled || showsBestDisc && markPlacement != .topLeading && markPlacement != .topTrailing
    }

    @ObservationIgnored var entries: [String: TitleRatings] = [:]
    @ObservationIgnored var queue: [Lookup] = []
    @ObservationIgnored var queued: Set<String> = []
    @ObservationIgnored var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var cacheTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var cachePriorities: Set<String> = []
    @ObservationIgnored var nextLookupAt: [String: Date] = [:]
    /// An explicit refresh bypasses disk freshness for the titles on screen, which ask again at once; nextLookupAt then prevents
    /// repeated requests. It lapses shortly after, so titles opened later read their cache as usual instead of spending OMDb's allowance.
    @ObservationIgnored private var ignoresCachedFreshnessUntil: Date?
    var ignoresCachedFreshness: Bool { ignoresCachedFreshnessUntil.map { now() < $0 } ?? false }
    private static let refreshWindow: TimeInterval = 30
    @ObservationIgnored var episodeTasks: [String: Task<[Int: Double], Never>] = [:]
    @ObservationIgnored var episodeRetryAfter: [String: Date] = [:]
    @ObservationIgnored var episodeDatasetScores: [String: EpisodeDatasetLookup] = [:]
    @ObservationIgnored var episodeIndexIDs: [String: EpisodeIndexLookup] = [:]
    /// Hero artwork answers by title, kept for the session and dropped with the other review data by `forgetAll`.
    @ObservationIgnored var heroArtworkByID: [String: TMDbArtwork] = [:]
    /// Hero artwork lookups under way, by title, so a title asked for twice at once (a prewarm and the page, say) shares one request.
    @ObservationIgnored var heroArtworkTasks: [String: Task<TMDbArtwork?, Never>] = [:]
    /// Age certificates by title and country. Empty when TMDb has none for that country.
    @ObservationIgnored var certificationByID: [String: String] = [:]
    @ObservationIgnored var certificationTasks: [String: Task<String?, Error>] = [:]
    /// The most prewarm lookups that run at once. A fast scroll past many cards asks TMDb for a few titles at a time, not all of them.
    static let maxPrewarmLookups = 4
    /// Prewarm lookups running, and the ones waiting for a turn with the callers that can drop them when their cards scroll away.
    @ObservationIgnored var prewarmRunning = 0
    @ObservationIgnored var prewarmWaiting: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []
    /// Set when OMDb refused the key or the daily quota ran out: nothing asks it again until then, so a bad key does not
    /// spend one failing request per poster.
    @ObservationIgnored var omdbPausedUntil: Date?
    @ObservationIgnored var isClearing = false
    /// The last MyAnimeList lookup a discover list or a search asked for, which the next one waits for.
    @ObservationIgnored private var listMyAnimeListTurn: Task<CachedRating?, Never>?
    @ObservationIgnored let letterboxd: LetterboxdRatings?
    @ObservationIgnored let myAnimeList: MyAnimeListRatings?
    @ObservationIgnored var omdb: OMDbRatings?
    @ObservationIgnored var tmdb: TMDbRatings?
    @ObservationIgnored let bestBlurays: BestBluraysClient?
    @ObservationIgnored let cache: any RatingsCache
    /// Disc and streamer marks, a few bytes a title, apart from the ratings so they are kept for many more titles.
    @ObservationIgnored let marks: TitleMarksCache
    /// IMDb's ratings dataset kept on the device. Read for every IMDb title shown, with no network.
    @ObservationIgnored let dataset: (any IMDbDataset)?
    /// Counts dataset installs. A title looked up under an older count is looked up again the next time it is asked for.
    @ObservationIgnored var datasetGeneration = 0
    @ObservationIgnored private var datasetChecked: [String: Int] = [:]
    @ObservationIgnored let maxConcurrentLookups: Int
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored let logger: AddonLogger

    public nonisolated init(isEnabled: Bool = true, letterboxd: LetterboxdRatings? = nil, cache: (any RatingsCache)? = nil,
                            maxConcurrentLookups: Int = 3, now: @escaping @Sendable () -> Date = { Date() },
                            omdb: OMDbRatings? = nil, tmdb: TMDbRatings? = nil, dataset: (any IMDbDataset)? = nil,
                            bestBlurays: BestBluraysClient? = nil, marks: TitleMarksCache? = nil, myAnimeList: MyAnimeListRatings? = nil,
                            logger: AddonLogger = .silent) {
        self._isEnabled = isEnabled
        self.myAnimeList = myAnimeList
        self.dataset = dataset
        self.letterboxd = letterboxd
        self.bestBlurays = bestBlurays
        self.omdb = omdb
        self.tmdb = tmdb
        self.cache = cache ?? InMemoryRatingsCache()
        self.marks = marks ?? TitleMarksCache(fileURL: nil, region: Locale.current.region?.identifier ?? "US")
        self.maxConcurrentLookups = max(1, maxConcurrentLookups)
        self.now = now
        self.logger = logger
    }

    /// Settings changed on another device: visible posters and review rows ask again with the current settings.
    public func settingsDidChangeElsewhere() {
        reviewServicesRevision += 1
    }

    /// Returns the same object every time. No observed property changes synchronously when called from a view body. `includeMarks` asks
    /// for the title's disc and streamer whether or not posters show marks, ahead of other titles, for a screen built on them (the video
    /// store's cases).
    func ratings(for item: MetaPreview, includeReviews: Bool = false, source: RatingSource? = nil,
                        includeMarks: Bool = false) -> TitleRatings {
        let entry = storedEntry(for: item)
        // MyAnimeList searches by name, so anime listed under its own databases' ids (Kitsu's, say) is looked up too.
        if !isClearing, myAnimeList != nil, entry.isAnime, isEnabled || includeReviews, source == nil {
            enqueue(item, provider: .myAnimeList, includeReviews: includeReviews)
        }
        let wantsMarks = (showsBestDisc || includeMarks) && source == nil
        let wantsDisc = wantsMarks && bestBlurays != nil && item.type == "movie"
        // A film asks for its streamer only once Best Blurays names no disc for it; a series has no disc to wait for.
        let wantsStreamer = wantsMarks && tmdb != nil
            && (item.type == "series" || item.type == "movie" && (bestBlurays == nil || entry.discChecked && entry.bestDisc == nil))
        guard !isClearing, isEnabled || includeReviews || wantsDisc || wantsStreamer, LetterboxdRatings.isIMDbID(item.id) else { return entry }
        if wantsDisc { enqueue(item, provider: .bestBlurays, includeReviews: includeMarks) }
        if wantsStreamer { enqueue(item, provider: .streaming, includeReviews: includeMarks) }
        guard isEnabled || includeReviews else { return entry }
        if source == nil || source == .imdb { lookUpInDataset(item, entry: entry) }
        if letterboxd != nil, item.type == "movie", source == nil || source == .letterboxd {
            enqueue(item, provider: .letterboxd, includeReviews: includeReviews)
        }
        if tmdb != nil, ["movie", "series"].contains(item.type), source == nil {
            enqueue(item, provider: .tmdb, includeReviews: includeReviews)
        }
        // OMDb gives Rotten Tomatoes and Metacritic for a film. Only the title page asks: every poster card calls this on each redraw, so it
        // must not do any work here. The allowance and any refusal are checked when the lookup runs.
        if includeReviews, omdb != nil, item.type == "movie", LetterboxdRatings.isIMDbID(item.id), source == nil {
            enqueue(item, provider: .omdb, includeReviews: includeReviews)
        }
        return entry
    }

    /// The title as the rating filters and the Rating sorts judge it (see `RatingSource.order(isAnime:)`); nil until a site has scored it.
    /// Asks for the scores it needs whatever the poster setting: IMDb's from the device at once, then Letterboxd's, TMDb's and, for
    /// anime, MyAnimeList's, in turn with the posters' lookups. Reading it inside observation tracking re-runs that as each score arrives.
    func judgedRating(for item: MetaPreview) -> JudgedRating? {
        let entry = storedEntry(for: item)
        guard !isClearing else { return entry.judgedRating }
        if myAnimeList != nil, entry.isAnime { enqueue(item, provider: .myAnimeList, includeReviews: false, forFilter: true) }
        if LetterboxdRatings.isIMDbID(item.id) {
            lookUpInDataset(item, entry: entry)
            if letterboxd != nil, item.type == "movie" { enqueue(item, provider: .letterboxd, includeReviews: false, forFilter: true) }
        }
        return entry.judgedRating
    }

    /// A title's rating out of 10 for a discover list's or a search's score bounds, as the rating filters judge it (see
    /// `RatingSource.order(isAnime:)`): IMDb's from the device, Letterboxd's and MyAnimeList's as kept on the device or else asked of the
    /// site. `tmdbScore` is unused by the filter. Each answer is kept and shown on the title's posters. Nil when no site has scored it.
    public func listRating(for item: MetaPreview, tmdbScore: Double?, isAnime: Bool) async -> Double? {
        let entry = storedEntry(for: item)
        if isAnime, !entry.isAnime { entry.isAnime = true }
        for source in RatingSource.order(isAnime: entry.isAnime) {
            if let score = await listScore(of: item, entry: entry, from: source, tmdbScore: tmdbScore) { return source.outOfTen(score) }
        }
        return nil
    }

    private func listScore(of item: MetaPreview, entry: TitleRatings, from source: RatingSource, tmdbScore: Double?) async -> Double? {
        switch source {
        case .imdb:
            if let dataset, LetterboxdRatings.isIMDbID(item.id), let found = await dataset.rating(for: item.id) { return found.rating }
            return entry.imdb
        case .tmdb:
            return tmdbScore ?? entry.tmdb
        case .letterboxd:
            if let known = entry.letterboxd { return known }
            guard let letterboxd, item.type == "movie", LetterboxdRatings.isIMDbID(item.id) else { return nil }
            return await keptAnswer(for: Lookup(item: item, provider: .letterboxd, includeReviews: false)) {
                CachedRating(rating: try await letterboxd.rating(imdbID: item.id), fetchedAt: self.now())
            }?.rating
        case .myAnimeList:
            if let known = entry.myAnimeList { return known }
            guard let myAnimeList else { return nil }
            // MyAnimeList is asked about one title at a time, as its search box would be: each list lookup waits for the one before.
            let previous = listMyAnimeListTurn
            let turn = Task { [self] () -> CachedRating? in
                _ = await previous?.value
                return await keptAnswer(for: Lookup(item: item, provider: .myAnimeList, includeReviews: false)) {
                    CachedRating(rating: nil, fetchedAt: self.now(), reviews: try await myAnimeList.ratings(for: item))
                }
            }
            listMyAnimeListTurn = turn
            return await turn.value?.reviews?.myAnimeList
        }
    }

    /// The same object for a title every time, keeping its catalog's IMDb rating current.
    private func storedEntry(for item: MetaPreview) -> TitleRatings {
        if let known = entries[item.identity] {
            if let rating = item.imdbRating {
                known.catalogIMDb = rating
                let shown = known.datasetIMDb ?? rating
                if known.imdb != shown { Task { known.imdb = known.datasetIMDb ?? known.catalogIMDb } }
            }
            return known
        }
        let entry = TitleRatings(id: item.identity, imdb: item.imdbRating, isAnime: ReviewSite.isAnime(item))
        entries[item.identity] = entry
        return entry
    }

    /// Reads the title's score from the dataset on the device. A title is read once per dataset install, however often views ask.
    private func lookUpInDataset(_ item: MetaPreview, entry: TitleRatings) {
        guard let dataset, datasetChecked[item.identity] != datasetGeneration else { return }
        datasetChecked[item.identity] = datasetGeneration
        let generation = datasetGeneration
        Task { [self] in
            let found = await dataset.rating(for: item.id)
            guard !isClearing, generation == datasetGeneration else {
                // Dropped on purpose (clearing, or a newer dataset arrived): ask again next time.
                if datasetChecked[item.identity] == generation { datasetChecked[item.identity] = nil }
                return
            }
            guard let found else { return }
            entry.datasetIMDb = found.rating
            if entry.imdb != found.rating { entry.imdb = found.rating }
            if entry.imdbVotes != found.votes { entry.imdbVotes = found.votes }
        }
    }

    /// Fetches a newer copy of the IMDb dataset when one is due (at most once a day; see `IMDbRatingsUpdater`). Runs off the main actor
    /// and never blocks a view. When new data arrives, visible titles read it at once.
    public func refreshIMDbDataset() async {
        guard let dataset else { return }
        let outcome = await dataset.refreshIfNeeded()
        switch outcome {
        case .updated(let titles):
            logger.log(.info, "IMDb ratings updated: \(titles) titles")
            datasetGeneration += 1
            reviewServicesRevision += 1
        case .episodeIndexUpdated:
            logger.log(.info, "IMDb offline episode mapping updated")
            datasetGeneration += 1
            reviewServicesRevision += 1
        case .failed(let reason):
            logger.log(.warning, "IMDb ratings update failed: \(reason)")
        case .skipped, .notModified:
            break
        }
    }

    /// What the device holds, for Settings. Nil when nothing has been downloaded yet.
    func imdbDatasetStatus() async -> IMDbDatasetStatus? { await dataset?.status() }

    /// Called after the user saves or removes credentials. Old requests finish cancelling before the clients change.
    public func setReviewServices(omdb: OMDbRatings? = nil, tmdb: TMDbRatings?, refreshCache: Bool = false) async {
        await cancelLookups()
        self.omdb = omdb
        self.tmdb = tmdb
        ignoresCachedFreshnessUntil = refreshCache ? now().addingTimeInterval(Self.refreshWindow) : nil
        omdbPausedUntil = nil
        omdbError = nil
        reviewServiceIssue = nil
        for entry in entries.values {
            if tmdb == nil {
                entry.tmdb = nil
                entry.tmdbURL = nil
            }
            // OMDb's scores go with its key, as TMDb's do.
            if omdb == nil {
                entry.rottenTomatoes = nil
                entry.metacritic = nil
            }
        }
        isClearing = false
        reviewServicesRevision += 1
    }

    /// Recheck visible titles, including old empty answers and failed requests. Keep good scores on screen and on disk.
    func refresh() async {
        await cancelLookups()
        ignoresCachedFreshnessUntil = now().addingTimeInterval(Self.refreshWindow)
        omdbPausedUntil = nil
        omdbError = nil
        reviewServiceIssue = nil
        isClearing = false
        reviewServicesRevision += 1
    }

    /// Cancel before clearing, so an old answer cannot restore cleared data.
    func forgetAll() async {
        await cancelLookups()
        await cache.clear()
        await marks.clear()
        heroArtworkByID.removeAll()
        heroArtworkTasks.removeAll()
        certificationByID.removeAll()
        certificationTasks.removeAll()
        for entry in entries.values {
            entry.imdb = entry.datasetIMDb ?? entry.catalogIMDb
            entry.letterboxd = nil
            entry.rottenTomatoes = nil
            entry.metacritic = nil
            entry.tmdb = nil
            entry.tmdbURL = nil
            entry.myAnimeList = nil
            entry.myAnimeListURL = nil
            entry.bestDisc = nil
            entry.streamer = nil
            entry.discChecked = false
        }
        omdbPausedUntil = nil
        omdbError = nil
        reviewServiceIssue = nil
        isClearing = false
        reviewServicesRevision += 1
    }

    func apply(_ cached: CachedRating, lookup: Lookup) {
        guard let entry = entries[lookup.item.identity] else { return }
        switch lookup.provider {
        case .letterboxd:
            // Each write redraws the posters that show this title, even one that sets the same value, so only changes are written.
            if let rating = cached.rating, entry.letterboxd != rating { entry.letterboxd = rating }
        case .tmdb:
            if let rating = cached.reviews?.tmdb, entry.tmdb != rating { entry.tmdb = rating }
            if let url = cached.reviews?.tmdbURL, entry.tmdbURL != url { entry.tmdbURL = url }
            // TMDb names Japanese animation listed under an IMDb id as anime: its MyAnimeList score is looked up next.
            if cached.reviews?.isAnime == true, !entry.isAnime {
                entry.isAnime = true
                if myAnimeList != nil {
                    enqueue(lookup.item, provider: .myAnimeList, includeReviews: lookup.includeReviews, forFilter: lookup.forFilter)
                }
            }
            // The answer names the title's TMDb id, also when it was read from the cache: its page then asks only for its artwork.
            if let tmdb, let reviews = cached.reviews {
                let item = lookup.item
                Task { await tmdb.rememberID(from: reviews, imdbID: item.id, type: item.type) }
            }
        case .omdb:
            // Only scores OMDb gave are set: a title it has none for keeps whatever the other providers said.
            if let score = cached.reviews?.rottenTomatoes, entry.rottenTomatoes != score { entry.rottenTomatoes = score }
            if let score = cached.reviews?.metacritic, entry.metacritic != score { entry.metacritic = score }
        case .myAnimeList:
            if let score = cached.reviews?.myAnimeList, entry.myAnimeList != score { entry.myAnimeList = score }
            if let url = cached.reviews?.myAnimeListURL, entry.myAnimeListURL != url { entry.myAnimeListURL = url }
        case .bestBlurays, .streaming:
            break
        }
    }

    enum Provider: String {
        case letterboxd, tmdb, omdb, bestBlurays, streaming, myAnimeList

        var isMark: Bool { self == .bestBlurays || self == .streaming }
    }
    struct Lookup {
        let item: MetaPreview
        let provider: Provider
        /// A screen asked for this title itself, so it goes ahead of the others and runs whatever the settings. For a mark: a screen built
        /// on marks asked (`includeMarks`).
        var includeReviews: Bool
        /// A rating filter or Rating sort needs the score, so it runs whatever the poster setting, in its turn.
        var forFilter = false
        var id: String { "\(provider.rawValue):\(item.identity)" }
        var cacheKey: String {
            switch provider {
            case .letterboxd: item.id
            case .tmdb: "tmdb:\(item.identity)"
            case .omdb: "omdb:\(item.identity)"
            case .myAnimeList: "mal:\(item.identity)"
            case .bestBlurays: "bestblurays:\(item.id)"
            case .streaming: "streaming:\(item.id)"
            }
        }
    }
}
