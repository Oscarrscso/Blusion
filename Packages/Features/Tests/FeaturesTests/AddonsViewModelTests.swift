import Foundation
import Testing
import StremioKit
import StremioKitTestSupport
@testable import Features

@MainActor
@Suite struct AddonsViewModelTests {
    let token = "tok_SECRET_77"

    private func make(_ server: MockServer) -> (AddonsViewModel, AppServices) {
        let client = AddonClient(configuration: AddonClientConfiguration(timeout: 5, maxRetries: 0))
        let services = AppServices(registry: AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client), client: client)
        return (AddonsViewModel(services: services), services)
    }

    @Test func installingFromTheTextFieldClearsItAndReportsTheName() async throws {
        let server = try MockServer.shared()
        let (model, _) = make(server)
        #expect(!model.canInstall)
        model.installText = "  \(server.catalogManifestURL(token: token).absoluteString)  "
        #expect(model.canInstall)
        await model.install()
        #expect(model.lastInstalledName == "Mock Catalog")
        #expect(model.installText.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(!model.isInstalling)
    }

    @Test func installErrorsAreReadableAndKeepTheText() async throws {
        let server = try MockServer.shared()
        let (model, _) = make(server)
        model.installText = "ftp://example.com/x"
        await model.install()
        #expect(model.errorMessage?.contains("ftp") == true)
        #expect(model.installText == "ftp://example.com/x", "the user can correct it")
        #expect(model.lastInstalledName == nil)
        model.installText = server.catalogManifestURL(flags: ["badmanifest"]).absoluteString
        await model.install()
        #expect(model.errorMessage?.hasPrefix("Couldn't load the addon") == true)
        model.installText = server.catalogManifestURL(flags: ["manifest500"], token: token).absoluteString
        await model.install()
        #expect(model.errorMessage?.contains(token) == false)
        model.clearMessages()
        #expect(model.errorMessage == nil)
    }

    @Test func installingTwiceExplainsItself() async throws {
        let server = try MockServer.shared()
        let (model, _) = make(server)
        model.installText = server.catalogManifestURL(token: token).absoluteString
        await model.install()
        model.installText = server.catalogManifestURL(token: token).absoluteString
        await model.install()
        #expect(model.errorMessage == "This addon is already installed.")
    }

    @Test func removeEnableAndReorderGoThroughTheRegistry() async throws {
        let server = try MockServer.shared()
        let (model, services) = make(server)
        let observing = Task { await model.observe() }
        for name in ["a", "b", "c"] {
            model.installText = server.catalogManifestURL(token: name).absoluteString
            await model.install()
        }
        try await waitUntil { model.addons.count == 3 }
        let ids = model.addons.map(\.id)
        await model.move(fromOffsets: [2], toOffset: 0)
        try await waitUntil { model.addons.map(\.id) == [ids[2], ids[0], ids[1]] }
        await model.setEnabled(false, id: ids[0])
        try await waitUntil { model.addons.first { $0.id == ids[0] }?.isEnabled == false }
        await model.remove(id: ids[1])
        try await waitUntil { model.addons.count == 2 }
        #expect(await services.registry.addons.count == 2)
        await model.remove(id: UUID())
        #expect(model.errorMessage == "That addon is no longer installed.")
        observing.cancel()
    }

    @Test func detailsDescribeTheAddonWithoutItsURL() async throws {
        let server = try MockServer.shared()
        let (model, services) = make(server)
        let addon = try await services.registry.install(from: server.catalogManifestURL(token: token).absoluteString)
        let details = model.details(for: addon)
        #expect(details.name == "Mock Catalog")
        #expect(details.resources == ["catalog", "meta"])
        #expect(details.types == ["movie", "series"])
        #expect(details.catalogs.contains("Mock Movies (movie)"))
        #expect(details.idPrefixes == ["mock:"])
        #expect(details.manifestJSON.contains("\"id\" : \"org.blusion.mock.catalog\""))
        let everything = "\(details)"
        #expect(!everything.contains(token))
        #expect(details.host.hasPrefix("127.0.0.1") || details.host.hasPrefix("localhost"))
    }

    @Test func theSuggestionIsCatalogsOnlyAndNeverAStreamAddon() {
        let suggestion = AddonsViewModel.suggestion
        #expect(suggestion.manifestURL == "https://v3-cinemeta.strem.io/manifest.json")
        #expect(suggestion.detail.contains("no streams"))
        #expect((try? AddonURLNormaliser.normalise(suggestion.manifestURL)) != nil)
    }
}
