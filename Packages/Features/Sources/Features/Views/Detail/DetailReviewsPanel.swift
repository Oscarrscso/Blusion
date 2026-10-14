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
            RatingButtonsRow(item: model.detail.preview, startsLoading: startsLoading, openSite: model.openedReviews?.site) { site, url, isSearch in
                model.toggleReviews(site, url: url, isSearch: isSearch)
            }
            if let reviews = model.openedReviews {
                DetailReviewsPanel(reviews: reviews, onClose: model.closeReviews)
            }
        }
    }
}

/// The reviews of one rating's site, on the page: the site's name and a close button over the site itself. It is as wide as the rating
/// buttons above it, and stays until it is closed or another rating is tapped.
struct DetailReviewsPanel: View {
    let reviews: DetailViewModel.OpenedReviews
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
                if reviews.isSearch {
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
            ReviewWebView(url: reviews.url)
                .frame(height: pageHeightNow)
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

/// A rating's site, loaded in the app. The page loads once per site: SwiftUI's re-renders leave the page the reader is on alone.
struct ReviewWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.allowsBackForwardNavigationGestures = true
        context.coordinator.requested = url
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.requested != url else { return }
        context.coordinator.requested = url
        view.load(URLRequest(url: url))
    }

    /// The address last asked for, so a re-render with the same address does not load it again.
    final class Coordinator {
        var requested: URL?
    }
}
#endif
