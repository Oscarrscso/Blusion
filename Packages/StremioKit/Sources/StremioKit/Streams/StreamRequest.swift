import Foundation

/// What the user wants to watch: enough to ask addons for streams and to label the player.
public struct StreamRequest: Sendable, Hashable, Codable {
    public var type: String
    /// Protocol id: `tt1234567`, or `tt1234567:1:2` for an episode.
    public var id: String
    public var title: String
    public var poster: URL?
    public var season: Int?
    public var episode: Int?
    /// For episodes: the next episode in watching order, so the player can offer it (and binge-continue) at the end.
    public var nextID: String?
    public var nextTitle: String?
    public var nextSeason: Int?
    public var nextEpisode: Int?

    public init(type: String, id: String, title: String, poster: URL? = nil, season: Int? = nil, episode: Int? = nil,
                nextID: String? = nil, nextTitle: String? = nil, nextSeason: Int? = nil, nextEpisode: Int? = nil) {
        self.type = type
        self.id = id
        self.title = title
        self.poster = poster
        self.season = season
        self.episode = episode
        self.nextID = nextID
        self.nextTitle = nextTitle
        self.nextSeason = nextSeason
        self.nextEpisode = nextEpisode
    }

    /// The request for the next episode, if the current one has a successor.
    public var nextRequest: StreamRequest? {
        guard let nextID, let nextTitle else { return nil }
        return StreamRequest(type: type, id: nextID, title: nextTitle, poster: poster, season: nextSeason, episode: nextEpisode)
    }

    /// Unique per piece of content (an id alone can repeat across types).
    public var identity: String { "\(type)/\(id)" }

    public init(movie preview: MetaPreview) {
        self.init(type: preview.type.isEmpty ? "movie" : preview.type, id: preview.id, title: preview.name, poster: preview.poster)
    }

    public init(episode video: Video, of series: MetaDetail) {
        let next = series.nextVideo(after: video)
        self.init(type: series.type.isEmpty ? "series" : series.type, id: video.id,
                  title: "\(series.name) · \(video.title)", poster: series.preview.poster, season: video.season, episode: video.episode,
                  nextID: next?.id, nextTitle: next.map { "\(series.name) · \($0.title)" }, nextSeason: next?.season, nextEpisode: next?.episode)
    }
}
