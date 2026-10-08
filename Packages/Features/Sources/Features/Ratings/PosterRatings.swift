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

    nonisolated init(id: String, imdb: Double? = nil, letterboxd: Double? = nil) {
        self.id = id
        self._imdb = imdb
        self._letterboxd = letterboxd
    }

    public var imdbText: String? { imdb.map { String(format: "%.1f", $0) } }
    public var letterboxdText: String? { letterboxd.map { String(format: "%.1f", $0 * 2) } }
    public var isEmpty: Bool { imdb == nil && letterboxd == nil }

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

/// Lazy, bounded lookups. Posters request Letterboxd only; supplemental API lookups run when a title's review row appears.
@MainActor
@Observable
public final class PosterRatingsStore {
    /// Makes a visible review row ask again after credentials change.
    public private(set) var reviewServicesRevision = 0
    public var isEnabled: Bool {
        didSet { if isEnabled { Task { startLookups() } } }
    }

    @ObservationIgnored private var entries: [String: TitleRatings] = [:]
    @ObservationIgnored private var queue: [Lookup] = []
    @ObservationIgnored private var queued: Set<String> = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var retryAfter: [String: Date] = [:]
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

    public nonisolated init(isEnabled: Bool = true, letterboxd: LetterboxdRatings? = nil, cache: (any RatingsCache)? = nil,
                            maxConcurrentLookups: Int = 3, now: @escaping @Sendable () -> Date = { Date() },
                            omdb: OMDbRatings? = nil, tmdb: TMDbRatings? = nil) {
        self._isEnabled = isEnabled
        self.letterboxd = letterboxd
        self.omdb = omdb
        self.tmdb = tmdb
        self.cache = cache ?? InMemoryRatingsCache()
        self.maxConcurrentLookups = max(1, maxConcurrentLookups)
        self.now = now
    }

    /// Returns the same object every time. No observed property changes synchronously when called from a view body.
    public func ratings(for item: MetaPreview, includeReviews: Bool = false) -> TitleRatings {
        let entry: TitleRatings
        if let known = entries[item.identity] {
            entry = known
            if known.imdb == nil, let rating = item.imdbRating {
                Task { if known.imdb == nil { known.imdb = rating } }
            }
        } else {
            entry = TitleRatings(id: item.identity, imdb: item.imdbRating)
            entries[item.identity] = entry
        }
        guard !isClearing, isEnabled || includeReviews, LetterboxdRatings.isIMDbID(item.id) else { return entry }
        if letterboxd != nil, item.type == "movie" { enqueue(item, provider: .letterboxd, includeReviews: includeReviews) }
        // OMDb fills the IMDb score a catalog left out, so a poster asks for it too; the review row also takes its critic scores.
        if omdb != nil, includeReviews || (entry.imdb == nil && item.imdbRating == nil), ["movie", "series"].contains(item.type) {
            enqueue(item, provider: .omdb, includeReviews: includeReviews)
        }
        if includeReviews, tmdb != nil, ["movie", "series"].contains(item.type) {
            enqueue(item, provider: .tmdb, includeReviews: true)
        }
        return entry
    }

    /// Called after the user saves or removes credentials. Old requests finish cancelling before the clients change.
    public func setReviewServices(omdb: OMDbRatings?, tmdb: TMDbRatings?) async {
        await cancelLookups()
        self.omdb = omdb
        self.tmdb = tmdb
        omdbPausedUntil = nil
        for entry in entries.values {
            entry.rottenTomatoes = nil
            entry.metacritic = nil
            entry.tmdb = nil
            entry.tmdbURL = nil
        }
        isClearing = false
        reviewServicesRevision += 1
    }

    /// Cancel before clearing, so an old answer cannot restore cleared data.
    public func forgetAll() async {
        await cancelLookups()
        await cache.clear()
        for entry in entries.values {
            entry.letterboxd = nil
            entry.rottenTomatoes = nil
            entry.metacritic = nil
            entry.tmdb = nil
            entry.tmdbURL = nil
        }
        isClearing = false
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
        retryAfter.removeAll()
    }

    private func enqueue(_ item: MetaPreview, provider: Provider, includeReviews: Bool) {
        let lookup = Lookup(item: item, provider: provider, includeReviews: includeReviews)
        if provider == .omdb, isOMDbPaused { return }
        if includeReviews, let index = queue.firstIndex(where: { $0.id == lookup.id }) {
            queue[index].includeReviews = true
            Task { startLookups() }
            return
        }
        guard retryAfter[lookup.id].map({ now() >= $0 }) ?? true, queued.insert(lookup.id).inserted else { return }
        queue.append(lookup)
        Task { startLookups() }
    }

    private func startLookups() {
        guard !isClearing else { return }
        while tasks.count < maxConcurrentLookups, let index = queue.firstIndex(where: { isEnabled || $0.includeReviews }) {
            let lookup = queue.remove(at: index)
            tasks[lookup.id] = Task { [self] in
                defer { tasks[lookup.id] = nil; startLookups() }
                do {
                    let cached = await cache.value(for: lookup.cacheKey)
                    guard !Task.isCancelled else { return }
                    if let cached, now().timeIntervalSince(cached.fetchedAt) < (hasAnswer(cached, provider: lookup.provider) ? 21 : 3) * 86_400 {
                        apply(cached, lookup: lookup)
                        return
                    }
                    let answer: CachedRating
                    switch lookup.provider {
                    case .letterboxd:
                        guard let letterboxd else { return }
                        answer = CachedRating(rating: try await letterboxd.rating(imdbID: lookup.item.id), fetchedAt: now())
                    case .omdb:
                        guard let omdb, !isOMDbPaused else {
                            queued.remove(lookup.id)   // asked again once the pause ends
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
                    apply(answer, lookup: lookup)
                } catch {
                    guard !Task.isCancelled else { return }
                    queued.remove(lookup.id)
                    retryAfter[lookup.id] = now().addingTimeInterval(600)
                    if lookup.provider == .omdb { pauseOMDbIfRefused(error) }
                }
            }
        }
    }

    /// IMDb scores of one season's episodes, by episode number, from OMDb. Empty without an OMDb key, for an id that is not an IMDb
    /// one, while OMDb is refusing the key, or when OMDb has nothing for the season. Answers are cached like the others (21 days, or
    /// 3 when empty), and a season asked for twice at once is fetched once.
    public func episodeRatings(for seriesID: String, season: Int) async -> [Int: Double] {
        guard !isClearing, let omdb, !isOMDbPaused, LetterboxdRatings.isIMDbID(seriesID), season >= 0 else { return [:] }
        let key = "omdb:\(seriesID):s\(season)"
        if let running = episodeTasks[key] { return await running.value }
        if let until = retryAfter[key], now() < until { return [:] }
        let task = Task<[Int: Double], Never> { [self] in
            let cached = await cache.value(for: key)
            if let cached, now().timeIntervalSince(cached.fetchedAt) < (cached.episodes?.isEmpty == false ? 21 : 3) * 86_400 {
                return cached.episodes ?? [:]
            }
            do {
                let scores = try await omdb.episodeRatings(imdbID: seriesID, season: season)
                guard !Task.isCancelled else { return [:] }
                await cache.store(CachedRating(rating: nil, fetchedAt: now(), episodes: scores), for: key)
                return scores
            } catch {
                if !Task.isCancelled {
                    retryAfter[key] = now().addingTimeInterval(600)
                    pauseOMDbIfRefused(error)
                }
                return [:]
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
        guard case AddonError.http(let status) = error, status == 401 || status == 429 else { return }
        omdbPausedUntil = now().addingTimeInterval(3600)
    }

    private func hasAnswer(_ cached: CachedRating, provider: Provider) -> Bool {
        provider == .letterboxd ? cached.rating != nil : cached.reviews?.isEmpty == false
    }

    private func apply(_ cached: CachedRating, lookup: Lookup) {
        guard let entry = entries[lookup.item.identity] else { return }
        switch lookup.provider {
        case .letterboxd: entry.letterboxd = cached.rating
        case .omdb:
            if entry.imdb == nil { entry.imdb = cached.reviews?.imdb }
            entry.rottenTomatoes = cached.reviews?.rottenTomatoes
            entry.metacritic = cached.reviews?.metacritic
        case .tmdb:
            entry.tmdb = cached.reviews?.tmdb
            entry.tmdbURL = cached.reviews?.tmdbURL
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
