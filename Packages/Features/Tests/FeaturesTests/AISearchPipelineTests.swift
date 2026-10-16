import Foundation
import Testing
import StremioKit
@testable import Features

@MainActor
@Suite struct AISearchPipelineTests {
    private actor Calls {
        var plans = 0
        var ranks = 0
        var queries: [TMDbDiscoverQuery] = []
        var updates: [AISearchUpdate] = []
        func plan() { plans += 1 }
        func rank() { ranks += 1 }
        func query(_ value: TMDbDiscoverQuery) { queries.append(value) }
        func update(_ value: AISearchUpdate) { updates.append(value) }
    }

    private struct Interpreter: DescriptionInterpreting {
        let answer: AISearchPlan
        let calls: Calls
        func interpret(_ text: String) async -> DescribedSearch { answer.filters }
        func plan(_ text: String) async -> AISearchPlan { await calls.plan(); return answer }
    }

    private struct Ranker: CandidateRanking {
        let calls: Calls
        var rejectAll = false
        func rank(request: String, references: [String], candidates: [String], watched: [String]) async throws -> [RankedCandidate] {
            await calls.rank()
            if rejectAll { return [] }
            return candidates.indices.map { RankedCandidate(number: $0 + 1, reason: "Matches the supplied evidence") }
        }
    }

    @Test(arguments: ["90s comedy", "80s horror", "2000s sci-fi", "drama before 2010"])
    func explicitFiltersUseDatabaseFactsInsteadOfRejectingPlots(_ request: String) async {
        let calls = Calls()
        let filters = DescribedSearch.reading(request)
        let service = DescribedSearchService(interpreter: Interpreter(answer: AISearchPlan(filters: filters), calls: calls),
            keywords: { _ in [] }, titles: { query in
                await calls.query(query)
                return (1...12).map { number in
                    MetaPreview(id: "tt\(query.kind.rawValue)\(number)", type: query.kind == .movie ? "movie" : "series",
                                name: "Title \(number)", releaseInfo: String(filters.earliestYear ?? 2000))
                }
            }, ranker: Ranker(calls: calls, rejectAll: true))
        let results = await service.titles(for: request) { await calls.update($0) }
        #expect(results.count == 24, "a database-filter request has no arbitrary eight-pick limit or synopsis requirement")
        #expect(await calls.plans == 1, "every query still invokes AI interpretation")
        #expect(await calls.ranks == 0, "plot inference cannot discard correct genre/year matches")
        let queries = await calls.queries
        #expect(queries.count == 2)
        #expect(Set(queries.map(\.kind)) == [.movie, .series])
        #expect(queries.allSatisfy { $0.releasedTo == "\(filters.latestYear!)-12-31" })
        #expect(await calls.updates.contains { !$0.items.isEmpty && $0.stage != .complete })
    }

    private actor Gate {
        private var open = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            if open { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { open = true; continuation?.resume(); continuation = nil }
    }

    private struct WaitingInterpreter: DescriptionInterpreting {
        let gate: Gate
        func interpret(_ text: String) async -> DescribedSearch { .reading(text) }
        func plan(_ text: String) async -> AISearchPlan {
            await gate.wait()
            return AISearchPlan(filters: .reading(text))
        }
    }

    @Test func firstFilterBatchAppearsBeforeTheModelOrNextPageFinishes() async {
        let gate = Gate()
        let calls = Calls()
        let service = DescribedSearchService(interpreter: WaitingInterpreter(gate: gate), keywords: { _ in [] }, titles: { _ in [] },
            pageTitles: { query, skip in
                await calls.query(query)
                guard skip < 12 else { return [] }
                return (skip..<(skip + 6)).map {
                    MetaPreview(id: "tt\(query.kind.rawValue)\($0)", type: query.kind == .movie ? "movie" : "series",
                                name: "Title \($0)", releaseInfo: "1995")
                }
            })
        // This can finish only if a partial result releases the model, rather than waiting for the model first.
        let items = await service.titles(for: "90s comedy") { update in
            await calls.update(update)
            if !update.items.isEmpty { await gate.release() }
        }
        let snapshots = await calls.updates.filter { !$0.items.isEmpty }.map(\.items)
        #expect(snapshots.first?.count == 6)
        #expect(items.count == 24)
        for pair in zip(snapshots, snapshots.dropFirst()) {
            #expect(pair.1.starts(with: pair.0), "later batches append without replacing or shuffling visible cards")
        }
    }

    @Test func semanticSearchPublishesEveryRankedBatchAndKeepsMoreThanEightMatches() async {
        let calls = Calls()
        let plan = AISearchPlan(filters: DescribedSearch(kind: .movie, genres: ["Crime"], moods: ["paranoia"]))
        let service = DescribedSearchService(interpreter: Interpreter(answer: plan, calls: calls), keywords: { _ in [] }, titles: { _ in
            (1...18).map { MetaPreview(id: "tt\($0)", type: "movie", name: "Title \($0)", description: "A paranoid investigation.") }
        }, ranker: Ranker(calls: calls))
        let items = await service.titles(for: "tense crime films about paranoia") { await calls.update($0) }
        let sizes = await calls.updates.map { $0.items.count }
        #expect(items.count == 18)
        #expect(sizes.contains(6) && sizes.contains(12) && sizes.contains(18))
        #expect(await calls.ranks == 3)
    }

    @Test func metadataOnlyCastSearchUsesVerifiedCreditsWithoutNeedingASynopsis() async {
        let calls = Calls()
        let person = AISearchPlan.Person(name: "Requested Actor", role: .cast)
        let plan = AISearchPlan(filters: DescribedSearch(kind: .movie), people: [person], requiresSemanticRanking: false)
        let movie = MetaPreview(id: "tt1", type: "movie", name: "A Film Without a Synopsis")
        let service = DescribedSearchService(interpreter: Interpreter(answer: plan, calls: calls), keywords: { _ in [] }, titles: { query in
            await calls.query(query); return []
        }, ranker: Ranker(calls: calls, rejectAll: true), peopleTitles: { people in
            #expect(people == [person])
            return [AISearchCandidate(item: movie, evidence: "cast: Requested Actor")]
        })
        #expect(await service.titles(for: "movies starring Requested Actor") == [movie])
        #expect(await calls.ranks == 0)
        #expect(await calls.queries.isEmpty)
    }

    @Test func languageStudioAndExclusionsReachBothDatabaseQueries() async {
        let calls = Calls()
        let plan = AISearchPlan(filters: DescribedSearch(genres: ["Animation"], excludedGenres: ["Horror"]),
                                companies: ["A Studio"], language: "ja", excludedTopics: ["revenge"], requiresSemanticRanking: false)
        let service = DescribedSearchService(interpreter: Interpreter(answer: plan, calls: calls), keywords: { _ in
            [.init(id: 55, name: "revenge")]
        }, titles: { query in await calls.query(query); return [] }, companies: { _ in [.init(id: 9, name: "A Studio")] })
        _ = await service.titles(for: "Japanese animation from A Studio without horror or revenge")
        let queries = await calls.queries
        #expect(queries.count == 2)
        #expect(queries.allSatisfy { $0.language == "ja" && $0.companies.map(\.id) == [9] && $0.excludedKeywords.map(\.id) == [55] })
        #expect(queries.first?.excludedGenres.map(\.id) == [27])
    }

    @Test func aReferenceTitleUsesRelatedTitlesAndNeverReturnsTheReferenceItself() async {
        let calls = Calls()
        let seed = MetaPreview(id: "tt1", type: "movie", name: "Reference")
        let match = MetaPreview(id: "tt2", type: "movie", name: "Match", description: "A tense investigation.")
        let plan = AISearchPlan(filters: DescribedSearch(), referenceTitles: ["Reference"])
        let service = DescribedSearchService(interpreter: Interpreter(answer: plan, calls: calls), keywords: { _ in [] },
            titles: { _ in [] }, ranker: Ranker(calls: calls), titleMatches: { _ in [seed] }, related: { _ in [seed, match] })
        #expect(await service.titles(for: "something like Reference") == [match])
    }

    @Test func explicitUnwatchedRequestExcludesHistoryBeforeRanking() async {
        let calls = Calls()
        let plan = AISearchPlan(filters: DescribedSearch(kind: .movie, genres: ["Drama"]), unwatchedOnly: true)
        let service = DescribedSearchService(interpreter: Interpreter(answer: plan, calls: calls), keywords: { _ in [] }, titles: { _ in
            [MetaPreview(id: "tt1", type: "movie", name: "Seen"), MetaPreview(id: "tt2", type: "movie", name: "New")]
        }, ranker: Ranker(calls: calls), watched: { ["movie/tt1"] })
        #expect(await service.titles(for: "dramas I haven't watched").map(\.name) == ["New"])
    }

    @Test func partialResultsStayVisibleWhileLaterWorkRunsAndCannotReturnAfterClearing() async throws {
        let gate = Gate()
        let calls = Calls()
        let item = MetaPreview(id: "tt1", type: "movie", name: "A Comedy", releaseInfo: "1995")
        let service = DescribedSearchService(interpreter: Interpreter(answer: AISearchPlan(filters: .reading("90s comedy")), calls: calls),
            keywords: { _ in [] }, titles: { _ in [] }, pageTitles: { query, _ in
                if query.kind == .movie { return [item] }
                await gate.wait() // Deliberately ignores cancellation like a slow network/cache callback.
                return []
            })
        let client = AddonClient()
        let services = AppServices(registry: AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client),
                                   client: client)
        let model = SearchViewModel(services: services, debounce: .milliseconds(1), describer: service, usesLivePicker: false)
        model.query = "90s comedy"
        model.queryDidChange()
        try await waitUntil { model.describedItems == [item] }
        #expect(model.aiPhase == .searching)
        model.query = ""
        model.queryDidChange()
        await gate.release()
        await model.waitUntilDone()
        #expect(model.describedItems.isEmpty && model.aiPhase == .idle)
    }

    @Test func aCombinedPersonRequestChecksGenreLanguageAndScoreToo() async throws {
        let calls = Calls()
        let data = Data(#"{"title":"Wrong Genre","imdb_id":"tt1","original_language":"en","genres":[{"name":"Horror"}],"vote_average":5,"vote_count":10}"#.utf8)
        let metadata = try #require(try TMDbSearchMetadata.parse(data, mediaType: "movie"))
        let plan = AISearchPlan(filters: DescribedSearch(kind: .movie, genres: ["Comedy"], minimumScore: 7),
                                people: [.init(name: "Requested Actor", role: .cast)], language: "fr", requiresSemanticRanking: false)
        let service = DescribedSearchService(interpreter: Interpreter(answer: plan, calls: calls), keywords: { _ in [] },
            titles: { _ in [] }, peopleTitles: { _ in [AISearchCandidate(item: metadata.item, evidence: "cast: Requested Actor", metadata: metadata)] })
        #expect(await service.titles(for: "highly rated French comedies starring Requested Actor").isEmpty)
    }
}
