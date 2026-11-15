import Foundation
import Observation
import StremioKit

extension PosterRatingsStore {
    /// TMDb scores fill episodes that have no rating from their addon.
    func episodeRatings(seriesIMDbID: String, season: Int) async -> [Int: Double] {
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

    /// IMDb scores from the local dataset using OMDb's episode IDs, with OMDb's scores filling gaps.
    /// One network request per season; complete seasons refresh daily, partial/empty ones hourly. Cached identities work offline.
    func episodeRatings(for seriesID: String, season: Int, expectedEpisodes: Set<Int> = []) async -> [Int: Double] {
        guard !isClearing, LetterboxdRatings.isIMDbID(seriesID), season >= 0 else { return [:] }
        let key = "omdb:\(seriesID):s\(season)"
        if let running = episodeTasks[key] { return await running.value }
        let task = Task<[Int: Double], Never> { [self] in
            let cached = await cache.value(for: key)
            guard !Task.isCancelled else { return [:] }
            let previousIDs = cached?.episodeIDs ?? [:]
            let indexedIDs = await localEpisodeIDs(for: seriesID, season: season, key: key)
            let ids = previousIDs.merging(indexedIDs) { _, local in local }
            var carried = cached?.episodes ?? [:]
            for (number, id) in ids where previousIDs[number] != nil && previousIDs[number] != id {
                carried[number] = nil // Never inherit a stale score from a mismatched identity.
            }
            let previous = await resolveEpisodeScores(carried, ids: ids, key: key)
            guard !Task.isCancelled else { return [:] }
            // Stored only for a real change. An old score-only entry keeps its missing IDs when none were found, since that is how
            // `needsIDs` below knows to ask OMDb for them once: writing empty IDs over it marked it upgraded without any.
            if var enriched = cached, enriched.episodes != previous || (!ids.isEmpty && enriched.episodeIDs != ids) {
                enriched.episodes = previous
                if !ids.isEmpty {
                    enriched.episodeIDs = ids
                    enriched.episodeNumbers = (enriched.episodeNumbers ?? []).union(ids.keys)
                }
                await cache.store(enriched, for: key)
            }
            guard !Task.isCancelled else { return [:] }
            if let retry = episodeRetryAfter[key], now() < retry { return previous }
            let knownEpisodes = (cached?.episodeNumbers ?? []).union(ids.keys)
            let expected = expectedEpisodes.isEmpty ? knownEpisodes : expectedEpisodes
            if !indexedIDs.isEmpty && !expected.isEmpty && expected.isSubset(of: Set(previous.keys)) {
                return previous // Fully resolved offline: no OMDb season request required.
            }
            let lifetime = Self.episodeCacheLifetime(scores: previous, knownEpisodes: knownEpisodes, expectedEpisodes: expectedEpisodes)
            let expires = cached?.fetchedAt.addingTimeInterval(lifetime) ?? .distantPast
            // Upgrade old score-only caches once, instead of making this fix wait for their 24-hour expiry.
            let needsIDs = dataset != nil && ids.isEmpty && cached?.episodeIDs == nil
            if !needsIDs, let until = nextLookupAt[key], now() < min(until, expires) { return previous }
            if !needsIDs, !ignoresCachedFreshness, now() < expires {
                return previous
            }
            guard let omdb, omdbAllowsEpisodeRequests else { return previous }
            do {
                let answer = try await omdb.seasonRatings(imdbID: seriesID, season: season)
                guard !Task.isCancelled else { return [:] }
                var retained = previous
                var remoteScores = answer.scores
                for (number, remoteID) in answer.episodeIDs {
                    if let localID = indexedIDs[number], localID != remoteID {
                        // Never assign OMDb's score for a different episode to the authoritative offline IMDb ID.
                        retained[number] = nil
                        remoteScores[number] = nil
                    } else if let previousID = previousIDs[number], previousID != remoteID {
                        retained[number] = nil
                    }
                }
                let mergedIDs = answer.episodeIDs.merging(ids) { _, local in local }
                let scores = await resolveEpisodeScores(retained.merging(remoteScores) { _, new in new }, ids: mergedIDs, key: key)
                guard !Task.isCancelled else { return [:] }
                let numbers = (cached?.episodeNumbers ?? []).union(answer.episodeNumbers)
                let fetchedAt = now()
                await cache.store(CachedRating(rating: nil, fetchedAt: fetchedAt, episodes: scores,
                                               episodeIDs: mergedIDs, episodeNumbers: numbers.union(mergedIDs.keys)), for: key)
                guard !Task.isCancelled else { return [:] }
                episodeRetryAfter[key] = nil
                nextLookupAt[key] = fetchedAt.addingTimeInterval(Self.episodeCacheLifetime(scores: scores, knownEpisodes: numbers,
                                                                                          expectedEpisodes: expectedEpisodes))
                if !isOMDbPaused { omdbError = nil }
                // The request that used up the allowance: cards ask again, and TMDb fills in from now on.
                if omdb.usage.today() >= OMDbUsage.dailyLimit { reviewServicesRevision += 1 }
                return scores
            } catch {
                if !Task.isCancelled {
                    episodeRetryAfter[key] = now().addingTimeInterval(60)
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

    /// Resolve an episode's IMDb title ID from the existing offline index or cached OMDb season.
    func imdbEpisodeID(seriesIMDbID: String, season: Int, episode: Int) async -> String? {
        guard LetterboxdRatings.isIMDbID(seriesIMDbID), season >= 0, episode >= 0 else { return nil }
        let key = "omdb:\(seriesIMDbID):s\(season)"
        let local = await localEpisodeIDs(for: seriesIMDbID, season: season, key: key)
        if let id = local[episode], LetterboxdRatings.isIMDbID(id) { return id }
        let cached = await cache.value(for: key)
        guard let id = cached?.episodeIDs?[episode], LetterboxdRatings.isIMDbID(id) else { return nil }
        return id
    }

    struct EpisodeIndexLookup {
        let generation: Int
        let ids: [Int: String]
    }

    private func localEpisodeIDs(for seriesID: String, season: Int, key: String) async -> [Int: String] {
        guard let dataset else { return [:] }
        if let cached = episodeIndexIDs[key], cached.generation == datasetGeneration { return cached.ids }
        let generation = datasetGeneration
        let ids = await dataset.episodeIDs(for: seriesID, season: season)
        if generation == datasetGeneration {
            episodeIndexIDs[key] = EpisodeIndexLookup(generation: generation, ids: ids)
        }
        return ids
    }

    struct EpisodeDatasetLookup {
        let generation: Int
        let ids: [Int: String]
        let scores: [Int: Double]
    }

    /// Indexed local reads, once per season and dataset generation. No per-episode network requests.
    private func resolveEpisodeScores(_ scores: [Int: Double], ids: [Int: String], key: String) async -> [Int: Double] {
        guard let dataset, !ids.isEmpty else { return scores }
        if let found = episodeDatasetScores[key], found.generation == datasetGeneration, found.ids == ids {
            return scores.merging(found.scores) { _, local in local }
        }
        let generation = datasetGeneration
        var local: [Int: Double] = [:]
        for (number, id) in ids {
            guard !Task.isCancelled else { return scores }
            if let rating = await dataset.rating(for: id), rating.rating.isFinite, rating.rating > 0, rating.rating <= 10 {
                local[number] = rating.rating
            }
        }
        guard !Task.isCancelled else { return scores }
        if generation == datasetGeneration { episodeDatasetScores[key] = EpisodeDatasetLookup(generation: generation, ids: ids, scores: local) }
        return scores.merging(local) { _, local in local }
    }

    private static func episodeCacheLifetime(scores: [Int: Double], knownEpisodes: Set<Int>, expectedEpisodes: Set<Int>) -> TimeInterval {
        let expected = expectedEpisodes.isEmpty ? knownEpisodes : expectedEpisodes
        return scores.isEmpty || !expected.isSubset(of: Set(scores.keys)) ? 3_600 : 86_400
    }

    /// Whether OMDb can still be asked for episode scores: there is a key, OMDb has not refused it (401 or the 429 quota pause) and today's
    /// requests from this device are under the daily limit. TMDb fills gaps after IMDb has been checked.
    var omdbAllowsEpisodeRequests: Bool {
        guard let omdb else { return false }
        return !isOMDbPaused && omdb.usage.today() < OMDbUsage.dailyLimit
    }

    var isOMDbPaused: Bool { omdbPausedUntil.map { now() < $0 } ?? false }

    /// A rejected key or an exhausted quota will fail the same way for every other title, so stop asking for an hour.
    func pauseOMDbIfRefused(_ error: Error) {
        switch error {
        case AddonError.http(401): omdbError = "OMDb rejected the API key. Check the key and save it again."
        case AddonError.http(429): omdbError = "OMDb's request limit was reached. Try again later."
        default: omdbError = "IMDb ratings couldn't load. Check your connection, then try Refresh Ratings."
        }
        guard case AddonError.http(let status) = error, status == 401 || status == 429 else { return }
        omdbPausedUntil = now().addingTimeInterval(3600)
        // Episode cards ask again, now that TMDb may fill their scores.
        reviewServicesRevision += 1
    }
}
