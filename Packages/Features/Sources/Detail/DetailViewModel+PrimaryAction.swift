import Foundation
import Observation
import PlayerKit
import StremioKit

extension DetailViewModel {
    /// Picks Shuffle's first episode and looks up its streams once the Play button's lookup has every answer, so the two never ask the
    /// addons at once, and the first tap of Shuffle starts at once. Coming back to the page looks the same episode up again.
    func prepareShuffle() {
        guard !hasTakenShuffle, prefetchedShuffleRequest == nil else { return }
        if shuffleNext == nil { shuffleNext = randomEpisode(avoiding: nextUp) }
        guard let video = shuffleNext else { return }
        let request = request(for: video)
        prefetchedShuffleRequest = request
        let play = prefetchedStreamRequest
        let streams = services.streams
        shuffleLookup = Task {
            if let play { await streams.waitForPrefetch(play) }
            guard !Task.isCancelled else { return }
            await streams.prefetch(request)
        }
    }

    /// Shuffle's episode for this tap: the one picked ahead, else a new pick. The next one is picked at once and named beside the button;
    /// only the first is looked up ahead, so later taps load as Play does.
    func takeShuffle() -> Video? {
        guard let video = shuffleNext ?? randomEpisode(avoiding: nil) else { return nil }
        hasTakenShuffle = true
        shuffleNext = randomEpisode(avoiding: video)
        return video
    }

    /// A random episode that has aired, other than `avoiding` when there is another to pick.
    private func randomEpisode(avoiding: Video?) -> Video? {
        let aired = detail.episodesCountingAsWatched()
        let others = aired.filter { $0.id != avoiding?.id }
        return (others.isEmpty ? aired : others).randomElement()
    }

    /// Series: resume the latest session, or move on from its completed episode before considering older unfinished ones.
    func findNextUp() -> Video? {
        guard isSeries else { return nil }
        let ordered = watchingOrder
        // Moving on never rolls from the regular seasons into specials (as `nextVideo` doesn't); a special that was started resumes.
        let regular = ordered.filter { $0.season != 0 }
        if let latest = ordered.filter({ savedProgress[episodeIdentity($0)] != nil }).max(by: { lastUpdate($0) < lastUpdate($1) }),
           watchedIdentities.contains(episodeIdentity(latest)), let index = regular.firstIndex(where: { $0.id == latest.id }),
           let next = regular.dropFirst(index + 1).first(where: { !watchedIdentities.contains(episodeIdentity($0)) }) {
            return next
        }
        let unfinished = ordered.filter { isUnfinished(episodeIdentity($0)) }
        if let latest = unfinished.max(by: { lastUpdate($0) < lastUpdate($1) }) { return latest }
        // A show of specials alone has only those to offer.
        let offered = regular.isEmpty ? ordered : regular
        return offered.first(where: { !watchedIdentities.contains(episodeIdentity($0)) }) ?? offered.first
    }

    /// "Resume" also means continuing a series at its next unstarted episode after earlier episodes were watched.
    /// An unaired next episode gives its air date instead (see `unairedAirLabel`).
    var primaryActionTitle: String {
        guard isSeries else { return progressFractions[movieIdentity] == nil ? "Play" : "Resume" }
        guard let next = nextUp else { return "Play" }
        if let airs = unairedAirLabel { return airs }
        let verb = progressFractions[episodeIdentity(next)] != nil || continuesSeries ? "Resume" : "Play"
        guard let season = next.season, let episode = next.episode else { return verb }
        return "\(verb) S\(season) · E\(episode)"
    }

    /// Minutes left on the title Play will resume, for Play's second line on a partly watched page. Nil when there is no resumable
    /// progress with a known length.
    var primaryRemainingTimeLabel: String? {
        let identity: String?
        if isSeries, let next = nextUp {
            identity = episodeIdentity(next)
        } else if !isSeries {
            identity = movieIdentity
        } else {
            identity = nil
        }
        guard let identity, let record = savedProgress[identity], progressFractions[identity] != nil,
              record.duration > 0, record.position.isFinite, record.duration.isFinite else { return nil }
        let minutes = max(1, ((record.duration - record.position) / 60).rounded(.up))
        return "\(minutes.formatted(.number.precision(.fractionLength(0))))m left"
    }

    /// What the main action plays: a movie itself, or a series' next episode once it has aired. Nil while a series' episodes are still
    /// arriving, and while the next episode has not aired: nothing is played then, and the button shows `unairedAirLabel` instead.
    var primaryRequest: StreamRequest? {
        guard isSeries else { return movieRequest }
        guard let next = nextUp, next.hasAired() else { return nil }
        return request(for: next)
    }

    /// The main action's label while a series' next episode has not aired yet: its air date, e.g. "Airs Oct 20, 2026". Nil otherwise.
    var unairedAirLabel: String? {
        guard let next = nextUp, !next.hasAired(), let airDate = next.airDate else { return nil }
        return "Airs \(airDate.formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: shuffle

    /// Whether Shuffle has an episode to pick: a series whose episodes have arrived, with at least one aired.
    var canShuffle: Bool {
        // Eligibility needs one aired regular episode, not every season sorted and every air date parsed.
        let now = Date()
        return isSeries && detail.videos.contains { ($0.season.map { $0 > 0 } ?? true) && $0.hasAired(by: now) }
    }

    /// Shuffle's pick: a random episode that has aired, from the episodes "watched" covers, so specials stay out. An episode that has not
    /// aired is never picked, as it is never the next one. Nil for a movie and when `canShuffle` is false.
    func shuffledRequest(now: Date = Date()) -> StreamRequest? {
        guard isSeries else { return nil }
        return detail.episodesCountingAsWatched(by: now).randomElement().map { request(for: $0) }
    }
}
