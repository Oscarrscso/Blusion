import Foundation
import Observation
import PlayerKit
import StremioKit

extension DetailViewModel {
    /// Runs the hero's load, and stops waiting for it after five seconds, so a slow picture never holds the page. The hero carries on.
    private func loadHero(_ hero: @escaping @MainActor @Sendable () async -> Void) async {
        let heroTask = Task { @MainActor in await hero() }
        let timer = Task { try? await Task.sleep(for: .seconds(5)) }
        // Not a task group: one waits for every child before it returns, and awaiting a task's value ignores cancellation, so the
        // group would always wait for the whole hero.
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let first = ResumeOnce(continuation)
                Task { await heroTask.value; first.resume() }
                Task { await timer.value; first.resume() }
            }
        } onCancel: {
            timer.cancel()
        }
    }

    func load(afterHero hero: (@MainActor @Sendable () async -> Void)? = nil,
                     priorityStream: StreamRequest? = nil, prefetchOnOpen: Bool = false) async {
        isLoading = true
        isLoadingReviews = true
        isLoadingCredits = true
        isLoadingRelated = true
        isLoadingFacts = true
        episodeRatingSeasons.removeAll()
        trailerSourcesTask = nil
        // Artwork and metadata load independently, so the page's content never waits for a picture.
        async let artwork: Void = loadArtwork()
        // Essential metadata supplies the right episode and watch progress for stream selection.
        async let playbackSettings = services.settings.load()
        let result = await services.browse.detail(for: preview)
        // A load that was cancelled must not overwrite what the newer load shows.
        guard !Task.isCancelled else { return }
        let settings = await playbackSettings
        matchesEpisodeWidthToText = settings.matchesEpisodeWidthToText
        detail = result.detail
        episodeRequests.removeAll()
        loadRevision += 1
        isFallback = result.isFallback
        if !result.isFallback { services.heroMeta.record(detail.preview, for: preview) }
        // What has been watched is read with the details, so Play and the episodes are right the moment they show: a tap on Play made
        // while the page loaded plays the episode it names.
        await refreshUserState()
        guard !Task.isCancelled else { return }
        // Open at the same episode and season named by Play/Resume.
        if selectedSeason == nil {
            selectedSeason = nextUp?.season ?? detail.seasons.first { $0 > 0 } ?? detail.seasons.first
        }
        isLoading = false
        // The content is usable already. Keep the hero ahead of secondary lookups without holding the page's metadata back.
        await artwork
        guard !Task.isCancelled else { return }
        if let hero, !hasSettledHero { await loadHero(hero) }
        guard !Task.isCancelled else { return }
        // Prime Play's stream lookup before starting any ratings, trailers, credits, or related-title requests.
        // Continue Watching primes its requested episode instead of an unrelated series episode.
        // The lookup runs independently after registration, so it does not block the page on addon responses.
        if prefetchOnOpen {
            await prefetchStreams(for: priorityStream ?? primaryRequest)
            guard !Task.isCancelled else { return }
        }
        hasSettledHero = true
        // Only after hero and stream prefetch do the less urgent enrichment requests start.
        async let reviews: Void = loadReviews()
        async let credits: Void = loadTitleCredits()
        async let related: Void = loadRelatedTitles()
        async let rating: Void = loadCertification()
        async let trailerSources: Void = loadTrailerSources()
        async let facts: Void = loadTitleFacts()
        async let prices: Void = loadTitlePrices()
        await reviews
        await credits
        await related
        await rating
        await trailerSources
        await facts
        await prices
    }

    func refresh() async {
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

    private func loadTitleFacts() async {
        defer { isLoadingFacts = false }
        let settings = await services.settings.load()
        guard let token = settings.tmdbReadToken, !token.isEmpty else { titleFacts = nil; return }
        let tmdb = TMDbRatings(client: services.client, readAccessToken: token)
        let loaded = try? await tmdb.titleFacts(imdbID: preview.id, type: preview.type)
        guard !Task.isCancelled else { return }
        titleFacts = loaded ?? nil
        await loadFranchise(facts: loaded ?? nil, tmdb: tmdb)
    }

    /// The movie's franchise, from the collection its facts name. The movie itself is left out of the shelf.
    private func loadFranchise(facts: TMDbTitleFacts?, tmdb: TMDbRatings) async {
        guard !isSeries, let collectionID = facts?.collectionID else { franchise = nil; return }
        let loaded = try? await tmdb.franchise(collectionID: collectionID)
        guard !Task.isCancelled else { return }
        let others = loaded?.excluding(tmdbID: facts?.tmdbID)
        franchise = others?.parts.isEmpty == false ? others : nil
    }

    private func loadTitleCredits() async {
        defer { isLoadingCredits = false }
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
        defer { isLoadingRelated = false }
        let settings = await services.settings.load()
        guard let token = settings.tmdbReadToken, !token.isEmpty else { relatedTitles = []; return }
        let loaded = try? await TMDbRatings(client: services.client, readAccessToken: token).relatedTitles(imdbID: preview.id, type: preview.type)
        guard !Task.isCancelled else { return }
        relatedTitles = loaded ?? []
    }

    /// Where the title can be watched in the viewer's region. The title page asks only while its Watch Anywhere section is on.
    func loadTitleWatch() async {
        let settings = await services.settings.load()
        guard let token = settings.tmdbReadToken, !token.isEmpty else { titleWatch = nil; return }
        let region = Locale.current.region?.identifier ?? "US"
        let loaded = try? await TMDbRatings(client: services.client, readAccessToken: token)
            .titleWatch(imdbID: preview.id, type: preview.type, region: region)
        guard !Task.isCancelled else { return }
        titleWatch = loaded
        if let loaded { await services.posterRatings.rememberWatch(loaded, imdbID: preview.id, region: region) }
    }

    /// The rent and buy prices in the viewer's region, from JustWatch. Needs no TMDb token.
    private func loadTitlePrices() async {
        let region = Locale.current.region?.identifier ?? "US"
        let loaded = try? await JustWatchPrices(client: services.client)
            .localPrices(id: preview.id, title: detail.preview.name, year: Self.releaseYear(detail.preview.releaseInfo), type: preview.type,
                         country: region)
        guard !Task.isCancelled else { return }
        titlePrices = loaded ?? nil
    }

    /// Sums up the TMDb reviews the page has, once per set of reviews. The page asks once its reviews are in.
    func loadReviewConsensus(using summarizer: (any ReviewSummarizing)? = nil) async {
        let request = UUID()
        reviewSummaryRequest = request
        let sourceReviews = reviews
        let key = ReviewConsensusReader.key(for: sourceReviews)
        let summarizer = summarizer ?? ReviewConsensusReader.available()
        reviewConsensus = summarizer == nil ? nil : ReviewConsensusReader.cache[key]
        reviewSummaryError = nil
        reviewedCount = 0
        isSummarizingReviews = reviewConsensus == nil && summarizer != nil && ReviewConsensusReader.texts(sourceReviews) != nil
        defer { if reviewSummaryRequest == request { isSummarizingReviews = false } }
        let line = await ReviewConsensusReader.line(for: sourceReviews, using: summarizer) { [weak self] scanned, _ in
            Task { @MainActor [weak self] in
                guard let self, self.reviewSummaryRequest == request else { return }
                self.reviewedCount = scanned
            }
        }
        guard !Task.isCancelled, reviewSummaryRequest == request, key == ReviewConsensusReader.key(for: reviews) else { return }
        reviewConsensus = line
        if line == nil && summarizer != nil && !sourceReviews.isEmpty {
            reviewSummaryError = "Could not summarise these reviews on device. Tap to retry."
        }
    }

    private func loadReviews() async {
        defer { isLoadingReviews = false }
        let settings = await services.settings.load()
        guard let token = settings.tmdbReadToken, !token.isEmpty else { reviews = []; return }
        let loaded = try? await TMDbRatings(client: services.client, readAccessToken: token).reviews(imdbID: preview.id, type: preview.type)
        guard !Task.isCancelled else { return }
        let newReviews = loaded ?? []
        if ReviewConsensusReader.key(for: newReviews) != ReviewConsensusReader.key(for: reviews) {
            // Invalidate a visible or in-flight summary if TMDb edits its review text.
            reviewSummaryRequest = UUID()
            reviewConsensus = nil
            isSummarizingReviews = false
            reviewSummaryError = nil
            reviewedCount = 0
        }
        reviews = newReviews
    }

    /// TMDb's videos and the iTunes preview, looked up once per load of the page: a trailer tap and the page's load share the lookup.
    func loadTrailerSources() async {
        if let trailerSourcesTask { return await trailerSourcesTask.value }
        let task = Task { [weak self] in
            guard let self else { return }
            async let videos: Void = self.loadVideos()
            async let preview: Void = self.loadPreview()
            await videos
            await preview
            guard !Task.isCancelled else { return }
            self.hasCheckedTrailerSources = true
        }
        trailerSourcesTask = task
        await task.value
    }

    /// Returns once the details are in, the caller is cancelled, or `deadline` has passed (a page left while it loaded never finishes). A
    /// tap made while the page is still loading waits here, so its button works from the moment it is shown.
    func waitForDetails(deadline: Duration = .seconds(30)) async {
        let end = ContinuousClock.now.advanced(by: deadline)
        while isLoading, !Task.isCancelled, ContinuousClock.now < end {
            try? await Task.sleep(for: .milliseconds(100))
        }
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
}
