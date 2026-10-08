import Foundation

public struct MetaLink: Sendable, Equatable, Hashable, Codable {
    public var name: String
    public var category: String
    public var url: String

    public init(name: String, category: String, url: String) {
        self.name = name
        self.category = category
        self.url = url
    }

    private enum Keys: String, CodingKey { case name, category, url }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        guard let name = container.string(.name) else { throw DroppedItem(reason: "link without name") }
        self.init(name: name, category: container.string(.category) ?? "", url: container.string(.url) ?? "")
    }
}

/// Catalog item: enough to draw a poster and open Detail.
public struct MetaPreview: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: String
    /// Empty when the addon omitted it; `AddonClient.catalog` fills it from the request.
    public var type: String
    public var name: String
    public var poster: URL?
    public var posterShape: String
    public var background: URL?
    public var logo: URL?
    public var description: String?
    /// Year or range as text (`"1999"`, `"2020-"`). Addons also send it as a number.
    public var releaseInfo: String?
    public var imdbRating: Double?
    public var genres: [String]
    public var runtime: String?

    public init(id: String, type: String = "", name: String? = nil, poster: URL? = nil, posterShape: String = "poster",
                background: URL? = nil, logo: URL? = nil, description: String? = nil, releaseInfo: String? = nil,
                imdbRating: Double? = nil, genres: [String] = [], runtime: String? = nil) {
        self.id = id
        self.type = type
        self.name = name ?? id
        self.poster = poster
        self.posterShape = posterShape
        self.background = background
        self.logo = logo
        self.description = description
        self.releaseInfo = releaseInfo
        self.imdbRating = imdbRating
        self.genres = genres
        self.runtime = runtime
    }

    private enum Keys: String, CodingKey {
        case id, type, name, poster, posterShape, background, logo, description, releaseInfo, year, imdbRating, genres, genre, runtime
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        guard let id = container.string(.id) else { throw DroppedItem(reason: "meta without id") }
        var genres = container.stringArray(.genres)
        if genres.isEmpty { genres = container.stringArray(.genre) }
        self.init(id: id,
                  type: container.string(.type) ?? "",
                  name: container.string(.name),
                  poster: container.url(.poster),
                  posterShape: container.string(.posterShape) ?? "poster",
                  background: container.url(.background),
                  logo: container.url(.logo),
                  description: container.string(.description),
                  releaseInfo: container.string(.releaseInfo) ?? container.string(.year),
                  imdbRating: container.double(.imdbRating),
                  genres: genres,
                  runtime: container.string(.runtime))
    }

    /// `type/id`: an id can repeat across types, so this is what tells two items apart.
    public var identity: String { "\(type)/\(id)" }
}

/// An episode (series) of a meta.
public struct Video: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: String
    public var title: String
    public var season: Int?
    public var episode: Int?
    /// Air date as the addon sent it: `released`, or `firstAired` when that is missing.
    public var released: String?
    public var thumbnail: URL?
    public var overview: String?
    /// Episode rating, usually IMDb's (0 to 10).
    public var rating: Double?

    public init(id: String, title: String? = nil, season: Int? = nil, episode: Int? = nil,
                released: String? = nil, thumbnail: URL? = nil, overview: String? = nil, rating: Double? = nil) {
        self.id = id
        self.title = title ?? id
        self.season = season
        self.episode = episode
        self.released = released
        self.thumbnail = thumbnail
        self.overview = overview
        self.rating = rating
    }

    private enum Keys: String, CodingKey {
        case id, title, name, season, episode, number, released, firstAired, thumbnail, overview, description, rating
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        guard let id = container.string(.id) else { throw DroppedItem(reason: "video without id") }
        self.init(id: id,
                  title: container.string(.title) ?? container.string(.name),
                  season: container.int(.season),
                  episode: container.int(.episode) ?? container.int(.number),
                  released: container.string(.released) ?? container.string(.firstAired),
                  thumbnail: container.url(.thumbnail),
                  overview: container.string(.overview) ?? container.string(.description),
                  rating: container.double(.rating))
    }
}

/// A trailer as addons send it: `trailerStreams` entries carry a YouTube id in `ytId`, the older `trailers` entries in `source`.
private struct TrailerEntry: Decodable {
    let ytId: String?
    let source: String?

    private enum Keys: String, CodingKey { case ytId, source }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        ytId = container.string(.ytId)
        source = container.string(.source)
    }
}

/// Full metadata for Detail. Superset of `MetaPreview`.
public struct MetaDetail: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var preview: MetaPreview
    public var released: String?
    public var director: [String]
    public var cast: [String]
    public var writers: [String]
    public var links: [MetaLink]
    public var videos: [Video]
    public var defaultVideoID: String?
    /// YouTube ids of the trailers, in the addon's order.
    public var trailers: [String]

    public var id: String { preview.id }
    public var type: String { preview.type }
    public var name: String { preview.name }

    public init(preview: MetaPreview, released: String? = nil, director: [String] = [], cast: [String] = [],
                writers: [String] = [], links: [MetaLink] = [], videos: [Video] = [], defaultVideoID: String? = nil,
                trailers: [String] = []) {
        self.preview = preview
        self.released = released
        self.director = director
        self.cast = cast
        self.writers = writers
        self.links = links
        self.videos = videos
        self.defaultVideoID = defaultVideoID
        self.trailers = trailers
    }

    private enum Keys: String, CodingKey { case released, director, cast, writer, writers, links, videos, behaviorHints, trailerStreams, trailers }
    private enum HintKeys: String, CodingKey { case defaultVideoId }

    public init(from decoder: Decoder) throws {
        let preview = try MetaPreview(from: decoder)
        let container = try decoder.container(keyedBy: Keys.self)
        var hint: String?
        if container.contains(.behaviorHints), let hints = try? container.nestedContainer(keyedBy: HintKeys.self, forKey: .behaviorHints) {
            hint = hints.string(.defaultVideoId)
        }
        var writers = container.stringArray(.writers)
        if writers.isEmpty { writers = container.stringArray(.writer) }
        self.init(preview: preview,
                  released: container.string(.released),
                  director: container.stringArray(.director),
                  cast: container.stringArray(.cast),
                  writers: writers,
                  links: container.lossyArray(.links),
                  videos: container.lossyArray(.videos),
                  defaultVideoID: hint,
                  trailers: Self.trailerIDs(streams: container.lossyArray(.trailerStreams), legacy: container.lossyArray(.trailers)))
    }

    /// `trailerStreams[].ytId`, or `trailers[].source` when that yields nothing. Empty and repeated ids are dropped.
    private static func trailerIDs(streams: [TrailerEntry], legacy: [TrailerEntry]) -> [String] {
        let fromStreams = uniqueIDs(streams.map(\.ytId))
        return fromStreams.isEmpty ? uniqueIDs(legacy.map(\.source)) : fromStreams
    }

    private static func uniqueIDs(_ values: [String?]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { $0 }.filter { seen.insert($0).inserted }
    }

    /// Episodes grouped by season, ascending; specials (season 0) last, as most UIs show them.
    public var seasons: [Int] {
        let all = Set(videos.compactMap(\.season))
        return all.filter { $0 > 0 }.sorted() + (all.contains(0) ? [0] : [])
    }

    public func episodes(inSeason season: Int) -> [Video] {
        videos.filter { $0.season == season }.sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
    }

    /// The episode after `video` in watching order: season by season, specials (season 0) only after the last regular season.
    public func nextVideo(after video: Video) -> Video? {
        let ordered = seasons.flatMap { episodes(inSeason: $0) }
        guard let index = ordered.firstIndex(where: { $0.id == video.id }), index + 1 < ordered.count else { return nil }
        let next = ordered[index + 1]
        // Don't roll from a regular season into specials automatically.
        if (video.season ?? 0) > 0, next.season == 0 { return nil }
        return next
    }

    /// Fills fields the addon's `meta` left out with what the catalog preview already showed (so Detail never loses its poster).
    public func filling(from preview: MetaPreview) -> MetaDetail {
        var copy = self
        copy.preview.poster = copy.preview.poster ?? preview.poster
        copy.preview.background = copy.preview.background ?? preview.background
        copy.preview.logo = copy.preview.logo ?? preview.logo
        copy.preview.description = copy.preview.description ?? preview.description
        copy.preview.releaseInfo = copy.preview.releaseInfo ?? preview.releaseInfo
        copy.preview.imdbRating = copy.preview.imdbRating ?? preview.imdbRating
        if copy.preview.genres.isEmpty { copy.preview.genres = preview.genres }
        if copy.preview.type.isEmpty { copy.preview.type = preview.type }
        return copy
    }

    /// Detail built from a catalog preview when the addon's `meta` request fails.
    public static func fallback(from preview: MetaPreview) -> MetaDetail { MetaDetail(preview: preview) }
}

// MARK: - Encodable (flat, so a round trip yields the same value)

extension MetaDetail {
    private enum EncodeKeys: String, CodingKey {
        case id, type, name, poster, posterShape, background, logo, description, releaseInfo, imdbRating, genres, runtime
        case released, director, cast, writers, links, videos, behaviorHints, trailerStreams
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: EncodeKeys.self)
        try container.encode(preview.id, forKey: .id)
        try container.encode(preview.type, forKey: .type)
        try container.encode(preview.name, forKey: .name)
        try container.encodeIfPresent(preview.poster, forKey: .poster)
        try container.encode(preview.posterShape, forKey: .posterShape)
        try container.encodeIfPresent(preview.background, forKey: .background)
        try container.encodeIfPresent(preview.logo, forKey: .logo)
        try container.encodeIfPresent(preview.description, forKey: .description)
        try container.encodeIfPresent(preview.releaseInfo, forKey: .releaseInfo)
        try container.encodeIfPresent(preview.imdbRating, forKey: .imdbRating)
        try container.encode(preview.genres, forKey: .genres)
        try container.encodeIfPresent(preview.runtime, forKey: .runtime)
        try container.encodeIfPresent(released, forKey: .released)
        try container.encode(director, forKey: .director)
        try container.encode(cast, forKey: .cast)
        try container.encode(writers, forKey: .writers)
        try container.encode(links, forKey: .links)
        try container.encode(videos, forKey: .videos)
        try container.encode(trailers.map { ["ytId": $0] }, forKey: .trailerStreams)
        if let defaultVideoID { try container.encode(["defaultVideoId": defaultVideoID], forKey: .behaviorHints) }
    }
}
