import Foundation
import StremioKit
import Testing
import WebKit
@testable import Features

@Suite struct ReviewPageRulesTests {
    @Test func theContentRulesAreWellFormedAndBlockOneHostEach() throws {
        let rules = try #require(JSONSerialization.jsonObject(with: Data(ReviewPageRules.contentRules.utf8)) as? [[String: Any]])
        #expect(rules.count > 1, "a block rule per ad host, then the ad slot hiding")
        for rule in rules {
            let trigger = try #require(rule["trigger"] as? [String: Any])
            let filter = try #require(trigger["url-filter"] as? String)
            #expect(!filter.contains("|"), "WebKit rejects alternation in a url-filter: \(filter)")
        }
        let hides = try rules.suffix(3).map { try #require($0["action"] as? [String: String]) }
        #expect(hides.allSatisfy { $0["type"] == "css-display-none" }, "the ad slots on every site, then IMDb's and Rotten Tomatoes' bars")
        for rule in rules.dropLast(3) {
            let action = try #require(rule["action"] as? [String: String])
            #expect(action["type"] == "block")
        }
    }

    @MainActor
    @Test func webKitCompilesTheContentRules() async {
        let identifier = "tests.review-page-rules.\(UUID().uuidString)"
        let compiled = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier,
                                                                    encodedContentRuleList: ReviewPageRules.contentRules) { list, error in
                if let error { print("WebKit rejected the review page rules: \(error)") }
                continuation.resume(returning: list != nil)
            }
        }
        #expect(compiled, "WebKit compiles every rule, so none is silently dropped")
    }

    @Test func theDarkModeScriptInvertsIMDbAndRottenTomatoesAndTheirPicturesBackAndNoOtherSite() {
        for site in [ReviewSite.imdb, .rottenTomatoes] {
            let script = ReviewPageRules.darkModeScript(for: site) ?? ""
            #expect(script.contains("filter:invert(1)"), "\(site.name)'s page is inverted")
            #expect(script.contains("img,video"), "pictures are inverted back")
            #expect(ReviewPageRules.isShownDark(site))
        }
        #expect(ReviewPageRules.darkModeScript(for: .imdb) == ReviewPageRules.darkModeScript(for: .rottenTomatoes), "one treatment, shared")
        for site in [ReviewSite.letterboxd, .metacritic, .tmdb] {
            #expect(ReviewPageRules.darkModeScript(for: site) == nil, "\(site.name) keeps its own look")
            #expect(!ReviewPageRules.isShownDark(site))
        }
    }

    @Test func rottenTomatoesBarsAreHiddenOnlyOnItsPages() throws {
        let rules = try #require(JSONSerialization.jsonObject(with: Data(ReviewPageRules.contentRules.utf8)) as? [[String: Any]])
        let rottenTomatoes = rules.first { ($0["trigger"] as? [String: Any])?["url-filter"] as? String == "rottentomatoes[.]com" }
        let selector = try #require(((rottenTomatoes?["action"] as? [String: Any])?["selector"]) as? String)
        for part in ["#main > header", "rt-header", "#onetrust-banner-sdk", ".onetrust-pc-dark-filter"] {
            #expect(selector.contains(part), "\(part) is hidden")
        }
    }

    @Test func rottenTomatoesShowsItsOwnPageAndMetacriticTheReader() {
        let item = MetaPreview(id: "tt1517268", type: "movie", name: "Barbie", releaseInfo: "2023")
        #expect(ReviewPageRules.script(for: .rottenTomatoes, item: item).contains(#""reads":false"#))
        #expect(ReviewPageRules.script(for: .metacritic, item: item).contains(#""reads":true"#))
    }

    @Test func theImdbHeaderIsHiddenOnlyOnIMDbPages() throws {
        let rules = try #require(JSONSerialization.jsonObject(with: Data(ReviewPageRules.contentRules.utf8)) as? [[String: Any]])
        let imdb = rules.first { ($0["trigger"] as? [String: Any])?["url-filter"] as? String == "imdb[.]com" }
        let selector = ((imdb?["action"] as? [String: Any])?["selector"]) as? String
        #expect(selector?.contains("[data-testid=atf-wrapper-bg]") == true, "the white header block is hidden on IMDb")
        #expect(selector?.contains("#imdbHeader") == true, "and IMDb's header bar")
    }

    @Test func theLetterboxdScriptGoesOnFromAFilmToItsReviews() {
        let script = ReviewPageRules.script(for: .letterboxd)
        #expect(script.contains("location.replace"))
        #expect(script.contains("'reviews/'"))
    }

    @Test func theOtherSitesScrollToTheirUserReviewsHeading() {
        for site in [ReviewSite.imdb, .rottenTomatoes, .metacritic, .tmdb] {
            #expect(ReviewPageRules.script(for: site).contains("(user|audience) reviews?"), "\(site.name) looks for its user reviews heading")
        }
    }
}
