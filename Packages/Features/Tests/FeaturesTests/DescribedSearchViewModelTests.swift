import Foundation
import Testing
import StremioKit
@testable import Features

@MainActor
@Suite struct DescribedSearchViewModelTests {
    /// Stands in for the on-device model: answers the same filters for any description.
    private struct StubInterpreter: DescriptionInterpreting {
        let answer: DescribedSearch
        func interpret(_ text: String) async -> DescribedSearch { answer }
    }

    private final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [TMDbDiscoverQuery] = []
        var queries: [TMDbDiscoverQuery] { lock.withLock { stored } }
        func record(_ query: TMDbDiscoverQuery) { lock.withLock { stored.append(query) } }
    }

    private func services() -> AppServices {
        let client = AddonClient(configuration: AddonClientConfiguration(timeout: 5, maxRetries: 0))
        return AppServices(registry: AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client), client: client)
    }

    private let found = [MetaPreview(id: "tt0083658", type: "movie", name: "Blade Runner"), MetaPreview(id: "tt0078748", type: "movie", name: "Alien")]

    private func describer(_ asked: Asked, answer: DescribedSearch) -> DescribedSearchService {
        let found = found
        return DescribedSearchService(interpreter: StubInterpreter(answer: answer), keywords: { mood in
            [TMDbDiscoverQuery.Named(id: mood.count, name: mood)]
        }, titles: { query in
            asked.record(query)
            return found
        })
    }

    @Test func aDescriptionShowsTheTitlesTMDbFindsForItsFilters() async {
        let asked = Asked()
        let answer = DescribedSearch(kind: .movie, genres: ["Science Fiction"], latestYear: 2009, moods: ["dark", "atmospheric"],
                                     minimumScore: 7.5)
        let model = SearchViewModel(services: services(), debounce: .milliseconds(1), describer: describer(asked, answer: answer))
        model.query = "a dark, atmospheric sci-fi film from before 2010 with great reviews"
        model.queryDidChange()
        await model.waitUntilDone()
        #expect(model.describedItems == found, "only titles the service returned are shown")
        let query = asked.queries.last
        #expect(query?.genres.map(\.id) == [878])
        #expect(query?.keywords.map(\.name) == ["dark", "atmospheric"])
        #expect(query?.releasedTo == "2009-12-31" && query?.minimumScore == 7.5)
    }

    private struct PlotRanker: CandidateRanking {
        func rank(request: String, references: [String], candidates: [String], watched: [String]) async throws -> [RankedCandidate] {
            guard candidates.count == 2, candidates[1].contains("Synopsis:") else { return [] }
            return [RankedCandidate(number: 2, reason: "Stronger thematic match"),
                    RankedCandidate(number: 1, reason: "Related")]
        }
    }

    @Test func descriptiveSearchUsesPlotToRerankTmdbResults() async {
        let films = [
            MetaPreview(id: "tt1", type: "movie", name: "First", description: "A space journey."),
            MetaPreview(id: "tt2", type: "movie", name: "Second", description: "An isolated protagonist doubts reality.")
        ]
        let describer = DescribedSearchService(interpreter: StubInterpreter(answer: DescribedSearch(genres: ["Drama"])),
                                               keywords: { _ in [] }, titles: { _ in films }, ranker: PlotRanker())
        let ranked = await describer.titles(for: "films about isolation and paranoia")
        #expect(ranked.map(\.name) == ["Second", "First"])
    }

    @Test func aTitleSearchAsksNothingOfTheDescriber() async {
        let asked = Asked()
        let model = SearchViewModel(services: services(), debounce: .milliseconds(1),
                                    describer: describer(asked, answer: DescribedSearch(genres: ["Drama"])))
        model.query = "Inception"
        model.queryDidChange()
        await model.waitUntilDone()
        #expect(model.describedItems.isEmpty && asked.queries.isEmpty)
    }

    @Test func aDescriptionWithNothingUnderstoodFindsNothing() async {
        let asked = Asked()
        let model = SearchViewModel(services: services(), debounce: .milliseconds(1), describer: describer(asked, answer: DescribedSearch()))
        model.query = "something to watch with my friends tonight"
        model.queryDidChange()
        await model.waitUntilDone()
        #expect(model.describedItems.isEmpty && asked.queries.isEmpty)
    }
}
