import Foundation
import Observation
import StremioKit

extension PosterRatingsStore {
    /// The site's kept answer while it is fresh, else a new one, kept and shown; the stale answer when asking fails. Nil when there is
    /// neither, or while the data is being cleared.
    func keptAnswer(for lookup: Lookup, fetch: () async throws -> CachedRating) async -> CachedRating? {
        let cached = await cache.value(for: lookup.cacheKey)
        guard !isClearing else { return nil }
        if let cached {
            apply(cached, lookup: lookup)
            if now() < cached.fetchedAt.addingTimeInterval(cacheLifetime(cached, provider: lookup.provider)) { return cached }
        }
        guard let answer = try? await fetch(), !isClearing else { return cached }
        await cache.store(answer, for: lookup.cacheKey)
        nextLookupAt[lookup.id] = answer.fetchedAt.addingTimeInterval(cacheLifetime(answer, provider: lookup.provider))
        apply(answer, lookup: lookup)
        return answer
    }

    func cancelLookups() async {
        isClearing = true
        queue.removeAll()
        let pending = Array(tasks.values) + Array(cacheTasks.values)
        let pendingEpisodes = Array(episodeTasks.values)
        for task in pending { task.cancel() }
        for task in pendingEpisodes { task.cancel() }
        for task in pending { await task.value }
        for task in pendingEpisodes { _ = await task.value }
        queued.removeAll()
        cacheTasks.removeAll()
        cachePriorities.removeAll()
        episodeTasks.removeAll()
        episodeRetryAfter.removeAll()
        episodeDatasetScores.removeAll()
        episodeIndexIDs.removeAll()
        nextLookupAt.removeAll()
    }

    func enqueue(_ item: MetaPreview, provider: Provider, includeReviews: Bool, forFilter: Bool = false) {
        let lookup = Lookup(item: item, provider: provider, includeReviews: includeReviews, forFilter: forFilter)
        if includeReviews, cacheTasks[lookup.id] != nil { cachePriorities.insert(lookup.id) }
        if includeReviews, let index = queue.firstIndex(where: { $0.id == lookup.id }) {
            var priority = queue.remove(at: index)
            priority.includeReviews = true
            queue.insert(priority, at: 0)
            Task { startLookups() }
            return
        }
        guard nextLookupAt[lookup.id].map({ now() >= $0 }) ?? true, queued.insert(lookup.id).inserted else { return }
        // Cache reads never wait for a network worker slot.
        cacheTasks[lookup.id] = Task { [self] in
            defer { cacheTasks[lookup.id] = nil; cachePriorities.remove(lookup.id) }
            var expires: Date?
            if lookup.provider.isMark {
                // A ratings refresh does not ask bestblurays.com or TMDb again for every title on screen: a fresh mark is kept.
                expires = await readMark(lookup)
            } else if let cached = await cache.value(for: lookup.cacheKey) {
                guard !Task.isCancelled else { return }
                apply(cached, lookup: lookup)
                if !ignoresCachedFreshness { expires = cached.fetchedAt.addingTimeInterval(cacheLifetime(cached, provider: lookup.provider)) }
            }
            guard !Task.isCancelled else { return }
            if let expires, now() < expires {
                nextLookupAt[lookup.id] = expires
                queued.remove(lookup.id)
                return
            }
            var ready = lookup
            ready.includeReviews = includeReviews || cachePriorities.contains(lookup.id)
            if ready.includeReviews { queue.insert(ready, at: 0) } else { queue.append(ready) }
            startLookups()
        }
    }

    func startLookups() {
        guard !isClearing else { return }
        while tasks.count < maxConcurrentLookups, let index = queue.firstIndex(where: canStart) {
            let lookup = queue.remove(at: index)
            tasks[lookup.id] = Task { [self] in
                defer { tasks[lookup.id] = nil; queued.remove(lookup.id); startLookups() }
                do {
                    if lookup.provider.isMark {
                        let expires = try await lookUpMark(lookup)
                        guard !Task.isCancelled else { return }
                        nextLookupAt[lookup.id] = expires ?? now().addingTimeInterval(900)
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
                    case .myAnimeList:
                        guard let myAnimeList else { return }
                        answer = CachedRating(rating: nil, fetchedAt: now(), reviews: try await myAnimeList.ratings(for: lookup.item))
                    case .omdb:
                        // The allowance and any refusal are checked here, off the view's redraw path.
                        guard let omdb, !isOMDbPaused, omdb.usage.today() < OMDbUsage.dailyLimit else { return }
                        answer = CachedRating(rating: nil, fetchedAt: now(), reviews: try await omdb.ratings(imdbID: lookup.item.id))
                    case .bestBlurays, .streaming:
                        return
                    }
                    guard !Task.isCancelled else { return }
                    await cache.store(answer, for: lookup.cacheKey)
                    guard !Task.isCancelled else { return }
                    nextLookupAt[lookup.id] = answer.fetchedAt.addingTimeInterval(cacheLifetime(answer, provider: lookup.provider))
                    apply(answer, lookup: lookup)
                    if lookup.provider == .tmdb { reviewServiceIssue = nil }
                } catch {
                    guard !Task.isCancelled else { return }
                    nextLookupAt[lookup.id] = now().addingTimeInterval(lookup.provider.isMark ? 900 : 60)
                    let mapped = AddonError.from(error)
                    logger.log(.warning, "\(lookup.provider.rawValue) lookup failed for \(lookup.item.identity): \(mapped.shortDescription)")
                    if lookup.provider == .tmdb { reviewServiceIssue = Self.issueText(for: mapped) }
                    if lookup.provider == .omdb { pauseOMDbIfRefused(error) }
                }
            }
        }
    }

    /// Score lookups run while ratings are on or a title page asks. Mark lookups run while marks are on or a screen built on them asks;
    /// disc lookups one film at a time, so bestblurays.com, a community site, is never asked about several films at once.
    private func canStart(_ lookup: Lookup) -> Bool {
        switch lookup.provider {
        case .bestBlurays: (showsBestDisc || lookup.includeReviews) && !tasks.keys.contains { $0.hasPrefix("\(Provider.bestBlurays.rawValue):") }
        case .streaming: showsBestDisc || lookup.includeReviews
        // MyAnimeList is asked about one title at a time, as its search box would be.
        case .myAnimeList: (isEnabled || lookup.includeReviews || lookup.forFilter)
            && !tasks.keys.contains { $0.hasPrefix("\(Provider.myAnimeList.rawValue):") }
        case .letterboxd, .tmdb: isEnabled || lookup.includeReviews || lookup.forFilter
        case .omdb: isEnabled || lookup.includeReviews
        }
    }

    private func cacheLifetime(_ cached: CachedRating, provider: Provider) -> TimeInterval {
        let hasScore: Bool
        switch provider {
        case .letterboxd: hasScore = cached.rating != nil
        // An answer kept before TMDb was asked whether the title is anime is asked again.
        case .tmdb: hasScore = cached.reviews?.tmdb != nil && cached.reviews?.isAnime != nil
        case .myAnimeList: hasScore = cached.reviews?.myAnimeList != nil
        case .omdb: hasScore = cached.reviews?.rottenTomatoes != nil || cached.reviews?.metacritic != nil
        // Marks are kept in the mark store, with their own lifetimes (see `readMark`).
        case .bestBlurays, .streaming: hasScore = false
        }
        return hasScore ? 7 * 86_400 : 3_600
    }
}
