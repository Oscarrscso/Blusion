#if canImport(UIKit)
import StremioKit
import SwiftUI

/// The spotlight section of Home: the carousel once its items arrive, a placeholder of the same size until then, and a message when
/// it cannot load.
struct HeroSection: View {
    let section: HomeViewModel.Section
    let onRetry: () -> Void
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            if !section.widget.hideTitle {
                SectionHeader(section.widget.title).padding(.horizontal, metrics.pageMargin)
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section.state {
        case .idle, .loading:
            HeroPlaceholder()
        case .loaded(let items) where !items.isEmpty:
            HeroCarousel(items: items)
        case .loaded:
            if let issue = section.issue {
                IssueMessage(issue: issue)
            }
        case .failed(let error):
            InlineErrorView(error.shortDescription, retry: onRetry)
                .padding(.horizontal, Theme.screenPadding)
        }
    }
}

/// A paging carousel of full-width pages. Each page is its item's artwork with the title (its logo when there is one), a metadata
/// line and a "Details" button over the bottom of it.
struct HeroCarousel: View {
    let items: [MetaPreview]
    @Environment(\.layoutMetrics) private var metrics
    /// The page on screen, counted from 0, read from the scroll position.
    @State private var index = 0

    var body: some View {
        // The height follows from the width the screen offers, so it is known on the first layout pass. A height the pages worked out
        // later made the list above jump.
        Color.clear
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical) { height, _ in metrics.heroHeight(forContainerHeight: height) }
            .overlay {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(items, id: \.identity) { item in
                            HeroPage(item: item)
                                .containerRelativeFrame(.horizontal)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollClipDisabled()
                .onScrollGeometryChange(for: Int.self, of: { geometry in
                    Int((geometry.contentOffset.x / max(geometry.containerSize.width, 1)).rounded())
                }, action: { _, newIndex in index = newIndex })
            }
            .overlay(alignment: .bottom) {
                if items.count > 1 { pageDots }
            }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.identity) { position, _ in
                let isCurrent = position == index
                Capsule()
                    .fill(.white.opacity(isCurrent ? 0.95 : 0.35))
                    .frame(width: isCurrent ? 16 : 6, height: 6)
            }
        }
        .animation(.snappy(duration: 0.25), value: index)
        .padding(.bottom, Theme.Spacing.m)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The grey stand-in for the spotlight, the same size as a page, shimmering while the items load.
struct HeroPlaceholder: View {
    @Environment(\.layoutMetrics) private var metrics
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical) { height, _ in metrics.heroHeight(forContainerHeight: height) }
            .background { Rectangle().fill(Theme.surface) }
            .mediaArtwork(cornerRadius: 0)
            .shimmering()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
    }
}

/// One page of the spotlight. The artwork is the link to the title and the place its screen zooms out of. The title block and the
/// "Details" button sit over it as a second link, so a tap on the button and a tap on the picture open the same title.
private struct HeroPage: View {
    /// The zoom source of this page's artwork: the title's screen zooms out of it.
    static func sourceID(for item: MetaPreview) -> String { "hero/\(item.identity)" }

    let item: MetaPreview
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let destination = TitleDestination(preview: item, sourceID: HeroPage.sourceID(for: item))
        ZStack(alignment: .bottomLeading) {
            NavigationLink(value: destination) {
                artwork
            }
            .buttonStyle(.plain)
            .titleTapHaptic()
            .accessibilityLabel(item.name)
            caption
        }
    }

    private var artwork: some View {
        Color.clear
            .overlay { ArtworkImage(url: item.background ?? item.poster, title: item.name, maxPixelSize: 1400) }
            .overlay { scrim }
            .mediaArtwork(cornerRadius: 0)
            .contentShape(Rectangle())
            .zoomSource(id: HeroPage.sourceID(for: item), in: zoomNamespace)
    }

    /// Clear over the picture, then the screen's own background at the bottom: the artwork fades into the screen, and the title sits on
    /// a dark ground whatever the picture is.
    private var scrim: some View {
        LinearGradient(stops: [
            .init(color: Theme.background.opacity(0.7), location: 0),
            .init(color: .clear, location: 0.14),
            .init(color: .clear, location: 0.36),
            .init(color: Theme.background.opacity(0.62), location: 0.58),
            .init(color: Theme.background.opacity(0.9), location: 0.76),
            .init(color: Theme.background, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    /// The title, its logo and the metadata line. The picture is the link, so the page carries no buttons of its own.
    private var caption: some View {
        VStack(alignment: metrics.isRegular ? .leading : .center, spacing: Theme.Spacing.s) {
            titleBlock
                .allowsHitTesting(false)
            MetaLine(metaParts)
                .allowsHitTesting(false)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, metrics.pageMargin)
        // Room for the page dots under the button.
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, alignment: metrics.isRegular ? .leading : .center)
    }

    @ViewBuilder
    private var titleBlock: some View {
        if let logo = item.logo {
            HeroLogo(url: logo, title: item.name)
        } else {
            Text(item.name)
                .font(.largeTitle.bold())
                .lineLimit(2)
                .multilineTextAlignment(metrics.isRegular ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Year, the first two genres and the rating, dot-separated. Parts that are missing are left out by `MetaLine`.
    private var metaParts: [String?] {
        let rating = item.imdbRating.map { "★ \($0.formatted(.number.precision(.fractionLength(1))))" }
        return [item.releaseInfo] + item.genres.prefix(2).map { Optional($0) } + [rating]
    }
}

/// A title's logo, fitted into a box of fixed size so the text under it never moves when it arrives. Shows the name when the logo
/// cannot be loaded.
private struct HeroLogo: View {
    static let box = CGSize(width: 260, height: 84)

    let url: URL
    let title: String
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Color.clear
            .frame(width: Self.box.width, height: Self.box.height)
            .overlay(alignment: .bottomLeading) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .transition(.opacity)
                } else if failed {
                    Text(title)
                        .font(.largeTitle.bold())
                        .lineLimit(2)
                }
            }
            .task(id: url) { await load() }
    }

    private func load() async {
        do {
            let loaded = try await ImagePipeline.shared.image(for: url, maxPixelSize: 800)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        } catch {
            failed = true
        }
    }
}
#endif
