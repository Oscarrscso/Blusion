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

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            RatingButtonsRow(item: model.detail.preview, startsLoading: startsLoading, openSite: model.openedReviews?.site,
                             isLoading: model.reviewsLoading) { site, url, isSearch in
                model.toggleReviews(site, url: url, isSearch: isSearch)
            }
            if let reviews = model.openedReviews {
                DetailReviewsPanel(reviews: reviews, item: model.detail.preview, isLoading: model.reviewsLoading,
                                   onLoaded: model.reviewsDidLoad, onClose: model.closeReviews)
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
        .id(Self.scrollID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.reviewsPanel")
    }
}

extension ReviewPageRules {
    /// Compiles the content rules and attaches them to a web view, then calls `ready`. The rules are small, so compiling them on each open is
    /// quick. If they do not compile, `ready` still runs, and the page loads without them.
    @MainActor
    static func attach(to view: WKWebView, then ready: @escaping @MainActor () -> Void) {
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: contentRules) { list, _ in
            MainActor.assumeIsolated {
                if let list { view.configuration.userContentController.add(list) }
                ready()
            }
        }
    }
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
        configuration.userContentController.addUserScript(WKUserScript(source: ReviewPageRules.darkModeScript,
                                                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // Metacritic's direct address for a title can be wrong; a "Page Not Found" falls back to its search.
        if site == .metacritic, let search = site.url(for: item),
           let fallback = ReviewPageRules.notFoundScript(fallback: search) {
            configuration.userContentController.addUserScript(WKUserScript(source: fallback, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        // The review pages are shown in the dark, whatever the device's setting, so they match the title page's dark look.
        view.overrideUserInterfaceStyle = .dark
        let coordinator = context.coordinator
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
    }

    /// The address last asked for, whether the rules are in place, and what to call when the page has loaded, so a re-render does not
    /// load the page again.
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var requested: URL?
        var isReady = false
        var onLoaded: () -> Void = {}

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onLoaded() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onLoaded() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onLoaded() }
    }
}
#endif
