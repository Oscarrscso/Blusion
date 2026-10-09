import Foundation
import Observation
import StremioKit

/// Observable per title, so a score arriving late redraws only its own poster or review row.
@MainActor
@Observable
public final class TitleRatings: Identifiable {
    public nonisolated let id: String
    /// IMDb's score out of 10, usually already carried by the catalog.
    public internal(set) var imdb: Double?
    /// Letterboxd's average out of 5, for films only.
    public internal(set) var letterboxd: Double?
    public internal(set) var rottenTomatoes: Double?
    public internal(set) var metacritic: Double?
    public internal(set) var tmdb: Double?
    public internal(set) var tmdbURL: URL?
    @ObservationIgnored var catalogIMDb: Double?

    nonisolated init(id: String, imdb: Double? = nil, letterboxd: Double? = nil) {
        self.id = id
        self._imdb = imdb
        self._letterboxd = letterboxd
        self.catalogIMDb = imdb
    }

    /// The site's own score, on its own scale; nil until that site has answered for this title.
    public func score(for source: RatingSource) -> Double? {
        switch source {
        case .letterboxd: letterboxd
        case .imdb: imdb
        case .rottenTomatoes: rottenTomatoes
        case .metacritic: metacritic
        }
    }

    public var imdbText: String? { imdb.map { String(format: "%.1f", $0) } }
    public var letterboxdText: String? { letterboxd.map { String(format: "%.1f", $0 * 2) } }
    /// Prefer IMDb and Letterboxd, then fill either missing score from the other available sites.
    public var posterSites: [ReviewSite] {
        Array(ReviewSite.allCases.filter { shortText(for: $0) != nil }.prefix(2))
    }
    public var isEmpty: Bool { posterSites.isEmpty }

    /// The score alone, for a small button that already shows the site's icon: "8.7", "91%", "82".
    public func shortText(for site: ReviewSite) -> String? {
        switch site {
        case .imdb: imdbText
        case .letterboxd: letterboxdText
        case .rottenTomatoes: rottenTomatoes.map { String(format: "%.0f%%", $0) }
        case .metacritic: metacritic.map { String(format: "%.0f", $0) }
        case .tmdb: tmdb.map { String(format: "%.1f", $0) }
        }
    }

    public func text(for site: ReviewSite) -> String? {
        switch site {
        case .imdb: imdbText.map { "\($0)/10" }
        case .letterboxd: letterboxdText.map { "\($0)/10" }
        case .rottenTomatoes: rottenTomatoes.map { String(format: "%.0f%%", $0) }
        case .metacritic: metacritic.map { String(format: "%.0f/100", $0) }
        case .tmdb: tmdb.map { String(format: "%.1f/10", $0) }
        }
    }
}

/// Lazy, bounded lookups. Cached scores stay visible while expired answers are refreshed.
@MainActor
@Observable
public final class PosterRatingsStore {
    /// Makes visible posters, review rows and episodes ask again after saving credentials or refreshing.
    public private(set) var reviewServicesRevision = 0
    public private(set) var omdbError: String?
    public private(set) var reviewServiceIssue: String?
    public var isEnabled: Bool {
        didSet { if isEnabled { Task { startLookups() } } }
    }
    /// Read by the rating logos: their brand colours when on, the text colour when off. Mirrors the saved setting.
    public var showsColouredLogos = false

    @ObservationIgnored private var entries: [String: TitleRatings] = [:]
    @ObservationIgnored private var queue: [Lookup] = []
    @ObservationIgnored private var queued: Set<String> = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextLookupAt: [String: Date] = [:]
    /// An explicit refresh bypasses disk freshness once per lookup; nextLookupAt then prevents repeated requests.
    @ObservationIgnored private var ignoresCachedFreshness = false
    @ObservationIgnored private var episodeTasks: [String: Task<[Int: Double], Never>] = [:]
    /// Set when OMDb refused the key or the daily quota ran out: nothing asks it again until then, so a bad key does not
    /// spend one failing request per poster.
    @ObservationIgnored private var omdbPausedUntil: Date?
    @ObservationIgnored private var isClearing = false
    @ObservationIgnored private let letterboxd: LetterboxdRatings?
    @ObservationIgnored private var omdb: OMDbRatings?
    @ObservationIgnored private var tmdb: TMDbRatings?
    @ObservationIgnored private let cache: any RatingsCache
    @ObservationIgnored private let maxConcurrentLookups: Int
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let logger: AddonLogger

    public nonisolated init(isEnabled: Bool = true, letterboxd: LetterboxdRatings? = nil, cache: (any RatingsCache)? = nil,
                            maxConcurrentLookups: Int = 3, now: @escaping @Sendable () -> Date = { Date() },
                            omdb: OMDbRatings? = nil, tmdb: TMDbRatings? = nil, logger: AddonLogger = .silent) {
        self._isEnabled = isEnabled
        self.letterboxd = letterboxd
        self.omdb = omdb
        self.tmdb = tmdb
        self.cache = cache ?? InMemoryRatingsCache()
        self.maxConcurrentLookups = max(1, maxConcurrentLookups)
        self.now = now
        self.logger = logger
    }

    /// Returns the same object every time. No observed property changes synchronously when called from a view body.
    public func ratings(for item: MetaPreview, includeReviews: Bool = false) -> TitleRatings {
        let entry: TitleRatings
        if let known = entries[item.identity] {
            entry = known
            if let rating = item.imdbRating {
                known.catalogIMDb = rating
                if known.imdb != rating { Task { known.imdb = known.catalogIMDb } }
            }
        } else {
            entry = TitleRatings(id: item.identity, imdb: item.imdbRating)
            entries[item.identity] = entry
        }
        guard !isClearing, isEnabled || includeReviews, LetterboxdRatings.isIMDbID(item.id) else { return entry }
        if letterboxd != nil, item.type == "movie" { enqueue(item, provider: .letterboxd, includeReviews: includeReviews) }
        // Posters need critic scores too, to fill either missing preferred source. Each provider uses its own cache.
        if omdb != nil, ["movie", "series"].contains(item.type) {
            enqueue(item, provider: .omdb, includeReviews: includeReviews)
        }
        if tmdb != nil, ["movie", "series"].contains(item.type) {
            enqueue(item, provider: .tmdb, includeReviews: includeReviews)
        }
        return entry
    }

    /// Called after the user saves or removes credentials. Old requests finish cancelling before the clients change.
    public func setReviewServices(omdb: OMDbRatings? = nil, tmdb: TMDbRatings?, refreshCache: Bool = false) async {
        await cancelLookups()
        self.omdb = omdb
        self.tmdb = tmdb
        ignoresCachedFreshness = refreshCache
        omdbPausedUntil = nil
        omdbError = nil
        reviewServiceIssue = nil
        for entry in entries.values {
            if omdb == nil {
                entry.rottenTomatoes = nil
                entry.metacritic = nil
            }
            if tmdb == nil {
                entry.tmdb = nil
                entry.tmdbURL = nil
            }
        }
        isClearing = false
        reviewServicesRevision += 1
    }

    /// Recheck visible titles, including old empty answers and failed requests. Keep good scores on screen and on disk.
    public func refresh() async {
        await cancelLookups()
        ignoresCachedFreshness = true
        omdbPausedUntil = nil
        omdbError = nil
        reviewServiceIssue = nil
        isClearing = false
        reviewServicesRevision += 1
    }

    /// Cancel before clearing, so an old answer cannot restore cleared data.
    public func forgetAll() async {
        await cancelLookups()
        await cache.clear()
        for entry in entries.values {
            entry.imdb = entry.catalogIMDb
            entry.letterboxd = nil
            entry.rottenTomatoes = nil
            entry.metacritic = nil
            entry.tmdb = nil
            entry.tmdbURL = nil
        }
        omdbPausedUntil = nil
        omdbError = nil
        reviewServiceIssue = nil
        isClearing = false
        reviewServicesRevision += 1
    }

    private func cancelLookups() async {
        isClearing = true
        queue.removeAll()
        let pending = Array(tasks.values)
        let pendingEpisodes = Array(episodeTasks.values)
        for task in pending { task.cancel() }
        for task in pendingEpisodes { task.cancel() }
        for task in pending { await task.value }
        for task in pendingEpisodes { _ = await task.value }
        queued.removeAll()
        episodeTasks.removeAll()
        nextLookupAt.removeAll()
    }

    private func enqueue(_ item: MetaPreview, provider: Provider, includeReviews: Bool) {
        let lookup = Lookup(item: item, provider: provider, includeReviews: includeReviews)
        if includeReviews, let index = queue.firstIndex(where: { $0.id == lookup.id }) {
            queue[index].includeReviews = true
            Task { startLookups() }
            return
        }
        guard nextLookupAt[lookup.id].map({ now() >= $0 }) ?? true, queued.insert(lookup.id).inserted else { return }
        queue.append(lookup)
        Task { startLookups() }
    }

    private func startLookups() {
        guard !isClearing else { return }
        while tasks.count < maxConcurrentLookups, let index = queue.firstIndex(where: { isEnabled || $0.includeReviews }) {
            let lookup = queue.remove(at: index)
            tasks[lookup.id] = Task { [self] in
                defer { tasks[lookup.id] = nil; queued.remove(lookup.id); startLookups() }
                do {
                    let cached = await cache.value(for: lookup.cacheKey)
                    guard !Task.isCancelled else { return }
                    if let cached {
                        apply(cached, lookup: lookup)
                        let expires = cached.fetchedAt.addingTimeInterval(cacheLifetime(cached, provider: lookup.provider))
                        if !ignoresCachedFreshness, now() < expires {
                            nextLookupAt[lookup.id] = expires
                            return
                        }
                    }
                    let answer: CachedRating
                    switch lookup.provider {
                    case .letterboxd:
                        guard let letterboxd else { return }
                        answer = CachedRating(rating: try await letterboxd.rating(imdbID: lookup.item.id), fetchedAt: now())
                    case .omdb:
                        guard let omdb, !isOMDbPaused else {
                            nextLookupAt[lookup.id] = omdbPausedUntil
                            return
                        }
                        answer = CachedRating(rating: nil, fetchedAt: now(), reviews: try await omdb.ratings(imdbID: lookup.item.id))
                    case .tmdb:
                        guard let tmdb else { return }
                        answer = CachedRating(rating: nil, fetchedAt: now(),
                                              reviews: try await tmdb.ratings(imdbID: lookup.item.id, type: lookup.item.type))
                    }
                    guard !Task.isCancelled else { return }
                    await cache.store(answer, for: lookup.cacheKey)
                    guard !Task.isCancelled else { return }
                    nextLookupAt[lookup.id] = answer.fetchedAt.addingTimeInterval(cacheLifetime(answer, provider: lookup.provider))
                    apply(answer, lookup: lookup)
                    if lookup.provider == .omdb, !isOMDbPaused { omdbError = nil }
                    if lookup.provider == .tmdb { reviewServiceIssue = nil }
                } catch {
                    guard !Task.isCancelled else { return }
                    nextLookupAt[lookup.id] = now().addingTimeInterval(60)
                    if lookup.provider == .omdb { pauseOMDbIfRefused(error) }
                    let mapped = AddonError.from(error)
                    logger.log(.warning, "\(lookup.provider.rawValue) lookup failed for \(lookup.item.identity): \(mapped.shortDescription)")
                    if lookup.provider == .tmdb { reviewServiceIssue = Self.issueText(for: mapped) }
                }
            }
        }
    }

    /// Full-resolution portrait and landscape artwork for the featured carousel, independent of poster rating visibility.
    public func heroArtwork(for item: MetaPreview) async -> TMDbArtwork? {
        guard let tmdb, !isClearing else { return nil }
        return try? await tmdb.artwork(imdbID: item.id, type: item.type)
    }

    /// TMDb scores fill episodes that have no rating from their addon.
    public func episodeRatings(seriesIMDbID: String, season: Int) async -> [Int: Double] {
        guard let tmdb, !isClearing else { return [:] }
        do {
            let scores = try await tmdb.seasonEpisodeRatings(seriesIMDbID: seriesIMDbID, season: season)
            guard !Task.isCancelled else { return [:] }
            reviewServiceIssue = nil
            return scores
        } catch {
            guard !Task.isCancelled else { return [:] }
            let mapped = AddonError.from(error)
            logger.log(.warning, "TMDb episode lookup for season \(season) failed: \(mapped.shortDescription)")
            reviewServiceIssue = Self.issueText(for: mapped)
            return [:]
        }
    }

    static func issueText(for error: AddonError) -> String {
        switch error {
        case .http(status: 401), .http(status: 403): "TMDb refused the Read Access Token. Check it in Settings."
        case .http(status: 429): "TMDb rate limit reached. Scores will return later."
        case .offline, .network, .timeout: "TMDb could not be reached."
        default: "TMDb lookup failed: \(error.shortDescription)."
        }
    }

    /// IMDb scores of one season's episodes, by episode number. New requests need an OMDb key; cached scores work offline.
    /// Seasons refresh daily (hourly when empty). A season asked for twice at once is fetched once.
    public func episodeRatings(for seriesID: String, season: Int) async -> [Int: Double] {
        guard !isClearing, LetterboxdRatings.isIMDbID(seriesID), season >= 0 else { return [:] }
        let key = "omdb:\(seriesID):s\(season)"
        if let running = episodeTasks[key] { return await running.value }
        let task = Task<[Int: Double], Never> { [self] in
            let cached = await cache.value(for: key)
            guard !Task.isCancelled else { return [:] }
            let previous = cached?.episodes ?? [:]
            if let until = nextLookupAt[key], now() < until { return previous }
            if let cached, !ignoresCachedFreshness,
               now().timeIntervalSince(cached.fetchedAt) < (previous.isEmpty ? 3_600 : 86_400) {
                return previous
            }
            guard let omdb, !isOMDbPaused else { return previous }
            do {
                let scores = try await omdb.episodeRatings(imdbID: seriesID, season: season)
                guard !Task.isCancelled else { return [:] }
                await cache.store(CachedRating(rating: nil, fetchedAt: now(), episodes: scores), for: key)
                guard !Task.isCancelled else { return [:] }
                nextLookupAt[key] = now().addingTimeInterval(scores.isEmpty ? 3_600 : 86_400)
                if !isOMDbPaused { omdbError = nil }
                return scores
            } catch {
                if !Task.isCancelled {
                    nextLookupAt[key] = now().addingTimeInterval(60)
                    pauseOMDbIfRefused(error)
                }
                return previous
            }
        }
        episodeTasks[key] = task
        let scores = await task.value
        if episodeTasks[key] == task { episodeTasks[key] = nil }
        return scores
    }

    private var isOMDbPaused: Bool { omdbPausedUntil.map { now() < $0 } ?? false }

    /// A rejected key or an exhausted quota will fail the same way for every other title, so stop asking for an hour.
    private func pauseOMDbIfRefused(_ error: Error) {
        switch error {
        case AddonError.http(401): omdbError = "OMDb rejected the API key. Check the key and save it again."
        case AddonError.http(429): omdbError = "OMDb's request limit was reached. Try again later."
        default: omdbError = "IMDb ratings couldn't load. Check your connection, then try Refresh Ratings."
        }
        guard case AddonError.http(let status) = error, status == 401 || status == 429 else { return }
        omdbPausedUntil = now().addingTimeInterval(3600)
    }

    private func cacheLifetime(_ cached: CachedRating, provider: Provider) -> TimeInterval {
        let hasScore: Bool
        switch provider {
        case .letterboxd: hasScore = cached.rating != nil
        case .omdb: hasScore = cached.reviews?.imdb != nil
        case .tmdb: hasScore = cached.reviews?.tmdb != nil
        }
        return hasScore ? 7 * 86_400 : 3_600
    }

    private func apply(_ cached: CachedRating, lookup: Lookup) {
        guard let entry = entries[lookup.item.identity] else { return }
        switch lookup.provider {
        case .letterboxd:
            if let rating = cached.rating { entry.letterboxd = rating }
        case .omdb:
            if entry.catalogIMDb == nil, let rating = cached.reviews?.imdb { entry.imdb = rating }
            if let rating = cached.reviews?.rottenTomatoes { entry.rottenTomatoes = rating }
            if let rating = cached.reviews?.metacritic { entry.metacritic = rating }
        case .tmdb:
            if let rating = cached.reviews?.tmdb { entry.tmdb = rating }
            if let url = cached.reviews?.tmdbURL { entry.tmdbURL = url }
        }
    }

    private enum Provider: String { case letterboxd, omdb, tmdb }
    private struct Lookup {
        let item: MetaPreview
        let provider: Provider
        var includeReviews: Bool
        var id: String { "\(provider.rawValue):\(item.identity)" }
        var cacheKey: String {
            switch provider {
            case .letterboxd: item.id
            case .omdb: "omdb:\(item.id)"
            case .tmdb: "tmdb:\(item.identity)"
            }
        }
    }
}
