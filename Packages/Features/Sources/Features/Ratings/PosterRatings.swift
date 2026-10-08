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
    /// TMDb's vote average out of 10, once a TMDb lookup has found the title.
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

    /// The score as the review row shows it. Rotten Tomatoes and Metacritic have no score source, so they never have one.
    public func text(for site: ReviewSite) -> String? {
        switch site {
        case .imdb: imdbText.map { "\($0)/10" }
        case .letterboxd: letterboxdText.map { "\($0)/10" }
        case .tmdb: tmdb.map { String(format: "%.1f/10", $0) }
        case .rottenTomatoes, .metacritic: nil
        }
    }
}

/// Lazy, bounded lookups. Posters request Letterboxd only; TMDb lookups run when a title's review row appears.
@MainActor
@Observable
public final class PosterRatingsStore {
    /// Makes a visible review row ask again after credentials change.
    public private(set) var reviewServicesRevision = 0
    /// Why the last TMDb request failed (a refused token, the rate limit, no connection), or nil after a success. The review row
    /// shows it, so a missing score says what went wrong.
    public private(set) var reviewServiceIssue: String?
    public var isEnabled: Bool {
        didSet { if isEnabled { Task { startLookups() } } }
    }

    @ObservationIgnored private var entries: [String: TitleRatings] = [:]
    @ObservationIgnored private var queue: [Lookup] = []
    @ObservationIgnored private var queued: Set<String> = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var retryAfter: [String: Date] = [:]
    @ObservationIgnored private var isClearing = false
    @ObservationIgnored private let letterboxd: LetterboxdRatings?
    @ObservationIgnored private var tmdb: TMDbRatings?
    @ObservationIgnored private let cache: any RatingsCache
    @ObservationIgnored private let maxConcurrentLookups: Int
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let logger: AddonLogger

    public nonisolated init(isEnabled: Bool = true, letterboxd: LetterboxdRatings? = nil, cache: (any RatingsCache)? = nil,
                            maxConcurrentLookups: Int = 3, now: @escaping @Sendable () -> Date = { Date() },
                            tmdb: TMDbRatings? = nil, logger: AddonLogger = .silent) {
        self._isEnabled = isEnabled
        self.letterboxd = letterboxd
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
            if known.imdb == nil, let rating = item.imdbRating {
                Task { if known.imdb == nil { known.imdb = rating } }
            }
        } else {
            entry = TitleRatings(id: item.identity, imdb: item.imdbRating)
            entries[item.identity] = entry
        }
        guard !isClearing, isEnabled || includeReviews, LetterboxdRatings.isIMDbID(item.id) else { return entry }
        if letterboxd != nil, item.type == "movie" { enqueue(item, provider: .letterboxd, includeReviews: includeReviews) }
        if includeReviews, tmdb != nil, ["movie", "series"].contains(item.type) { enqueue(item, provider: .tmdb, includeReviews: true) }
        return entry
    }

    /// Called after the user saves or removes the TMDb credential. Old requests finish cancelling before the client changes.
    public func setReviewServices(tmdb: TMDbRatings?) async {
        await cancelLookups()
        self.tmdb = tmdb
        for entry in entries.values {
            entry.tmdb = nil
            entry.tmdbURL = nil
        }
        reviewServiceIssue = nil
        isClearing = false
        reviewServicesRevision += 1
    }

    /// Cancel before clearing, so an old answer cannot restore cleared data.
    public func forgetAll() async {
        await cancelLookups()
        await cache.clear()
        for entry in entries.values {
            entry.letterboxd = nil
            entry.tmdb = nil
            entry.tmdbURL = nil
        }
        reviewServiceIssue = nil
        isClearing = false
    }

    /// TMDb's per-episode scores for one season of a series, keyed by episode number. Empty without a TMDb credential, when TMDb has
    /// no votes for the season, or when the request fails; a failure is logged and shown through `reviewServiceIssue`.
    public func episodeRatings(seriesIMDbID: String, season: Int) async -> [Int: Double] {
        guard let tmdb, !isClearing else { return [:] }
        do {
            let scores = try await tmdb.seasonEpisodeRatings(seriesIMDbID: seriesIMDbID, season: season)
            reviewServiceIssue = nil
            return scores
        } catch {
            if Task.isCancelled { return [:] }
            let mapped = AddonError.from(error)
            logger.log(.warning, "TMDb episode lookup for season \(season) failed: \(mapped.shortDescription)")
            reviewServiceIssue = Self.issueText(for: mapped)
            return [:]
        }
    }

    private func cancelLookups() async {
        isClearing = true
        queue.removeAll()
        let pending = Array(tasks.values)
        for task in pending { task.cancel() }
        for task in pending { await task.value }
        queued.removeAll()
        retryAfter.removeAll()
    }

    private func enqueue(_ item: MetaPreview, provider: Provider, includeReviews: Bool) {
        let lookup = Lookup(item: item, provider: provider, includeReviews: includeReviews)
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
                    case .tmdb:
                        guard let tmdb else { return }
                        answer = CachedRating(rating: nil, fetchedAt: now(),
                                              reviews: try await tmdb.ratings(imdbID: lookup.item.id, type: lookup.item.type))
                    }
                    guard !Task.isCancelled else { return }
                    await cache.store(answer, for: lookup.cacheKey)
                    guard !Task.isCancelled else { return }
                    if lookup.provider == .tmdb { reviewServiceIssue = nil }
                    apply(answer, lookup: lookup)
                } catch {
                    guard !Task.isCancelled else { return }
                    queued.remove(lookup.id)
                    retryAfter[lookup.id] = now().addingTimeInterval(600)
                    let mapped = AddonError.from(error)
                    logger.log(.warning, "\(lookup.provider.rawValue) lookup failed for \(lookup.item.identity): \(mapped.shortDescription)")
                    if lookup.provider == .tmdb { reviewServiceIssue = Self.issueText(for: mapped) }
                }
            }
        }
    }

    /// The reason a TMDb request failed, in words the review row can show.
    static func issueText(for error: AddonError) -> String {
        switch error {
        case .http(status: 401), .http(status: 403):
            "TMDb refused the Read Access Token. Check it in Settings."
        case .http(status: 429):
            "TMDb rate limit reached. Scores will return later."
        case .offline, .network, .timeout:
            "TMDb could not be reached."
        default:
            "TMDb lookup failed: \(error.shortDescription)."
        }
    }

    private func hasAnswer(_ cached: CachedRating, provider: Provider) -> Bool {
        provider == .letterboxd ? cached.rating != nil : cached.reviews?.isEmpty == false
    }

    private func apply(_ cached: CachedRating, lookup: Lookup) {
        guard let entry = entries[lookup.item.identity] else { return }
        switch lookup.provider {
        case .letterboxd: entry.letterboxd = cached.rating
        case .tmdb:
            entry.tmdb = cached.reviews?.tmdb
            entry.tmdbURL = cached.reviews?.tmdbURL
        }
    }

    private enum Provider: String { case letterboxd, tmdb }
    private struct Lookup {
        let item: MetaPreview
        let provider: Provider
        var includeReviews: Bool
        var id: String { "\(provider.rawValue):\(item.identity)" }
        var cacheKey: String {
            switch provider {
            case .letterboxd: item.id
            case .tmdb: "tmdb:\(item.identity)"
            }
        }
    }
}
