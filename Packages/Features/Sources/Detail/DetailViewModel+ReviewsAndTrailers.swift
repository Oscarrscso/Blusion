import Foundation
import Observation
import PlayerKit
import StremioKit

extension DetailViewModel {
    /// The title's trailers known without a tap, merged and ordered (see `TrailerCatalog`): the iTunes preview first when there is one,
    /// then the addon's direct links; YouTube trailers only when there is no direct file at all.
    var trailers: [Trailer] {
        TrailerCatalog.merge(previews: itunesTrailer.map { [$0] } ?? [], addonYouTubeIDs: detail.trailers, addonURLs: detail.trailerURLs,
                             tmdb: tmdbVideos)
    }

    /// Whether the trailer button can do anything: a trailer is known, or its sources have not all answered yet, so a tap waits for them.
    var canPlayTrailer: Bool { !trailers.isEmpty || !hasCheckedTrailerSources }

    /// A rating's site, shown on the page under the ratings: its reviews for this title, or a search when the site has no page for it.
    struct OpenedReviews: Equatable, Sendable {
        let site: ReviewSite
        let url: URL
        let isSearch: Bool
    }

    /// A rating's tap: shows its site's reviews under the ratings, or closes them when that site's are already open. Another site's reviews
    /// replace the ones open once they have loaded: until then the open site stays on screen. A trailer that is open stays open: the two
    /// sit on the page together, the trailer above the reviews.
    func toggleReviews(_ site: ReviewSite, url: URL, isSearch: Bool) {
        if openedReviews?.site == site || shownReviews?.site == site {
            closeReviews()
            return
        }
        // The site on screen: the open one once it has loaded, or the one still kept while another loaded.
        if let open = openedReviews, !reviewsLoading { shownReviews = open }
        openedReviews = OpenedReviews(site: site, url: url, isSearch: isSearch)
        reviewsLoading = true
        startReviewsTimeout()
    }

    /// Closes the reviews opened from a rating.
    func closeReviews() {
        openedReviews = nil
        shownReviews = nil
        reviewsDidLoad()
    }

    /// The reviews' page has loaded, or failed to: the spinner stops and the reviews open, in place of the site kept on screen meanwhile.
    func reviewsDidLoad() {
        reviewsLoadTimeout?.cancel()
        reviewsLoadTimeout = nil
        reviewsLoading = false
        shownReviews = nil
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

    /// Closes the trailer after the full-screen trailer's X, which gave its own haptic, so the Trailer button stays silent.
    func closeTrailerQuietly() {
        trailerQuietCloses += 1
        trailer.close()
    }

    /// The trailer button's tap: loads the title's trailer into the page, or closes it while it plays. A YouTube video is checked
    /// with YouTube before it is tried in the page's embedded player. Reviews opened from a rating stay open, under the trailer.
    func toggleTrailer() {
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
    func trailerPlan() async -> TrailerPlan {
        // A tap made while the page loads waits for the details and the trailers they lead to, rather than finding none.
        if !hasCheckedTrailerSources {
            await waitForDetails()
            if !Task.isCancelled { await loadTrailerSources() }
        }
        return TrailerPlan(trailers: TrailerCatalog.playbackOrder(previews: itunesTrailer.map { [$0] } ?? [], addonYouTubeIDs: detail.trailers,
                                                          addonURLs: detail.trailerURLs, tmdb: tmdbVideos))
    }
}
