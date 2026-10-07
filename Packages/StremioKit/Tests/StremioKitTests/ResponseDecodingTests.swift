import Foundation
import Testing
@testable import StremioKit

@Suite struct ResponseDecodingTests {
    private func data(_ name: String) throws -> Data { try Fixture.data("responses/\(name).json") }

    private struct MissingMeta: Error {}

    private func loadMeta(_ blob: Data, defaultType: String = "") throws -> MetaDetail {
        guard let detail = try ResponseDecoder.meta(from: blob, defaultType: defaultType) else { throw MissingMeta() }
        return detail
    }

    @Test func catalogBasic() throws {
        let metas = try ResponseDecoder.catalog(from: data("catalog-basic"), defaultType: "movie")
        #expect(metas.map(\.id) == ["tt0000001", "tt0000002"])
        #expect(metas[0].imdbRating == 7.5)
        #expect(metas[0].genres == ["Action", "Drama"])
        #expect(metas[0].releaseInfo == "1999")
        #expect(metas[0].poster?.absoluteString == "https://example.com/1.jpg")
    }

    @Test func catalogNumbersAsStrings() throws {
        let m = try #require(ResponseDecoder.catalog(from: data("catalog-strnums")).first)
        #expect(m.imdbRating == 8.1)
        #expect(m.releaseInfo == "2010")
        #expect(m.runtime == "120")
    }

    @Test func catalogDropsBadItemsAndKeepsGoodOnes() throws {
        let metas = try ResponseDecoder.catalog(from: data("catalog-nulls"))
        #expect(metas.map(\.id) == ["tt0000004", "tt0000005"])
        #expect(metas[0].genres.isEmpty)
        #expect(metas[0].poster == nil)
        #expect(metas[1].poster == nil, "about:blank is not a poster")
        #expect(metas[1].genres == ["Action", "Comedy"])
    }

    @Test func nullOrWronglyShapedMetasAreEmptyNotErrors() throws {
        #expect(try ResponseDecoder.catalog(from: data("catalog-metas-null")).isEmpty)
        #expect(try ResponseDecoder.catalog(from: data("catalog-wrong-shape")).isEmpty)
        #expect(try ResponseDecoder.catalog(from: Data("{}".utf8)).isEmpty)
        #expect(try ResponseDecoder.catalog(from: Data(#"{"err": "nope"}"#.utf8)).isEmpty)
    }

    @Test func defaultTypeFillsMissingType() throws {
        let metas = try ResponseDecoder.catalog(from: data("catalog-nulls"), defaultType: "movie")
        #expect(metas.allSatisfy { $0.type == "movie" })
        let explicit = try ResponseDecoder.catalog(from: data("catalog-basic"), defaultType: "series")
        #expect(explicit.allSatisfy { $0.type == "movie" }, "an explicit type is never overwritten")
    }

    @Test func metaDetail() throws {
        let meta = try loadMeta(data("meta-movie"))
        #expect(meta.name == "One")
        #expect(meta.preview.imdbRating == 7.5)
        #expect(meta.released == "1999-03-31T00:00:00.000Z")
        #expect(meta.preview.runtime == "136 min")
        #expect(meta.director == ["Dir A"])
        #expect(meta.cast == ["Actor A", "Actor B"])
        #expect(meta.writers == ["Writer A"])
        #expect(meta.links.map(\.name) == ["Action"], "a link without a name is dropped")
        #expect(meta.defaultVideoID == "tt0000001")
        #expect(meta.preview.background?.host == "example.com")
    }

    @Test func seriesEpisodesAreGroupedAndOrdered() throws {
        let meta = try loadMeta(data("meta-series"))
        #expect(meta.videos.count == 4, "the video without an id is dropped")
        #expect(meta.seasons == [1, 2, 0], "specials last")
        #expect(meta.episodes(inSeason: 1).map(\.title) == ["One", "Two"])
        #expect(meta.episodes(inSeason: 1).first?.season == 1, "season given as a string is coerced")
        #expect(meta.episodes(inSeason: 9).isEmpty)
    }

    @Test func missingMetaIsNilNotAnError() throws {
        #expect(try ResponseDecoder.meta(from: data("meta-missing")) == nil)
        #expect(try ResponseDecoder.meta(from: Data("{}".utf8)) == nil)
        #expect(try ResponseDecoder.meta(from: Data(#"{"meta": {"name": "no id"}}"#.utf8)) == nil)
    }

    @Test func metaDefaultTypeAndFallback() throws {
        let meta = try loadMeta(Data(#"{"meta": {"id": "x"}}"#.utf8), defaultType: "movie")
        #expect(meta.type == "movie")
        let preview = MetaPreview(id: "p", type: "movie", name: "P")
        #expect(MetaDetail.fallback(from: preview).name == "P")
        #expect(MetaDetail.fallback(from: preview).videos.isEmpty)
    }

    @Test func metaRoundTrips() throws {
        let meta = try loadMeta(data("meta-series"))
        let again = try JSONDecoder().decode(MetaDetail.self, from: JSONEncoder().encode(meta))
        #expect(again == meta)
        let movie = try loadMeta(data("meta-movie"))
        #expect(try JSONDecoder().decode(MetaDetail.self, from: JSONEncoder().encode(movie)) == movie)
    }

    @Test func streamsOfEveryKind() throws {
        let streams = try ResponseDecoder.streams(from: data("streams-all-kinds"))
        #expect(streams.count == 8)
        #expect(streams[0].source == .direct(URL(string: "https://cdn.example.com/a.mp4")!))
        #expect(streams[0].description == "1080p\nline two")
        #expect(streams[0].behaviorHints.bingeGroup == "g1")
        #expect(streams[0].behaviorHints.videoSize == 1_048_576)
        #expect(streams[0].behaviorHints.filename == "a.mp4")
        #expect(streams[1].source == .torrent(infoHash: "abcdef0123456789abcdef0123456789abcdef01", fileIndex: 2, sources: ["tracker:udp://t.example:1"]))
        #expect(streams[1].description == "legacy title", "legacy `title` maps to description")
        #expect(streams[2].source == .youtube("aqz-KE-bpKQ"))
        #expect(streams[3].source == .external(URL(string: "https://example.com/watch")!))
        #expect(streams[4].source == .archive(kind: "nzbUrl"))
        #expect(streams[5].source == .archive(kind: "rarUrls"))
        #expect(streams[6].behaviorHints.notWebReady)
        #expect(streams[6].behaviorHints.proxyHeaders?.request == ["Referer": "https://example.com"])
        #expect(streams[6].behaviorHints.proxyHeaders?.response == ["X": "1"])
        #expect(streams[7].subtitles.count == 1, "a subtitle without a url is dropped")
    }

    @Test func streamsWithoutUsableSourceAreDropped() throws {
        let streams = try ResponseDecoder.streams(from: data("streams-bad-items"))
        #expect(streams.map(\.name) == ["ok"])
    }

    @Test func streamsRoundTrip() throws {
        let streams = try ResponseDecoder.streams(from: data("streams-all-kinds"))
        let encoded = try JSONEncoder().encode(["streams": streams])
        #expect(try ResponseDecoder.streams(from: encoded) == streams)
    }

    @Test func streamDisplayName() {
        let url = URL(string: "https://e.com/a.mp4")!
        #expect(AddonStream(name: "N", source: .direct(url)).displayName == "N")
        #expect(AddonStream(description: "first\nsecond", source: .direct(url)).displayName == "first")
        #expect(AddonStream(source: .direct(url)).displayName == "Stream")
    }

    @Test func subtitles() throws {
        let subs = try ResponseDecoder.subtitles(from: data("subtitles-basic"))
        #expect(subs.map(\.lang) == ["eng", "spa"])
        #expect(subs[0].id == "1")
        #expect(subs[1].id == "https://example.com/es.vtt", "id falls back to the url")
    }

    @Test func garbageIsInvalidJSONForEveryResource() {
        let junk = [Data(), Data("not json".utf8), Data("[]".utf8), Data("null".utf8), Data("{\"metas\":".utf8)]
        for blob in junk {
            #expect(throws: AddonError.invalidJSON) { try ResponseDecoder.catalog(from: blob) }
            #expect(throws: AddonError.invalidJSON) { try ResponseDecoder.meta(from: blob) }
            #expect(throws: AddonError.invalidJSON) { try ResponseDecoder.streams(from: blob) }
            #expect(throws: AddonError.invalidJSON) { try ResponseDecoder.subtitles(from: blob) }
        }
    }
}
