import Foundation
import StremioKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One title picked for a "what should I watch?" request, with the one-line reason the on-device model gave for it.
public struct WatchPick: Sendable, Equatable, Identifiable {
    public let item: MetaPreview
    public let reason: String
    public var id: String { item.identity }
}

/// What a "what should I watch?" request asks for: the titles it names as a reference ("like Prisoners") and its filters.
public struct WatchWish: Sendable, Equatable {
    public var likeTitles: [String]
    public var search: DescribedSearch

    public init(likeTitles: [String] = [], search: DescribedSearch = DescribedSearch()) {
        self.likeTitles = likeTitles
        self.search = search
    }
}

/// A candidate's number in the list the model was shown (from 1), and why it fits.
public struct RankedCandidate: Sendable, Equatable {
    public let number: Int
    public let reason: String

    public init(number: Int, reason: String) {
        self.number = number
        self.reason = reason
    }
}

/// Reads a request into a wish. Nil when it cannot (no model).
public protocol WishInterpreting: Sendable {
    func interpret(_ text: String) async -> WatchWish?
}

/// Chooses from a numbered list of real candidates, best first, with a reason each.
public protocol CandidateRanking: Sendable {
    /// `references` describes the titles the request names, so "like Prisoners" is read as that film, not as a word.
    func rank(request: String, references: [String], candidates: [String], watched: [String]) async throws -> [RankedCandidate]
}

/// "Something like Prisoners, but less depressing, under two hours": real candidates are gathered first (TMDb's recommendations for the
/// titles the request names, and TMDb's discover list for its filters), the titles already watched are left out, and the on-device model
/// only ranks that list and says why. A pick the model makes outside the list is dropped, so every pick is a real, unwatched title.
public struct WatchPicker: Sendable {
    let interpreter: any WishInterpreting
    let ranker: any CandidateRanking
    /// The title an addon search finds for a name, with its IMDb id. Nil when none.
    let findTitle: @Sendable (String) async -> MetaPreview?
    /// TMDb's recommendations for a title, as titles with IMDb ids.
    let related: @Sendable (MetaPreview) async -> [MetaPreview]
    let discover: @Sendable (TMDbDiscoverQuery) async throws -> [MetaPreview]
    /// Titles watched or started on this device (and through Trakt), as identities and names.
    let watched: @Sendable () async -> [(identity: String, name: String)]

    public init(interpreter: any WishInterpreting, ranker: any CandidateRanking,
                findTitle: @escaping @Sendable (String) async -> MetaPreview?,
                related: @escaping @Sendable (MetaPreview) async -> [MetaPreview],
                discover: @escaping @Sendable (TMDbDiscoverQuery) async throws -> [MetaPreview],
                watched: @escaping @Sendable () async -> [(identity: String, name: String)]) {
        self.interpreter = interpreter
        self.ranker = ranker
        self.findTitle = findTitle
        self.related = related
        self.discover = discover
        self.watched = watched
    }

    static let maxPicks = 8
    static let maxCandidates = 30
    static let maxSeeds = 2

    /// Whether a search asks what to watch: "something like …", "similar to …", "what should I watch", "recommend …".
    public static func readsLikeRequest(_ text: String) -> Bool {
        let text = " " + text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ") + " "
        return [" something like ", " anything like ", " movies like ", " films like ", " shows like ", " series like ",
                " similar to ", " what should i watch ", " what to watch ", " recommend "].contains { text.contains($0) }
    }

    /// The picks for a request, best first. Empty when nothing fits or the model is not there.
    public func picks(for text: String) async -> [WatchPick] {
        guard let wish = await interpreter.interpret(text), !Task.isCancelled else { return [] }
        var seeds: [MetaPreview] = []
        for name in wish.likeTitles.prefix(Self.maxSeeds) {
            if let seed = await findTitle(name), !seeds.contains(where: { $0.identity == seed.identity }) { seeds.append(seed) }
        }
        var search = wish.search
        if search.genres.isEmpty {
            // The named titles' own genres stand in for genres the request does not give.
            var genres: [String] = []
            for genre in seeds.flatMap(\.genres) where !genres.contains(genre) { genres.append(genre) }
            search.genres = Array(genres.prefix(2))
        }
        var pool: [MetaPreview] = []
        /// Which named title TMDb recommended each candidate for, for the reasons given when the model cannot rank.
        var recommendedFor: [String: String] = [:]
        for seed in seeds {
            for item in await related(seed) {
                pool.append(item)
                if recommendedFor[item.identity] == nil { recommendedFor[item.identity] = seed.name }
            }
        }
        if !search.isEmpty || seeds.isEmpty { pool += (try? await discover(search.query(keywords: []))) ?? [] }
        guard !Task.isCancelled else { return [] }
        let seen = await watched()
        let excluded = Set(seeds.map(\.identity) + seen.map(\.identity))
        var candidates: [MetaPreview] = []
        for item in pool where !excluded.contains(item.identity) && !candidates.contains(where: { $0.identity == item.identity })
            && Self.fitsRuntime(item, search) && Self.fitsKindAndYears(item, search) {
            candidates.append(item)
            if candidates.count == Self.maxCandidates { break }
        }
        guard !candidates.isEmpty else { return [] }
        do {
            let ranked = try await ranker.rank(request: text, references: seeds.map(Self.line), candidates: candidates.map(Self.line),
                                               watched: seen.prefix(12).map(\.name))
            return Self.validated(ranked, candidates: candidates)
        } catch {
            // The model refused or failed: the candidates in TMDb's order, each with where it came from, rather than nothing.
            guard !Task.isCancelled else { return [] }
            return candidates.prefix(Self.maxPicks).map { item in
                WatchPick(item: item, reason: recommendedFor[item.identity].map { "TMDb recommends it alongside \($0)." }
                          ?? "On TMDb's list for what you asked.")
            }
        }
    }

    /// False for a title whose known runtime is outside the request's: the model does not weigh runtimes reliably. A title with no known
    /// runtime is kept.
    static func fitsRuntime(_ item: MetaPreview, _ search: DescribedSearch) -> Bool {
        guard let minutes = minutes(item.runtime) else { return true }
        if let longest = search.maximumRuntime, minutes > longest { return false }
        if let shortest = search.minimumRuntime, minutes < shortest { return false }
        return true
    }

    /// False for a title of the other kind, or released outside the request's years when its year is known. TMDb's recommendations are
    /// not filtered by TMDb, so they are checked here.
    static func fitsKindAndYears(_ item: MetaPreview, _ search: DescribedSearch) -> Bool {
        if let kind = search.kind, item.type != (kind == .movie ? "movie" : "series") { return false }
        guard let year = item.releaseInfo.flatMap({ Int($0.prefix(4)) }) else { return true }
        if let earliest = search.earliestYear, year < earliest { return false }
        if let latest = search.latestYear, year > latest { return false }
        return true
    }

    /// "157 min", "2h 37min" or "2 h" as minutes; nil when it says no number.
    static func minutes(_ runtime: String?) -> Int? {
        guard let runtime = runtime?.lowercased() else { return nil }
        let numbers = runtime.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let first = numbers.first else { return nil }
        guard runtime.contains("h") else { return first }
        return first * 60 + (numbers.count > 1 ? numbers[1] : 0)
    }

    /// The picks that name a candidate in the list, once each, with a reason, at most `maxPicks`.
    static func validated(_ ranked: [RankedCandidate], candidates: [MetaPreview]) -> [WatchPick] {
        var picks: [WatchPick] = []
        for entry in ranked {
            let reason = entry.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard candidates.indices.contains(entry.number - 1), !reason.isEmpty else { continue }
            let item = candidates[entry.number - 1]
            guard !picks.contains(where: { $0.item.identity == item.identity }) else { continue }
            picks.append(WatchPick(item: item, reason: reason))
            if picks.count == maxPicks { break }
        }
        return picks
    }

    /// A candidate as the model reads it: "Zodiac (2007), film. Crime, Drama, Mystery. 157 min".
    static func line(_ item: MetaPreview) -> String {
        var parts = [item.releaseInfo.map { "\(item.name) (\($0))" } ?? item.name]
        parts[0] += item.type == "series" ? ", series" : ", film"
        if !item.genres.isEmpty { parts.append(item.genres.prefix(3).joined(separator: ", ")) }
        if let runtime = item.runtime, !runtime.isEmpty { parts.append(runtime) }
        // No plot: the on-device model's safety check refuses some crime films' synopses, and it then answers nothing at all.
        return parts.joined(separator: ". ")
    }

    /// The live picker, or nil where the on-device model is not available: then the request gets no picks row.
    static func live(_ services: AppServices) -> WatchPicker? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *), case .available = SystemLanguageModel.default.availability else { return nil }
        let settings = services.settings
        let client = services.client
        let content = services.widgetContent
        let browse = services.browse
        let progress = services.progress
        return WatchPicker(interpreter: ModelWishInterpreter(), ranker: ModelCandidateRanker(), findTitle: { name in
            for await response in await browse.search(name) {
                if case .success(let items) = response.result,
                   let match = items.first(where: { LetterboxdRatings.isIMDbID($0.id) && $0.name.caseInsensitiveCompare(name) == .orderedSame })
                    ?? items.first(where: { LetterboxdRatings.isIMDbID($0.id) }) {
                    return match
                }
            }
            return nil
        }, related: { seed in
            guard let token = await settings.load().tmdbReadToken else { return [] }
            let tmdb = TMDbRatings(client: client, readAccessToken: token)
            guard let titles = try? await tmdb.relatedTitles(imdbID: seed.id, type: seed.type) else { return [] }
            return await withTaskGroup(of: (Int, MetaPreview?).self) { group in
                for (index, title) in titles.prefix(10).enumerated() {
                    group.addTask {
                        guard let imdb = try? await tmdb.imdbID(tmdbID: title.tmdbID, mediaType: title.mediaType) else { return (index, nil) }
                        return (index, MetaPreview(id: imdb, type: title.mediaType == "tv" ? "series" : "movie", name: title.title,
                                                   poster: title.poster, releaseInfo: title.releaseDate.map { String($0.prefix(4)) }))
                    }
                }
                var found: [(Int, MetaPreview)] = []
                for await (index, item) in group { if let item { found.append((index, item)) } }
                return found.sorted { $0.0 < $1.0 }.map(\.1)
            }
        }, discover: { query in
            try await content.items(for: .tmdbDiscover(query), limit: maxCandidates)
        }, watched: {
            await progress.all().filter { $0.isWatched || $0.position > 0 }.map { entry in
                let id = entry.seriesID ?? entry.contentID
                return (identity: "\(entry.type)/\(id)", name: entry.title)
            }
        })
        #else
        return nil
        #endif
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
struct ModelWishInterpreter: WishInterpreting {
    private static let instructions = """
        You read a request for something to watch. List the titles it names as a reference, and turn the rest into search filters. \
        Only use what the request says or clearly implies.
        """

    func interpret(_ text: String) async -> WatchWish? {
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let answer = try await session.respond(to: text, generating: GeneratedWish.self).content
            let kind: TMDbDiscoverQuery.Kind? = switch answer.kind {
            case .film: .movie
            case .series: .series
            case .either: nil
            }
            let search = DescribedSearch(kind: kind, excludedGenres: answer.excludedGenres, earliestYear: answer.earliestYear,
                                         latestYear: answer.latestYear, minimumScore: answer.minimumScore,
                                         maximumRuntime: answer.maximumRuntime)
            return WatchWish(likeTitles: answer.likeTitles, search: search.correcting(with: .reading(text)))
        } catch {
            return nil
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct ModelCandidateRanker: CandidateRanking {
    private static let instructions = """
        You recommend what to watch. You may only choose from the numbered candidates you are given, by their numbers. Rank first the \
        candidates closest to the titles the request names in genre and tone, then follow the changes the request asks for. Pick at \
        most eight, best first. Give each a short reason of one sentence about its genre, tone or length; never describe a plot.
        """

    func rank(request: String, references: [String], candidates: [String], watched: [String]) async throws -> [RankedCandidate] {
        let list = candidates.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let named = references.isEmpty ? "" : "\nThe titles the request names are: \(references.joined(separator: " | ")).\n"
        let history = watched.isEmpty ? "" : "\nThey have already watched: \(watched.joined(separator: "; ")).\n"
        let prompt = "Request: \(request)\n\(named)\(history)\nCandidates:\n\(list)"
        let session = LanguageModelSession(instructions: Self.instructions)
        let answer = try await session.respond(to: prompt, generating: GeneratedPicks.self).content
        return answer.picks.map { RankedCandidate(number: $0.number, reason: $0.reason) }
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedWish {
    @Guide(description: "Titles the request names as a reference, such as Prisoners in 'something like Prisoners'")
    var likeTitles: [String]
    @Guide(description: "Whether it asks for films, TV series, or does not say")
    var kind: GeneratedKind
    @Guide(description: """
        Genres it rules out, from: Action, Adventure, Animation, Comedy, Crime, Documentary, Drama, Family, Fantasy, History, Horror, \
        Mystery, Romance, Science Fiction, Thriller, War, Western
        """)
    var excludedGenres: [String]
    @Guide(description: "The earliest release year it allows, for words such as after, since or from. After 2000 is 2001")
    var earliestYear: Int?
    @Guide(description: "The latest release year it allows, for words such as before or until. Before 2010 is 2009")
    var latestYear: Int?
    @Guide(description: "The lowest audience score out of 10 it asks for, if it asks for good reviews")
    var minimumScore: Double?
    @Guide(description: "The longest runtime in minutes it allows: under two hours is 120")
    var maximumRuntime: Int?
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedPicks {
    @Guide(description: "The chosen candidates, best first, at most eight")
    var picks: [GeneratedPick]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedPick {
    @Guide(description: "The candidate's number in the list")
    var number: Int
    @Guide(description: "One short sentence on why it fits the request")
    var reason: String
}
#endif
