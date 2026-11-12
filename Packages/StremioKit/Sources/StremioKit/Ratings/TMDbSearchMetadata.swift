import Foundation

/// Search-only facts. TMDb's audience score must never be stored in MetaPreview.imdbRating.
public struct TMDbSearchMetadata: Sendable {
    public let item: MetaPreview
    public let language: String?
    public let score: Double?
    public let companies: [String]

    public static func parse(_ data: Data, mediaType: String) throws -> TMDbSearchMetadata? {
        let raw: Raw
        do { raw = try JSONDecoder().decode(Raw.self, from: data) } catch { throw AddonError.invalidJSON }
        guard let imdb = raw.imdb_id ?? raw.external_ids?.imdb_id, LetterboxdRatings.isIMDbID(imdb),
              let name = raw.title ?? raw.name else { return nil }
        let runtime = raw.runtime ?? raw.episode_run_time?.first
        let year = (raw.release_date ?? raw.first_air_date).map { String($0.prefix(4)) }
        let item = MetaPreview(id: imdb, type: mediaType == "tv" ? "series" : "movie", name: name,
                               poster: TMDbImage.url(raw.poster_path, size: "w500"),
                               background: TMDbImage.url(raw.backdrop_path, size: "w1280"), description: raw.overview,
                               releaseInfo: year, genres: raw.genres?.map(\.name) ?? [],
                               runtime: runtime.flatMap { $0 > 0 ? "\($0) min" : nil })
        return TMDbSearchMetadata(item: item, language: raw.original_language,
                                  score: (raw.vote_count ?? 0) > 0 ? raw.vote_average : nil,
                                  companies: raw.production_companies?.map(\.name) ?? [])
    }

    private struct Raw: Decodable {
        let title: String?, name: String?, imdb_id: String?, overview: String?
        let external_ids: ExternalIDs?
        let release_date: String?, first_air_date: String?, original_language: String?
        let runtime: Int?, episode_run_time: [Int]?
        let genres: [Named]?, production_companies: [Named]?
        let vote_average: Double?, vote_count: Int?
        let poster_path: String?, backdrop_path: String?
    }
    private struct Named: Decodable { let name: String }
    private struct ExternalIDs: Decodable { let imdb_id: String? }
}

extension TMDbRatings {
    /// One bounded request supplies the IMDb identity and full metadata for a filmography candidate.
    public func searchMetadata(tmdbID: Int, mediaType: String) async throws -> TMDbSearchMetadata? {
        guard tmdbID > 0, ["movie", "tv"].contains(mediaType), credential != nil else { return nil }
        let (url, headers) = try request(path: [mediaType, String(tmdbID)],
                                        query: [URLQueryItem(name: "append_to_response", value: "external_ids")])
        let result = try await client.get(url, headers: headers, limits: FetchLimits(maxBytes: 512 * 1024), timeout: 8)
        return try TMDbSearchMetadata.parse(result.data, mediaType: mediaType)
    }
}

/// What a universal search finds on TMDb: titles and people, kept apart.
public struct TMDbSearchHits: Sendable, Equatable {
    /// Movies and series with IMDb identities, in TMDb's order.
    public var titles: [MetaPreview]
    /// A title's original name where it differs from the one shown, by `MetaPreview.identity`: another name a search may use.
    public var originalNames: [String: String]
    /// Each person once. `roles` holds TMDb's department for them ("Acting", "Directing"), when it gives one.
    public var people: [TMDbTitlePerson]
    /// How many TMDb ratings a title has, by `MetaPreview.identity`: how likely it is to be the one meant.
    public var votes: [String: Int]

    public static let empty = TMDbSearchHits()

    public init(titles: [MetaPreview] = [], originalNames: [String: String] = [:], people: [TMDbTitlePerson] = [],
                votes: [String: Int] = [:]) {
        self.titles = titles
        self.originalNames = originalNames
        self.people = people
        self.votes = votes
    }

    /// The movies and series of a `/search/multi` answer, before their IMDb ids are known, and its people. An entry with no name, an
    /// id of 0 or less, or another media type is skipped. Throws `invalidJSON` when the answer has no `results` list.
    static func parseMulti(_ data: Data) throws -> (media: [(mediaType: String, entry: TMDbDiscoverEntry, originalName: String?)],
                                                     people: [TMDbTitlePerson]) {
        let raw: RawMulti
        do { raw = try JSONDecoder().decode(RawMulti.self, from: data) } catch { throw AddonError.invalidJSON }
        guard let results = raw.results else { throw AddonError.invalidJSON }
        func text(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        var media: [(mediaType: String, entry: TMDbDiscoverEntry, originalName: String?)] = []
        var people: [TMDbTitlePerson] = []
        for hit in results {
            guard let id = hit.id, id > 0, let name = text(hit.title) ?? text(hit.name) else { continue }
            switch hit.media_type {
            case "movie", "tv":
                let entry = TMDbDiscoverEntry(tmdbID: id, title: name, overview: text(hit.overview) ?? "", posterPath: hit.poster_path,
                                              backdropPath: hit.backdrop_path, date: text(hit.release_date) ?? text(hit.first_air_date),
                                              genreIDs: hit.genre_ids ?? [], voteAverage: hit.vote_average, voteCount: hit.vote_count,
                                              originalLanguage: text(hit.original_language))
                media.append((hit.media_type ?? "movie", entry, text(hit.original_title) ?? text(hit.original_name)))
            case "person":
                guard !people.contains(where: { $0.id == id }) else { continue }
                let department = text(hit.known_for_department)
                people.append(TMDbTitlePerson(id: id, name: name, roles: department.map { [$0] } ?? [], isCast: department == "Acting",
                                              profile: TMDbImage.url(hit.profile_path, size: "w342")))
            default:
                continue
            }
        }
        return (media, people)
    }

    private struct RawMulti: Decodable { let results: [RawHit]? }

    private struct RawHit: Decodable {
        let id: Int?
        let media_type: String?
        let title: String?, name: String?, original_title: String?, original_name: String?, overview: String?
        let release_date: String?, first_air_date: String?, original_language: String?
        let poster_path: String?, backdrop_path: String?, profile_path: String?, known_for_department: String?
        let genre_ids: [Int]?
        let vote_average: Double?, vote_count: Int?
    }
}
