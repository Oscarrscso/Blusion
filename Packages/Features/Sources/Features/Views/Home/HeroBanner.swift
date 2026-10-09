#if canImport(UIKit)
import StremioKit
import SwiftUI

/// A `.banner` widget: a large featured landscape title over a row of smaller cards once its items arrive. Until then, and when it has
/// nothing to show, the same header sits over a placeholder, a message or a retry, so the layout does not move when the cards arrive.
struct HeroBannerSection: View {
    let section: HomeViewModel.Section
    let row: RowConfiguration
    let onRetry: () -> Void
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            if !section.widget.hideTitle {
                SectionHeader(section.widget.title).padding(.horizontal, metrics.pageMargin)
            }
            content
        }
        .accessibilityIdentifier("board.row.\(section.widget.id)")
    }

    @ViewBuilder
    private var content: some View {
        switch section.state {
        case .idle, .loading:
            HeroBannerPlaceholder()
        case .loaded(let items) where !items.isEmpty:
            HeroBanner(items: items, row: row)
        case .loaded:
            if let issue = section.issue {
                IssueMessage(issue: issue)
            } else {
                Text("Nothing here yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, metrics.pageMargin)
            }
        case .failed(let error):
            InlineErrorView(error.shortDescription, retry: onRetry)
                .padding(.horizontal, metrics.pageMargin)
        }
    }
}

/// One rounded card: the featured title's backdrop on top with its name and year at the top left, and the rest of the list as a
/// row of small landscape cards on a tray tinted by the same picture, blurred.
struct HeroBanner: View {
    let items: [MetaPreview]
    let row: RowConfiguration
    @Environment(\.layoutMetrics) private var metrics
    @State private var heroArtwork: TMDbArtwork?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BannerFeature(item: items[0], showsRating: row.presentation.showsRatings, heroArtwork: $heroArtwork)
            if items.count > 1 {
                MediaRow("", hideTitle: true) {
                    ForEach(Array(items.dropFirst()), id: \.identity) { item in
                        MediaCardLink(item: item, aspect: .wide, size: row.presentation.cardStyle.cardSize,
                                      showsRating: row.presentation.showsRatings, width: cardWidth, subtitle: item.releaseInfo ?? " ")
                    }
                }
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.m)
            }
        }
        .environment(\.colorScheme, .dark)
        .background { tray }
        .clipShape(RoundedRectangle(cornerRadius: HeroBanner.cornerRadius, style: .continuous))
        .padding(.horizontal, metrics.pageMargin)
    }

    static let cornerRadius: CGFloat = 28

    /// The small cards of the tray: about a third of the banner's width on a phone.
    private var cardWidth: CGFloat {
        (metrics.posterWidth * 1.1 * row.presentation.cardStyle.cardSize.scale).rounded()
    }

    /// The featured picture, blurred and darkened, so the tray picks up the colours above it.
    private var tray: some View {
        ArtworkImage(url: heroArtwork?.backdrop ?? items[0].background ?? MetahubArtwork.background(imdbID: items[0].id), maxPixelSize: 256,
                     contentMode: .fill, placeholderURL: items[0].poster, imageAlignment: .bottom)
            .blur(radius: 40)
            .overlay { Color.black.opacity(0.55) }
            .background(Theme.surface)
    }
}

/// The featured title of a banner: its backdrop, with its name and year at the top left and a soft fade into the tray at the bottom.
private struct BannerFeature: View {
    let item: MetaPreview
    let showsRating: Bool
    @Binding var heroArtwork: TMDbArtwork?
    @Environment(AppRouter.self) private var router
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(PosterRatingsStore.self) private var ratings

    var body: some View {
        let sourceID = "banner/\(item.identity)"
        let openTitle = {
            Haptics.tap()
            router.homePath.append(TitleDestination(preview: item, sourceID: sourceID, artwork: heroArtwork))
        }
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                ArtworkImage(url: heroArtwork?.backdrop ?? item.background ?? MetahubArtwork.background(imdbID: item.id), maxPixelSize: 2048,
                             contentMode: .fill, placeholderURL: item.poster ?? MetahubArtwork.poster(imdbID: item.id), imageAlignment: .top)
            }
            .clipped()
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .black.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .zoomSource(id: sourceID, in: zoomNamespace, cornerRadius: HeroBanner.cornerRadius)
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 110)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                caption
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: openTitle)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { openTitle() }
            .task(id: ratings.reviewServicesRevision) {
                let loaded = await ratings.heroArtwork(for: item)
                guard !Task.isCancelled else { return }
                heroArtwork = loaded
            }
    }

    /// The name in bold, the year (and the rating, when shown) in a lighter line under it.
    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name)
                .font(.title.bold())
                .lineLimit(2)
            Text([item.releaseInfo, rating].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rating: String? {
        showsRating ? item.imdbRating.map { "★ \($0.formatted(.number.precision(.fractionLength(1))))" } : nil
    }
}

/// The grey stand-in for a banner, the same shape as the loaded card, shimmering while the items load.
struct HeroBannerPlaceholder: View {
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit)
            Color.clear.frame(height: 130)
        }
        .frame(maxWidth: .infinity)
        .background { Rectangle().fill(Theme.surface) }
        .shimmering()
        .clipShape(RoundedRectangle(cornerRadius: HeroBanner.cornerRadius, style: .continuous))
        .padding(.horizontal, metrics.pageMargin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}
#endif
