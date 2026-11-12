import Foundation
import Testing
import StremioKit
import StremioKitTestSupport
@testable import Features

/// Search's one relevance, spelling and de-duplication.
@Suite struct SearchRelevanceTests {
    private func movie(_ id: String, _ name: String, _ year: String? = nil, type: String = "movie", poster: URL? = nil) -> MetaPreview {
        MetaPreview(id: id, type: type, name: name, poster: poster, releaseInfo: year)
    }

    @Test func aCloserNameAlwaysScoresHigher() {
        #expect(SearchResults.relevance("Dune", query: "dune") == 1000)
        #expect(SearchResults.relevance("Amélie", query: "amelie") == 1000, "accents and case are no difference")
        #expect(SearchResults.relevance("The Lego Movie", query: "lego movie") == 950, "a leading article aside")
        #expect(SearchResults.relevance("Spider-Man", query: "spiderman") == 900, "punctuation and spacing aside")
        #expect(SearchResults.relevance("Dune: Part Two", query: "dune") == 800)
        #expect(SearchResults.relevance("Blade Runner 2049", query: "runner blade") == 600)
        #expect(SearchResults.relevance("Blade Runner", query: "bla run") == 500, "words still being typed")
        #expect(SearchResults.relevance("Heat", query: "dune") == 0)
    }

    @Test func aMisspellingStillMatchesBelowEveryLiteralMatch() {
        let missing = SearchResults.relevance("Inception", query: "incepton")
        let swapped = SearchResults.relevance("Inception", query: "inecption")
        #expect(missing == 260 && swapped == 260, "a missing letter and two swapped letters are one slip each")
        #expect(missing < SearchResults.literalMatch)
        #expect(SearchResults.relevance("Interstellar", query: "incepton") == 0)
        #expect(SearchResults.relevance("Up", query: "ip") == 0, "a short word must be spelled right")
    }

    @Test func preciseMatchesComeBeforeLooserOnesWhateverOrderTheyCameIn() {
        let items = [movie("tt3", "The Dunes"), movie("tt2", "Dune: Part Two"), movie("tt9", "Popular Film"), movie("tt1", "Dune")]
        let ranked = SearchResults.ranked(items, query: "dune", filter: SearchResultFilter())
        #expect(ranked.map(\.name) == ["Dune", "Dune: Part Two", "The Dunes", "Popular Film"])
        let named = SearchResults.ranked(items, query: "dune", filter: SearchResultFilter(), minimumRelevance: SearchResults.wordMatch)
        #expect(!named.contains { $0.name == "Popular Film" })
    }

    @Test func anOriginalNameAnswersTheWordsToo() {
        let item = movie("tt0245429", "Spirited Away", "2001")
        let other = movie("tt1", "Away We Go")
        let ranked = SearchResults.ranked([other, item], query: "sen to chihiro", filter: SearchResultFilter(),
                                          aliases: [item.identity: "Sen to Chihiro no Kamikakushi"])
        #expect(ranked.first == item)
    }

    @Test func theSameTitleFromTwoSourcesIsOneCardWithTheAddonsIdentity() throws {
        let poster = try #require(URL(string: "https://image.tmdb.org/t/p/w500/dune.jpg"))
        let merged = SearchResults.merged([
            movie("tmdb:movie:438631", "Dune", "2021", poster: poster),
            movie("tt1160419", "Dune", "2021"),
            movie("tt0087182", "Dune", "1984"),
            movie("tt0142032", "Dune", "2021", type: "series"),
            movie("tt1160419", "Dune"),
        ])
        #expect(merged.map(\.identity) == ["movie/tt1160419", "movie/tt0087182", "series/tt0142032"],
                "the remake and the series stay apart")
        #expect(merged.first?.poster == poster, "the playable identity keeps what only the other entry knew")
        #expect(merged.first?.releaseInfo == "2021")
    }

    @Test func aCorrectionIsOfferedOnlyWhenNothingMatchesTheWordsAsTyped() {
        #expect(SearchResults.correction(for: "incepton", among: ["Interstellar", "Inception"]) == "Inception")
        #expect(SearchResults.correction(for: "dune", among: ["Dune", "Dunes"]) == nil, "a valid search is never corrected")
        #expect(SearchResults.correction(for: "incepton", among: ["Inception", "Incepton"]) == nil)
        #expect(SearchResults.correction(for: "heat", among: ["Inception"]) == nil)
        #expect(SearchResults.isSameName("Christopher Nolen", "Christopher Nolan"))
        #expect(!SearchResults.isSameName("Tom Hanks", "Tom Hardy"))
    }

    @Test func aFilterTakesAnyOfItsGenres() {
        var filter = SearchResultFilter()
        filter.genres = ["Crime", "Horror"]
        #expect(filter.genre == "Crime" && filter.isActive)
        #expect(filter.matches(MetaPreview(id: "tt1", type: "movie", name: "A", genres: ["horror"])))
        #expect(!filter.matches(MetaPreview(id: "tt2", type: "movie", name: "B", genres: ["Comedy"])))
        filter.genre = nil
        #expect(filter.genres.isEmpty && !filter.isActive)
    }
}

/// What a described search is read as asking for without the model: people, services, history, and the chips that show it.
@Suite struct SearchGroundingTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func runsOfWordsThatStateNoFactAreCheckedAsNames() {
        typealias Phrase = AISearchGrounding.PersonPhrase
        #expect(AISearchGrounding.personPhrases(in: "Tom Hanks films from the 90s") == [Phrase(phrase: "tom hanks")])
        #expect(AISearchGrounding.personPhrases(in: "Christopher Nolan directed films") == [Phrase(phrase: "christopher nolan", role: .director)])
        #expect(AISearchGrounding.personPhrases(in: "movies directed by Christopher Nolan") == [Phrase(phrase: "christopher nolan", role: .director)])
        #expect(AISearchGrounding.personPhrases(in: "Brad Pitt and George Clooney movies")
                == [Phrase(phrase: "brad pitt"), Phrase(phrase: "george clooney")])
        #expect(AISearchGrounding.personPhrases(in: "films written by Aaron Sorkin and directed by David Fincher")
                == [Phrase(phrase: "aaron sorkin", role: .writer), Phrase(phrase: "david fincher", role: .director)])
        #expect(AISearchGrounding.personPhrases(in: "movies with Tom Hanks as Forrest Gump")
                == [Phrase(phrase: "tom hanks", character: "forrest gump")])
        #expect(AISearchGrounding.personPhrases(in: "funny heist movies").isEmpty)
    }

    @Test func aNamedPersonLeavesOnlyTheFactsAsRequirements() {
        let plan = AISearchGrounding.plan(ModelReading(cast: ["tom hanks"]), for: "Tom Hanks films from the 90s", now: now)
        #expect(plan.people == [AISearchPlan.Person(name: "tom hanks", role: .cast)])
        #expect(plan.filters.kind == .movie && plan.filters.earliestYear == 1990 && plan.filters.latestYear == 1999)
        #expect(plan.filters.moods.isEmpty && !plan.requiresSemanticRanking, "credits and dates need no synopsis check")
        let directed = AISearchGrounding.plan(ModelReading(directors: ["christopher nolan"]), for: "Christopher Nolan directed films", now: now)
        #expect(directed.filters.moods.isEmpty, "\"directed\" is a credit, never a story topic")
    }

    @Test func aStreamingServiceIsReadFromTheWordsAndReachesTheDatabaseQuery() {
        let plan = AISearchGrounding.plan(ModelReading(), for: "comedies on Netflix", now: now)
        #expect(plan.providers == [.netflix] && plan.filters.genres == ["Comedy"] && plan.filters.kind == nil)
        #expect(plan.filters.moods.isEmpty)
        let queries = plan.queries(keywords: [])
        #expect(!queries.isEmpty && queries.allSatisfy { $0.providers.map(\.id) == [8] })
        #expect(AISearchGrounding.plan(ModelReading(), for: "Disney comedies", now: now).providers.isEmpty, "a studio's name is no service")
        #expect(AISearchGrounding.plan(ModelReading(), for: "comedies on Disney+", now: now).providers == [.disneyPlus])
    }

    @Test func watchedAndUnwatchedAreReadApart() {
        let seen = AISearchGrounding.plan(ModelReading(), for: "comedies I've seen", now: now)
        #expect(seen.watchedOnly && !seen.unwatchedOnly)
        let unseen = AISearchGrounding.plan(ModelReading(), for: "comedies I haven't seen", now: now)
        #expect(unseen.unwatchedOnly && !unseen.watchedOnly)
    }

    @Test func aPlansRequirementsAreChipsThatCanBeChangedOrRemoved() {
        let plan = AISearchPlan(filters: DescribedSearch(kind: .movie, genres: ["Comedy"], earliestYear: 1990, latestYear: 1999,
                                                         moods: ["heist"], maximumRuntime: 120),
                                people: [.init(name: "Tom Hanks", role: .cast)], unwatchedOnly: true)
        #expect(plan.chips.map(\.title) == ["Movies", "Tom Hanks", "Comedy", "1990s", "Under 120 min", "Heist", "Unwatched"])
        let withoutYears = plan.removing(.years)
        #expect(withoutYears.filters.earliestYear == nil && withoutYears.filters.latestYear == nil)
        #expect(withoutYears.filters.genres == ["Comedy"], "nothing else changes")
        let withoutTheme = plan.removing(.theme("heist"))
        #expect(withoutTheme.filters.moods.isEmpty && !withoutTheme.requiresSemanticRanking, "nothing is left for a synopsis to show")
        #expect(plan.removing(.person("Tom Hanks")).people.isEmpty)
        #expect(plan.options(for: .kind).map(\.title) == ["Movies", "Series"])
        #expect(plan.options(for: .kind).last?.plan.filters.kind == .series)
        #expect(plan.options(for: .runtime).first?.plan.filters.maximumRuntime == 90)
        #expect(plan.options(for: .years, now: now).first?.title == "2020s")
        #expect(plan.options(for: .genre("Comedy")).isEmpty, "a genre chip can only be removed")
        #expect(AISearchPlan.yearsTitle(1994, 1994) == "1994" && AISearchPlan.yearsTitle(nil, 2009) == "Until 2009")
    }
}

/// The search pipeline: TMDb titles and people beside the addons, the model kept for descriptions, and chips that do not re-read.
@MainActor
@Suite struct UniversalSearchTests {
    private actor Recorder {
        var plans = 0
        var queries: [TMDbDiscoverQuery] = []
        var people: [AISearchPlan.Person] = []
        var filters: DescribedSearch?
        func plan() { plans += 1 }
        func query(_ value: TMDbDiscoverQuery) { queries.append(value) }
        func asked(_ people: [AISearchPlan.Person], _ filters: DescribedSearch) { self.people = people; self.filters = filters }
    }

    private struct Interpreter: DescriptionInterpreting {
        let recorder: Recorder
        var answer = AISearchPlan(filters: DescribedSearch(), requiresSemanticRanking: false)
        func interpret(_ text: String) async -> DescribedSearch { answer.filters }
        func plan(_ text: String) async -> AISearchPlan { await recorder.plan(); return answer }
    }

    private let dune = MetaPreview(id: "tt1160419", type: "movie", name: "Dune", releaseInfo: "2021")
    private let duneSeries = MetaPreview(id: "tt0142032", type: "series", name: "Dune", releaseInfo: "2000")
    private let hanks = TMDbTitlePerson(id: 31, name: "Tom Hanks", roles: ["Acting"], isCast: true, profile: nil)

    private func emptyServices() -> AppServices {
        let client = AddonClient(configuration: AddonClientConfiguration(timeout: 5, maxRetries: 0))
        return AppServices(registry: AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client), client: client)
    }

    private func addonServices(_ body: String) async throws -> AppServices {
        let manifest = Manifest(id: "a", name: "a", version: "1", resources: [ResourceDescriptor(name: "catalog")], types: ["movie"],
                                catalogs: [CatalogDescriptor(type: "movie", id: "main", extra: [ExtraDescriptor(name: "search")])])
        let (registry, client) = try await makeStubbedRegistry(manifests: [manifest], transport: StubTransport(data: Data(body.utf8)))
        return AppServices(registry: registry, client: client, browse: BrowseService(registry: registry, client: client))
    }

    private var quiet: DescribedSearchService {
        DescribedSearchService(interpreter: KeywordDescriptionInterpreter(), keywords: { _ in [] }, titles: { _ in [] })
    }

    // MARK: The described search

    @Test func aTitleIsNeverReadByTheModel() async {
        let recorder = Recorder()
        let dune = dune
        let service = DescribedSearchService(interpreter: Interpreter(recorder: recorder), keywords: { _ in [] }, titles: { query in
            await recorder.query(query)
            return []
        }, titleMatches: { _ in [dune] })
        #expect(await service.titles(for: "Dune") == [dune])
        #expect(await recorder.plans == 0, "an ordinary title search starts no on-device inference")
        #expect(await recorder.queries.isEmpty, "and lists no popular titles beside the one named")
    }

    @Test func anEditedPlanIsSearchedAsItStandsWithoutReadingTheWordsAgain() async {
        let recorder = Recorder()
        let comedy = MetaPreview(id: "tt1", type: "movie", name: "A Comedy", releaseInfo: "2005", genres: ["Comedy"])
        let service = DescribedSearchService(interpreter: Interpreter(recorder: recorder), keywords: { _ in [] }, titles: { query in
            await recorder.query(query)
            return [comedy]
        })
        let edited = AISearchPlan(filters: DescribedSearch(kind: .movie, genres: ["Comedy"]), requiresSemanticRanking: false)
        #expect(await service.titles(for: "funny 90s movies", plan: edited) == [comedy], "the words' own decade is not applied again")
        #expect(await recorder.plans == 0)
        let queries = await recorder.queries
        #expect(queries.count == 1 && queries.allSatisfy { $0.kind == .movie && $0.genres.map(\.id) == [35] && $0.releasedFrom == nil })
    }

    @Test func aPersonTheModelMissedIsFoundByNameAndAnsweredFromTheirCredits() async {
        let recorder = Recorder()
        let hanks = hanks
        let gump = MetaPreview(id: "tt0109830", type: "movie", name: "Forrest Gump", releaseInfo: "1994")
        let service = DescribedSearchService(interpreter: Interpreter(recorder: recorder), keywords: { _ in [] }, titles: { query in
            await recorder.query(query)
            return []
        }, peopleTitles: { people, filters in
            await recorder.asked(people, filters)
            return [AISearchCandidate(item: gump, evidence: "cast: Tom Hanks")]
        }, people: { name in
            name == "tom hanks" ? [hanks] : []
        })
        #expect(await service.titles(for: "Tom Hanks films from the 90s") == [gump])
        #expect(await recorder.people == [AISearchPlan.Person(name: "Tom Hanks", role: .cast)], "TMDb's own spelling, in the role they are known for")
        let filters = await recorder.filters
        #expect(filters?.kind == .movie && filters?.earliestYear == 1990 && filters?.latestYear == 1999)
        #expect(await recorder.queries.isEmpty, "credits answer the search: no popularity page is asked for")
    }

    @Test func onlyAPartPlayedAsTheCharacterAskedForCounts() {
        #expect(DescribedSearchService.plays("Forrest Gump", "forrest gump"))
        #expect(DescribedSearchService.plays("Captain John Miller", "john miller"))
        #expect(!DescribedSearchService.plays("Woody (voice)", "forrest gump") && !DescribedSearchService.plays(nil, "forrest gump"))
        #expect(DescribedSearchService.plays(nil, nil), "any part when none is asked for")
    }

    // MARK: The screen's search

    @Test func tmdbAnswersTitlesAndPeopleApartEvenWithNoSearchableAddon() async {
        let hanks = hanks
        let film = MetaPreview(id: "tt15398776", type: "movie", name: "Tom Hanks: The Nomad", releaseInfo: "2023")
        let show = MetaPreview(id: "tt0000001", type: "series", name: "Hanks", releaseInfo: "2001")
        let model = SearchViewModel(services: emptyServices(), debounce: .milliseconds(1), describer: quiet, universal: { _ in
            TMDbSearchHits(titles: [film, show], people: [hanks, TMDbTitlePerson(id: 2, name: "Someone Else", roles: [], isCast: false, profile: nil)])
        })
        model.query = "Tom Hanks"
        await model.submit()
        await model.waitUntilDone()
        #expect(model.phase == .done && !model.isDiscovery)
        #expect(model.people == [hanks], "only people whose names answer the words")
        #expect(model.results(in: .all) == [film, show] && model.results(in: .movies) == [film] && model.results(in: .series) == [show])
        #expect(model.results(in: .people).isEmpty, "people are never forced into the titles")
        #expect(model.hasResults && !model.showsNoResults && !model.showsNoSearchableAddons)
    }

    @Test func withoutTMDbOrOfflineTheAddonsResultsStandAlone() async throws {
        let services = try await addonServices(#"{"metas":[{"id":"tt1160419","name":"Dune"}]}"#)
        let sources: [@Sendable (String) async throws -> TMDbSearchHits?] = [{ _ in nil }, { _ in throw AddonError.invalidJSON }]
        for universal in sources {
            let model = SearchViewModel(services: services, debounce: .milliseconds(1), describer: quiet, universal: universal)
            model.query = "Dune"
            await model.submit()
            await model.waitUntilDone()
            #expect(model.results(in: .all).map(\.name) == ["Dune"])
            #expect(model.phase == .done && model.failures.isEmpty && model.people.isEmpty && !model.hasTMDb)
            #expect(model.aiIssue == nil, "a title search says nothing about a missing token")
        }
    }

    @Test func anAddonsTitleAndTMDbsAreOneCardThatKeepsBoth() async throws {
        let services = try await addonServices(#"{"metas":[{"id":"tt1160419","name":"Dune"}]}"#)
        let poster = try #require(URL(string: "https://image.tmdb.org/t/p/w500/dune.jpg"))
        var found = dune
        found.poster = poster
        let hits = TMDbSearchHits(titles: [found, duneSeries])
        let model = SearchViewModel(services: services, debounce: .milliseconds(1), describer: quiet, universal: { _ in hits })
        model.query = "Dune"
        await model.submit()
        await model.waitUntilDone()
        let results = model.results(in: .all)
        #expect(results.map(\.identity) == ["movie/tt1160419", "series/tt0142032"])
        #expect(results.first?.poster == poster)
    }

    @Test func aSlowAnswerForOlderWordsNeverReplacesTheNewerOnes() async throws {
        let dune = dune, duneSeries = duneSeries
        let model = SearchViewModel(services: emptyServices(), debounce: .milliseconds(1), describer: quiet, universal: { text in
            if text == "first" {
                try? await Task.sleep(for: .milliseconds(200))
                return TMDbSearchHits(titles: [dune])
            }
            return TMDbSearchHits(titles: [duneSeries])
        })
        model.query = "first"
        model.queryDidChange()
        try await Task.sleep(for: .milliseconds(60))
        model.query = "second"
        model.queryDidChange()
        await model.waitUntilDone()
        #expect(model.tmdbTitles == [duneSeries])
        try await Task.sleep(for: .milliseconds(250))
        #expect(model.tmdbTitles == [duneSeries], "the cancelled search's answer is dropped when it arrives")
    }

    @Test func suggestionsComeAtOnceFromWhatWasFoundBeforeAndGiveWayToFullResults() async {
        let dune = dune
        let model = SearchViewModel(services: emptyServices(), debounce: .seconds(30), describer: quiet, universal: { _ in
            TMDbSearchHits(titles: [dune])
        })
        model.query = "Dune"
        await model.submit()
        await model.waitUntilDone()
        #expect(!model.showsSuggestions, "a submitted search shows its full results")
        model.query = "du"
        model.queryDidChange()
        #expect(model.showsSuggestions && model.phase == .searching, "the debounce has not asked anyone yet")
        #expect(model.suggestions == [.media(dune)], "the recent search for the same title is that title's row")
        model.query = "funny 90s movies"
        model.queryDidChange()
        #expect(model.suggestions.isEmpty && model.isDiscovery, "a description goes straight to its results")
        model.cancel()
    }

    @Test func removingAChipSearchesTheEditedPlanWithoutInterpretingAgain() async {
        let recorder = Recorder()
        let comedy = MetaPreview(id: "tt1", type: "movie", name: "A Comedy", releaseInfo: "1995", genres: ["Comedy"])
        var interpreter = Interpreter(recorder: recorder)
        interpreter.answer = AISearchPlan(filters: DescribedSearch(kind: .movie, genres: ["Comedy"], earliestYear: 1990, latestYear: 1999),
                                          requiresSemanticRanking: false)
        let service = DescribedSearchService(interpreter: interpreter, keywords: { _ in [] }, titles: { query in
            await recorder.query(query)
            return [comedy]
        })
        let model = SearchViewModel(services: emptyServices(), debounce: .milliseconds(1), describer: service, universal: { _ in nil })
        model.query = "funny 90s movies about friendship"
        await model.submit()
        await model.waitUntilDone()
        #expect(model.isDiscovery && model.describedItems == [comedy])
        #expect(model.chips.map(\.title) == ["Movies", "Comedy", "1990s"])
        #expect(await recorder.queries.last?.releasedFrom == "1990-01-01")
        #expect(await recorder.plans == 1)

        let years = model.chips.first { $0.kind == .years }
        if let years { model.remove(years) }
        #expect(model.aiPhase == .searching)
        await model.waitUntilDone()
        #expect(model.chips.map(\.title) == ["Movies", "Comedy"])
        #expect(await recorder.queries.last?.releasedFrom == nil)
        #expect(await recorder.plans == 1, "changing a chip reads nothing again")
        #expect(model.describedItems == [comedy] && model.results(in: .all) == [comedy])

        // A local filter or sort asks nobody.
        let asked = await recorder.queries.count
        model.filter.sort = .newest
        model.filter.genres = ["Comedy"]
        #expect(model.results(in: .all) == [comedy])
        #expect(await recorder.queries.count == asked && model.aiPhase == .done)
    }

    @Test func theShowPickerSearchesAddonsOnly() async throws {
        let services = try await addonServices(#"{"metas":[{"id":"tt1160419","name":"Dune"}]}"#)
        let model = SearchViewModel(services: services, debounce: .milliseconds(1), includesAISearch: false, universal: { _ in
            Issue.record("Blusion TV's picker never asks TMDb")
            return nil
        })
        model.query = "funny 90s movies"
        await model.submit()
        #expect(model.phase == .done && model.aiPhase == .done && !model.isDiscovery)
        #expect(model.results(in: .series).isEmpty && model.results(in: .all).map(\.name) == ["Dune"])
    }
}
