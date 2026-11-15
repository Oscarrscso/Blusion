import Foundation
import PlayerKit
import StremioKit

/// The shows you like, for Blusion TV's own channels: shows saved to the Library and shows watched, scored so that the most-watched and
/// most recently watched come first. Pure, so it can be tested without stores.
struct TVTaste {
    /// The best-liked shows, best first.
    let favourites: [MetaPreview]
    /// Every show saved or watched, by identity, so recommendations can leave them out.
    let known: Set<String>

    init(progress: [WatchProgress], library: [LibraryItem], now: Date = Date(), limit: Int = 15) {
        var scores: [String: Double] = [:]
        var previews: [String: MetaPreview] = [:]
        for record in progress where record.type == "series" && (record.isWatched || record.position > 0) {
            let key = WatchedCards.titleKey(of: record)
            // Each episode counts, half as much for every two months since it was watched.
            let days = max(0, now.timeIntervalSince(record.updatedAt)) / 86400
            scores[key, default: 0] += pow(0.5, days / 60)
            if previews[key] == nil {
                previews[key] = MetaPreview(id: record.seriesID ?? record.contentID, type: "series", name: WatchedCards.name(of: record),
                                            poster: record.poster)
            }
        }
        for item in library where item.type == "series" {
            let preview = item.preview
            scores[preview.identity, default: 0] += 3
            previews[preview.identity] = preview
        }
        known = Set(scores.keys)
        favourites = scores.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(limit).compactMap { previews[$0.key] }
    }

    /// Blusion's channels from the favourites and the shows recommended for them: For You, a channel for each genre at least three of
    /// them share (the best-liked genres first, up to four), and New to You, the recommendations alone. `genres` is each show's,
    /// by identity. Every channel is random and goes on air `onAir`.
    static func channels(favourites: [MetaPreview], picks: [MetaPreview], genres: [String: [String]], onAir: Date) -> [TVChannel] {
        func channel(_ name: String, _ shows: [MetaPreview]) -> TVChannel {
            TVChannel(id: stableID(name), name: name, shows: shows, order: .shuffle, onAir: onAir)
        }
        guard !favourites.isEmpty else { return [] }
        var channels = [channel("For You", Array(favourites.prefix(10)) + Array(picks.prefix(5)))]
        let everything = favourites + picks
        var weights: [String: Double] = [:]
        for (rank, show) in favourites.enumerated() {
            for genre in genres[show.identity] ?? [] { weights[genre, default: 0] += 1 / Double(rank + 1) + 1 }
        }
        var sets = [Set(channels[0].shows.map(\.identity))]
        for genre in weights.keys.sorted(by: { (weights[$0] ?? 0, $1) > (weights[$1] ?? 0, $0) }) where channels.count < 5 {
            let shows = everything.filter { (genres[$0.identity] ?? []).contains(genre) }
            let set = Set(shows.map(\.identity))
            // A genre every channel already covers adds nothing.
            guard shows.count >= 3, !sets.contains(set) else { continue }
            sets.append(set)
            channels.append(channel(genre, Array(shows.prefix(15))))
        }
        if picks.count >= 3 { channels.append(channel("New to You", Array(picks.prefix(12)))) }
        return channels
    }

    /// The same id for a channel name every time, so a channel Blusion makes again keeps its place and its schedule.
    static func stableID(_ name: String) -> UUID {
        let halves = (TVLineup.hash("blusion.tv/\(name)").bigEndian, TVLineup.hash("\(name)/blusion.tv").bigEndian)
        return withUnsafeBytes(of: halves) { UUID(uuid: $0.load(as: uuid_t.self)) }
    }
}
