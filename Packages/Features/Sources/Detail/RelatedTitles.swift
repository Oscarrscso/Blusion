import Foundation
import StremioKit

extension TMDbRelatedTitle {
    /// The release year. Nil when the date is missing or has no year in it.
    public var year: Int? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        return Int(releaseDate.prefix(4))
    }

    /// The title a related card opens: the existing title page, looked up by its TMDb id.
    var titleDestination: TMDbTitleDestination {
        TMDbTitleDestination(tmdbID: tmdbID, mediaType: mediaType, name: title, poster: poster, backdrop: backdrop, year: year)
    }

    /// The title as the shared media cards draw it.
    public var preview: MetaPreview {
        MetaPreview(id: "tmdb:\(mediaType):\(tmdbID)", type: mediaType == "movie" ? "movie" : "series", name: title,
                    poster: poster, background: backdrop, releaseInfo: year.map(String.init), genres: genres)
    }

    /// The title as a card with its resolved IMDb id.
    public func preview(imdbID: String) -> MetaPreview {
        let synopsis = overview?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MetaPreview(id: imdbID, type: mediaType == "movie" ? "movie" : "series", name: title,
                           poster: poster, background: backdrop, description: synopsis?.isEmpty == false ? synopsis : nil,
                           releaseInfo: year.map(String.init), genres: genres)
    }
}
