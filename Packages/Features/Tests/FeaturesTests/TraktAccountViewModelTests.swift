import Foundation
import Testing
import PlayerKit
import StremioKit
import StremioKitTestSupport
@testable import Features

@MainActor
@Suite struct TraktAccountViewModelTests {
    private let when = Date(timeIntervalSince1970: 1700000000)
    private let codeJSON = #"{"device_code":"device","user_code":"ABCD1234","verification_url":"https://trakt.tv/activate","expires_in":600,"interval":5}"#
    private let tokenJSON = #"{"access_token":"access","refresh_token":"refresh","expires_in":604800,"created_at":1700000000}"#

    private func services(transport: StubTransport, library: [LibraryItem] = [], progress: [WatchProgress] = []) async throws -> AppServices {
        let client = makeClient(StubTransport(data: Data()))
        let registry = AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client)
        let settings = InMemorySettingsStore(PlaybackSettings(traktClientID: "client"))
        let account = TraktAccount(settings: settings, secrets: InMemorySecretStore(), transport: transport, now: { Date(timeIntervalSince1970: 1700000001) })
        try await account.saveClientSecret("secret")
        let code = try JSONDecoder().decode(TraktDeviceCode.self, from: Data(codeJSON.utf8))
        _ = try await account.checkAuthorization(code)
        return AppServices(registry: registry, client: client, settings: settings, progress: InMemoryProgressStore(progress),
                           library: InMemoryLibraryStore(library), traktAccount: account)
    }

    @Test func loadingAndSavingCredentialsKeepTheExistingSettings() async throws {
        let tokenJSON = tokenJSON
        let transport = StubTransport(data: Data(tokenJSON.utf8))
        let services = try await services(transport: transport)
        var settings = await services.settings.load()
        settings.preferredResolution = 1080
        await services.settings.save(settings)
        let model = TraktAccountViewModel(services: services)
        await model.load()
        #expect(model.isSignedIn && model.clientIDText == "client" && model.clientSecretText == "secret")
        model.clientIDText = " new-client "
        model.clientSecretText = " new-secret "
        await model.saveCredentials()
        #expect(model.errorMessage == nil && !model.isSignedIn)
        let saved = await services.settings.load()
        #expect(saved.traktClientID == "new-client" && saved.preferredResolution == 1080)
        #expect(await services.traktAccount.clientSecret() == "new-secret")
    }

    @Test func importAddsMissingItemsAndKeepsSavedTitlesAndPlaybackPositions() async throws {
        let tokenJSON = tokenJSON
        let transport = StubTransport { request, _ in
            if request.url?.path == "/oauth/device/token" { return StubTransport.response(Data(tokenJSON.utf8), for: request) }
            if request.url?.path == "/sync/watchlist" {
                return StubTransport.response(Data(#"[{"movie":{"title":"Remote","ids":{"imdb":"tt2"}}},{"movie":{"title":"Remote copy","ids":{"imdb":"tt1"}}}]"#.utf8), for: request)
            }
            if request.url?.path.hasPrefix("/sync/collection/") == true {
                return StubTransport.response(Data("[]".utf8), for: request)
            }
            if request.url?.path == "/sync/watched/movies" {
                return StubTransport.response(Data(#"[{"movie":{"title":"Remote","ids":{"imdb":"tt2"}},"last_watched_at":"2023-11-14T22:13:20.000Z"}]"#.utf8), for: request)
            }
            return StubTransport.response(Data(#"[{"show":{"title":"Series","ids":{"imdb":"tt3"}},"seasons":[{"number":1,"episodes":[{"number":2,"last_watched_at":"2023-11-14T22:13:20Z"}]}]}]"#.utf8), for: request)
        }
        let saved = LibraryItem(preview: MetaPreview(id: "tt1", type: "movie", name: "Local title"), addedAt: when)
        let partial = WatchProgress(id: "movie/tt2", type: "movie", contentID: "tt2", title: "Local movie", position: 50, duration: 100,
                                    isWatched: false, updatedAt: when)
        let services = try await services(transport: transport, library: [saved], progress: [partial])
        let model = TraktAccountViewModel(services: services)
        await model.importFromTrakt()
        #expect(model.errorMessage == nil)
        #expect(model.message == "Imported 1 saved titles and 2 watched items from Trakt.")
        let library = await services.library.all()
        #expect(Set(library.map(\.id)) == ["movie/tt1", "movie/tt2"])
        #expect(library.first(where: { $0.id == saved.id })?.name == "Local title")
        let progress = await services.progress.progress(for: partial.id)
        #expect(progress?.isWatched == true && progress?.position == 50 && progress?.duration == 100 && progress?.title == "Local movie")
        let episode = await services.progress.progress(for: "series/tt3:1:2")
        #expect(episode?.isWatched == true && episode?.season == 1 && episode?.episode == 2)
        await model.importFromTrakt()
        #expect(model.message == "Imported 0 saved titles and 0 watched items from Trakt.")
    }

    @Test func exportSkipsExistingWatchesAndUnsupportedIDs() async throws {
        let tokenJSON = tokenJSON
        let transport = StubTransport { request, _ in
            if request.url?.path == "/oauth/device/token" { return StubTransport.response(Data(tokenJSON.utf8), for: request) }
            if request.httpMethod == "POST" {
                let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
                let movies = try #require(body["movies"] as? [[String: Any]])
                #expect(movies.count == 1 && (movies[0]["ids"] as? [String: String])?["imdb"] == "tt2")
                return StubTransport.response(Data(#"{"added":{"movies":1,"episodes":0}}"#.utf8), status: 201, for: request)
            }
            if request.url?.path == "/sync/watched/shows" { return StubTransport.response(Data("[]".utf8), for: request) }
            return StubTransport.response(Data(#"[{"movie":{"title":"Existing","ids":{"imdb":"tt1"}},"last_watched_at":"2023-11-14T22:13:20Z"}]"#.utf8), for: request)
        }
        let library = ["tt1", "tt2", "private-id"].map { LibraryItem(preview: MetaPreview(id: $0, type: "movie", name: $0), addedAt: when) }
        let progress = ["tt1", "tt2", "private-id"].map {
            WatchProgress(id: "movie/\($0)", type: "movie", contentID: $0, title: $0, position: 0, duration: 0, isWatched: true, updatedAt: when)
        }
        let services = try await services(transport: transport, library: library, progress: progress)
        let model = TraktAccountViewModel(services: services)
        await model.sendToTrakt()
        #expect(model.errorMessage == nil && model.message == "Sent 1 saved titles and 1 watched items to Trakt.")
        #expect(transport.requests.filter { $0.httpMethod == "POST" }.map { $0.url?.path } == ["/oauth/device/token", "/sync/watchlist", "/sync/history"])
        #expect(await services.library.all().count == 3)
        #expect(await services.progress.all().count == 3)
    }

    @Test func uncheckedSyncOptionsMakeNoRequests() async throws {
        let services = try await services(transport: StubTransport(data: Data(tokenJSON.utf8)))
        let model = TraktAccountViewModel(services: services)
        model.syncWatchlist = false
        model.syncCollection = false
        model.syncHistory = false
        await model.importFromTrakt()
        await model.sendToTrakt()
        #expect(model.message == nil && model.errorMessage == nil && !model.isWorking)
    }

    @Test func collectionAndWatchlistMergeWithoutDuplicatesOrMarkingCollectedTitlesWatched() async throws {
        let tokenJSON = tokenJSON
        let transport = StubTransport { request, _ in
            if request.url?.path == "/oauth/device/token" { return StubTransport.response(Data(tokenJSON.utf8), for: request) }
            if request.url?.path == "/sync/watchlist" {
                return StubTransport.response(Data(#"[{"movie":{"title":"Watch later","ids":{"imdb":"tt1"}}}]"#.utf8), for: request)
            }
            if request.url?.path == "/sync/collection/movies" {
                return StubTransport.response(Data(#"[{"movie":{"title":"Duplicate","ids":{"imdb":"tt1"}}},{"movie":{"title":"Owned movie","ids":{"imdb":"tt2"}}}]"#.utf8), for: request)
            }
            if request.url?.path == "/sync/collection/shows" {
                return StubTransport.response(Data(#"[{"show":{"title":"Owned show","ids":{"imdb":"tt3"}}}]"#.utf8), for: request)
            }
            return StubTransport.response(Data("[]".utf8), for: request)
        }
        let services = try await services(transport: transport)
        let model = TraktAccountViewModel(services: services)
        await model.importFromTrakt()
        #expect(model.errorMessage == nil && model.message == "Imported 3 saved titles and 0 watched items from Trakt.")
        let saved = await services.library.all()
        #expect(Set(saved.map(\.id)) == ["movie/tt1", "movie/tt2", "series/tt3"])
        #expect(saved.first(where: { $0.id == "movie/tt1" })?.name == "Watch later")
        #expect(await services.progress.all().isEmpty)
        await model.importFromTrakt()
        #expect(model.message == "Imported 0 saved titles and 0 watched items from Trakt.")
    }

    @Test func failedCollectionFetchDoesNotPartiallyImportTheWatchlist() async throws {
        let tokenJSON = tokenJSON
        let transport = StubTransport { request, _ in
            if request.url?.path == "/oauth/device/token" { return StubTransport.response(Data(tokenJSON.utf8), for: request) }
            if request.url?.path == "/sync/watchlist" {
                return StubTransport.response(Data(#"[{"movie":{"title":"Watch later","ids":{"imdb":"tt1"}}}]"#.utf8), for: request)
            }
            return StubTransport.response(Data(), status: 503, for: request)
        }
        let services = try await services(transport: transport)
        let model = TraktAccountViewModel(services: services)
        await model.importFromTrakt()
        #expect(model.errorMessage != nil && model.message == nil)
        #expect(await services.library.all().isEmpty)
        #expect(await services.progress.all().isEmpty)
    }

    @Test func signOutKeepsLocalLibraryAndHistory() async throws {
        let saved = LibraryItem(preview: MetaPreview(id: "tt1", type: "movie", name: "Movie"), addedAt: when)
        let services = try await services(transport: StubTransport(data: Data(tokenJSON.utf8)), library: [saved])
        let model = TraktAccountViewModel(services: services)
        await model.load()
        #expect(model.isSignedIn)
        await model.signOut()
        #expect(!model.isSignedIn && model.errorMessage == nil)
        #expect(await services.library.all() == [saved])
    }
}
