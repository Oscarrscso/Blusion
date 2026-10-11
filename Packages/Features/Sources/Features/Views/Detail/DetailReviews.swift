#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// The TMDb reviews shelf: a sort menu, then one card per review. A card opens to its whole text, and opening one widens it to the page.
struct DetailReviews: View {
    private enum ReviewSort: String, CaseIterable {
        case highestRated = "Highest rated"
        case lowestRated = "Lowest rated"
        case longest = "Longest review"
        case shortest = "Shortest review"
    }

    let reviews: [TMDbReview]
    let width: CGFloat
    let contentMargin: CGFloat
    @State private var reviewSort = ReviewSort.highestRated
    /// The review whose card is open: full width, with its whole text. Opening and closing animate the text and the width together.
    @State private var expandedReviewID: String?
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            HStack(spacing: 0) {
                Text("TMDb Reviews")
                    .font(Theme.Typography.shelfTitle)
                    .accessibilityAddTraits(.isHeader)
                Menu {
                    Picker("Sort reviews", selection: $reviewSort) {
                        ForEach(ReviewSort.allCases, id: \.self) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption2.weight(.semibold))
                }
                .glassCircleButton(.small)
                .padding(.leading, Theme.Spacing.s)
                .accessibilityLabel("Sort TMDb reviews")
                .accessibilityValue(reviewSort.rawValue)
                .accessibilityIdentifier("detail.reviews.sort")
            }
            .padding(.horizontal, contentMargin)
            ScrollViewReader { proxy in
                // A plain row, not a lazy one: a few dozen reviews are all built, so the shelf is exactly as tall as its tallest card
                // and grows and shrinks with an opened card's own animation.
                ShelfScroll(margin: contentMargin, spacing: metrics.cardSpacing, lazy: false) {
                        ForEach(sortedReviews) { review in
                            let foldedWidth = metrics.reviewCardWidth
                            let expandedWidth = max(0, width - contentMargin * 2)
                            ReviewCard(review: review, isExpanded: expandedReviewID == review.id,
                                       foldedWidth: foldedWidth, expandedWidth: expandedWidth) {
                                toggleReview(review.id)
                            }
                            .frame(width: expandedReviewID == review.id ? expandedWidth : foldedWidth)
                            .id(review.id)
                            .reportsShelfEdge(id: review.id)
                            .onGeometryChange(for: Bool.self) { [expandedReviewID, contentMargin] geometry in
                                expandedReviewID == review.id &&
                                abs(geometry.size.width - (width - contentMargin * 2)) < 0.5
                            } action: { isFullWidth in
                                if isFullWidth {
                                    withAnimation(.snappy(duration: 0.35)) {
                                        proxy.scrollTo(review.id, anchor: .center)
                                    }
                                }
                            }
                        }
                }
            }
        }
    }

    private var sortedReviews: [TMDbReview] {
        reviews.sorted {
            switch reviewSort {
            case .longest:
                return $0.content.count > $1.content.count
            case .shortest:
                return $0.content.count < $1.content.count
            case .highestRated, .lowestRated:
                guard let left = $0.rating else { return false }
                guard let right = $1.rating else { return true }
                return reviewSort == .highestRated ? left > right : left < right
            }
        }
    }

    /// Opening a review widens its card and unfolds its text together. Closing one folds the text and narrows the card in the same motion,
    /// as it opened: one animation for the state, the card's width and the text.
    private func toggleReview(_ id: String) {
        withAnimation(.snappy(duration: 0.35)) {
            expandedReviewID = expandedReviewID == id ? nil : id
        }
    }
}

/// One TMDb review. Folded, every card is the same height: the text keeps six lines whether or not it fills them. A tap opens or
/// folds it, and only a review that runs past those lines folds. Links in the text are drawn as links in both states, and a tap on one
/// opens it only once the card is expanded; folded, the tap expands the card as any other tap on the text does.
private struct ReviewCard: View {
    let review: TMDbReview
    let isExpanded: Bool
    /// The card's outer width folded and expanded. The text is laid out at the inner width of each and never re-wraps while the card animates.
    let foldedWidth: CGFloat
    let expandedWidth: CGFloat
    let onToggle: () -> Void
    @State private var isTruncated = false
    @Environment(\.openURL) private var openURL

    private var folds: Bool { isExpanded || isTruncated }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    // Short cards cut a long name to one line; an expanded card has the width, so the name wraps in full.
                    Text(review.author).font(.headline).lineLimit(isExpanded ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let rating = review.rating {
                        let stars = min(10, max(0, rating)).rounded() / 2
                        HStack(spacing: 2) {
                            ForEach(0..<5) { index in
                                Image(systemName: stars >= Double(index + 1) ? "star.fill" :
                                        stars >= Double(index) + 0.5 ? "star.leadinghalf.filled" : "star")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        // The stars keep their width; the name takes what is left, and wraps or cuts before the stars are squeezed.
                        .fixedSize()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Rating \(stars.formatted(.number.precision(.fractionLength(0...1)))) out of 5 stars")
                    }
                }
                // The gap under the header belongs to the header, so a tap there folds or opens the card as before.
                .padding(.bottom, Theme.Spacing.m)
                .contentShape(Rectangle())
                .onTapGesture {
                    if folds { onToggle() }
                }
                // Two texts, each at its final width: the old one fades out as laid out and the new one fades in already laid out.
                // The text takes its own taps (see `tapText`), so the card's tap does not reach it.
                ZStack(alignment: .topLeading) {
                    if isExpanded {
                        JustifiedText(text: review.content, textStyle: .subheadline, isMarkdown: true, lineLimit: 0,
                                      showsLinks: true, linksAreTappable: true, onTap: tapText)
                            .frame(width: max(0, expandedWidth - Self.padding * 2), alignment: .leading)
                            .transition(.opacity)
                    } else {
                        JustifiedText(text: review.content, textStyle: .subheadline, isMarkdown: true, lineLimit: 6,
                                      reservesSpace: true, isTruncated: $isTruncated, showsLinks: true, onTap: tapText)
                            .frame(width: max(0, foldedWidth - Self.padding * 2), alignment: .leading)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(Self.padding)
        .cardSurface()
        // Fixed-width text never draws outside the card while it grows or shrinks.
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.surface, style: .continuous))
    }

    /// A tap on a link opens it and leaves the card as it is. Any other tap on the text folds or opens the card, as a tap on the header does.
    /// Folded, a link is not tappable, so every tap on the text reaches here with no link.
    private func tapText(_ link: URL?) {
        if let link {
            openURL(link)
        } else if folds {
            onToggle()
        }
    }

    private static let padding: CGFloat = 16
}
#endif
