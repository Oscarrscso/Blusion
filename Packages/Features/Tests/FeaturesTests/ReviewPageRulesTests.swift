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
        let last = try #require(rules.last?["action"] as? [String: String])
        #expect(last["type"] == "css-display-none")
        for rule in rules.dropLast() {
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

    @Test func theDarkModeScriptInvertsThePageAndItsPicturesBack() {
        let script = ReviewPageRules.darkModeScript
        #expect(script.contains("filter:invert(1)"), "the page is inverted")
        #expect(script.contains("img,video"), "pictures are inverted back")
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
