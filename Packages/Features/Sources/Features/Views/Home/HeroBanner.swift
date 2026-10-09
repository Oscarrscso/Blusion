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

/// The featured title, then the rest of the list as a snapping row of cards beneath the picture's fade.
struct HeroBanner: View {
    let items: [MetaPreview]
    let row: RowConfiguration
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            BannerFeature(item: items[0], showsRating: row.presentation.showsRatings)
            if items.count > 1 {
                MediaRow("", hideTitle: true) {
                    ForEach(Array(items.dropFirst()), id: \.identity) { item in
                        MediaCardLink(item: item, aspect: .poster, size: row.presentation.cardStyle.cardSize,
                                      showsRating: row.presentation.showsRatings)
                    }
                }
            }
        }
    }
}

/// The featured title of a banner: its backdrop edge to edge, faded into the page, with its logo, name and metadata at the bottom.
private struct BannerFeature: View {
    let item: MetaPreview
    let showsRating: Bool
    @Environment(AppRouter.self) private var router
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(PosterRatingsStore.self) private var ratings
    @State private var heroArtwork: TMDbArtwork?
    /// Set once the TMDb artwork lookup has finished, so a title with no logo can fall back to its name.
    @State private var artworkChecked = false

    var body: some View {
        let sourceID = "banner/\(item.identity)"
        let openTitle = {
            Haptics.tap()
            router.homePath.append(TitleDestination(preview: item, sourceID: sourceID, artwork: heroArtwork))
        }
        Color.clear
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                ArtworkImage(url: heroArtwork?.backdrop ?? item.background ?? MetahubArtwork.background(imdbID: item.id), maxPixelSize: 2048,
                             contentMode: .fill, placeholderURL: item.poster ?? MetahubArtwork.poster(imdbID: item.id), imageAlignment: .top)
            }
            .clipped()
            .zoomSource(id: sourceID, in: zoomNamespace)
            .overlay { BottomFade(length: 0.6) }
            .overlay(alignment: .bottomLeading) {
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
                artworkChecked = true
            }
    }

    /// The logo as soon as its URL is known, else the name once the lookup has found no logo. Blank until then.
    private var caption: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            titleBlock
            MetaLine(metaParts)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, metrics.pageMargin)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var titleBlock: some View {
        if let logo = item.logo ?? heroArtwork?.logo {
            HeroLogo(url: logo, title: item.name)
        } else if artworkChecked {
            Text(item.name)
                .font(.title.bold())
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: HeroLogo.box.width, height: HeroLogo.box.height)
        }
    }

    /// Year, the first two genres and, when ratings are shown, the IMDb rating, dot-separated.
    private var metaParts: [String?] {
        let rating = showsRating ? item.imdbRating.map { "★ \($0.formatted(.number.precision(.fractionLength(1))))" } : nil
        return [item.releaseInfo] + item.genres.prefix(2).map { Optional($0) } + [rating]
    }
}

/// The grey stand-in for a banner, the same shape as its featured picture, shimmering while the items load.
struct HeroBannerPlaceholder: View {
    var body: some View {
        Color.clear
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background { Rectangle().fill(Theme.surface) }
            .shimmering()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
    }
}
#endif
