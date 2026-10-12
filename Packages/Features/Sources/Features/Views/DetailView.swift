#if canImport(UIKit)
import SwiftUI
import StremioKit

/// The title page, drawn the way Apple's TV app draws one: artwork under the navigation bar with the logo low on it, one quiet
/// metadata line, the main action, round secondary actions, the synopsis, then for a series its seasons and episodes, and last
/// the credits.
struct DetailView: View {
    @State private var model: DetailViewModel
    @State private var isDescriptionExpanded = false
    @State private var isDescriptionTruncated = false
    @State private var isConfirmingUnmarkShow = false
    /// True while an episode's context menu is open. The page blurs behind it.
    @State private var isHoldingEpisode = false
    /// The streams the page shows in place of its details after Play; nil shows the details.
    @State private var pickedRequest: StreamRequest?
    /// How far the page has been pulled down past its top. The portrait hero stretches by this much, like a refresh.
    @State private var scrollPull: CGFloat = 0
    /// Loads the hero picture and logo together, and reveals them together. Starts with what the spotlight showed, when it opened this title.
    @State private var hero: HeroLoader
    /// The page's own side safe-area inset, as its geometry reports it: the notch side of a phone held in landscape, zero elsewhere. The
    /// window's share is added in `contentMargin`.
    @State private var sideInset: CGFloat = 0
    /// The least space kept clear above the logo, as the page's own geometry reports the top safe area. The page runs under the status bar,
    /// so the window's share is added where the hero uses it (see `windowSafeArea`).
    @State private var topInset: CGFloat = 0
    /// The largest bottom safe-area inset reported while the page has been this width (home indicator, tab bar, bottom accessory). The tab
    /// bar shrinks when it minimises during a scroll, so the end of the page clears the larger size, not the current one.
    @State private var bottomPeak: CGFloat = 0
    /// The width the page was last laid out at. A change (a rotation, a resized window) starts `bottomPeak` again.
    @State private var layoutWidth: CGFloat = 0
    /// The bottom inset the page's scroll view actually applies to its content, including the extra margin added below.
    @State private var scrollBottom: CGFloat = 0
    /// True when Home's spotlight opened the page (the only caller that passes a handoff). Only such a page plays the settle.
    private let opensFromSpotlight: Bool
    /// The stream picker shown in place of the details needs the services.
    private let services: AppServices
    /// Turns true when the page first appears, so the settle plays once for a page opened from the spotlight and not again when the user
    /// returns to it from a deeper page.
    @State private var hasSettled = false
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isLandscape) private var isLandscape
    @Environment(\.windowSafeArea) private var windowSafeArea

    /// How far the page's scroll indicator is kept from the top and bottom of the screen.
    private static let scrollIndicatorInset: CGFloat = 260
    /// The back button with its leading gap and the gap after it. In landscape the page keeps this column free.
    private static let backButtonColumn: CGFloat = 72
    /// How far the page blurs while an episode's menu is open.
    private static let heldBlur: CGFloat = 4
    /// The streams replace the details, or the details come back, in this swap.
    private static let swapAnimation = Animation.easeInOut(duration: 0.22)

    /// In portrait the artwork runs under the bar, so the page margin is enough. In landscape on iPhone the page keeps the portrait margin
    /// plus only the device's side safe-area inset, with no back-button column. On Mac the back button floats over the page's top
    /// leading corner with nothing behind it, so the page starts beside it rather than under it: the content keeps clear of the
    /// button's column, on both sides so it stays centred, and nothing scrolls beneath the button.
    private var contentMargin: CGFloat {
        guard isLandscape else { return metrics.contentMargin }
        #if targetEnvironment(macCatalyst)
        return max(sideInset, windowSideInset) + Self.backButtonColumn
        #else
        // Just clear of the notch and rounded corners: the side inset plus a small gap, never less than a slim margin.
        return max(max(sideInset, windowSideInset) + Theme.Spacing.xs, Theme.Spacing.m)
        #endif
    }

    /// The window's own side insets, from the root (see `windowSafeArea`). The root lets screens run under them, so the page's geometry
    /// may not report them.
    private var windowSideInset: CGFloat {
        max(windowSafeArea.leading, windowSafeArea.trailing)
    }

    /// What the scroll view lacks of the bottom safe area. The page is a scroll view inside a geometry reader, so it may not apply the
    /// tab bar and accessory inset to its content itself. The inset it applies, less the extra margin added here, is what the system
    /// gives; only the rest of the peak safe area is added, so it is never counted twice.
    @State private var bottomExtra: CGFloat = 0

    private func refreshBottomExtra() {
        let fromSystem = max(0, scrollBottom - bottomExtra)
        let next = max(0, bottomPeak - fromSystem)
        if abs(next - bottomExtra) > 0.5 { bottomExtra = next }
    }

    init(preview: MetaPreview, services: AppServices, artwork: TMDbArtwork? = nil, artworkChecked: Bool = false, handoff: HeroHandoff? = nil) {
        _model = State(initialValue: DetailViewModel(preview: preview, services: services, artwork: artwork, artworkChecked: artworkChecked,
                                                     trailerPreparer: AVTrailerPreparer()))
        _hero = State(initialValue: HeroLoader(seeding: handoff))
        self.services = services
        opensFromSpotlight = handoff != nil
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        DetailHero(model: model, size: geometry.size, contentMargin: contentMargin,
                                   topInset: max(topInset, windowSafeArea.top), scrollPull: scrollPull, pictureSlot: pictureSlot,
                                   logoSlot: logoSlot, isRevealed: isHeroRevealed, hidesLogo: hidesLogo,
                                   showsDetails: pickedRequest == nil) {
                            DetailActions(model: model, isConfirmingUnmarkShow: $isConfirmingUnmarkShow,
                                          showsActions: pickedRequest == nil, play: showStreams)
                        } trailer: {
                            DetailTrailerPanel(model: model, width: trailerWidth(in: geometry.size))
                        } synopsis: {
                            DetailSynopsis(description: model.detail.preview.description, isExpanded: $isDescriptionExpanded,
                                           isTruncated: $isDescriptionTruncated)
                        }
                        if let request = pickedRequest {
                            // The streams take the place of everything below the metadata line. The picture, the logo and the line stay.
                            StreamPickerView(request: request, services: services, isEmbedded: true, onClose: closeStreams)
                                .id(request.id)
                                .padding(.top, metrics.titleRatingsGap)
                                // At least a screen tall, so the page is never shorter than where it was scrolled to when Play was
                                // tapped: a page that became too short would jump back to its top.
                                .frame(minHeight: geometry.size.height, alignment: .top)
                                .transition(.opacity)
                        } else {
                            Group {
                                Rectangle()
                                    .fill(Theme.separator)
                                    .frame(height: 1)
                                    .padding(.horizontal, contentMargin)
                                    .padding(.top, metrics.titleRatingsGap)
                                    .accessibilityHidden(true)
                                if model.isSeries {
                                    DetailEpisodes(model: model, pageWidth: geometry.size.width, contentMargin: contentMargin,
                                                   isHoldingEpisode: $isHoldingEpisode)
                                        .padding(.top, metrics.titleRatingsGap)
                                }
                                VStack(alignment: .leading, spacing: metrics.titleSectionSpacing) {
                                    if !model.reviews.isEmpty {
                                        DetailReviews(reviews: model.reviews, width: geometry.size.width, contentMargin: contentMargin)
                                    }
                                    DetailCredits(model: model, contentMargin: contentMargin)
                                }
                                .padding(.top, model.isSeries ? metrics.titleSectionSpacing : metrics.titleRatingsGap)
                                if !model.relatedTitles.isEmpty {
                                    related
                                        .padding(.top, metrics.titleSectionSpacing)
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .padding(.bottom, Theme.Spacing.xxl)
                    // The panel's appearance and disappearance moves the content below it, rather than jumping.
                    .animation(.snappy(duration: 0.35), value: model.trailer.showsPanel)
                    // The system draws the held episode and its menu above the page, so they stay sharp.
                    .blur(radius: isHoldingEpisode ? Self.heldBlur : 0)
                    .animation(.easeOut(duration: 0.2), value: isHoldingEpisode)
                }
                // The track of the page's own scroll indicator is inset, so the bar is a short line rather than the whole screen height.
                .contentMargins(.vertical, Self.scrollIndicatorInset, for: .scrollIndicators)
                .contentMargins(.bottom, bottomExtra, for: .scrollContent)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.bottom } action: { _, value in
                    scrollBottom = value
                    refreshBottomExtra()
                }
                .onScrollGeometryChange(for: CGFloat.self) { max(0, -($0.contentOffset.y + $0.contentInsets.top)) } action: { _, value in
                    scrollPull = value
                }
                // A panel that appears may be below the fold. The page moves only as far as it needs to, and not at all when the panel is
                // already in view. The short wait lets the panel's own appearance start first, so the page moves to where it ends up.
                .onChange(of: model.trailer.showsPanel) { _, shows in
                    guard shows else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(50))
                        withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(DetailTrailerPanel.scrollID) }
                    }
                }
            }
        }
        .onGeometryChange(for: [CGFloat].self) {
            [$0.size.width, $0.safeAreaInsets.leading, $0.safeAreaInsets.trailing, $0.size.height, $0.safeAreaInsets.bottom,
             $0.safeAreaInsets.top]
        } action: { values in
            // Kept in state so a rotation lays the page out again with the new insets.
            sideInset = max(values[1], values[2])
            topInset = values[5]
            if abs(values[0] - layoutWidth) > 0.5 {
                layoutWidth = values[0]
                bottomPeak = 0
            }
            bottomPeak = max(bottomPeak, values[4])
            refreshBottomExtra()
        }
        // The settle scales the whole visible page about the screen's centre; the background behind it stays put.
        .heroSettle(trigger: hasSettled)
        .screenBackground()
        .ignoresSafeArea(.container, edges: isLandscape ? [] : .top)
        .scrollEdgeEffectHidden(true, for: .top)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(afterHero: { await loadHero() }) }
        .task(id: "\(heroURL?.absoluteString ?? "-")|\(logoURL?.absoluteString ?? "-")|\(model.isLoadingArtwork)|\(isLandscape)") {
            await loadHero()
        }
        // The Play button's stream lookup starts once the hero has settled, so it never delays the hero images.
        .task(id: "\(model.hasSettledHero)|\(model.primaryRequest?.id ?? "-")") {
            guard model.hasSettledHero else { return }
            model.prefetchStreams(for: model.primaryRequest)
        }
        .onAppear {
            Task { await model.refreshUserState() }
            if opensFromSpotlight { hasSettled = true }
        }
        .onDisappear {
            model.releaseStreamPrefetch()
            // A full-screen trailer covers the page without leaving it, so its player stays. Leaving the page stops the load and player.
            if !model.trailer.isFullScreen { model.trailer.cancel() }
        }
        .accessibilityIdentifier("detail.scroll")
        .youTubeTrailer(Bindable(model.trailer).youTubeHandoff)
    }

    // MARK: - Streams

    /// Play shows this title's streams in place of its details, and the trailer stops, since it would play behind them. The page does
    /// not scroll, and back still leaves the page, by the button or the swipe: the streams are part of the title's page, not a screen
    /// of their own.
    private func showStreams(_ request: StreamRequest) {
        model.trailer.cancel()
        withAnimation(Self.swapAnimation) { pickedRequest = request }
    }

    /// Takes the streams away and shows the details again: the streams' own close button.
    private func closeStreams() {
        withAnimation(Self.swapAnimation) { pickedRequest = nil }
    }

    // MARK: - Header

    /// The trailer's panel is the page's width less its margins. In landscape it is also kept to the screen's height at 16:9, so the panel
    /// never runs off the bottom of a short screen.
    private func trailerWidth(in size: CGSize) -> CGFloat {
        let fitting = max(0, size.width - contentMargin * 2)
        guard isLandscape else { return fitting }
        return min(fitting, max(160, size.height * 0.78) * 16 / 9)
    }

    /// The main picture: the backdrop in landscape, the tall artwork in portrait. Nil until the artwork lookup answers; nothing is drawn for it until the picture and the logo are both ready.
    private var heroURL: URL? { isLandscape ? model.backdropURL : model.portraitArtworkURL }

    /// The longest edge the hero is decoded to: full screen in landscape, the smaller size shared with Home in portrait.
    private var heroPixelSize: CGFloat { isLandscape ? TitleHero.landscapePixelSize : TitleHero.portraitPixelSize }

    /// Portrait only, and only when the picture carries the title: the logo is neither loaded nor drawn, its space is kept.
    private var hidesLogo: Bool { !isLandscape && model.portraitHidesLogo }
    private var logoURL: URL? { hidesLogo ? nil : model.logoURL }
    private var pictureSlot: HeroSlot { hero.slot(url: heroURL, maxPixelSize: heroPixelSize, lookupFinished: !model.isLoadingArtwork) }
    private var logoSlot: HeroSlot { hero.slot(url: logoURL, maxPixelSize: HeroLoader.logoPixelSize, lookupFinished: !model.isLoadingArtwork) }
    /// The picture and the logo are revealed together, once neither is still pending.
    private var isHeroRevealed: Bool { HeroLoader.isRevealed(pictureSlot, logoSlot) }

    /// The title page's own picture and logo are urgent: they skip the queue behind Home's posters, since the user is waiting on them.
    private func loadHero() async {
        await hero.load(urgent: true, picture: heroURL, pictureSize: heroPixelSize, logo: logoURL, logoSize: HeroLoader.logoPixelSize)
    }

    /// Titles TMDb recommends for this one, at the bottom of the page. Each opens its own page.
    private var related: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            SectionHeader("More Like This")
                .padding(.horizontal, contentMargin)
            ShelfScroll(margin: contentMargin, spacing: metrics.cardSpacing) {
                ForEach(model.relatedTitles) { title in
                    NavigationLink(value: title.titleDestination) {
                        MediaCard(item: title.preview, aspect: .poster, showsRating: false)
                    }
                    .buttonStyle(PressableCardStyle())
                    .titleTapHaptic()
                    .reportsShelfEdge(id: title.id)
                    .accessibilityIdentifier("detail.related.\(title.id)")
                }
            }
            .accessibilityIdentifier("detail.related")
        }
    }
}
#endif
