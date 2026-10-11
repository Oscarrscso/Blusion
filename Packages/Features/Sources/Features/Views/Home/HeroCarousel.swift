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
                .padding(.horizontal, metrics.pageMargin)
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
    @Environment(\.heroContainerWidth) private var containerWidth
    @Environment(\.isHomeScrolling) private var isHomeScrolling
    @Environment(\.heroPull) private var heroPull
    @Environment(PosterRatingsStore.self) private var ratings
    /// Keep the same title aligned when the window resizes or the device rotates.
    @State private var pageID: String?

    /// How many pages ahead of (and behind) the one on screen load their full-quality picture. The nearest page and its neighbour start at
    /// once; the rest of the window follows. Pages beyond it show their poster until the swipe brings them in range.
    static let loadWindow = 2

    private var currentIndex: Int {
        items.firstIndex { $0.identity == (pageID ?? items.first?.identity) } ?? 0
    }

    var body: some View {
        let preferred = metrics.heroHeight(forContainerHeight: containerHeight) + 100
        let portrait = TitleHero.height(width: containerWidth, metrics: metrics) + TitleHero.captionBelow
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: isLandscape ? min(containerHeight, preferred) : portrait)
            .overlay {
                GeometryReader { geometry in
                    // In portrait the spotlight stretches downward when pulled past the top; its top stays at the top of the screen.
                    let pull = isLandscape ? 0 : heroPull
                    let height = geometry.size.height + pull
                    TabView(selection: $pageID) {
                        ForEach(Array(items.enumerated()), id: \.element.identity) { index, item in
                            HeroPage(item: item, isScrolling: isHomeScrolling, artworkHeight: height - TitleHero.captionBelow,
                                     cachedArtwork: ratings.cachedHeroArtwork(for: item), distance: abs(index - currentIndex))
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
    @Environment(\.heroContainerWidth) private var containerWidth
    var body: some View {
        let preferred = metrics.heroHeight(forContainerHeight: containerHeight) + 100
        let portrait = TitleHero.height(width: containerWidth, metrics: metrics) + TitleHero.captionBelow
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: isLandscape ? min(containerHeight, preferred) : portrait)
            .background { Rectangle().fill(Theme.surface) }
            .shimmering()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
    }
}

/// One hero page of the spotlight, using a separate image for each orientation.
private struct HeroPage: View {
    /// The zoom source of this page's artwork: the title's screen zooms out of it.
    nonisolated static func sourceID(for item: MetaPreview) -> String { "hero/\(item.identity)" }

    let item: MetaPreview
    let isScrolling: Bool
    /// The picture's height in portrait: the page less the caption band under it, so a pull stretches the picture too.
    let artworkHeight: CGFloat
    /// Pages between this one and the one on screen. Only pages inside `HeroCarousel.loadWindow` load their picture.
    let distance: Int
    @Environment(AppRouter.self) private var router
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isLandscape) private var isLandscape
    @Environment(PosterRatingsStore.self) private var ratings
    /// Starts from the artwork already looked up this session, so a title coming back into view shows its logo and picture at once.
    @State private var heroArtwork: TMDbArtwork?
    /// Set once the TMDb artwork lookup has finished, so a title with no logo can fall back to its name. Starts set when the artwork is known.
    @State private var artworkChecked: Bool
    @State private var hero = HeroLoader()

    init(item: MetaPreview, isScrolling: Bool, artworkHeight: CGFloat, cachedArtwork: TMDbArtwork?, distance: Int) {
        self.distance = distance
        self.item = item
        self.isScrolling = isScrolling
        self.artworkHeight = artworkHeight
        _heroArtwork = State(initialValue: cachedArtwork)
        _artworkChecked = State(initialValue: cachedArtwork != nil)
    }

    private var isInWindow: Bool { distance <= HeroCarousel.loadWindow }
    /// The nearest two pages jump the queue; the next one waits behind them.
    private var loadPriority: TaskPriority { distance <= 1 ? .high : .medium }
    /// What stands in for the picture and logo until both are ready.
    private var placeholderURL: URL? { item.poster ?? MetahubArtwork.poster(imdbID: item.id) }

    private var heroURL: URL? {
        (isLandscape ? heroArtwork?.backdrop : heroArtwork?.portrait)
            ?? (artworkChecked ? (item.background ?? MetahubArtwork.background(imdbID: item.id)) : nil)
    }
    private var heroPixelSize: CGFloat { isLandscape ? 4096 : TitleHero.portraitPixelSize }
    private var logoURL: URL? { item.logo ?? heroArtwork?.logo }
    private var pictureSlot: HeroSlot { hero.slot(url: heroURL, maxPixelSize: heroPixelSize, lookupFinished: artworkChecked) }
    private var logoSlot: HeroSlot { hero.slot(url: logoURL, maxPixelSize: HeroLoader.logoPixelSize, lookupFinished: artworkChecked) }
    private var isRevealed: Bool { HeroLoader.isRevealed(pictureSlot, logoSlot) }

    var body: some View {
        let destination = TitleDestination(preview: item, sourceID: HeroPage.sourceID(for: item), artwork: heroArtwork,
                                           artworkChecked: artworkChecked)
        let openTitle = {
            Haptics.tap()
            router.homePath.append(destination)
        }
        pageContent
        .overlay(alignment: .top) {
            // A tap anywhere on the page opens the title, but never claims a drag or disables views during one.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .task(id: "\(ratings.reviewServicesRevision)|\(isInWindow)") {
            guard isInWindow else { return }
            let loaded = await ratings.heroArtwork(for: item)
            guard !Task.isCancelled else { return }
            heroArtwork = loaded
            artworkChecked = true
        }
        .task(id: "\(heroURL?.absoluteString ?? "-")|\(heroPixelSize)|\(logoURL?.absoluteString ?? "-")|\(artworkChecked)|\(isInWindow)|\(distance <= 1)") {
            guard isInWindow else { return }
            await hero.load(priority: loadPriority, picture: heroURL, pictureSize: heroPixelSize, logo: logoURL, logoSize: HeroLoader.logoPixelSize,
                            lookupFinished: artworkChecked)
        }
    }

    /// Landscape keeps the caption over the picture. Portrait stops the picture above a band that holds the metadata, and the title sits
    /// low on the picture as it does on the title page.
    @ViewBuilder
    private var pageContent: some View {
        if isLandscape {
            ZStack(alignment: .bottom) {
                artwork
                    .allowsHitTesting(false)
                // Keep the fade outside the zoom source so a cancelled press cannot hide it. The same fade the title page's hero uses,
                // and the only shading on the picture.
                BottomFade(length: 0.42)
                caption
                    .allowsHitTesting(false)
            }
        } else {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    artwork
                        .allowsHitTesting(false)
                    BottomFade(length: TitleHero.fadeLength, strength: TitleHero.fadeStrength)
                    portraitTitle
                }
                .frame(height: artworkHeight)
                MetaLine(metaParts)
                    .multilineTextAlignment(.center)
                    .allowsHitTesting(false)
                    .padding(.top, Theme.Spacing.s)
                    .frame(height: TitleHero.captionBelow, alignment: .top)
            }
            .foregroundStyle(.white)
        }
    }

    /// The portrait title, low on the picture above the bottom gap.
    private var portraitTitle: some View {
        titleBlock
            .allowsHitTesting(false)
            .padding(.horizontal, metrics.contentMargin)
            .padding(.bottom, TitleHero.logoBottomGap)
    }

    private var artwork: some View {
        Color.clear
            .overlay {
                HeroPicture(slot: pictureSlot, isRevealed: isRevealed, contentMode: isLandscape ? .fit : .fill, placeholderURL: placeholderURL)
            }
            .zoomSource(id: HeroPage.sourceID(for: item), in: zoomNamespace)
    }

    /// The title, its logo and the metadata line.
    private var caption: some View {
        VStack(alignment: .center, spacing: Theme.Spacing.s) {
            titleBlock
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

    /// The logo once it is loaded, the name when there is no logo, and blank while the logo is pending. Hidden until the hero reveals.
    private var titleBlock: some View {
        Group {
            switch logoSlot {
            case .ready(let image):
                HeroLogo(image: image, isPortrait: !isLandscape)
            case .none:
                Text(item.name)
                    .font(.largeTitle.bold())
                    .lineLimit(isLandscape ? 2 : 3)
                    .minimumScaleFactor(isLandscape ? 1 : 0.7)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            case .pending:
                if isLandscape {
                    Color.clear.frame(width: HeroLogo.box.width, height: HeroLogo.box.height)
                } else {
                    Color.clear.frame(maxWidth: .infinity).frame(height: TitleHero.logoMaxHeight)
                }
            }
        }
        .opacity(isRevealed ? 1 : 0)
    }

    /// Year, the first two genres and the rating, dot-separated. Parts that are missing are left out by `MetaLine`.
    private var metaParts: [String?] {
        let rating = item.imdbRating.map { "★ \($0.formatted(.number.precision(.fractionLength(1))))" }
        return [item.releaseInfo] + item.genres.prefix(2).map { Optional($0) } + [rating]
    }
}

/// A title's logo, fitted into a box of fixed size so the text under it never moves when it arrives. On Home's portrait spotlight the
/// box is the full width and the title page's logo height, so the two match.
struct HeroLogo: View {
    static let box = CGSize(width: 260, height: 84)

    let image: UIImage
    var isPortrait = false

    var body: some View {
        logoBox
    }

    @ViewBuilder
    private var logoBox: some View {
        if isPortrait {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: TitleHero.logoMaxHeight)
                .overlay(alignment: .bottom) { picture }
        } else {
            Color.clear
                .frame(width: Self.box.width, height: Self.box.height)
                .overlay(alignment: .bottom) { picture }
        }
    }

    private var picture: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
    }
}
#endif
