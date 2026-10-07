import Foundation
import Testing
import PlayerKit
import StremioKit
import StremioKitTestSupport
@testable import Features

@MainActor
@Suite struct LibraryAndSettingsViewModelTests {
    private let when = Date(timeIntervalSince1970: 1_700_000_000)

    private func progress(_ id: String, _ position: Double, duration: Double = 100, watched: Bool = false, age: TimeInterval = 0, type: String = "movie",
                          season: Int? = nil, episode: Int? = nil) -> WatchProgress {
        WatchProgress(id: "\(type)/\(id)", type: type, contentID: id, title: "T \(id)", position: position, duration: duration, isWatched: watched,
                      updatedAt: when.addingTimeInterval(age), season: season, episode: episode)
    }

    private func services(progress: [WatchProgress] = [], library: [LibraryItem] = [], settings: PlaybackSettings = PlaybackSettings()) -> AppServices {
        let client = makeClient(StubTransport(data: Data()))
        let registry = AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client)
        return AppServices(registry: registry, client: client, settings: InMemorySettingsStore(settings),
                           progress: InMemoryProgressStore(progress), library: InMemoryLibraryStore(library))
    }

    // MARK: library

    @Test func continueWatchingKeepsOnlyResumableItemsNewestFirst() async {
        let model = LibraryViewModel(services: services(progress: [
            progress("old", 40, age: 0), progress("new", 60, age: 100), progress("barely", 2, age: 50), progress("nearly", 97, age: 60),
            progress("done", 95, watched: true, age: 70),
        ]))
        #expect(!model.hasLoaded)
        await model.load()
        #expect(model.hasLoaded)
        #expect(model.continueWatching.map(\.contentID) == ["new", "old"], "barely started, nearly finished and watched items don't qualify")
        #expect(model.watched.map(\.contentID) == ["done"])
        #expect(model.isEmpty == false)
    }

    @Test func onlyTheLatestEpisodePerSeriesContinues() async {
        let items = [
            progress("tt9:1:1", 30, age: 0, type: "series", season: 1, episode: 1),
            progress("tt9:1:2", 30, age: 100, type: "series", season: 1, episode: 2),
            progress("tt8:1:1", 30, age: 50, type: "series", season: 1, episode: 1),
        ]
        let model = LibraryViewModel(services: services(progress: items))
        await model.load()
        #expect(model.continueWatching.map(\.contentID) == ["tt9:1:2", "tt8:1:1"])
    }

    @Test func savedTitlesAndRemoval() async {
        let saved = [LibraryItem(id: "movie/a", type: "movie", contentID: "a", name: "A", addedAt: when),
                     LibraryItem(id: "movie/b", type: "movie", contentID: "b", name: "B", addedAt: when.addingTimeInterval(10))]
        let model = LibraryViewModel(services: services(library: saved))
        await model.load()
        #expect(model.saved.map(\.contentID) == ["b", "a"])
        await model.removeSaved(model.saved[0])
        #expect(model.saved.map(\.contentID) == ["a"])
    }

    @Test func removingMarkingAndUnmarking() async {
        let model = LibraryViewModel(services: services(progress: [progress("a", 40), progress("b", 50, age: -10)]))
        await model.load()
        #expect(model.continueWatching.map(\.contentID) == ["a", "b"])
        await model.removeFromContinueWatching(model.continueWatching[0])
        #expect(model.continueWatching.map(\.contentID) == ["b"])
        await model.markWatched(model.continueWatching[0])
        #expect(model.continueWatching.isEmpty && model.watched.map(\.contentID) == ["b"])
        await model.markUnwatched(model.watched[0])
        #expect(model.watched.isEmpty && model.isEmpty)
    }

    @Test func requestsToResumeCarryEverythingTheyNeed() {
        let p = WatchProgress(id: "series/tt9:2:3", type: "series", contentID: "tt9:2:3", title: "Show · Three", poster: URL(string: "https://e.com/p.jpg"),
                              position: 10, duration: 50, isWatched: false, updatedAt: when, season: 2, episode: 3)
        let request = LibraryViewModel.request(for: p)
        #expect(request.type == "series" && request.id == "tt9:2:3" && request.title == "Show · Three" && request.season == 2 && request.episode == 3)
        #expect(request.identity == p.id, "the player finds the saved position under the same identity")
    }

    @Test func homeShowsContinueWatching() async throws {
        let model = BoardViewModel(services: services(progress: [progress("a", 40), progress("b", 99)]))
        await model.load()
        #expect(model.continueWatching.map(\.contentID) == ["a"])
    }

    @Test func homeRefreshesContinueWatchingWithoutReloadingRows() async {
        let services = services(progress: [progress("a", 40)])
        let model = BoardViewModel(services: services)
        await model.refreshContinueWatching()
        #expect(model.continueWatching.map(\.contentID) == ["a"])
        await services.progress.save(progress("b", 30, age: 10))
        await model.refreshContinueWatching()
        #expect(model.continueWatching.map(\.contentID) == ["b", "a"])
        #expect(model.rows.isEmpty && model.phase == .loading, "rows are untouched")
    }

    // MARK: detail: library and watched

    private func detailModel(_ services: AppServices, preview: MetaPreview) -> DetailViewModel { DetailViewModel(preview: preview, services: services) }

    @Test func detailTogglesTheLibrary() async {
        let services = services()
        let model = detailModel(services, preview: MetaPreview(id: "tt1", type: "movie", name: "Film"))
        await model.refreshUserState()
        #expect(!model.isInLibrary)
        await model.toggleLibrary()
        #expect(model.isInLibrary)
        #expect(await services.library.all().map(\.id) == ["movie/tt1"])
        await model.toggleLibrary()
        let afterRemoval = await services.library.all()
        #expect(!model.isInLibrary && afterRemoval.isEmpty)
    }

    @Test func detailMarksMoviesWatched() async {
        let services = services()
        let model = detailModel(services, preview: MetaPreview(id: "tt1", type: "movie", name: "Film"))
        let request = model.movieRequest
        #expect(!model.isWatched(request))
        await model.setWatched(true, for: request)
        #expect(model.isWatched(request))
        let saved = await services.progress.progress(for: request.identity)
        #expect(saved?.isWatched == true)
        #expect(ProgressRecorder.resumePosition(for: saved) == 0, "a watched title starts from the beginning")
        await model.setWatched(false, for: request)
        let afterUnmark = await services.progress.progress(for: request.identity)
        #expect(!model.isWatched(request) && afterUnmark == nil)
    }

    // MARK: settings

    @Test func settingsPersistEachChange() async {
        let services = services()
        let model = SettingsViewModel(services: services)
        await model.load()
        #expect(model.settings == PlaybackSettings())
        await model.setPreferredResolution(1080)
        await model.setSubtitleLanguage("eng")
        await model.setFallbackEngineEnabled(false)
        let stored = await services.settings.load()
        #expect(stored == PlaybackSettings(preferredResolution: 1080, subtitleLanguage: "eng", streamingServerURL: nil, fallbackEngineEnabled: false))
        await model.setSubtitleLanguage(nil)
        #expect(await services.settings.load().subtitleLanguage == nil)
    }

    @Test func theServerURLIsSavedOnlyWhenValidOrEmpty() async {
        let services = services()
        let model = SettingsViewModel(services: services)
        await model.load()
        model.serverURLText = "not a url"
        #expect(model.serverURLMessage?.contains("full address") == true)
        await model.commitServerURL()
        #expect(await services.settings.load().streamingServerURL == nil, "an invalid value is not saved")
        model.serverURLText = " http://192.168.1.9:11470 "
        #expect(model.serverURLMessage == nil)
        await model.commitServerURL()
        #expect(await services.settings.load().streamingServerURL == "http://192.168.1.9:11470")
        model.serverURLText = ""
        await model.commitServerURL()
        #expect(await services.settings.load().streamingServerURL == nil, "clearing the field removes it")
    }

    @Test func settingsLoadExistingValues() async {
        let model = SettingsViewModel(services: services(settings: PlaybackSettings(preferredResolution: 720, subtitleLanguage: "fre", streamingServerURL: "http://nas:11470")))
        await model.load()
        #expect(model.settings.preferredResolution == 720 && model.settings.subtitleLanguage == "fre" && model.serverURLText == "http://nas:11470")
        #expect(!model.fallbackEngineLinked, "no engine linked in tests")
    }

    @Test func optionsListsAreComplete() {
        #expect(SettingsViewModel.resolutionOptions.first?.value == nil && SettingsViewModel.resolutionOptions.count == 5)
        let languages = SettingsViewModel.languageOptions
        #expect(languages.first?.label == "Off" && languages.first?.value == nil)
        #expect(languages.contains { $0.value == "eng" && $0.label == "English" } && languages.count > 30)
        #expect(Set(languages.map(\.id)).count == languages.count, "ids are unique")
        #expect(!SettingsViewModel.appVersion.isEmpty)
    }

    // MARK: clearing data

    @Test func eachScopeClearsOnlyItsOwnData() async throws {
        let server = try MockServer.shared()
        let client = AddonClient(configuration: AddonClientConfiguration(timeout: 5, maxRetries: 0))
        let secrets = InMemorySecretStore()
        let registry = AddonRegistry(store: InMemoryAddonStore(), secrets: secrets, client: client)
        _ = try await registry.install(from: server.catalogManifestURL(token: "tok").absoluteString)
        let services = AppServices(registry: registry, client: client, settings: InMemorySettingsStore(PlaybackSettings(subtitleLanguage: "eng")),
                                   progress: InMemoryProgressStore([progress("a", 40)]),
                                   library: InMemoryLibraryStore([LibraryItem(id: "movie/a", type: "movie", contentID: "a", name: "A", addedAt: when)]))
        let reset = DataResetService(services: services)

        let message = await reset.clear(.history)
        #expect(message == "Watch history cleared.")
        var history = await services.progress.all()
        var saved = await services.library.all()
        #expect(history.isEmpty && !saved.isEmpty)
        await reset.clear(.library)
        saved = await services.library.all()
        var current = await services.settings.load()
        #expect(saved.isEmpty && current.subtitleLanguage == "eng")
        await reset.clear(.settings)
        current = await services.settings.load()
        #expect(current == PlaybackSettings())
        var installed = await registry.addons
        #expect(installed.count == 1, "addons survive until asked")
        await reset.clear(.addons)
        installed = await registry.addons
        let remainingSecrets = await secrets.snapshot
        #expect(installed.isEmpty)
        #expect(remainingSecrets.isEmpty, "removing addons removes their saved links")
        history = await services.progress.all()
        #expect(history.isEmpty)
    }

    @Test func everythingClearsEverything() async throws {
        let server = try MockServer.shared()
        let client = AddonClient(configuration: AddonClientConfiguration(timeout: 5, maxRetries: 0))
        let registry = AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client)
        _ = try await registry.install(from: server.catalogManifestURL(token: "tok").absoluteString)
        let services = AppServices(registry: registry, client: client, settings: InMemorySettingsStore(PlaybackSettings(subtitleLanguage: "eng")),
                                   progress: InMemoryProgressStore([progress("a", 40)]), library: InMemoryLibraryStore([LibraryItem(preview: MetaPreview(id: "a", name: "A"))]))
        let model = SettingsViewModel(services: services)
        await model.load()
        await model.clear(.everything)
        #expect(model.lastMessage == "Everything cleared.")
        let history = await services.progress.all()
        let saved = await services.library.all()
        let installed = await registry.addons
        #expect(history.isEmpty && saved.isEmpty && installed.isEmpty)
        #expect(model.settings == PlaybackSettings(), "the screen reloads after a reset")
        #expect(DataResetService.Scope.allCases.allSatisfy { !$0.warning.isEmpty && !$0.title.isEmpty })
    }
}
