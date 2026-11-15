import Foundation
import Testing
import PlayerKit
import StremioKit
import StremioKitTestSupport
@testable import Features

private let testJWT = "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJ0ZXN0In0.signature"

@MainActor
@Suite struct DiscoverViewModelTests {
    private func savedItem(_ id: String, type: String = "movie", name: String? = nil) -> LibraryItem {
        LibraryItem(preview: MetaPreview(id: id, type: type, name: name ?? id))
    }

    private func makeServices(transport: StubTransport, token: String? = testJWT, library: [LibraryItem] = [],
                              progress: [WatchProgress] = []) -> AppServices {
        let client = makeClient(transport, retries: 0)
        let registry = AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client)
        let settings = InMemorySettingsStore(PlaybackSettings(tmdbReadToken: token))
        return AppServices(registry: registry, client: client, settings: settings,
                           progress: InMemoryProgressStore(progress), library: InMemoryLibraryStore(library))
    }

    private nonisolated func recommendationJSON(id: Int, title: String, mediaType: String = "movie", year: String = "2022-05-01",
                                    genres: [Int] = [18]) -> String {
        let nameKey = mediaType == "tv" ? "name" : "title"
        let dateKey = mediaType == "tv" ? "first_air_date" : "release_date"
        let genreList = genres.map(String.init).joined(separator: ",")
        return #"{"id":\#(id),"\#(nameKey)":"\#(title)","media_type":"\#(mediaType)","\#(dateKey)":"\#(year)","genre_ids":[\#(genreList)],"poster_path":"/p\#(id).jpg"}"#
    }

    private nonisolated func discoverJSON(id: Int, title: String, isSeries: Bool = false, year: String = "2023-01-01",
                              genres: [Int] = [18]) -> String {
        let nameKey = isSeries ? "name" : "title"
        let dateKey = isSeries ? "first_air_date" : "release_date"
        let genreList = genres.map(String.init).joined(separator: ",")
        return #"{"id":\#(id),"\#(nameKey)":"\#(title)","\#(dateKey)":"\#(year)","genre_ids":[\#(genreList)],"poster_path":"/p\#(id).jpg"}"#
    }

    @Test func mixesSixShuffledSeedsInterleavesRecommendationsAndCapsWindowAtTwentyFour() async throws {
        let library = (1...8).map { index in
            savedItem(String(format: "tt000000%d", index), type: index.isMultiple(of: 2) ? "series" : "movie")
        }
        let transport = StubTransport { request, _ in
            let path = request.url?.path ?? ""
            if path.hasPrefix("/3/find/tt000000"), let seedNumber = Int(path.suffix(1)) {
                let isSeries = seedNumber.isMultiple(of: 2)
                let body = isSeries
                    ? #"{"movie_results":[],"tv_results":[{"id":\#(seedNumber),"vote_average":8.0,"vote_count":100}]}"#
                    : #"{"movie_results":[{"id":\#(seedNumber),"vote_average":8.0,"vote_count":100}],"tv_results":[]}"#
                return StubTransport.response(Data(body.utf8), for: request)
            }
            let parts = path.split(separator: "/")
            if parts.count == 4, parts[3] == "recommendations", let seedNumber = Int(parts[2]) {
                let mediaType = parts[1] == "tv" ? "tv" : "movie"
                let items = (1...5).map { offset in
                    let id = seedNumber * 100 + offset
                    return self.recommendationJSON(id: id, title: "Rec \(id)", mediaType: mediaType)
                }
                let body = #"{"results":[\#(items.joined(separator: ","))]}"#
                return StubTransport.response(Data(body.utf8), for: request)
            }
            if parts.count == 4, parts[3] == "external_ids", let id = Int(parts[2]) {
                let imdb = String(format: "tt%07d", id)
                return StubTransport.response(Data(#"{"imdb_id":"\#(imdb)"}"#.utf8), for: request)
            }
            return StubTransport.response(Data(), status: 500, for: request)
        }

        let services = makeServices(transport: transport, library: library)
        let model = DiscoverViewModel(services: services, shuffle: { Array($0.reversed()) })
        await model.reload()

        #expect(model.seeds.map(\.id) == ["tt0000008", "tt0000007", "tt0000006", "tt0000005", "tt0000004", "tt0000003"])
        #expect(model.items.count == 24)
        #expect(Array(model.items.prefix(6)).map(\.id) == ["tt0000801", "tt0000701", "tt0000601", "tt0000501", "tt0000401", "tt0000301"])
        let externalLookups = transport.requests.filter { ($0.url?.path ?? "").hasSuffix("/external_ids") }
        #expect(externalLookups.count == 24)
        let keywordLookups = transport.requests.filter { ($0.url?.path ?? "").hasSuffix("/keywords") }
        #expect(keywordLookups.isEmpty)
        #expect(model.state == .loaded)
        #expect(model.canLoadMore)
    }

    @Test func skipsLibraryTitlesDuplicatesMissingIMDbIDsAndFailingSeeds() async throws {
        let library = [
            savedItem("tt0000001", type: "movie"),
            savedItem("tt0000002", type: "movie"),
            savedItem("tt0000003", type: "movie"),
            savedItem("tt0000999", type: "movie")
        ]
        let watched = [
            WatchProgress(id: "movie/tt0000888", type: "movie", contentID: "tt0000888", title: "Watched",
                          position: 100, duration: 100, isWatched: true, updatedAt: Date())
        ]
        let transport = StubTransport { request, _ in
            let path = request.url?.path ?? ""
            switch path {
            case "/3/find/tt0000001":
                return StubTransport.response(Data(#"{"movie_results":[{"id":1}],"tv_results":[]}"#.utf8), for: request)
            case "/3/find/tt0000002":
                return StubTransport.response(Data(#"{"movie_results":[{"id":2}],"tv_results":[]}"#.utf8), for: request)
            case "/3/find/tt0000003":
                return StubTransport.response(Data(), status: 500, for: request)
            case "/3/movie/1/recommendations":
                let entries = [
                    self.recommendationJSON(id: 999, title: "Already Saved"),
                    self.recommendationJSON(id: 888, title: "Already Watched"),
                    self.recommendationJSON(id: 101, title: "Keep One"),
                    self.recommendationJSON(id: 102, title: "No IMDb"),
                    self.recommendationJSON(id: 103, title: "Shared Title")
                ]
                return StubTransport.response(Data(#"{"results":[\#(entries.joined(separator: ","))]}"#.utf8), for: request)
            case "/3/movie/2/recommendations":
                let entries = [
                    self.recommendationJSON(id: 103, title: "Shared Title"),
                    self.recommendationJSON(id: 201, title: "Same IMDb As Keep One"),
                    self.recommendationJSON(id: 202, title: "Keep Two")
                ]
                return StubTransport.response(Data(#"{"results":[\#(entries.joined(separator: ","))]}"#.utf8), for: request)
            case "/3/movie/999/external_ids":
                return StubTransport.response(Data(#"{"imdb_id":"tt0000999"}"#.utf8), for: request)
            case "/3/movie/888/external_ids":
                return StubTransport.response(Data(#"{"imdb_id":"tt0000888"}"#.utf8), for: request)
            case "/3/movie/101/external_ids", "/3/movie/201/external_ids":
                return StubTransport.response(Data(#"{"imdb_id":"tt0000101"}"#.utf8), for: request)
            case "/3/movie/102/external_ids":
                return StubTransport.response(Data(#"{"imdb_id":null}"#.utf8), for: request)
            case "/3/movie/103/external_ids":
                return StubTransport.response(Data(#"{"imdb_id":"tt0000103"}"#.utf8), for: request)
            case "/3/movie/202/external_ids":
                return StubTransport.response(Data(#"{"imdb_id":"tt0000202"}"#.utf8), for: request)
            default:
                if path.hasSuffix("/keywords") {
                    return StubTransport.response(Data(#"{"keywords":[]}"#.utf8), for: request)
                }
                return StubTransport.response(Data(), status: 500, for: request)
            }
        }

        let services = makeServices(transport: transport, library: library, progress: watched)
        let model = DiscoverViewModel(services: services, shuffle: { $0 })
        await model.reload()

        #expect(model.items.map(\.id) == ["tt0000103", "tt0000101", "tt0000202"])
        #expect(model.state == .loaded)
    }

    @Test func failsOnlyWhenEverySeedFailsAndNothingWasKept() async throws {
        let library = [savedItem("tt0000001", type: "movie"), savedItem("tt0000002", type: "movie")]
        let transport = StubTransport { request, _ in
            StubTransport.response(Data("not json".utf8), for: request)
        }
        let model = DiscoverViewModel(services: makeServices(transport: transport, library: library), shuffle: { $0 })
        await model.reload()
        #expect(model.state == .failed(.invalidJSON))
        #expect(model.items.isEmpty)
    }

    @Test func loadMoreKeepsTheSameSeedsAndRequestsNextRecommendationPage() async throws {
        let library = [savedItem("tt0000001", type: "movie"), savedItem("tt0000002", type: "series")]
        let transport = StubTransport { request, _ in
            let path = request.url?.path ?? ""
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "page" }?.value ?? "1"
            switch path {
            case "/3/find/tt0000001":
                return StubTransport.response(Data(#"{"movie_results":[{"id":10}],"tv_results":[]}"#.utf8), for: request)
            case "/3/find/tt0000002":
                return StubTransport.response(Data(#"{"movie_results":[],"tv_results":[{"id":20}]}"#.utf8), for: request)
            case "/3/movie/10/recommendations":
                let base = page == "2" ? 200 : 100
                let entries = (1...12).map { self.recommendationJSON(id: base + $0, title: "M \(base + $0)", mediaType: "movie") }
                return StubTransport.response(Data(#"{"results":[\#(entries.joined(separator: ","))]}"#.utf8), for: request)
            case "/3/tv/20/recommendations":
                let base = page == "2" ? 400 : 300
                let entries = (1...12).map { self.recommendationJSON(id: base + $0, title: "S \(base + $0)", mediaType: "tv") }
                return StubTransport.response(Data(#"{"results":[\#(entries.joined(separator: ","))]}"#.utf8), for: request)
            default:
                let parts = path.split(separator: "/")
                if parts.count == 4, parts[3] == "external_ids", let id = Int(parts[2]) {
                    let imdb = String(format: "tt%07d", id)
                    return StubTransport.response(Data(#"{"imdb_id":"\#(imdb)"}"#.utf8), for: request)
                }
                return StubTransport.response(Data(), status: 500, for: request)
            }
        }

        let services = makeServices(transport: transport, library: library)
        var shuffleCalls = 0
        let model = DiscoverViewModel(services: services, shuffle: { seeds in
            shuffleCalls += 1
            return seeds
        })
        await model.reload()
        let initialSeeds = model.seeds
        #expect(shuffleCalls == 1)
        #expect(model.items.count == 24)
        #expect(model.items.first?.id == "tt0000101")
        #expect(model.items.dropFirst().first?.id == "tt0000301")

        await model.loadMore()
        #expect(shuffleCalls == 1)
        #expect(model.seeds == initialSeeds)
        #expect(model.items.count == 48)
        #expect(model.items[24].id == "tt0000201")
        #expect(model.items[25].id == "tt0000401")
    }

    @Test func changingTypeReloadsSeedsForThatType() async throws {
        let library = [savedItem("tt0000001", type: "movie"), savedItem("tt0000002", type: "series")]
        let transport = StubTransport { request, _ in
            let path = request.url?.path ?? ""
            switch path {
            case "/3/find/tt0000001":
                return StubTransport.response(Data(#"{"movie_results":[{"id":10}],"tv_results":[]}"#.utf8), for: request)
            case "/3/find/tt0000002":
                return StubTransport.response(Data(#"{"movie_results":[],"tv_results":[{"id":20}]}"#.utf8), for: request)
            case "/3/movie/10/recommendations":
                let entry = self.recommendationJSON(id: 101, title: "Movie Rec", mediaType: "movie")
                return StubTransport.response(Data(#"{"results":[\#(entry)]}"#.utf8), for: request)
            case "/3/tv/20/recommendations":
                let entry = self.recommendationJSON(id: 201, title: "Series Rec", mediaType: "tv")
                return StubTransport.response(Data(#"{"results":[\#(entry)]}"#.utf8), for: request)
            case "/3/movie/101/external_ids":
                return StubTransport.response(Data(#"{"imdb_id":"tt0000101"}"#.utf8), for: request)
            case "/3/tv/201/external_ids":
                return StubTransport.response(Data(#"{"imdb_id":"tt0000201"}"#.utf8), for: request)
            default:
                if path.hasSuffix("/keywords") {
                    return StubTransport.response(Data(#"{"keywords":[],"results":[]}"#.utf8), for: request)
                }
                return StubTransport.response(Data(), status: 500, for: request)
            }
        }

        let model = DiscoverViewModel(services: makeServices(transport: transport, library: library), shuffle: { $0 })
        await model.reload()
        #expect(model.showsAllTypes)
        #expect(model.seeds.map(\.type) == ["movie", "series"])
        #expect(model.items.map(\.id) == ["tt0000101", "tt0000201"])

        await model.select(type: "movie")
        #expect(model.selectedType == "movie")
        #expect(model.seeds.map(\.id) == ["tt0000001"])
        #expect(model.items.map(\.id) == ["tt0000101"])

        await model.select(type: "series")
        #expect(model.selectedType == "series")
        #expect(model.seeds.map(\.id) == ["tt0000002"])
        #expect(model.items.map(\.id) == ["tt0000201"])

        await model.selectAllTypes()
        #expect(model.showsAllTypes)
        #expect(model.seeds.count == 2)
    }

    @Test func genreYearRatingAndSortFilterLoadedTitlesLocallyWithoutReloading() async throws {
        let library = [savedItem("tt0000001", type: "movie")]
        let transport = StubTransport { request, _ in
            let path = request.url?.path ?? ""
            switch path {
            case "/3/find/tt0000001":
                return StubTransport.response(Data(#"{"movie_results":[{"id":10}],"tv_results":[]}"#.utf8), for: request)
            case "/3/movie/10/recommendations":
                let entries = [
                    self.recommendationJSON(id: 101, title: "Zulu", mediaType: "movie", year: "1995-03-01", genres: [28, 18]),
                    self.recommendationJSON(id: 102, title: "Alpha", mediaType: "movie", year: "2021-07-01", genres: [35]),
                    self.recommendationJSON(id: 103, title: "Bravo", mediaType: "movie", year: "2023-11-01", genres: [18])
                ]
                return StubTransport.response(Data(#"{"results":[\#(entries.joined(separator: ","))]}"#.utf8), for: request)
            case "/3/movie/101/external_ids":
                return StubTransport.response(Data(#"{"imdb_id":"tt0000101"}"#.utf8), for: request)
            case "/3/movie/102/external_ids":
                return StubTransport.response(Data(#"{"imdb_id":"tt0000102"}"#.utf8), for: request)
            case "/3/movie/103/external_ids":
                return StubTransport.response(Data(#"{"imdb_id":"tt0000103"}"#.utf8), for: request)
            default:
                if path.hasSuffix("/keywords") {
                    return StubTransport.response(Data(#"{"keywords":[]}"#.utf8), for: request)
                }
                return StubTransport.response(Data(), status: 500, for: request)
            }
        }

        let services = makeServices(transport: transport, library: library)
        services.posterRatings.ratings(for: MetaPreview(id: "tt0000101", type: "movie", name: "Zulu")).imdb = 8.6
        services.posterRatings.ratings(for: MetaPreview(id: "tt0000102", type: "movie", name: "Alpha")).imdb = 6.4
        services.posterRatings.ratings(for: MetaPreview(id: "tt0000103", type: "movie", name: "Bravo")).imdb = 9.1

        let model = DiscoverViewModel(services: services, shuffle: { $0 })
        await model.reload()
        let callCountAfterLoad = transport.callCount

        #expect(model.genres == ["Action", "Comedy", "Drama"])
        await model.select(genre: "Drama")
        #expect(transport.callCount == callCountAfterLoad)
        #expect(model.visibleItems.map(\.id) == ["tt0000101", "tt0000103"])
        #expect(model.visibleItems.first?.genres.first == "Drama")

        model.minimumYear = 2000
        #expect(model.visibleItems.map(\.id) == ["tt0000103"])

        model.minimumYear = nil
        await model.select(genre: nil)
        model.minimumRating = 8.0
        #expect(model.visibleItems.map(\.id) == ["tt0000101", "tt0000103"])

        model.minimumRating = nil
        model.sort = .title
        #expect(model.visibleItems.map(\.name) == ["Alpha", "Bravo", "Zulu"])
        #expect(transport.callCount == callCountAfterLoad)
    }

    @Test func keywordFillRunsOnlyWhenTheRecommendationWindowIsShort() async throws {
        let library = [savedItem("tt0000001", type: "movie"), savedItem("tt0000002", type: "series")]
        let transport = StubTransport { request, _ in
            let path = request.url?.path ?? ""
            let keywordParam = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "with_keywords" }?.value ?? ""
            switch path {
            case "/3/find/tt0000001":
                return StubTransport.response(Data(#"{"movie_results":[{"id":10}],"tv_results":[]}"#.utf8), for: request)
            case "/3/find/tt0000002":
                return StubTransport.response(Data(#"{"movie_results":[],"tv_results":[{"id":20}]}"#.utf8), for: request)
            case "/3/movie/10/recommendations":
                let entry = self.recommendationJSON(id: 101, title: "Rec Movie", mediaType: "movie")
                return StubTransport.response(Data(#"{"results":[\#(entry)]}"#.utf8), for: request)
            case "/3/tv/20/recommendations":
                let entry = self.recommendationJSON(id: 201, title: "Rec Series", mediaType: "tv")
                return StubTransport.response(Data(#"{"results":[\#(entry)]}"#.utf8), for: request)
            case "/3/movie/10/keywords":
                let body = #"{"keywords":[{"id":501,"name":"heist"},{"id":502,"name":"noir"},{"id":503,"name":"escape"}]}"#
                return StubTransport.response(Data(body.utf8), for: request)
            case "/3/tv/20/keywords":
                let body = #"{"results":[{"id":601,"name":"detective"},{"id":602,"name":"mystery"}]}"#
                return StubTransport.response(Data(body.utf8), for: request)
            case "/3/discover/movie":
                let kw = Int(keywordParam) ?? 500
                let entry = self.discoverJSON(id: kw + 1000, title: "Keyword Movie \(kw)")
                return StubTransport.response(Data(#"{"page":1,"total_pages":1,"results":[\#(entry)]}"#.utf8), for: request)
            case "/3/discover/tv":
                let kw = Int(keywordParam) ?? 600
                let entry = self.discoverJSON(id: kw + 1000, title: "Keyword Series \(kw)", isSeries: true)
                return StubTransport.response(Data(#"{"page":1,"total_pages":1,"results":[\#(entry)]}"#.utf8), for: request)
            default:
                let parts = path.split(separator: "/")
                if parts.count == 4, parts[3] == "external_ids", let id = Int(parts[2]) {
                    let imdb = String(format: "tt%07d", id)
                    return StubTransport.response(Data(#"{"imdb_id":"\#(imdb)"}"#.utf8), for: request)
                }
                return StubTransport.response(Data(), status: 500, for: request)
            }
        }

        let model = DiscoverViewModel(services: makeServices(transport: transport, library: library), shuffle: { $0 })
        await model.reload()

        let discoverRequests = transport.requests.filter { ($0.url?.path ?? "").hasPrefix("/3/discover/") }
        #expect(discoverRequests.count == 4)
        #expect(model.items.map(\.id) == ["tt0000101", "tt0000201", "tt0001501", "tt0001601", "tt0001502", "tt0001602"])
    }

    @Test func emptyLibraryWithTokenShowsPopularMovieAndSeriesPagesInterleaved() async throws {
        let transport = StubTransport { request, _ in
            let path = request.url?.path ?? ""
            switch path {
            case "/3/discover/movie":
                let entries = [self.discoverJSON(id: 11, title: "Popular Movie 1"), self.discoverJSON(id: 12, title: "Popular Movie 2")]
                return StubTransport.response(Data(#"{"page":1,"total_pages":2,"results":[\#(entries.joined(separator: ","))]}"#.utf8), for: request)
            case "/3/discover/tv":
                let entries = [self.discoverJSON(id: 21, title: "Popular Series 1", isSeries: true),
                               self.discoverJSON(id: 22, title: "Popular Series 2", isSeries: true)]
                return StubTransport.response(Data(#"{"page":1,"total_pages":2,"results":[\#(entries.joined(separator: ","))]}"#.utf8), for: request)
            default:
                let parts = path.split(separator: "/")
                if parts.count == 4, parts[3] == "external_ids", let id = Int(parts[2]) {
                    let imdb = String(format: "tt%07d", id)
                    return StubTransport.response(Data(#"{"imdb_id":"\#(imdb)"}"#.utf8), for: request)
                }
                return StubTransport.response(Data(), status: 500, for: request)
            }
        }

        let model = DiscoverViewModel(services: makeServices(transport: transport, library: []))
        await model.reload()

        #expect(model.seeds.isEmpty)
        #expect(model.items.map(\.id) == ["tt0000011", "tt0000021", "tt0000012", "tt0000022"])
        #expect(model.items.map(\.type) == ["movie", "series", "movie", "series"])
        #expect(model.state == .loaded)
        #expect(model.canLoadMore)
    }

    @Test func withoutTokenLeavesEmptyStateAndSendsNoRequests() async throws {
        let transport = StubTransport { request, _ in
            StubTransport.response(Data(), status: 500, for: request)
        }
        let library = [savedItem("tt0000001", type: "movie")]
        let model = DiscoverViewModel(services: makeServices(transport: transport, token: nil, library: library))
        await model.loadSources()

        #expect(model.state == .loaded)
        #expect(model.items.isEmpty)
        #expect(!model.canLoadMore)
        #expect(transport.callCount == 0)
    }

    @Test func genresLeaveOutOrdersAndYearsAndRepeats() {
        func catalog(_ id: String, _ options: [String]) -> CatalogDescriptor {
            CatalogDescriptor(type: "movie", id: id, extra: [ExtraDescriptor(name: "genre", options: options)])
        }
        let genres = DiscoverViewModel.genres(of: [
            catalog("sorts", ["Date Added ↓", "Date Added ↑", "Title A-Z", "Title Z-A", "Actions"]),
            catalog("library", ["Recently Added", "Oldest Added", "Film Name", "Release Date (Newest)", "Release Date (Oldest)"]),
            catalog("years", ["2024", "2023", "1990s"]),
            catalog("genres", ["Thriller", "Action", "Top Rated", "Sci-Fi", "Comedy"]),
            catalog("more", ["action", "Drama", "Film-Noir"]),
        ])
        #expect(genres == ["Action", "Comedy", "Drama", "Film-Noir", "Science Fiction", "Thriller"])
    }

    @Test func yearSpanLabelWordsTheSpanLikeTheLibraryChips() {
        let transport = StubTransport { request, _ in StubTransport.response(Data(), for: request) }
        let model = DiscoverViewModel(services: makeServices(transport: transport, token: nil))
        #expect(model.yearSpanLabel == nil)
        model.minimumYear = 1990
        model.maximumYear = 1999
        #expect(model.yearSpanLabel == "1990–1999")
        model.minimumYear = 2005
        model.maximumYear = 2005
        #expect(model.yearSpanLabel == "2005")
        model.minimumYear = 2000
        model.maximumYear = nil
        #expect(model.yearSpanLabel == "From 2000")
        model.minimumYear = nil
        model.maximumYear = 1979
        #expect(model.yearSpanLabel == "Until 1979")
    }
}
