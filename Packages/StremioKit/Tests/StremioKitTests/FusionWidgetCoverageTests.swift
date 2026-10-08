import Foundation
import Testing
@testable import StremioKit

/// The Fusion widget types and sources found in Fusion's own starter-kit exports, and how each one reads, keeps and writes back.
@Suite struct FusionWidgetCoverageTests {
    private func decode(_ text: String) throws -> FusionWidgetCodec.ImportResult {
        try FusionWidgetCodec.decode(Data(text.utf8), installed: [])
    }

    private func roundTrip(_ widgets: [HomeWidget]) throws -> [[String: Any]] {
        let data = try FusionWidgetCodec.encode(widgets)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["widgets"] as? [[String: Any]])
    }

    @Test func aNumberedRowDecodesAsARowWithRanks() throws {
        let result = try decode(#"""
        { "widgets": [
          { "id": "top", "title": "Top 10", "type": "row.classic.numbered", "limit": 10,
            "presentation": { "aspectRatio": "poster", "cardStyle": "medium", "badges": { "providers": false, "ratings": true } },
            "dataSource": { "kind": "traktList", "payload": { "listName": "Top", "listSlug": "top", "username": "u" } } }
        ] }
        """#)
        #expect(result.skipped == 0)
        let widget = try #require(result.widgets.first)
        guard case .row(let row) = widget.content else {
            Issue.record("a numbered row should decode to a row")
            return
        }
        #expect(row.presentation.showsRank, "the card carries its rank")
        #expect(row.limit == 10)
        #expect(row.presentation.aspectRatio == .poster && row.presentation.showsRatings)
    }

    @Test func aNumberedRowWritesBackAsNumbered() throws {
        let row = RowConfiguration(source: .traktList(TraktListReference(username: "u", listSlug: "s", listName: "S")),
                                   presentation: WidgetPresentation(showsRank: true))
        let written = try roundTrip([HomeWidget(id: "n", title: "N", content: .row(row))])
        #expect(written.first?["type"] as? String == "row.classic.numbered")

        let again = try FusionWidgetCodec.decode(try FusionWidgetCodec.encode([HomeWidget(id: "n", title: "N", content: .row(row))]), installed: [])
        #expect(again.widgets.first?.content == .row(row))
    }

    @Test func aPlainRowIsNotNumbered() throws {
        let row = RowConfiguration(source: .traktList(TraktListReference(username: "u", listSlug: "s", listName: "S")))
        let written = try roundTrip([HomeWidget(id: "p", title: "P", content: .row(row))])
        #expect(written.first?["type"] as? String == "row.classic")
    }

    @Test func anUnknownWidgetTypeIsKeptWithItsTypeAndWrittenBack() throws {
        let result = try decode(#"""
        { "widgets": [ { "id": "cal", "title": "Calendar", "type": "calendar.week", "dataSource": { "kind": "traktCalendar", "payload": { "x": 1 } } } ] }
        """#)
        #expect(result.skipped == 0)
        #expect(result.widgets.first?.content == .unsupported(type: "calendar.week"))
        #expect(result.widgets.first?.title == "Calendar")

        let written = try roundTrip(result.widgets)
        #expect(written.first?["type"] as? String == "calendar.week", "the type survives a round trip")
        #expect(written.first?["dataSource"] == nil, "the unreadable contents are not kept")
    }

    @Test func aTraktRecommendationsSourceIsKeptAsUnsupported() throws {
        let result = try decode(#"""
        { "widgets": [ { "id": "rec", "title": "For you", "type": "row.classic",
            "dataSource": { "kind": "traktRecommendations", "payload": { "ignoreWatchlisted": true, "limit": 20, "type": "movies" } } } ] }
        """#)
        guard case .row(let row) = result.widgets.first?.content else {
            Issue.record("the row should be kept")
            return
        }
        #expect(row.source == .unsupported(kind: "traktRecommendations"))
    }

    @Test func aTmdbDiscoverTileSourceIsKeptAsUnsupported() throws {
        let result = try decode(#"""
        { "widgets": [ { "id": "c", "title": "Genres", "type": "collection.row",
            "dataSource": { "kind": "collection", "payload": { "items": [
              { "id": "t1", "title": "Action", "imageAspect": "wide",
                "dataSources": [ { "kind": "tmdbDiscover", "payload": { "includeGenres": [28], "sortBy": "popularity.desc", "type": "movie" } } ] } ] } } } ] }
        """#)
        let tile = try #require(result.widgets.first.flatMap { widget -> CollectionItem? in
            if case .collection(let tiles) = widget.content { return tiles.first }
            return nil
        })
        #expect(tile.sources == [.unsupported(kind: "tmdbDiscover")])
    }

    @Test func aPresentationWithoutRankStillDecodes() throws {
        let json = #"{"aspectRatio":"wide","cardStyle":"large","showsRatings":false,"showsProviders":true}"#
        let presentation = try JSONDecoder().decode(WidgetPresentation.self, from: Data(json.utf8))
        #expect(presentation == WidgetPresentation(aspectRatio: .wide, cardStyle: .large, showsRatings: false, showsProviders: true, showsRank: false))
    }
}
