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

extension EnvironmentValues {
    /// How far Home has been pulled down past its top while the spotlight is its first section. The portrait spotlight stretches by this
    /// much, like a refresh.
    @Entry var heroPull: CGFloat = 0
}

/// A paging carousel of full-resolution portrait or landscape heroes, each clipped to its own page.
struct HeroCarousel: View {
    let items: [MetaPreview]
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isLandscape) private var isLandscape
    @Environment(\.heroContainerHeight) private var containerHeight
    @Environment(\.isHomeScrolling) private var isHomeScrolling
    @Environment(\.heroPull) private var heroPull
    /// Keep the same title aligned when the window resizes or the device rotates.
    @State private var pageID: String?

    var body: some View {
        let preferred = metrics.heroHeight(forContainerHeight: containerHeight) + 100
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: isLandscape ? min(containerHeight, preferred) : preferred)
            .overlay {
                GeometryReader { geometry in
                    // In portrait the spotlight stretches downward when pulled past the top; its top stays at the top of the screen.
                    let pull = isLandscape ? 0 : heroPull
                    let height = geometry.size.height + pull
                    TabView(selection: $pageID) {
                        ForEach(items, id: \.identity) { item in
                            HeroPage(item: item, isScrolling: isHomeScrolling)
                                .frame(width: geometry.size.width, height: height)
                                .clipped()
                                .tag(Optional(item.identity))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(width: geometry.size.width, height: height)
                    .clipped()
                    .offset(y: -pull)
                    .onChange(of: pageID) { oldID, newID in
                        guard let oldID, let newID, oldID != newID,
                              items.contains(where: { $0.identity == oldID }) else { return }
                        Haptics.scrollSnap()
                    }
                    .onAppear {
                        pageID = pageID ?? items.first?.identity
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if items.count > 1 { pageDots }
            }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.identity) { item in
                let isCurrent = item.identity == (pageID ?? items.first?.identity)
                Capsule()
                    .fill(.white.opacity(isCurrent ? 0.95 : 0.35))
                    .frame(width: isCurrent ? 16 : 6, height: 6)
            }
        }
        .animation(.snappy(duration: 0.25), value: pageID)
        .padding(.bottom, Theme.Spacing.m)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The grey stand-in for the spotlight, the same size as a page, shimmering while the items load.
struct HeroPlaceholder: View {
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isLandscape) private var isLandscape
    @Environment(\.heroContainerHeight) private var containerHeight
    var body: some View {
        let preferred = metrics.heroHeight(forContainerHeight: containerHeight) + 100
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: isLandscape ? min(containerHeight, preferred) : preferred)
            .background { Rectangle().fill(Theme.surface) }
            .shimmering()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
    }
}

/// One hero page of the spotlight, using a separate image for each orientation.
private struct HeroPage: View {
    /// The zoom source of this page's artwork: the title's screen zooms out of it.
    static func sourceID(for item: MetaPreview) -> String { "hero/\(item.identity)" }

    let item: MetaPreview
    let isScrolling: Bool
    @Environment(AppRouter.self) private var router
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isLandscape) private var isLandscape
    @Environment(PosterRatingsStore.self) private var ratings
    @State private var heroArtwork: TMDbArtwork?
    @State private var titleTop: CGFloat = 0
    /// Set once the TMDb artwork lookup has finished, so a title with no logo can fall back to its name.
    @State private var artworkChecked = false

    var body: some View {
        let destination = TitleDestination(preview: item, sourceID: HeroPage.sourceID(for: item), artwork: heroArtwork)
        let openTitle = {
            Haptics.tap()
            router.homePath.append(destination)
        }
        ZStack(alignment: .bottom) {
            artwork
                .allowsHitTesting(false)
            // Keep the fade outside the zoom source so a cancelled press cannot hide it.
            scrim
                .allowsHitTesting(false)
            caption
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            // A tap can open the title, but never claims a drag or disables views during one.
            Color.clear
                .frame(height: max(0, titleTop - Theme.Spacing.m))
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {
                    guard !isScrolling else { return }
                    openTitle()
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { openTitle() }
        }
        .overlay(alignment: .bottomTrailing) {
            if isLandscape {
                PosterRatingsOverlay(item: item, isLandscape: true)
                    .padding(.horizontal, metrics.pageMargin)
                    .padding(.bottom, Theme.Spacing.m)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: HeroPage.sourceID(for: item))
        .task(id: ratings.reviewServicesRevision) {
            let loaded = await ratings.heroArtwork(for: item)
            guard !Task.isCancelled else { return }
            heroArtwork = loaded
            artworkChecked = true
        }
    }

    private var artwork: some View {
        Color.clear
            .overlay {
                ArtworkImage(url: isLandscape ? heroArtwork?.backdrop ?? item.background ?? MetahubArtwork.background(imdbID: item.id) : heroArtwork?.portrait,
                             maxPixelSize: 4096, contentMode: isLandscape ? .fit : .fill,
                             placeholderURL: item.poster ?? MetahubArtwork.poster(imdbID: item.id), imageAlignment: .top)
            }
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

    /// The title, its logo and the metadata line. Only the picture above the logo accepts taps.
    private var caption: some View {
        VStack(alignment: .center, spacing: Theme.Spacing.s) {
            titleBlock
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.frame(in: .named(HeroPage.sourceID(for: item))).minY
                } action: { titleTop = $0 }
                .allowsHitTesting(false)
            MetaLine(metaParts)
                .multilineTextAlignment(.center)
                .allowsHitTesting(false)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, metrics.pageMargin)
        // Room for the page dots beneath the metadata.
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// The logo as soon as its URL is known. Blank until then, and the name only once the lookup has found no logo.
    @ViewBuilder
    private var titleBlock: some View {
        if let logo = item.logo ?? heroArtwork?.logo {
            HeroLogo(url: logo, title: item.name)
        } else if artworkChecked {
            Text(item.name)
                .font(.largeTitle.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        } else {
            Color.clear.frame(width: HeroLogo.box.width, height: HeroLogo.box.height)
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
            .overlay(alignment: .bottom) {
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
