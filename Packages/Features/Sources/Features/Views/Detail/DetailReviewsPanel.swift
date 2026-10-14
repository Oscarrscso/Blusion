#if canImport(UIKit)
import StremioKit
import SwiftUI
import UIKit
import WebKit

/// The title's rating buttons, with the reviews of the one tapped open right under them. A tap on a rating shows its site here, in the
/// app, rather than in a browser; the inline trailer stops while reviews are open, and opening the trailer closes them.
struct DetailRatings: View {
    let model: DetailViewModel
    /// False holds the lookup back until the screen allows it (the title page waits for its hero).
    var startsLoading = true
    /// The most width the rating buttons take. The reviews are not held to it: they take the page's full width.
    var buttonsWidth: CGFloat?

    var body: some View {
        // No spacing between the buttons and the reviews: the gap is the reviews' own top padding, added only once they show, so the screen
        // does not move while the page loads.
        VStack(alignment: .leading, spacing: 0) {
            RatingButtonsRow(item: model.detail.preview, startsLoading: startsLoading, openSite: model.openedReviews?.site,
                             isLoading: model.reviewsLoading) { site, url, isSearch in
                model.toggleReviews(site, url: url, isSearch: isSearch)
            }
            .frame(maxWidth: buttonsWidth ?? .infinity, alignment: .leading)
            if let reviews = model.openedReviews {
                DetailReviewsPanel(reviews: reviews, item: model.detail.preview, isLoading: model.reviewsLoading,
                                   onLoaded: model.reviewsDidLoad, onClose: model.closeReviews)
                    .padding(.top, model.reviewsLoading ? 0 : Theme.Spacing.m)
            }
        }
    }
}

/// The reviews of one rating's site, on the page: the site's name and a close button over the site itself. It is as wide as the rating
/// buttons above it, and stays until it is closed or another rating is tapped.
struct DetailReviewsPanel: View {
    let reviews: DetailViewModel.OpenedReviews
    let item: MetaPreview
    /// True until the page has loaded: a spinner shows over it.
    var isLoading = false
    /// Called once the page has loaded, or has failed to.
    var onLoaded: () -> Void = {}
    let onClose: () -> Void
    /// The id the page scrolls to when the reviews open, so they are in view.
    static let scrollID = "detail.reviewsPanel"
    /// How tall the site's page is on the page. A Mac window has room for more of it than a phone.
    #if targetEnvironment(macCatalyst)
    private static let pageHeight: CGFloat = 540
    #else
    private static let pageHeight: CGFloat = 440
    /// A phone held sideways has about 390 pt of height, so a taller page would sit past the screen's edge and take the page's drags.
    private static let phoneLandscapeHeight: CGFloat = 300
    #endif
    @Environment(\.isPhoneLandscape) private var isPhoneLandscape

    private var pageHeightNow: CGFloat {
        #if targetEnvironment(macCatalyst)
        Self.pageHeight
        #else
        isPhoneLandscape ? Self.phoneLandscapeHeight : Self.pageHeight
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ReviewSiteIcon(site: reviews.site, size: 14, keepsColour: true)
                Text(reviews.site.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if reviews.isSearch && !ReviewPageReader.supports(reviews.site) {
                    Text("Search")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(reviews.site.name) reviews")
                .accessibilityIdentifier("detail.reviews.close")
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            Divider()
            ReviewWebView(site: reviews.site, url: reviews.url, item: item, onLoaded: onLoaded)
                // A new site gets a new page with its own script, so its view is rebuilt rather than reused.
                .id(reviews.site)
                .frame(height: pageHeightNow)
                .overlay {
                    if isLoading { ProgressView().controlSize(.large).tint(.white) }
                }
                .accessibilityIdentifier("detail.reviewsWeb")
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: .infinity)
        // Takes no room and draws nothing while the page loads, so the screen does not move; the page keeps its full size inside, so it
        // still loads. Once it has, the reviews open.
        .frame(height: isLoading ? 0 : nil, alignment: .top)
        .clipped()
        .animation(.snappy(duration: 0.35), value: isLoading)
        .id(Self.scrollID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.reviewsPanel")
    }
}

/// Each open of a rating's reviews, appended to a file in the app's Caches folder: why the page was ready and how long it took from the page
/// start. The file is copied off the device to read the timings.
enum ReviewTimingLog {
    static var fileURL: URL? {
        try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("reviews-timings.log")
    }

    static func append(_ timing: [String: Any], site: ReviewSite?) {
        guard let url = fileURL else { return }
        let reason = timing["reason"] as? String ?? "?"
        let headingMs = timing["headingMs"] as? Int ?? -1
        let readyMs = timing["readyMs"] as? Int ?? -1
        let line = "\(Date().formatted(.iso8601)) site=\(site?.name ?? "?") reason=\(reason) headingMs=\(headingMs) readyMs=\(readyMs)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

extension ReviewPageRules {
    /// The compiled rules, kept once WebKit has compiled them, so each open attaches them without a wait.
    @MainActor private static var compiled: WKContentRuleList?
    /// A web view kept from launch: it holds a WebKit process that has already started, so the first reviews page does not wait for one.
    @MainActor private static var warmed: WKWebView?

    /// Attaches the content rules to a web view, then calls `ready`. The first open compiles them, which WebKit then keeps; later opens attach
    /// them at once. If they do not compile, `ready` still runs, and the page loads without them.
    @MainActor
    static func attach(to view: WKWebView, then ready: @escaping @MainActor () -> Void) {
        if let compiled {
            view.configuration.userContentController.add(compiled)
            ready()
            return
        }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: contentRules) { list, _ in
            MainActor.assumeIsolated {
                if let list {
                    compiled = list
                    view.configuration.userContentController.add(list)
                }
                ready()
            }
        }
    }

    /// Compiles the rules and starts a WebKit process at launch, after Home has shown, so the first reviews page waits for neither.
    @MainActor
    static func prewarm() {
        guard warmed == nil else { return }
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        warmed = view
        attach(to: view) { view.loadHTMLString("", baseURL: nil) }
    }

    /// Tells the app that the reviews are on screen and have settled. The panel opens on this, not on the load: the page draws its reviews
    /// after it loads, and a panel that opened earlier showed the black the reader saw. The reviews are on screen when their heading (the
    /// one the reviews scroll looks for) is in the viewport, and settled when nothing has changed for about 300 ms: no DOM change and no
    /// scroll. A page with no such heading posts after six seconds, well inside the 25-second limit.
    static let paintedScript = #"""
    (function () {
      var heading = /^\s*(user|audience) reviews?\s*$/i;
      var started = Date.now();
      var headingNode = null;
      var headingAt = 0;
      var lastSignature = '';
      var stableFor = 0;
      var done = false;
      var interval = null;

      // A visible element whose top is in the viewport: the heading has been scrolled to.
      function onScreen(el) {
        if (!el || el.getClientRects().length === 0) return false;
        var top = el.getBoundingClientRect().top;
        return top >= -2 && top <= window.innerHeight * 0.9;
      }

      function findHeading() {
        var nodes = document.querySelectorAll('h1, h2, h3, h4, h5, a, span, button');
        for (var i = 0; i < nodes.length; i++) {
          if (heading.test(nodes[i].textContent || '') && nodes[i].getClientRects().length > 0) return nodes[i];
        }
        return null;
      }

      // The first review under the heading: the first visible element after it with a few lines of text.
      function firstReview(h) {
        var scope = h;
        for (var up = 0; up < 4 && scope; up++) {
          var el = scope.nextElementSibling;
          for (var seen = 0; el && seen < 40; seen++) {
            if ((el.textContent || '').trim().length >= 60 && el.getClientRects().length > 0) return el;
            el = el.nextElementSibling;
          }
          scope = scope.parentElement;
        }
        return null;
      }

      function finish(reason) {
        if (done) return;
        done = true;
        clearInterval(interval);
        window.webkit.messageHandlers.painted.postMessage({
          reason: reason,
          headingMs: headingAt ? headingAt - started : -1,
          readyMs: Date.now() - started
        });
      }

      // Every 60 ms, look only at the heading, the first review and the scroll position. Ready when the heading is on screen, the first
      // review has text, and those have not moved for 120 ms. A hard cap of 1.2 s after the heading first shows ends the wait regardless.
      function check() {
        if (done) return;
        var now = Date.now();
        if (!headingNode || headingNode.getClientRects().length === 0) headingNode = findHeading();
        if (!headingNode) {
          if (now - started >= 6000) finish('no-heading');
          return;
        }
        if (!headingAt) headingAt = now;
        var review = firstReview(headingNode);
        var h = headingNode.getBoundingClientRect();
        var signature = Math.round(h.top) + ',' + Math.round(window.scrollY);
        if (review) {
          var r = review.getBoundingClientRect();
          signature += '|' + Math.round(r.top) + ',' + Math.round(r.height);
        }
        if (signature === lastSignature) { stableFor += 60; } else { stableFor = 0; lastSignature = signature; }
        var visible = onScreen(headingNode);
        if (visible && review && stableFor >= 120) return finish('stable');
        if (visible && now - headingAt >= 1200) return finish('cap');
        if (!visible && now - headingAt >= 8000) finish('heading-off-screen');
      }

      interval = setInterval(check, 60);
      check();
    })();
    """#

    /// Letterboxd's reviews have no heading the script can find, so its page reports ready after its load and two frames, as it always did.
    static let loadedScript = #"""
    (function () {
      function painted() {
        requestAnimationFrame(function () {
          requestAnimationFrame(function () {
            window.webkit.messageHandlers.painted.postMessage('painted');
          });
        });
      }
      if (document.readyState === 'complete') { painted(); } else { window.addEventListener('load', painted); }
    })();
    """#
}

/// A rating's site, loaded in the app with its ads and trackers blocked. The page opens its user reviews when it can. It loads once per
/// address: SwiftUI's re-renders leave the page the reader is on alone.
struct ReviewWebView: UIViewRepresentable {
    let site: ReviewSite
    let url: URL
    let item: MetaPreview
    var onLoaded: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(source: ReviewPageRules.script(for: site, item: item),
                                                                       injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        if let dark = ReviewPageRules.darkModeScript(for: site) {
            configuration.userContentController.addUserScript(WKUserScript(source: dark, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        // Metacritic's direct address for a title can be wrong; a "Page Not Found" falls back to its search.
        if site == .metacritic, let search = site.url(for: item),
           let fallback = ReviewPageRules.notFoundScript(fallback: search) {
            configuration.userContentController.addUserScript(WKUserScript(source: fallback, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        // The panel opens once the page has painted (see `paintedScript`), so the spinner stays until the reader can see the page.
        configuration.userContentController.addUserScript(WKUserScript(source: site == .letterboxd ? ReviewPageRules.loadedScript : ReviewPageRules.paintedScript,
                                                                       injectionTime: .atDocumentEnd,
                                                                       forMainFrameOnly: true))
        let coordinator = context.coordinator
        coordinator.site = site
        configuration.userContentController.add(coordinator, name: "painted")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        // IMDb's reviews are shown in the dark, whatever the device's setting; the other sites keep the device's look.
        view.overrideUserInterfaceStyle = site == .imdb ? .dark : .unspecified
        coordinator.onLoaded = onLoaded
        view.navigationDelegate = coordinator
        coordinator.requested = url
        ReviewPageRules.attach(to: view) {
            // The page loads once its rules are in place, at the address asked for last.
            coordinator.isReady = true
            if let latest = coordinator.requested { view.load(URLRequest(url: latest)) }
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onLoaded = onLoaded
        guard coordinator.requested != url else { return }
        coordinator.requested = url
        // Before the rules are in place, the load that is waiting for them picks up this address.
        guard coordinator.isReady else { return }
        view.load(URLRequest(url: url))
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        // A compilation callback still waiting for the content rules must not reopen a dismissed page.
        coordinator.requested = nil
        view.stopLoading()
        view.navigationDelegate = nil
        // WebKit keeps a message handler until it is removed, so the view's handler goes with it.
        view.configuration.userContentController.removeScriptMessageHandler(forName: "painted")
    }

    /// The address last asked for, whether the rules are in place, and what to call when the page has loaded, so a re-render does not
    /// load the page again.
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var requested: URL?
        var isReady = false
        var onLoaded: () -> Void = {}
        var site: ReviewSite?

        /// The load itself does not open the panel: the page has still to paint, and `painted` says so.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onLoaded() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onLoaded() }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // Per open: why the reviews were ready, and how long the heading and the ready state took from the start of the page.
            if let timing = message.body as? [String: Any] { ReviewTimingLog.append(timing, site: site) }
            onLoaded()
        }
    }
}
#endif
