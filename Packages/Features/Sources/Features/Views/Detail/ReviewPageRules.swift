import StremioKit

/// What a rating's review page loads with: the ad and tracker requests it may not make, the ad slots it hides, and a script that opens the
/// page's user reviews. These are plain data and script text. `ReviewWebView` compiles and attaches them.
enum ReviewPageRules {
    /// The identifier WebKit keeps the compiled rules under.
    static let identifier = "app.blusion.review-page-rules"

    /// The ad-serving and tracking hosts whose requests are blocked, one rule each: WebKit's content-blocking patterns have no alternation,
    /// so a rule with `(a|b)` makes WebKit reject the whole list. A dot is written `[.]`, so no backslash needs escaping in the JSON.
    private static let adHosts = [
        "doubleclick[.]net", "googlesyndication[.]com", "googleadservices[.]com", "adservice[.]google[.][a-z]+",
        "taboola[.]com", "outbrain[.]com", "criteo[.]com", "criteo[.]net", "amazon-adsystem[.]com", "adnxs[.]com",
        "pubmatic[.]com", "rubiconproject[.]com", "openx[.]net", "moatads[.]com", "scorecardresearch[.]com",
    ]

    /// The ad slots: Google's, and IMDb's sticky bottom ad, a fixed "adhesion" wrapper with inline ad frames inside it.
    private static let adSlots = "ins.adsbygoogle, div[id^=div-gpt-ad], div[id^=adhesion_], div[class*=AdhesionAdSlot], iframe[id^=inline]"

    /// WebKit content-blocking rules, as JSON. Requests to ad-serving and tracking hosts are blocked, and the common ad slots are hidden
    /// where they remain.
    static var contentRules: String {
        let blocks = adHosts.map { #"{"trigger": {"url-filter": "\#($0)"}, "action": {"type": "block"}}"# }
        let hides = [#"{"trigger": {"url-filter": ".*"}, "action": {"type": "css-display-none", "selector": "\#(adSlots)"}}"#]
        return "[\n" + (blocks + hides).joined(separator: ",\n") + "\n]"
    }

    /// The script for a site, run once the page's document is ready. Letterboxd's address for a title opens the film's page, which goes on
    /// to the film's reviews. The other sites load their user reviews after the page, so the script scrolls to their heading once it is
    /// there. RT and Metacritic can also resolve a title search and read the reviews from the page already being loaded.
    static func script(for site: ReviewSite, item: MetaPreview? = nil) -> String {
        if let item, ReviewPageReader.supports(site) { return ReviewPageReader.script(for: site, item: item) }
        switch site {
        case .letterboxd: return letterboxdScript
        case .imdb, .rottenTomatoes, .metacritic, .tmdb: return reviewsHeadingScript
        }
    }

    private static let letterboxdScript = """
    (function () {
      if (/^\\/film\\/[^\\/]+\\/?$/.test(location.pathname)) {
        location.replace(location.pathname.replace(/\\/?$/, '/') + 'reviews/');
      }
    })();
    """

    private static let reviewsHeadingScript = """
    (function () {
      var heading = /^\\s*(user|audience) reviews?\\s*$/i;
      var tries = 0;
      var timer = setInterval(function () {
        tries += 1;
        var nodes = document.querySelectorAll('h1, h2, h3, h4, h5, a, span, button');
        for (var i = 0; i < nodes.length; i++) {
          if (heading.test(nodes[i].textContent || '')) {
            nodes[i].scrollIntoView({ block: 'start' });
            clearInterval(timer);
            return;
          }
        }
        if (tries >= 20) { clearInterval(timer); }
      }, 500);
    })();
    """
}
