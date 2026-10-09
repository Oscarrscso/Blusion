import Foundation
import Testing
@testable import StremioKit

@Suite struct LibraryAndSettingsTests {
    private let when = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: library

    @Test func libraryItemsRoundTripThroughPreviews() {
        let preview = MetaPreview(id: "tt1", type: "movie", name: "Film", poster: URL(string: "https://e.com/p.jpg"), releaseInfo: "1999")
        let item = LibraryItem(preview: preview, addedAt: when)
        #expect(item.id == "movie/tt1" && item.contentID == "tt1" && item.type == "movie")
        #expect(item.preview.id == "tt1" && item.preview.name == "Film" && item.preview.poster == preview.poster && item.preview.releaseInfo == "1999")
        #expect(LibraryItem(preview: MetaPreview(id: "tt2", name: "No type"), addedAt: when).type == "movie", "an empty type defaults to movie")
        #expect(LibraryItem.identity(type: "series", contentID: "tt9") == "series/tt9")
        let encoded = try? JSONEncoder().encode(item)
        #expect(encoded.flatMap { try? JSONDecoder().decode(LibraryItem.self, from: $0) } == item)
    }

    @Test func inMemoryLibraryAddsRemovesAndOrdersByRecency() async {
        let store = InMemoryLibraryStore()
        func item(_ id: String, _ age: TimeInterval) -> LibraryItem {
            LibraryItem(id: "movie/\(id)", type: "movie", contentID: id, name: id, addedAt: when.addingTimeInterval(age))
        }
        await store.add(item("old", 0))
        await store.add(item("new", 100))
        await store.add(item("old", 0))   // adding twice keeps one
        #expect(await store.all().map(\.contentID) == ["new", "old"])
        let hasNew = await store.contains("movie/new")
        let hasNone = await store.contains("movie/none")
        #expect(hasNew && !hasNone)
        await store.remove("movie/new")
        #expect(await store.all().map(\.contentID) == ["old"])
        await store.clear()
        #expect(await store.all().isEmpty)
    }

    // MARK: settings

    private func isolatedDefaults() -> UserDefaults {
        let name = "blusion.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsRoundTripAndTheServerURLGoesToTheSecretStore() async {
        let defaults = isolatedDefaults()
        let secrets = InMemorySecretStore()
        let store = DefaultsSettingsStore(defaults: defaults, secrets: secrets)
        #expect(await store.load() == PlaybackSettings(), "fresh install: all defaults")

        let settings = PlaybackSettings(preferredResolution: 1080, subtitleLanguage: "eng", streamingServerURL: "http://user:pw@192.168.1.9:11470",
                                        fallbackEngineEnabled: false, traktClientID: "client-abc", playerPreference: .infuse,
                                        showsPosterRatings: false, autoPlayBestStream: true, tmdbReadToken: "tmdb-test-token")
        await store.save(settings)
        #expect(await store.load() == settings)
        #expect(await secrets.snapshot[DefaultsSettingsStore.Keys.serverSecret] == "http://user:pw@192.168.1.9:11470")
        #expect(await secrets.snapshot[DefaultsSettingsStore.Keys.traktClientSecret] == "client-abc", "the Trakt client ID is a secret too")
        let stored = String(describing: defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("settings.") })
        #expect(!stored.contains("192.168.1.9") && !stored.contains("pw@"), "the server URL is never written to UserDefaults")
        #expect(!stored.contains("client-abc"), "the Trakt client ID is never written to UserDefaults")
        #expect(await secrets.snapshot[DefaultsSettingsStore.Keys.tmdbReadToken] == "tmdb-test-token")
        #expect(!stored.contains("tmdb-test-token"), "the TMDb credential stays out of UserDefaults")
    }

    @Test func clearingValuesRemovesThem() async {
        let defaults = isolatedDefaults()
        let secrets = InMemorySecretStore()
        let store = DefaultsSettingsStore(defaults: defaults, secrets: secrets)
        await store.save(PlaybackSettings(preferredResolution: 720, subtitleLanguage: "fre", streamingServerURL: "http://nas:11470", traktClientID: "client",
                                         tmdbReadToken: "tmdb-token"))
        await store.save(PlaybackSettings(preferredResolution: nil, subtitleLanguage: nil, streamingServerURL: "   ", traktClientID: "  "))
        let loaded = await store.load()
        #expect(loaded.preferredResolution == nil && loaded.subtitleLanguage == nil && loaded.streamingServerURL == nil && loaded.traktClientID == nil)
        #expect(loaded.tmdbReadToken == nil)
        #expect(await secrets.snapshot.isEmpty, "blank values delete their secrets")
        #expect(loaded.fallbackEngineEnabled, "the fallback toggle defaults to on")
    }

    @Test func theTraktClientIDIsTrimmedStoredAsASecretAndClearable() async {
        let defaults = isolatedDefaults()
        let secrets = InMemorySecretStore()
        let store = DefaultsSettingsStore(defaults: defaults, secrets: secrets)
        let initial = await store.load().traktClientID
        #expect(initial == nil, "no client ID until the user adds one")

        await store.save(PlaybackSettings(traktClientID: "  client-abc \n"))
        let loaded = await store.load().traktClientID
        #expect(loaded == "client-abc")
        #expect(await secrets.snapshot[DefaultsSettingsStore.Keys.traktClientSecret] == "client-abc")

        await store.save(PlaybackSettings(traktClientID: nil))
        let cleared = await store.load().traktClientID
        #expect(cleared == nil)
        #expect(await secrets.snapshot[DefaultsSettingsStore.Keys.traktClientSecret] == nil)
    }

    @Test func settingsDeriveTheirPolicies() {
        let settings = PlaybackSettings(preferredResolution: 720, streamingServerURL: " http://192.168.1.9:11470/ ", fallbackEngineEnabled: true)
        #expect(settings.serverURL?.absoluteString == "http://192.168.1.9:11470/")
        #expect(settings.rankingPreferences.preferredResolution == 720)
        #expect(settings.policy(fallbackEngineLinked: true).fallbackEngineAvailable)
        #expect(!settings.policy(fallbackEngineLinked: false).fallbackEngineAvailable, "not linked: never available")
        var off = settings
        off.fallbackEngineEnabled = false
        #expect(!off.policy(fallbackEngineLinked: true).fallbackEngineAvailable)
        #expect(settings.policy(fallbackEngineLinked: true).playerPreference == .infuseWhenNeeded,
                "by default Infuse takes only what Blusion's own player cannot open")
        var infuse = settings
        infuse.playerPreference = .infuse
        #expect(infuse.policy(fallbackEngineLinked: false).playerPreference == .infuse)
        #expect(PlayerPreference.builtIn.externalPlayer == nil)
        #expect(PlayerPreference.infuseWhenNeeded.externalPlayer == .infuse)
        for bad in ["", "   ", "not a url", "ftp://nas.local", "nas:11470", "//nas"] { #expect(PlaybackSettings(streamingServerURL: bad).serverURL == nil, "\(bad)") }
    }

    @Test func serverURLValidationMessages() {
        #expect(PlaybackSettings.validationMessage(forServerURL: "") == nil)
        #expect(PlaybackSettings.validationMessage(forServerURL: "  ") == nil)
        #expect(PlaybackSettings.validationMessage(forServerURL: "http://192.168.1.10:11470") == nil)
        #expect(PlaybackSettings.validationMessage(forServerURL: "https://nas.example.com") == nil)
        #expect(PlaybackSettings.validationMessage(forServerURL: "ftp://nas.example.com")?.contains("http") == true)
        #expect(PlaybackSettings.validationMessage(forServerURL: "nas")?.contains("full address") == true)
    }
}
