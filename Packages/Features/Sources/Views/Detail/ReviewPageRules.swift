import Foundation
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

    /// The ad slots on every site: Google's, and IMDb's sticky bottom ad, a fixed "adhesion" wrapper with inline ad frames inside it.
    private static let adSlots = "ins.adsbygoogle, div[id^=div-gpt-ad], div[id^=adhesion_], div[class*=AdhesionAdSlot], iframe[id^=inline]"

    /// IMDb's own header on its reviews page: the header bar with sign-in and app links, and the white block with Back, the title and the
    /// "User reviews" heading. Only IMDb's pages hide them, so the reviews panel starts at the count and "Add a review".
    private static let imdbHeaderSlots = "#imdbHeader, [data-testid=atf-wrapper-bg], .ipc-scroll-to-top-button"

    /// Rotten Tomatoes' own bars: its header (the leaderboard ad and the navigation bar), the app banner, the notification bar, and its
    /// cookie banner and the shade behind it, which cover the page. Only Rotten Tomatoes' pages hide them, so the reviews panel starts at the
    /// reviews' heading.
    private static let rottenTomatoesHeaderSlots = "#main > header, rt-header, mobile-android-banner, notification-alert, back-to-top, "
        + "#onetrust-consent-sdk, #onetrust-banner-sdk, .onetrust-pc-dark-filter"

    /// TMDB's own bars: its header (logo, menus, search), the bar of title links under it, and the block with the title and "Back to main",
    /// and its cookie banner. Only TMDB's pages hide them, so the reviews panel starts at the first review.
    private static let tmdbHeaderSlots = "header.main-header, .shortcut_bar_outer, #new_shortcut_bar, div.header.small.first, "
        + "#onetrust-consent-sdk, #onetrust-banner-sdk, .onetrust-pc-dark-filter"

    /// Metacritic's own navigation bar (logo, menu, search, sign-in), its cookie banner, and its ads: Fandom's ad slots, which hold their
    /// space (a 300 by 250 box above the reviews, a top banner, more between reviews) before an ad loads. Only Metacritic's pages hide them,
    /// so the reviews panel starts at the title's "User Reviews" and the reviews follow on with no gaps. A content rule keeps applying to
    /// slots the page adds later, as it scrolls.
    private static let metacriticHeaderSlots = "header.c-site-header, #onetrust-consent-sdk, #onetrust-banner-sdk, .onetrust-pc-dark-filter, "
        + ".fandom-ad-wrapper, .fandom-ad-placeholder, .fandom-ad-sticky-container, [id^=incontent_boxad], #top_leaderboard"

    /// MyAnimeList's own bars and the title's block above its reviews: its header and menu (phone and desktop layouts), the ribbon and
    /// billboard ads, the anchored bottom ad, the title's picture and details, the breadcrumb, and its cookie banner. Only MyAnimeList's
    /// pages hide them, so the reviews panel starts at the reviews.
    private static let myAnimeListHeaderSlots = "#header, #headerSmall, #menu, .text-ribbon, .ad-block-for-billboard, .koukoku_unit, "
        + ".anchor-ad, .review-detail, .breadcrumb, #qc-cmp2-container, .qc-cmp2-container"

    /// WebKit content-blocking rules, as JSON. Requests to ad-serving and tracking hosts are blocked, and the ad slots are hidden where they
    /// remain. Each site's own bars are hidden on that site's pages only: IMDb's, Rotten Tomatoes', TMDB's and Metacritic's.
    static var contentRules: String {
        let blocks = adHosts.map { #"{"trigger": {"url-filter": "\#($0)"}, "action": {"type": "block"}}"# }
        let hides = [#"{"trigger": {"url-filter": ".*"}, "action": {"type": "css-display-none", "selector": "\#(adSlots)"}}"#,
                     #"{"trigger": {"url-filter": "imdb[.]com"}, "action": {"type": "css-display-none", "selector": "\#(imdbHeaderSlots)"}}"#,
                     #"{"trigger": {"url-filter": "rottentomatoes[.]com"}, "action": {"type": "css-display-none", "selector": "\#(rottenTomatoesHeaderSlots)"}}"#,
                     #"{"trigger": {"url-filter": "themoviedb[.]org"}, "action": {"type": "css-display-none", "selector": "\#(tmdbHeaderSlots)"}}"#,
                     #"{"trigger": {"url-filter": "metacritic[.]com"}, "action": {"type": "css-display-none", "selector": "\#(metacriticHeaderSlots)"}}"#,
                     #"{"trigger": {"url-filter": "myanimelist[.]net"}, "action": {"type": "css-display-none", "selector": "\#(myAnimeListHeaderSlots)"}}"#]
        return "[\n" + (blocks + hides).joined(separator: ",\n") + "\n]"
    }

    /// The script for a site, run once the page's document is ready. Letterboxd's address for a title opens the film's page, which goes on
    /// to the film's reviews. The other sites load their user reviews after the page, so the script scrolls to their heading once it is
    /// there. RT and Metacritic can also resolve a title search and read the reviews from the page already being loaded.
    static func script(for site: ReviewSite, item: MetaPreview? = nil,
                       background: AppearancePreferences.RGB = .init(red: 0, green: 0, blue: 0)) -> String {
        if let item, ReviewPageReader.supports(site) { return ReviewPageReader.script(for: site, item: item, background: background) }
        switch site {
        case .letterboxd: return letterboxdScript
        case .myAnimeList: return myAnimeListScript
        case .imdb, .rottenTomatoes, .metacritic, .tmdb: return reviewsHeadingScript
        }
    }

    /// The dark treatment, for IMDb's, Rotten Tomatoes', TMDB's, Metacritic's and MyAnimeList's pages: the page is inverted, then its pictures are inverted
    /// back, so text reads light on a dark ground. Nil for Letterboxd, which keeps its own look. Runs before the page is drawn, so no white
    /// flashes.
    static func darkModeScript(for site: ReviewSite,
                               background: AppearancePreferences.RGB = .init(red: 0, green: 0, blue: 0)) -> String? {
        guard isShownDark(site) else { return nil }
        return invertedDarkScript.replacingOccurrences(of: "__BLUSION_GROUND__", with: cssColour(invertedGround(for: background)))
    }

    /// The app's page background as a CSS colour.
    static func cssColour(_ rgb: AppearancePreferences.RGB) -> String {
        "rgb(\(Int((rgb.red * 255).rounded())),\(Int((rgb.green * 255).rounded())),\(Int((rgb.blue * 255).rounded())))"
    }

    /// The colour that `invert(1) hue-rotate(180deg)` turns into `background`, so an inverted page's ground matches the app's. A
    /// half-turn of hue is its own inverse, so the colour is the background turned half round, then inverted.
    static func invertedGround(for background: AppearancePreferences.RGB) -> AppearancePreferences.RGB {
        let (r, g, b) = (background.red, background.green, background.blue)
        return AppearancePreferences.RGB(red: 1 - (-0.574 * r + 1.430 * g + 0.144 * b),
                                         green: 1 - (0.426 * r + 0.430 * g + 0.144 * b),
                                         blue: 1 - (0.426 * r + 1.430 * g - 0.856 * b))
    }

    /// A site's own layout fixes once its bars are hidden, run before the page is drawn. TMDB keeps room above its pages for its fixed
    /// header, so with the header hidden that band goes too. MyAnimeList's hidden cookie banner still cancels touches and taps, so its
    /// pages scroll again and its buttons and links answer. Nil for the other sites, whose bars take their room with them.
    static func layoutScript(for site: ReviewSite) -> String? {
        switch site {
        case .tmdb: tmdbLayoutScript
        case .myAnimeList: myAnimeListLayoutScript
        default: nil
        }
    }

    private static let myAnimeListLayoutScript = """
    (function () {
      if (!/(^|\\.)myanimelist\\.net$/.test(location.hostname)) return;
      // The hidden cookie banner's focus trap cancels every touchstart outside it, so no swipe scrolls the page. Touch and wheel
      // listeners are made passive, so none can stop a scroll.
      // The trap also catches every click on its way down, at the document, and cancels it, so no button (Read more) or link
      // answered a tap. While the banner is in the page, a click listener the document or window catches first cannot cancel or
      // stop the click; the page's own handlers, which take clicks on their way up, are left as they are.
      var add = EventTarget.prototype.addEventListener;
      var remove = EventTarget.prototype.removeEventListener;
      var wrapped = new WeakMap();
      var banner = '#qc-cmp2-container, .qc-cmp2-container';
      function capturing(options) {
        return typeof options === 'object' && options !== null ? !!options.capture : !!options;
      }
      function catchesClicksFirst(target, type, options) {
        return type === 'click' && (target === document || target === window) && capturing(options);
      }
      function uncancellable(listener) {
        if (wrapped.has(listener)) return wrapped.get(listener);
        var wrapper = function (event) {
          var call = function () {
            return typeof listener === 'function' ? listener.call(this, event) : listener.handleEvent(event);
          }.bind(this);
          if (!document.querySelector(banner)) return call();
          var ignore = function () {};
          event.preventDefault = ignore;
          event.stopPropagation = ignore;
          event.stopImmediatePropagation = ignore;
          try { return call(); } finally {
            delete event.preventDefault;
            delete event.stopPropagation;
            delete event.stopImmediatePropagation;
          }
        };
        wrapped.set(listener, wrapper);
        return wrapper;
      }
      EventTarget.prototype.addEventListener = function (type, listener, options) {
        if (type === 'touchstart' || type === 'touchmove' || type === 'wheel') {
          options = typeof options === 'object' && options !== null ? Object.assign({}, options, { passive: true })
            : { capture: !!options, passive: true };
        } else if (listener && catchesClicksFirst(this, type, options)) {
          listener = uncancellable(listener);
        }
        return add.call(this, type, listener, options);
      };
      EventTarget.prototype.removeEventListener = function (type, listener, options) {
        if (listener && catchesClicksFirst(this, type, options) && wrapped.has(listener)) listener = wrapped.get(listener);
        return remove.call(this, type, listener, options);
      };
    })();
    """

    private static let tmdbLayoutScript = """
    (function () {
      if (!/(^|\\.)themoviedb\\.org$/.test(location.hostname)) return;
      var style = document.createElement('style');
      style.textContent = 'main{margin-top:0 !important}';
      (document.head || document.documentElement).appendChild(style);
    })();
    """

    /// Whether a site's page is shown in the dark treatment, and its web view in dark mode.
    static func isShownDark(_ site: ReviewSite) -> Bool {
        [.imdb, .rottenTomatoes, .tmdb, .metacritic, .myAnimeList].contains(site)
    }

    private static let invertedDarkScript = """
    (function () {
      var style = document.createElement('style');
      style.textContent = 'html,body{background:__BLUSION_GROUND__ !important}html{filter:invert(1) hue-rotate(180deg) !important}' +
        'img,video,picture,svg image,[role=img]{filter:invert(1) hue-rotate(180deg) !important}';
      (document.head || document.documentElement).appendChild(style);
    })();
    """

    /// Sends a "Page Not Found" to `fallback`, the site's search for the title. Nil when the address cannot be written into a script.
    static func notFoundScript(fallback: URL) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [fallback.absoluteString]),
              let encoded = String(data: data, encoding: .utf8) else { return nil }
        let target = String(encoded.dropFirst().dropLast())
        return """
        (function () {
          if (/page not found/i.test(document.title)) { location.replace(\(target)); }
        })();
        """
    }

    private static let letterboxdScript = """
    (function () {
      if (/^\\/film\\/[^\\/]+\\/?$/.test(location.pathname)) {
        location.replace(location.pathname.replace(/\\/?$/, '/') + 'reviews/');
      }
    })();
    """

    /// MyAnimeList: a search goes on to its first anime's reviews, a title's page to its reviews, and its reviews page scrolls to the
    /// first review.
    private static let myAnimeListScript = """
    (function () {
      var path = location.pathname;
      if (/^\\/anime\\.php$/.test(path)) {
        // The results first, so a link in the page's header is not taken for one.
        var scopes = [document.querySelector('.content-main'), document.querySelector('#content'), document];
        for (var s = 0; s < scopes.length; s++) {
          if (!scopes[s]) continue;
          var links = scopes[s].querySelectorAll('a[href]');
          for (var i = 0; i < links.length; i++) {
            var match = (links[i].getAttribute('href') || '').match(/^(?:https:\\/\\/myanimelist\\.net)?(\\/anime\\/[0-9]+\\/[^\\/?#]+)/);
            if (match) { location.replace(match[1] + '/reviews'); return; }
          }
        }
        return;
      }
      if (/^\\/anime\\/[0-9]+(\\/[^\\/]+)?\\/?$/.test(path)) {
        location.replace(path.replace(/\\/?$/, '') + (/^\\/anime\\/[0-9]+\\/?$/.test(path) ? '/_' : '') + '/reviews');
        return;
      }
      var tries = 0;
      var timer = setInterval(function () {
        tries += 1;
        var review = document.querySelector('.review-element');
        if (review) { review.scrollIntoView({ block: 'start' }); clearInterval(timer); return; }
        if (tries >= 20) { clearInterval(timer); }
      }, 300);
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
