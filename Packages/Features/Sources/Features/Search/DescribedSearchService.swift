import Foundation
import StremioKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns a search typed as a description into filters: the on-device model where Apple Intelligence is on, else the keyword reader.
public protocol DescriptionInterpreting: Sendable {
    func interpret(_ text: String) async -> DescribedSearch
}

/// The keyword reader (`DescribedSearch.reading`), for a device without the on-device model.
struct KeywordDescriptionInterpreter: DescriptionInterpreting {
    func interpret(_ text: String) async -> DescribedSearch { .reading(text) }
}

/// Finds real titles for a search typed as a description: the description becomes filters, its moods become TMDb keywords, and TMDb's
/// discover list for those filters is the answer. The model only reads the description: every title comes from TMDb.
public struct DescribedSearchService: Sendable {
    let interpreter: any DescriptionInterpreting
    /// TMDb's keywords for a mood, best match first. Empty without a TMDb token.
    let keywords: @Sendable (String) async -> [TMDbDiscoverQuery.Named]
    /// TMDb's titles for a discover query.
    let titles: @Sendable (TMDbDiscoverQuery) async throws -> [MetaPreview]

    public init(interpreter: any DescriptionInterpreting, keywords: @escaping @Sendable (String) async -> [TMDbDiscoverQuery.Named],
                titles: @escaping @Sendable (TMDbDiscoverQuery) async throws -> [MetaPreview]) {
        self.interpreter = interpreter
        self.keywords = keywords
        self.titles = titles
    }

    /// How many titles the description's row holds.
    static let limit = 20

    /// The titles for a description, or none when nothing in it was understood or TMDb has none.
    public func titles(for text: String) async -> [MetaPreview] {
        let search = await interpreter.interpret(text)
        guard !search.isEmpty, !Task.isCancelled else { return [] }
        var found: [TMDbDiscoverQuery.Named] = []
        for mood in search.moods.prefix(DescribedSearch.maxMoods) {
            let matches = await keywords(mood)
            if let match = matches.first(where: { $0.name.caseInsensitiveCompare(mood) == .orderedSame }) ?? matches.first,
               !found.contains(match) {
                found.append(match)
            }
        }
        guard !Task.isCancelled else { return [] }
        return (try? await titles(search.query(keywords: found))) ?? []
    }

    /// The live service: TMDb with the saved token, through the widgets' content service (which caches its answers).
    static func live(_ services: AppServices) -> DescribedSearchService {
        let settings = services.settings
        let client = services.client
        let content = services.widgetContent
        return DescribedSearchService(interpreter: OnDeviceDescriptionInterpreter.availableInterpreter(), keywords: { mood in
            guard let token = await settings.load().tmdbReadToken else { return [] }
            return (try? await TMDbRatings(client: client, readAccessToken: token).searchKeywords(mood)) ?? []
        }, titles: { query in
            try await content.items(for: .tmdbDiscover(query), limit: limit)
        })
    }
}

/// Reads a description with Apple's on-device model. Falls back to the keyword reader when the model is not there or fails.
enum OnDeviceDescriptionInterpreter {
    /// The interpreter for this device: the on-device model when Apple Intelligence is available, else the keyword reader.
    static func availableInterpreter() -> any DescriptionInterpreting {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            return ModelDescriptionInterpreter()
        }
        #endif
        return KeywordDescriptionInterpreter()
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
struct ModelDescriptionInterpreter: DescriptionInterpreting {
    private static let instructions = """
        You turn a person's description of what they want to watch into search filters for a film and TV database. Only use what the \
        description says or clearly implies; leave a filter empty when it says nothing about it. Never name a title.
        """

    func interpret(_ text: String) async -> DescribedSearch {
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let answer = try await session.respond(to: text, generating: GeneratedSearch.self).content
            return answer.described
        } catch {
            return .reading(text)
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedSearch {
    @Guide(description: "Whether the description asks for films, TV series, or does not say")
    var kind: GeneratedKind
    @Guide(description: """
        Genres the description names or clearly implies, from: Action, Adventure, Animation, Comedy, Crime, Documentary, Drama, Family, \
        Fantasy, History, Horror, Mystery, Romance, Science Fiction, Thriller, War, Western
        """)
    var genres: [String]
    @Guide(description: "Genres the description rules out, from the same list")
    var excludedGenres: [String]
    @Guide(description: "The earliest release year it allows, if it gives one")
    var earliestYear: Int?
    @Guide(description: "The latest release year it allows, if it gives one. Before 2010 is 2009")
    var latestYear: Int?
    @Guide(description: "Up to three short mood or theme keywords it names, such as dark, atmospheric or time travel")
    var moods: [String]
    @Guide(description: "The lowest audience score out of 10 it asks for: 7.5 for great reviews, 7 for good reviews, nothing otherwise")
    var minimumScore: Double?
    @Guide(description: "The longest runtime in minutes it allows: under two hours is 120")
    var maximumRuntime: Int?

    var described: DescribedSearch {
        let kind: TMDbDiscoverQuery.Kind? = switch self.kind {
        case .film: .movie
        case .series: .series
        case .either: nil
        }
        return DescribedSearch(kind: kind, genres: genres, excludedGenres: excludedGenres, earliestYear: earliestYear,
                               latestYear: latestYear, moods: Array(moods.prefix(DescribedSearch.maxMoods)),
                               minimumScore: minimumScore, maximumRuntime: maximumRuntime)
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
enum GeneratedKind {
    case film, series, either
}
#endif
