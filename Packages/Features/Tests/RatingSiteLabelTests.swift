import StremioKit
import Testing
@testable import Features

/// Exactly two rating sites replace their logos with coloured uppercase names. One site, or three or more, keep the logos.
@Suite struct RatingSiteLabelTests {
    @Test func exactlyTwoSitesUseNames() {
        #expect(RatingSiteLabel.usesName(siteCount: 2))
    }

    @Test func otherCountsKeepLogos() {
        for count in [0, 1, 3, 4, 6] {
            #expect(!RatingSiteLabel.usesName(siteCount: count))
        }
    }

    @Test func namesAreTheUppercaseSiteNames() {
        #expect(RatingSiteLabel.text(for: .imdb) == "IMDB")
        #expect(RatingSiteLabel.text(for: .tmdb) == "TMDB")
        #expect(RatingSiteLabel.text(for: .letterboxd) == "LETTERBOXD")
        #expect(RatingSiteLabel.text(for: .rottenTomatoes) == "ROTTEN TOMATOES")
        #expect(RatingSiteLabel.text(for: .metacritic) == "METACRITIC")
        #expect(RatingSiteLabel.text(for: .myAnimeList) == "MYANIMELIST")
    }

    @Test func myAnimeListNameIsLighterThanItsLogo() throws {
        // The logo fill is a dark ground. The name keeps that blue, lifted so it reads on the pill.
        #expect(RatingSiteLabel.colourHex(for: .myAnimeList) != "2E51A2")
        let value = try #require(UInt32(RatingSiteLabel.colourHex(for: .myAnimeList), radix: 16))
        #expect(value & 0xFF > 0xA2)
    }

    @Test func everySiteHasItsOwnBrandColour() {
        let hexes = ReviewSite.allCases.map { site in
            let name = RatingSiteLabel.name(for: site)
            #expect(name.text == RatingSiteLabel.text(for: site))
            #expect(name.colourHex == RatingSiteLabel.colourHex(for: site))
            #expect(UInt32(name.colourHex, radix: 16) != nil)
            #expect(name.colourHex.count == 6)
            return name.colourHex
        }
        #expect(Set(hexes).count == ReviewSite.allCases.count)
    }
}
