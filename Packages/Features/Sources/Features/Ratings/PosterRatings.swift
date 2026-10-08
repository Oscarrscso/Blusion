import Foundation
import Observation
import StremioKit

/// The ratings shown on one poster. Observable per title, so a rating that arrives late redraws only its own poster.
@MainActor
@Observable
public final class TitleRatings: Identifiable {
    /// `MetaPreview.identity` of the title.
    public nonisolated let id: String
    /// IMDb's rating, 0 to 10. It comes with the catalog item.
    public internal(set) var imdb: Double?
    /// Letterboxd's average, 0 to 5. Looked up in the background; films only.
    public internal(set) var letterboxd: Double?

    nonisolated init(id: String, imdb: Double? = nil, letterboxd: Double? = nil) {
        self.id = id
        self._imdb = imdb
        self._letterboxd = letterboxd
    }

    /// "9.0": one decimal, as IMDb prints it.
    public var imdbText: String? { imdb.map { String(format: "%.1f", $0) } }
    /// "4.5": one decimal, as Letterboxd prints it.
    public var letterboxdText: String? { letterboxd.map { String(format: "%.1f", $0) } }
    public var isEmpty: Bool { imdb == nil && letterboxd == nil }
}

/// Hands out the ratings of titles for poster badges, and fetches what a catalog does not carry.
@MainActor
@Observable
public final class PosterRatingsStore {
    /// The Settings switch "Ratings on posters".
    public var isEnabled: Bool

    /// Not observed: views ask for entries from their bodies, and filling this in must not invalidate them.
    @ObservationIgnored private var entries: [String: TitleRatings] = [:]

    public nonisolated init(isEnabled: Bool = true) {
        self._isEnabled = isEnabled
    }

    /// The ratings of a title. Asking is cheap and can be done from a view's body: the same object comes back every time.
    public func ratings(for item: MetaPreview) -> TitleRatings {
        if let known = entries[item.identity] { return known }
        let entry = TitleRatings(id: item.identity, imdb: item.imdbRating)
        entries[item.identity] = entry
        return entry
    }
}
