import Foundation
import Testing
import StremioKit
import StremioKitTestSupport
@testable import Features

@MainActor
@Suite struct SearchViewModelTests {
    private func manifest(_ id: String, searchable: Bool = true) -> Manifest {
        Manifest(id: id, name: id, version: "1", resources: [ResourceDescriptor(name: "catalog")], types: ["movie"],
                 catalogs: [CatalogDescriptor(type: "movie", id: "main", extra: searchable ? [ExtraDescriptor(name: "search")] : [])])
    }

    /// Answers `{"metas":[{"id":"<host>-<term>"}]}` and counts calls; hosts containing "fail" answer 500; "slow0" waits a bit.
    private func stub() -> StubTransport {
        StubTransport { request, _ in
            let host = request.url?.host ?? ""
            if host.contains("stub2") { try await Task.sleep(for: .milliseconds(150)) }
            if host.contains("stub1") { return StubTransport.response(Data(), status: 500, for: request) }
            let term = request.url?.path.components(separatedBy: "search=").last?.replacingOccurrences(of: ".json", with: "") ?? "?"
            return StubTransport.response(Data(#"{"metas":[{"id":"\#(host)-\#(term)","name":"\#(term)"}]}"#.utf8), for: request)
        }
    }

    private func model(manifests: [Manifest], transport: StubTransport, debounce: Duration = .milliseconds(40)) async throws -> SearchViewModel {
        let (registry, client) = try await makeStubbedRegistry(manifests: manifests, transport: transport)
        return SearchViewModel(services: AppServices(registry: registry, client: client, browse: BrowseService(registry: registry, client: client)), debounce: debounce)
    }

    @Test func typingIsDebouncedIntoOneSearch() async throws {
        let transport = stub()
        let model = try await model(manifests: [manifest("a")], transport: transport, debounce: .milliseconds(120))
        for text in ["b", "bl", "blu", "blue"] {
            model.query = text
            model.queryDidChange()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.phase == .searching)
        await model.waitUntilDone()
        #expect(transport.callCount == 1, "only the final text was searched")
        #expect(model.phase == .done)
        #expect(model.sections.first?.items.first?.name == "blue")
    }

    @Test func clearingTheQueryResetsEverything() async throws {
        let model = try await model(manifests: [manifest("a")], transport: stub())
        model.query = "x"
        model.queryDidChange()
        await model.waitUntilDone()
        #expect(model.hasResults)
        model.query = "   "
        model.queryDidChange()
        #expect(model.phase == .idle)
        #expect(model.sections.isEmpty && model.failures.isEmpty)
        #expect(!model.showsNoResults)
    }

    @Test func eachAddonGetsASectionAndFailuresBecomeChips() async throws {
        let model = try await model(manifests: [manifest("stub0"), manifest("stub1"), manifest("stub2")], transport: stub())
        model.query = "dune"
        await model.submit()
        #expect(model.phase == .done)
        #expect(model.sections.map(\.addon.name) == ["stub0", "stub2"])
        #expect(model.failures.map(\.addon.name) == ["stub1"])
        #expect(model.failures.first?.text == "stub1: Server error (500)")
        #expect(model.hasResults)
        #expect(!model.showsNoResults)
    }

    @Test func sectionsStayInAddonOrderWhateverOrderTheyAnswerIn() async throws {
        // The first addon (host stub0) answers 150 ms late; the second (stub1) answers at once.
        let transport = StubTransport { request, _ in
            if request.url?.host == "stub0.example.com" { try await Task.sleep(for: .milliseconds(150)) }
            return StubTransport.response(Data(#"{"metas":[{"id":"x"}]}"#.utf8), for: request)
        }
        let model = try await model(manifests: [manifest("first"), manifest("second")], transport: transport)
        model.query = "q"
        let search = Task { await model.submit() }
        try await waitUntil { model.sections.count == 1 }
        #expect(model.sections.map(\.addon.name) == ["second"], "the fast addon appears first while the slow one is pending")
        await search.value
        #expect(model.sections.map(\.addon.name) == ["first", "second"], "then it slots into the user's order")
    }

    @Test func noResultsIsReportedOnlyWhenNothingFailed() async throws {
        let empty = StubTransport(data: Data(#"{"metas":[]}"#.utf8))
        let model = try await model(manifests: [manifest("a")], transport: empty)
        model.query = "zzz"
        await model.submit()
        #expect(model.showsNoResults)
        let failing = StubTransport(data: Data(), status: 500)
        let other = try await self.model(manifests: [manifest("a")], transport: failing)
        other.query = "zzz"
        await other.submit()
        #expect(!other.showsNoResults, "an error chip explains the empty screen")
        #expect(other.failures.count == 1)
    }

    @Test func addonsWithoutSearchableCatalogsAreNotAsked() async throws {
        let transport = stub()
        let model = try await model(manifests: [manifest("a", searchable: false)], transport: transport)
        model.query = "x"
        await model.submit()
        #expect(transport.callCount == 0)
        #expect(model.showsNoSearchableAddons)
        #expect(!model.showsNoResults, "no addon could have answered, so 'no results' would mislead")
    }

    @Test func resultsAreGroupedByTypeAndDeduplicatedAcrossAddons() async throws {
        // Addon "a" has one movie catalog. Addon "b" has the same movie plus a movie, a channel, a series and an anime catalog, in that order.
        let movies = Manifest(id: "a", name: "A", version: "1", resources: [ResourceDescriptor(name: "catalog")], types: ["movie"],
                              catalogs: [CatalogDescriptor(type: "movie", id: "movies", extra: [ExtraDescriptor(name: "search")])])
        let mixed = Manifest(id: "b", name: "B", version: "1", resources: [ResourceDescriptor(name: "catalog")],
                             types: ["movie", "tv", "series", "anime"],
                             catalogs: [CatalogDescriptor(type: "movie", id: "films", extra: [ExtraDescriptor(name: "search")]),
                                        CatalogDescriptor(type: "tv", id: "channels", extra: [ExtraDescriptor(name: "search")]),
                                        CatalogDescriptor(type: "series", id: "shows", extra: [ExtraDescriptor(name: "search")]),
                                        CatalogDescriptor(type: "anime", id: "kitsu", extra: [ExtraDescriptor(name: "search")])])
        let bodies = [
            "movie/movies": #"{"metas":[{"id":"tt1","name":"Dune"},{"id":"tt2","name":"Arrival"}]}"#,
            "movie/films": #"{"metas":[{"id":"tt1","name":"Dune"},{"id":"tt3","name":"Heat"}]}"#,
            "tv/channels": #"{"metas":[{"id":"ch1","name":"Channel One"}]}"#,
            "series/shows": #"{"metas":[{"id":"tt9","name":"The Wire"}]}"#,
            "anime/kitsu": #"{"metas":[{"id":"kitsu:1","name":"Akira"}]}"#,
        ]
        let transport = StubTransport { request, _ in
            let path = request.url?.path ?? ""
            let body = bodies.first { path.contains("/catalog/\($0.key)/") }?.value ?? #"{"metas":[]}"#
            return StubTransport.response(Data(body.utf8), for: request)
        }
        let model = try await model(manifests: [movies, mixed], transport: transport)
        model.query = "x"
        await model.submit()
        #expect(model.groups.map(\.type) == ["movie", "series", "tv", "anime"], "movies, then series, then other types in order of first appearance")
        #expect(model.groups.map(\.title) == ["Movies", "Series", "Live TV", "Anime"])
        #expect(model.groups.first?.items.map(\.name) == ["Dune", "Arrival", "Heat"], "Dune from both addons appears once, in addon order")
        #expect(model.groups.first { $0.type == "tv" }?.items.map(\.name) == ["Channel One"])
    }

    @Test func aSeriesResultLandsInTheSeriesGroup() async throws {
        let shows = Manifest(id: "shows", name: "Shows", version: "1", resources: [ResourceDescriptor(name: "catalog")], types: ["series"],
                             catalogs: [CatalogDescriptor(type: "series", id: "top", extra: [ExtraDescriptor(name: "search")])])
        let model = try await model(manifests: [shows], transport: stub())
        model.query = "wire"
        await model.submit()
        #expect(model.groups.map(\.title) == ["Series"])
        #expect(model.groups.first?.items.first?.type == "series")
        #expect(model.hasResults)
        #expect(!model.showsNoResults)
    }

    @Test func aRegistryWithOnlyStreamAddonsSaysSoWithoutAskingAnyone() async throws {
        let streams = Manifest(id: "streams", name: "Streams", version: "1", resources: [ResourceDescriptor(name: "stream", types: ["movie"])],
                               types: ["movie"])
        let transport = stub()
        let model = try await model(manifests: [streams], transport: transport)
        await model.refreshAvailability()
        #expect(!model.hasSearchableAddons)
        #expect(model.showsNoSearchableAddons)
        model.query = "dune"
        await model.submit()
        #expect(model.phase == .done)
        #expect(model.sections.isEmpty && model.failures.isEmpty)
        #expect(!model.showsNoResults)
        #expect(model.groups.isEmpty)
        #expect(transport.callCount == 0)
    }

    @Test func aNewQueryCancelsTheRunningSearch() async throws {
        let transport = stub()
        let model = try await model(manifests: [manifest("stub2")], transport: transport, debounce: .milliseconds(10))
        model.query = "first"
        model.queryDidChange()
        try await Task.sleep(for: .milliseconds(60))   // first search is in flight (150 ms answer)
        model.query = "second"
        model.queryDidChange()
        await model.waitUntilDone()
        #expect(model.sections.first?.items.first?.name == "second")
        #expect(model.sections.count == 1)
    }
}
