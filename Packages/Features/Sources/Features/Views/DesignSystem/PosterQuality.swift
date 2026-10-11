import Foundation
import StremioKit

/// The smallest poster of a title, for cards that draw it small, and the larger poster a hero shows while its picture loads. Metahub's
/// posters are the English ones and come in three sizes; TMDb's come in several. This only rewrites the URL: no request is made, and a URL
/// it does not know is returned as it came.
enum PosterQuality {
    /// TMDb's poster sizes are w92, w154, w185, w342, w500, w780 and original. w92 is too soft on a 3x phone, so w154 is the floor.
    static let tmdbSize = "w154"
    static let metahubSize = "small"
    /// The size a hero shows while its picture loads: two TMDb steps above the floor, and Metahub's next size up.
    static let placeholderTMDbSize = "w342"
    static let placeholderMetahubSize = "medium"

    /// `url` at the smallest usable poster size. Only poster URLs change; a background, a logo or an unknown host is returned as it is.
    static func smallest(_ url: URL?) -> URL? {
        resized(url, tmdbSize: tmdbSize, metahubSize: metahubSize)
    }

    /// `url` at the size a hero shows while its picture loads, sharp enough to read before the picture arrives. Only poster URLs change.
    static func placeholder(_ url: URL?) -> URL? {
        resized(url, tmdbSize: placeholderTMDbSize, metahubSize: placeholderMetahubSize)
    }

    /// `url` with its size rewritten for the host it comes from. A host or path it does not know is left alone.
    private static func resized(_ url: URL?, tmdbSize: String, metahubSize: String) -> URL? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return url }
        var parts = components.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        switch host {
        case "images.metahub.space":
            // /poster/<size>/<id>/img
            guard parts.count == 5, parts[0].isEmpty, parts[1] == "poster", parts[4] == "img" else { return url }
            parts[2] = metahubSize
        case "image.tmdb.org":
            // /t/p/<size>/<file>
            guard parts.count == 5, parts[0].isEmpty, parts[1] == "t", parts[2] == "p" else { return url }
            parts[3] = tmdbSize
        default:
            return url
        }
        components.path = parts.joined(separator: "/")
        return components.url ?? url
    }

    /// The poster a card shows for `item`: its own, or Metahub's for its IMDb id, at the smallest size.
    static func poster(for item: MetaPreview) -> URL? {
        smallest(item.poster ?? MetahubArtwork.poster(imdbID: item.id))
    }
}
