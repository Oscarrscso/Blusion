#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// The title page, drawn the way Apple's TV app draws one: artwork under the navigation bar with the logo low on it, one quiet
/// metadata line, the main action, round secondary actions, the synopsis, then for a series its seasons and episodes, and last
/// the credits.
struct DetailView: View {
    private enum ReviewSort: String, CaseIterable {
        case highestRated = "Highest rated"
        case lowestRated = "Lowest rated"
        case longest = "Longest review"
        case shortest = "Shortest review"
    }

    @State private var model: DetailViewModel
    @State private var isDescriptionExpanded = false
    @State private var isDescriptionTruncated = false
    @State private var isConfirmingUnmarkShow = false
    @State private var reviewSort = ReviewSort.highestRated
    @State private var expandedReviewID: String?
    /// How far the page has been pulled down past its top. The portrait hero stretches by this much, like a refresh.
    @State private var scrollPull: CGFloat = 0
    @State private var renderedLogoHeight: CGFloat = TitleHero.logoMaxHeight
    /// Loads the hero picture and logo together, and reveals them together.
    @State private var hero = HeroLoader()
    /// The screen's safe-area inset at its sides: the notch side of a phone held in landscape, zero elsewhere.
    @State private var sideInset: CGFloat = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isLandscape) private var isLandscape
    @Environment(TitleActions.self) private var titleActions

    /// How far the page's scroll indicator is kept from the top and bottom of the screen.
    private static let scrollIndicatorInset: CGFloat = 260
    /// The back button with its leading gap and the gap after it. In landscape the page keeps this column free.
    private static let backButtonColumn: CGFloat = 72
    /// The one gap in the action row: between Play and the round actions beside it, and between those actions. All gaps are equal.
    private static let actionGap: CGFloat = 6
    /// The height of the season picker and of the episode-width toggle, so the two sit level on one line.
    private static let secondaryControlHeight: CGFloat = 36

    /// In portrait the artwork runs under the bar, so the page margin is enough. In landscape on iPhone the page keeps the portrait margin
    /// plus only the device's side safe-area inset, with no back-button column. On Mac the back button floats over the page's top
    /// leading corner with nothing behind it, so the page starts beside it rather than under it: the content keeps clear of the
    /// button's column, on both sides so it stays centred, and nothing scrolls beneath the button.
    private var contentMargin: CGFloat {
        guard isLandscape else { return metrics.contentMargin }
        #if targetEnvironment(macCatalyst)
        return max(sideInset, windowSideInset) + Self.backButtonColumn
        #else
        return metrics.contentMargin + max(sideInset, windowSideInset)
        #endif
    }

    /// The window's own side insets. The root lets screens run under them, so the page's geometry may not report them.
    private var windowSideInset: CGFloat {
        let insets = UIApplication.shared.connectedScenes.lazy.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets
        return max(insets?.left ?? 0, insets?.right ?? 0)
    }
    private let sectionSpacing = Theme.Spacing.xl + Theme.Spacing.l

    init(preview: MetaPreview, services: AppServices, artwork: TMDbArtwork? = nil, artworkChecked: Bool = false) {
        _model = State(initialValue: DetailViewModel(preview: preview, services: services, artwork: artwork, artworkChecked: artworkChecked))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    feature(in: geometry.size)
                    if model.isSeries { episodesSection(pageWidth: geometry.size.width) }
                    credits(in: geometry.size.width)
                        .padding(.top, sectionSpacing)
                    if !model.relatedTitles.isEmpty {
                        related
                            .padding(.top, sectionSpacing)
                    }
                }
                .padding(.bottom, Theme.Spacing.xxl)
            }
            // The track of the page's own scroll indicator is inset, so the bar is a short line rather than the whole screen height.
            .contentMargins(.vertical, Self.scrollIndicatorInset, for: .scrollIndicators)
            .onScrollGeometryChange(for: CGFloat.self) { max(0, -($0.contentOffset.y + $0.contentInsets.top)) } action: { _, value in
                scrollPull = value
            }
        }
        .onGeometryChange(for: [CGFloat].self) { [$0.size.width, $0.safeAreaInsets.leading, $0.safeAreaInsets.trailing] } action: { values in
            // Kept in state so a rotation lays the page out again with the new inset.
            sideInset = max(values[1], values[2], windowSideInset)
        }
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
        .task(id: "\(model.hasSettledHero)|\(primaryRequest?.id ?? "-")") {
            guard model.hasSettledHero else { return }
            model.prefetchStreams(for: primaryRequest)
        }
        .onAppear { Task { await model.refreshUserState() } }
        .onDisappear { model.releaseStreamPrefetch() }
        .accessibilityIdentifier("detail.scroll")
    }

    // MARK: - Header

    /// The main picture: the backdrop in landscape, the tall artwork in portrait. Nil until the artwork lookup answers; nothing is drawn for it until the picture and the logo are both ready.
    private var heroURL: URL? { isLandscape ? model.backdropURL : model.portraitArtworkURL }

    /// The longest edge the hero is decoded to: full screen in landscape, the smaller size shared with Home in portrait.
    private var heroPixelSize: CGFloat { isLandscape ? 4096 : TitleHero.portraitPixelSize }

    private var placeholderURL: URL? { model.preview.poster ?? MetahubArtwork.poster(imdbID: model.preview.id) }
    private var logoURL: URL? { model.logoURL }
    private var pictureSlot: HeroSlot { hero.slot(url: heroURL, maxPixelSize: heroPixelSize, lookupFinished: !model.isLoadingArtwork) }
    private var logoSlot: HeroSlot { hero.slot(url: logoURL, maxPixelSize: HeroLoader.logoPixelSize, lookupFinished: !model.isLoadingArtwork) }
    /// The picture and the logo are revealed together, once neither is still pending.
    private var isHeroRevealed: Bool { HeroLoader.isRevealed(pictureSlot, logoSlot) }

    private func loadHero() async {
        await hero.load(picture: heroURL, pictureSize: heroPixelSize, logo: logoURL, logoSize: HeroLoader.logoPixelSize,
                        lookupFinished: !model.isLoadingArtwork)
    }

    @ViewBuilder
    private func feature(in size: CGSize) -> some View {
        if isLandscape {
            let artworkWidth = max(120, (size.width - contentMargin * 2 - Theme.Spacing.xl) * TitleHero.landscapeArtworkShare)
            HStack(alignment: .center, spacing: Theme.Spacing.xl) {
                HeroPicture(slot: pictureSlot, isRevealed: isHeroRevealed, contentMode: .fit, placeholderURL: placeholderURL)
                    .frame(width: artworkWidth, height: artworkWidth * 9 / 16)
                    .overlay(alignment: .bottomTrailing) {
                        PosterRatingsOverlay(item: model.preview, isLandscape: true, startsLoading: model.hasSettledHero)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.surface, style: .continuous))
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    titleArt(alignment: .leading)
                    controls
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, contentMargin)
            .padding(.vertical, Theme.Spacing.m)
            synopsis
                .padding(.horizontal, contentMargin)
                .padding(.top, Theme.Spacing.s)
        } else {
            let height = TitleHero.height(width: size.width, metrics: metrics)
            VStack(spacing: 0) {
                // Reserve artwork above the measured logo; all text and controls participate in normal vertical layout.
                Color.clear
                    .frame(height: max(0, height - renderedLogoHeight - TitleHero.logoBottomGap))
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    titleArt(alignment: .center)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { renderedLogoHeight = $0 }
                    // The block below the logo keeps the section gap from the logo, the same gap the season picker or the credits keep
                    // below it, so the block sits centred between the two. The stack's own spacing is part of that gap.
                    controls
                        .padding(.top, sectionSpacing - Theme.Spacing.m)
                    synopsis
                    RatingButtonsRow(item: model.detail.preview, startsLoading: model.hasSettledHero)
                }
                .padding(.horizontal, contentMargin)
            }
            .background(alignment: .top) {
                ZStack(alignment: .bottom) {
                    HeroPicture(slot: pictureSlot, isRevealed: isHeroRevealed, contentMode: .fill, placeholderURL: placeholderURL)
                    BottomFade(length: TitleHero.fadeLength, strength: TitleHero.fadeStrength)
                }
                .frame(width: size.width, height: height + scrollPull)
                .clipped()
                .offset(y: -scrollPull)
            }
        }
    }

    private func titleArt(alignment: Alignment) -> some View {
        TitleArt(name: model.detail.name, slot: logoSlot, alignment: alignment, compact: isLandscape)
            .frame(maxWidth: .infinity, alignment: alignment)
            // Hidden rather than removed, so the layout does not move when the title appears.
            .opacity(isHeroRevealed ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.detail.name)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("detail.title")
    }

    private var controls: some View {
        VStack(alignment: isLandscape ? .leading : .center, spacing: Theme.Spacing.m) {
            MetaLine([model.detail.preview.genres.first] + model.metaParts.map { Optional($0) })
                .multilineTextAlignment(isLandscape ? .leading : .center)
            actionRow
            if model.isFallback && !model.isLoading {
                Label("Only basic details are available for this title.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("detail.fallbackNote")
            }
        }
    }

    /// The one main action. A movie plays itself; a series plays its next episode. While a series' episodes are still arriving,
    /// a placeholder holds the place.
    @ViewBuilder
    private var primaryAction: some View {
        if let request = primaryRequest {
            NavigationLink(value: request) {
                Label(model.primaryActionTitle, systemImage: "play.fill")
            }
            .buttonStyle(.primaryAction)
            .accessibilityIdentifier("detail.playButton")
        } else if model.isLoading {
            Capsule()
                .fill(Theme.surfaceStrong)
                .frame(height: 50)
                .shimmering()
                .accessibilityHidden(true)
        }
    }

    private var primaryRequest: StreamRequest? {
        guard model.isSeries else { return model.movieRequest }
        return model.nextUp.map { model.request(for: $0) }
    }

    /// Play fills the remaining width beside the circle actions, on one line. The label shrinks before the row ever stacks, so a long
    /// "Resume S3 · E12" stays beside Save, Watched and Trailer.
    @ViewBuilder
    private var actionRow: some View {
        #if !targetEnvironment(macCatalyst)
        if isLandscape {
            GlassEffectContainer(spacing: Self.actionGap / 2) {
                HStack(alignment: .center, spacing: Self.actionGap) {
                    primaryAction
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                    HStack(spacing: Self.actionGap) {
                        saveAction
                        watchedAction
                        trailerAction
                    }
                    .fixedSize()
                    .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            portraitActionRow
        }
        #else
        portraitActionRow
        #endif
    }

    private var portraitActionRow: some View {
        HStack(alignment: .center, spacing: Self.actionGap) {
            primaryAction
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
            secondaryActions
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: isLandscape ? .leading : .center)
    }

    private var secondaryActions: some View {
        GlassEffectContainer(spacing: Self.actionGap) {
            HStack(spacing: Self.actionGap) {
                saveAction
                watchedAction
                trailerAction
            }
        }
        .fixedSize()
    }

    private var saveAction: some View {
        CircleActionButton(title: "Save", systemImage: "bookmark", isOn: model.isInLibrary, onTitle: "Saved", onSystemImage: "bookmark.fill") {
            Task {
                await model.toggleLibrary()
                await titleActions.refresh()
            }
        }
        .accessibilityValue(model.isInLibrary ? "Saved" : "Not saved")
        .accessibilityIdentifier("detail.libraryButton")
    }

    /// A movie is marked on its own. A show is marked as a whole: every episode that has aired. Clearing a whole show asks first,
    /// because it removes the mark from every episode at once.
    @ViewBuilder
    private var watchedAction: some View {
        if model.isSeries {
            let watched = model.isSeriesWatched
            CircleActionButton(title: "Watched", systemImage: "eye", isOn: watched) {
                if watched {
                    isConfirmingUnmarkShow = true
                } else {
                    Task {
                        await model.setSeriesWatched(true)
                        await titleActions.refresh()
                    }
                }
            }
            .disabled(model.detail.videos.isEmpty)
            .opacity(model.detail.videos.isEmpty ? 0.4 : 1)
            .accessibilityValue(watched ? "Every episode watched" : "Not watched")
            .accessibilityHint(watched ? "Clears the watched mark from every episode" : "Marks every episode that has aired as watched")
            .accessibilityIdentifier("detail.watchedButton")
            .confirmationDialog("Mark every episode as not watched?", isPresented: $isConfirmingUnmarkShow, titleVisibility: .visible) {
                Button("Mark Show as Not Watched", role: .destructive) {
                    Task {
                        await model.setSeriesWatched(false)
                        await titleActions.refresh()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        } else {
            let request = model.movieRequest
            let watched = model.isWatched(request)
            CircleActionButton(title: "Watched", systemImage: "eye", isOn: watched) {
                Task {
                    await model.setWatched(!watched, for: request)
                    await titleActions.refresh()
                }
            }
            .accessibilityValue(watched ? "Watched" : "Not watched")
            .accessibilityIdentifier("detail.watchedButton")
        }
    }

    /// Opens the trailer with the app's shared web link handler. It is there from the start, so the row does not change when the page
    /// loads; until the trailer is known it is dimmed and does nothing.
    private var trailerAction: some View {
        CircleActionButton(title: "Trailer", systemImage: "play.rectangle") {
            if let url = model.trailerURL { openURL(url) }
        }
        .disabled(model.trailerURL == nil)
        .opacity(model.trailerURL == nil ? 0.4 : 1)
        .accessibilityIdentifier("detail.trailerButton")
    }

    @ViewBuilder
    private var synopsis: some View {
        if let description = model.detail.preview.description, !description.isEmpty {
            // Folded when it runs past three lines; one that fits has nothing to fold, so a tap does nothing.
            let folds = isDescriptionExpanded || isDescriptionTruncated
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                JustifiedText(text: description, color: UIColor.white.withAlphaComponent(0.85), lineLimit: isDescriptionExpanded ? 0 : 3,
                              isTruncated: $isDescriptionTruncated)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    // A tap on the text folds or opens it.
                    .onTapGesture {
                        if folds { toggleDescription() }
                    }
                    .pointerFeedback(folds)
                    .accessibilityAddTraits(folds ? .isButton : [])
                    .accessibilityHint(folds ? (isDescriptionExpanded ? "Collapses the synopsis" : "Expands the synopsis") : "")
            }
        }
    }

    private func toggleDescription() {
        withAnimation(.easeInOut(duration: 0.25)) { isDescriptionExpanded.toggle() }
    }

    // MARK: - Series

    /// The season chips and the episodes of the selected season, each a row with its still, progress and watched mark.
    private func episodesSection(pageWidth: CGFloat) -> some View {
        let width = episodeWidth(pageWidth: pageWidth)
        return VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.m) {
                seasonMenu
                Spacer(minLength: 0)
                episodeWidthToggle
            }
            .padding(.horizontal, contentMargin)
            if model.isLoading && model.episodes.isEmpty {
                SkeletonRow(aspect: .wide)
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: metrics.cardSpacing) {
                    ForEach(model.episodes) { episode in
                        episodeRow(episode, width: width)
                            .id(episode.id).reportsShelfEdge(id: episode.id)
                    }
                }
                .scrollTargetLayout()
            }
            .shelfIndicators()
            .contentMargins(.horizontal, contentMargin, for: .scrollContent)
            .softSnappingScroll()
            .scrollClipDisabled()
            .animation(.snappy, value: model.matchesEpisodeWidthToText)
        }
        .padding(.top, sectionSpacing)
        // IMDb's per-episode scores come from OMDb, a season at a time as the viewer picks one (and again if the key changes).
        .task(id: "\(model.selectedSeason.map(String.init) ?? "-"):\(model.reviewServicesRevision):\(model.isLoading):\(model.hasSettledHero)") {
            guard model.hasSettledHero else { return }
            await model.loadEpisodeScores(season: model.selectedSeason)
        }
    }

    /// The season name with its chevron. Choosing opens the list of seasons, and the mark-as-watched action for the selected one.
    private var seasonMenu: some View {
        Menu {
            ForEach(model.seasons, id: \.self) { season in
                Button(season == 0 ? "Specials" : "Season \(season)") { model.selectedSeason = season }
            }
            if let season = model.selectedSeason {
                Divider()
                let watched = model.isSeasonWatched(season)
                let name = season == 0 ? "Specials" : "Season \(season)"
                Button(watched ? "Mark \(name) as Not Watched" : "Mark \(name) as Watched",
                       systemImage: watched ? "xmark.circle" : "checkmark.circle") {
                    Task {
                        await model.setSeasonWatched(!watched, season: season)
                        await titleActions.refresh()
                    }
                }
                .accessibilityIdentifier("detail.seasonWatched")
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.selectedSeason == 0 ? "Specials" : "Season \(model.selectedSeason ?? 1)").font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.glass)
        .frame(height: Self.secondaryControlHeight)
        .pointerFeedback()
        .accessibilityIdentifier("detail.seasonPicker")
    }

    /// Switches the episode cards between their fixed width and the width of the text. The symbol shows the layout in use: a row of
    /// cards, or one card across the page.
    private var episodeWidthToggle: some View {
        let isWide = model.matchesEpisodeWidthToText
        return Button {
            Task { await model.setMatchesEpisodeWidthToText(!isWide) }
        } label: {
            Image(systemName: isWide ? "rectangle" : "rectangle.split.3x1")
                .font(.body.weight(.semibold))
                .contentTransition(.symbolEffect(.replace))
        }
        .glassCircleButton(.regular)
        .frame(width: Self.secondaryControlHeight, height: Self.secondaryControlHeight)
        .titleTapHaptic()
        .accessibilityLabel("Episode width")
        .help("Episode width")
        .accessibilityValue(isWide ? "Full width" : "Fixed width")
        .accessibilityIdentifier("detail.episodeWidthToggle")
    }

    /// The text above the episodes runs from one page margin to the other. With the toggle on, each card is that wide, so the cards
    /// line up with it; otherwise they keep their fixed width.
    private func episodeWidth(pageWidth: CGFloat) -> CGFloat {
        model.matchesEpisodeWidthToText ? pageWidth - contentMargin * 2 : metrics.episodeWidth
    }

    private func episodeRow(_ video: Video, width: CGFloat) -> some View {
        NavigationLink(value: model.request(for: video)) {
            EpisodeRow(video: video, fraction: model.progressFraction(for: video), watched: model.isWatched(video),
                       artwork: model.backdropURL, score: model.score(for: video), width: width,
                       showsWholeOverview: model.matchesEpisodeWidthToText)
        }
        .buttonStyle(PressableCardStyle())
        .titleTapHaptic()
        .contextMenu {
            let watched = model.isWatched(video)
            Button(watched ? "Mark as not watched" : "Mark as watched", systemImage: watched ? "xmark.circle" : "checkmark.circle") {
                Task {
                    await model.setWatched(!watched, for: model.request(for: video))
                    await titleActions.refresh()
                }
            }
        }
        .accessibilityIdentifier("detail.episode.\(video.id)")
    }

    // MARK: - Credits

    private var sortedReviews: [TMDbReview] {
        model.reviews.sorted {
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

    private func credits(in width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            if isLandscape {
                RatingButtonsRow(item: model.detail.preview, startsLoading: model.hasSettledHero)
                    .padding(.horizontal, contentMargin)
            }
            if !model.reviews.isEmpty {
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
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: metrics.cardSpacing) {
                                ForEach(sortedReviews) { review in
                                    ReviewCard(review: review, isExpanded: expandedReviewID == review.id) {
                                        withAnimation(.snappy(duration: 0.35)) {
                                            expandedReviewID = expandedReviewID == review.id ? nil : review.id
                                        }
                                    }
                                    .frame(width: expandedReviewID == review.id
                                           ? max(0, width - contentMargin * 2)
                                           : (metrics.isRegular ? 340 : 280))
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
                            .scrollTargetLayout()
                        }
                        .shelfIndicators()
                        .contentMargins(.horizontal, contentMargin, for: .scrollContent)
                        .softSnappingScroll()
                        .scrollClipDisabled()
                    }
                }
            }
            if let people = model.castAndCrew, !people.isEmpty {
                VStack(alignment: .leading, spacing: metrics.headerSpacing) {
                    // TMDb's cast and key crew, with photos. Each photo loads as its card scrolls on, behind the rest of the page.
                    SectionHeader("Cast & Crew")
                        .padding(.horizontal, contentMargin)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: metrics.cardSpacing) {
                            ForEach(people) { PersonCardLink(person: $0).reportsShelfEdge(id: $0.id) }
                        }
                        .scrollTargetLayout()
                    }
                    .shelfIndicators()
                    .contentMargins(.horizontal, contentMargin, for: .scrollContent)
                    .softSnappingScroll()
                    .scrollClipDisabled()
                    .accessibilityIdentifier("detail.castCarousel")
                }
            } else if !model.detail.cast.isEmpty {
                VStack(alignment: .leading, spacing: metrics.headerSpacing) {
                    // Without TMDb (no read token, or it did not answer) the addon's names still show, as initials, and open nothing.
                    SectionHeader("Cast & Crew")
                        .padding(.horizontal, contentMargin)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: metrics.cardSpacing) {
                            ForEach(model.detail.cast, id: \.self) { name in
                                VStack(spacing: 8) {
                                    Text(name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined())
                                        .font(.title2.weight(.medium))
                                        .frame(width: metrics.avatarSize, height: metrics.avatarSize)
                                        .background(Theme.surfaceStrong, in: Circle())
                                    Text(name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                                }
                                .frame(width: metrics.avatarSize + 12)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(name)
                                .reportsShelfEdge(id: name)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .shelfIndicators()
                    .contentMargins(.horizontal, contentMargin, for: .scrollContent)
                    .softSnappingScroll()
                    .scrollClipDisabled()
                }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader("Information")
                information("Released", model.detail.preview.releaseInfo)
                information("Runtime", model.detail.preview.runtime)
                information("Genres", model.detail.preview.genres.joined(separator: ", "))
                information("Director", model.detail.director.joined(separator: ", "))
                information("Writers", model.detail.writers.joined(separator: ", "))
            }
            .frame(maxWidth: metrics.readableWidth, alignment: .leading)
            .padding(.horizontal, contentMargin)
        }
    }

    /// Titles TMDb recommends for this one, at the bottom of the page. Each opens its own page.
    private var related: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            SectionHeader("More Like This")
                .padding(.horizontal, contentMargin)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: metrics.cardSpacing) {
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
                .scrollTargetLayout()
            }
            .shelfIndicators()
            .contentMargins(.horizontal, contentMargin, for: .scrollContent)
            .scrollClipDisabled()
            .softSnappingScroll()
            .accessibilityIdentifier("detail.related")
        }
    }

    @ViewBuilder
    private func information(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(title) { Text(value).foregroundStyle(.primary) }
                .font(.footnote)
        }
    }
}

// MARK: - Pieces

/// One TMDb review. Folded, every card is the same height: the text keeps six lines whether or not it fills them. A tap opens or
/// folds it, and only a review that runs past those lines folds.
private struct ReviewCard: View {
    let review: TMDbReview
    let isExpanded: Bool
    let onToggle: () -> Void
    @State private var isTruncated = false

    private var folds: Bool { isExpanded || isTruncated }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
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
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Rating \(stars.formatted(.number.precision(.fractionLength(0...1)))) out of 5 stars")
                    }
                }
                JustifiedText(text: review.content, textStyle: .subheadline, isMarkdown: true, lineLimit: isExpanded ? 0 : 6,
                              reservesSpace: true, isTruncated: $isTruncated)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if folds { onToggle() }
            }
        }
        .padding(16)
        .cardSurface()
    }
}

/// The logo, or the name when there is no logo or it failed to load. The logo comes from the shared hero loader and is revealed with the
/// picture. While it is pending the name is not drawn, and its full height is kept, so the text below does not move when it arrives.
private struct TitleArt: View {
    let name: String
    let slot: HeroSlot
    let alignment: Alignment
    let compact: Bool

    /// The tallest a logo can be on this page.
    private var logoHeight: CGFloat { compact ? TitleHero.landscapeLogoMaxHeight : TitleHero.logoMaxHeight }
    /// Whether the slot has no logo: no URL once the lookup has finished, or a failed load.
    private var isNone: Bool {
        if case .none = slot { return true }
        return false
    }
    /// A title keeps the logo's space until the logo is ready or known to be absent.
    private var reservesLogoHeight: Bool { !isNone }

    var body: some View {
        Group {
            if case .ready(let image) = slot {
                LogoLayout(imageSize: image.size, maxWidth: compact ? TitleHero.landscapeLogoMaxWidth : .infinity, maxHeight: logoHeight) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Text(name)
                    .font(compact ? .title2.bold() : .largeTitle.bold())
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .foregroundStyle(.white)
                    .lineLimit(compact ? 2 : 3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isNone ? 1 : 0)
            }
        }
        // Bottom-aligned, so a logo shorter than the reserved space sits where it did before, just above the controls.
        .frame(minHeight: reservesLogoHeight ? logoHeight : nil, alignment: Alignment(horizontal: alignment.horizontal, vertical: .bottom))
    }
}

/// Reports the fitted image bounds instead of a taller frame containing empty space.
private struct LogoLayout: Layout {
    let imageSize: CGSize
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let width = min(proposal.width ?? imageSize.width, maxWidth)
        let scale = min(width / imageSize.width, maxHeight / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

/// One episode: its still with the progress line or watched mark over it, the numbered title, the air date and rating, and the
/// overview: three lines in a fixed-width card, all of it in a full-width one.
private struct EpisodeRow: View {
    let video: Video
    let fraction: Double?
    let watched: Bool
    let artwork: URL?
    let score: DetailViewModel.EpisodeScore?
    let width: CGFloat
    /// Set for a full-width card: the whole overview shows at its own height, so the rating sits under this episode's own text.
    var showsWholeOverview = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            still
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let episode = video.episode {
                    Text("EPISODE \(episode)").font(Theme.Typography.eyebrow).foregroundStyle(.secondary)
                }
                Text(video.title)
                    .font(.headline)
                    .lineLimit(2)
                if let overview = video.overview, !overview.isEmpty {
                    JustifiedText(text: overview, textStyle: .footnote, color: .secondaryLabel,
                                  lineLimit: showsWholeOverview ? 0 : 3)
                }
                dateAndScore
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width, alignment: .leading)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
    }

    /// The episode's own still, or the series' backdrop when the addon sent none.
    private var still: some View {
        ArtworkImage(url: video.thumbnail ?? artwork, maxPixelSize: width * 3)
            .frame(width: width, height: width / CardAspect.wide.ratio)
            .overlay {
                if !watched, let fraction {
                    PlaybackProgressOverlay(fraction: fraction, width: width)
                }
            }
            .overlay(alignment: .topTrailing) {
                if watched { checkmark }
            }
            .mediaArtwork(cornerRadius: Theme.Radius.small)
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(.black.opacity(0.6), in: Circle())
            .padding(Theme.Spacing.xs)
            .accessibilityHidden(true)
    }

    /// "Jan 20, 2008 · [IMDb] 8.9": the air date, then the score with the IMDb mark when it is IMDb's (a star when it is the addon's).
    @ViewBuilder
    private var dateAndScore: some View {
        let date = video.airDate?.formatted(date: .abbreviated, time: .omitted)
        if date != nil || score != nil {
            HStack(spacing: 5) {
                if let date { Text(date) }
                if date != nil, score != nil { Text("·") }
                if let score {
                    if score.isIMDb {
                        ReviewSiteIcon(site: .imdb, size: 13)
                    } else {
                        Image(systemName: "star.fill").font(.system(size: 9, weight: .bold))
                    }
                    Text(score.text).monospacedDigit()
                    if !score.isIMDb, video.ratingSource == .tmdb { Text("TMDb") }
                }
            }
            .font(Theme.Typography.metaLine)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([date, score.map {
                "\($0.isIMDb ? "IMDb rating" : video.ratingSource == .tmdb ? "TMDb rating" : "Rating") \($0.text)"
            }].compactMap { $0 }.joined(separator: ", "))
        }
    }
}
#endif
