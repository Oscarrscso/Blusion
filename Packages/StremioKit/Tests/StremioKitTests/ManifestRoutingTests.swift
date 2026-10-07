import Foundation
import Testing
@testable import StremioKit

private func manifest(_ file: String) throws -> Manifest {
    try ResponseDecoder.manifest(from: Fixture.data("manifests/\(file)"))
}

@Suite struct RoutingTests {
    @Test func resourceLevelPrefixesWinOverTopLevel() throws {
        let m = try manifest("05-resource-level-idprefixes.json")
        #expect(m.supports(.stream, type: "movie", id: "tt123"))
        #expect(!m.supports(.stream, type: "movie", id: "custom:1"))
        #expect(m.supports(.meta, type: "movie", id: "custom:1"))
        #expect(!m.supports(.meta, type: "movie", id: "tt123"))
        // top-level `ignored:` must not apply where a resource declares its own prefixes
        #expect(!m.supports(.stream, type: "movie", id: "ignored:1"))
    }

    @Test func topLevelPrefixesApplyToStringResources() throws {
        let m = try manifest("04-top-level-idprefixes.json")
        #expect(m.supports(.stream, type: "series", id: "kitsu:5"))
        #expect(m.supports(.stream, type: "movie", id: "tt0000001"))
        #expect(!m.supports(.stream, type: "movie", id: "xyz"))
    }

    @Test func noPrefixesMatchEverything() throws {
        let m = try manifest("11-stream-only.json")
        #expect(m.supports(.stream, type: "movie", id: "anything:at:all"))
        #expect(m.supports(.stream, type: "movie", id: ""))
    }

    @Test func typesAreRespected() throws {
        let m = try manifest("11-stream-only.json")
        #expect(!m.supports(.stream, type: "series", id: "tt1"))
        let objects = try manifest("02-object-resources.json")
        #expect(objects.supports(.subtitles, type: "series", id: "whatever"))
        #expect(!objects.supports(.stream, type: "movie", id: "whatever"))
        #expect(objects.supports(.stream, type: "movie", id: "tt1"))
    }

    @Test func resourcesNotListedAreNeverRouted() throws {
        let m = try manifest("11-stream-only.json")
        #expect(!m.supports(.meta, type: "movie", id: "tt1"))
        #expect(!m.supports(.catalog, type: "movie", id: "tt1"))
        #expect(!m.provides(.subtitles))
        #expect(m.provides(.stream))
    }

    @Test func manifestWithoutAnyTypesAcceptsEveryType() throws {
        let m = try manifest("08-null-arrays.json")
        #expect(m.types.isEmpty)
        #expect(m.supports(.stream, type: "movie", id: "tt1"))
        #expect(m.supports(.stream, type: "tv", id: "x"))
    }

    @Test func emptyPrefixListsMeanNoRestriction() {
        let m = Manifest(id: "a", name: "A", resources: [ResourceDescriptor(name: "stream", types: ["movie"], idPrefixes: [])], types: ["movie"], idPrefixes: [])
        #expect(m.supports(.stream, type: "movie", id: "whatever"))
    }

    @Test func catalogHelpersRequireTheCatalogResource() throws {
        let m = try manifest("08-null-arrays.json")
        #expect(m.browsableCatalogs().isEmpty)
        let streamOnly = Manifest(id: "a", name: "A", resources: [ResourceDescriptor(name: "stream")], types: ["movie"],
                                  catalogs: [CatalogDescriptor(type: "movie", id: "x")])
        #expect(streamOnly.browsableCatalogs().isEmpty)
        #expect(streamOnly.searchableCatalogs.isEmpty)
    }
}
