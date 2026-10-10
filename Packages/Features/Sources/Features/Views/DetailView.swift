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

    private enum HeroPictureStatus { case pending, loaded, failed }

    @State private var model: DetailViewModel
    @State private var isDescriptionExpanded = false
    @State private var isDescriptionTruncated = false
    @State private var isConfirmingUnmarkShow = false
    @State private var reviewSort = ReviewSort.highestRated
    @State private var expandedReviewID: String?
    /// How far the page has been pulled down past its top. The portrait hero stretches by this much, like a refresh.
    @State private var scrollPull: CGFloat = 0
    @State private var renderedLogoHeight: CGFloat = 150
    /// Set once the hero picture has loaded or failed, or the timeout has passed. The title waits for it: the poster shown meanwhile
    /// often has the title printed on it.
    @State private var heroSettled = false
    /// Where the hero picture's download stands. It changes on every finish, so the spinner over the hero updates even after the
    /// timeout has already revealed the title.
    @State private var heroPicture = HeroPictureStatus.pending
    /// The height of the season's longest overview at the full card width. See `overviewRuler`.
    @State private var tallestOverview: CGFloat = 0
    /// The screen's safe-area inset at its sides: the notch side of a phone held in landscape, zero elsewhere.
    @State private var sideInset: CGFloat = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isLandscape) private var isLandscape
    @Environment(TitleActions.self) private var titleActions

    /// How far the page's scroll indicator is kept from the top and bottom of the screen.
    private static let scrollIndicatorInset: CGFloat = 260
    /// How long the title waits for the hero picture, counted from opening the page. After this it shows over the poster.
    private static let heroTimeout: Duration = .seconds(5)
    /// The back button with its leading gap and the gap after it. In landscape the page keeps this column free.
    private static let backButtonColumn: CGFloat = 72

    /// In landscape the back button floats over the page's top leading corner with nothing behind it, and the page starts beside it
    /// rather than under it: the content keeps clear of the button's column, on both sides so it stays centred, and nothing scrolls
    /// beneath the button. In portrait the artwork runs under the bar, so the page margin is enough.
    private var contentMargin: CGFloat {
        isLandscape ? max(sideInset, windowSideInset) + Self.backButtonColumn : metrics.contentMargin
    }

    /// The window's own side insets. The root lets screens run under them, so the page's geometry may not report them.
    private var windowSideInset: CGFloat {
        let insets = UIApplication.shared.connectedScenes.lazy.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets
        return max(insets?.left ?? 0, insets?.right ?? 0)
    }
    private let sectionSpacing = Theme.Spacing.xl + Theme.Spacing.l

    init(preview: MetaPreview, services: AppServices, artwork: TMDbArtwork? = nil) {
        _model = State(initialValue: DetailViewModel(preview: preview, services: services, artwork: artwork))
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
        .task { await model.load() }
        .task(id: heroURL) { await settleHero() }
        .task {
            // Starts on opening, so a slow artwork lookup counts against the same five seconds as a slow download.
            guard (try? await Task.sleep(for: Self.heroTimeout)) != nil else { return }
            heroSettled = true
        }
        .onAppear { Task { await model.refreshUserState() } }
        .accessibilityIdentifier("detail.scroll")
    }

    // MARK: - Header

    /// The main picture: the backdrop in landscape, the tall artwork in portrait. Until the artwork lookup answers, the poster stands in.
    private var heroURL: URL? { isLandscape ? model.backdropURL : model.portraitArtworkURL }

    /// The title shows once the hero picture has loaded or failed, with the poster behind it. With no picture to wait for, it shows
    /// as soon as the artwork lookup has answered.
    private var isTitleRevealed: Bool { heroSettled || (heroURL == nil && !model.isLoadingArtwork) }

    /// Waits for the hero picture to finish. `ImagePipeline` shares this download with the `ArtworkImage` showing it, so no extra request.
    private func settleHero() async {
        guard let heroURL else { return }
        heroPicture = .pending
        let picture = try? await ImagePipeline.shared.image(for: heroURL, maxPixelSize: 4096)
        guard !Task.isCancelled else { return }
        heroPicture = picture == nil ? .failed : .loaded
        heroSettled = true
    }

    /// The spinner over the hero until its picture is decoded: while the artwork lookup runs, then while the picture downloads. A
    /// failed download stops it. `ImagePipeline` caches a picture before it is returned, so a cached one never shows the spinner.
    private var isHeroLoading: Bool {
        guard let heroURL else { return model.isLoadingArtwork }
        return heroPicture != .failed && ImagePipeline.shared.cachedImage(for: heroURL, maxPixelSize: 4096) == nil
    }

    /// A small native spinner in the middle of the hero, shown while `isHeroLoading`.
    @ViewBuilder
    private var heroSpinner: some View {
        if isHeroLoading {
            ProgressView()
                .controlSize(.regular)
                .tint(.white)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func feature(in size: CGSize) -> some View {
        if isLandscape {
            let artworkWidth = max(120, (size.width - contentMargin * 2 - Theme.Spacing.xl) * 0.48)
            HStack(alignment: .center, spacing: Theme.Spacing.xl) {
                ArtworkImage(url: heroURL, maxPixelSize: 4096, contentMode: .fit,
                             placeholderURL: model.preview.poster ?? MetahubArtwork.poster(imdbID: model.preview.id), placeholderBlur: 0)
                    .frame(width: artworkWidth, height: artworkWidth * 9 / 16)
                    .overlay { heroSpinner }
                    .overlay(alignment: .bottomTrailing) { PosterRatingsOverlay(item: model.preview, isLandscape: true) }
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
            let height = min(size.width * 1.5, metrics.heroMaxHeight)
            VStack(spacing: 0) {
                // Reserve artwork above the measured logo; all text and controls participate in normal vertical layout.
                Color.clear
                    .frame(height: max(0, height - renderedLogoHeight - Theme.Spacing.xl))
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    titleArt(alignment: .center)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { renderedLogoHeight = $0 }
                    controls
                    synopsis
                    RatingButtonsRow(item: model.detail.preview)
                }
                .padding(.horizontal, contentMargin)
            }
            .background(alignment: .top) {
                ZStack(alignment: .bottom) {
                    ArtworkImage(url: heroURL, maxPixelSize: 4096, contentMode: .fill,
                                 placeholderURL: model.preview.poster ?? MetahubArtwork.poster(imdbID: model.preview.id), placeholderBlur: 0)
                    BottomFade(length: 0.42)
                }
                .frame(width: size.width, height: height + scrollPull)
                .clipped()
                .overlay { heroSpinner }
                .animation(.easeOut(duration: 0.25), value: isHeroLoading)
                .offset(y: -scrollPull)
            }
        }
    }

    private func titleArt(alignment: Alignment) -> some View {
        TitleArt(name: model.detail.name, logo: model.logoURL, alignment: alignment, compact: isLandscape)
            .frame(maxWidth: .infinity, alignment: alignment)
            // Hidden rather than removed, so the layout does not move when the title appears.
            .opacity(isTitleRevealed ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: isTitleRevealed)
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
    private var actionRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
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
        GlassEffectContainer(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                saveAction
                watchedAction
                if let trailer = model.trailerURL { trailerAction(trailer) }
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

    /// Opens the trailer with the app's shared web link handler.
    private func trailerAction(_ url: URL) -> some View {
        CircleActionButton(title: "Trailer", systemImage: "play.rectangle") {
            openURL(url)
        }
        .accessibilityIdentifier("detail.trailerButton")
    }

    @ViewBuilder
    private var synopsis: some View {
        if let description = model.detail.preview.description, !description.isEmpty {
            // Folded when it runs past three lines; one that fits has nothing to fold and no button.
            let folds = isDescriptionExpanded || isDescriptionTruncated
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                TruncatingText(text: Text(description), lineLimit: 3, isExpanded: isDescriptionExpanded, isTruncated: $isDescriptionTruncated)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    // A double tap folds or opens the synopsis too, as it does a review.
                    .onTapGesture(count: 2) {
                        if folds { toggleDescription() }
                    }
                if folds {
                    Button(isDescriptionExpanded ? "Less" : "More", action: toggleDescription)
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
        }
    }

    private func toggleDescription() {
        withAnimation(.easeInOut(duration: 0.25)) { isDescriptionExpanded.toggle() }
    }

    // MARK: - Series

    /// The season chips and the episodes of the selected season, each a row with its still, progress and watched mark.
    private func episodesSection(pageWidth: CGFloat) -> some View {
        let isWide = model.matchesEpisodeWidthToText
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
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: metrics.cardSpacing) {
                    ForEach(model.episodes) { episode in
                        episodeRow(episode, width: width, overviewHeight: isWide ? tallestOverview : nil)
                            .id(episode.id).reportsShelfEdge(id: episode.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, contentMargin, for: .scrollContent)
            .softSnappingScroll()
            .scrollClipDisabled()
            .animation(.snappy, value: model.matchesEpisodeWidthToText)
        }
        .background { if isWide { overviewRuler(width: width) } }
        .padding(.top, sectionSpacing)
        // IMDb's per-episode scores come from OMDb, a season at a time as the viewer picks one (and again if the key changes).
        .task(id: "\(model.selectedSeason.map(String.init) ?? "-"):\(model.reviewServicesRevision):\(model.isLoading)") {
            await model.loadEpisodeScores(season: model.selectedSeason)
        }
    }

    /// Every overview of the season at the full card width, unseen. Full-width cards show the whole overview, and a lazy row takes
    /// its height from its first card, so the tallest overview sets one height for all of them.
    private func overviewRuler(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            ForEach(model.episodes) { episode in
                Text(episode.overview ?? "")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: width)
        .hidden()
        .accessibilityHidden(true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tallestOverview = $0 }
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
            HStack(spacing: 6) {
                Text(model.selectedSeason == 0 ? "Specials" : "Season \(model.selectedSeason ?? 1)").font(Theme.Typography.shelfTitle)
                Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.glass)
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
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .titleTapHaptic()
        .accessibilityLabel("Episode width")
        .accessibilityValue(isWide ? "Full width" : "Fixed width")
        .accessibilityIdentifier("detail.episodeWidthToggle")
    }

    /// The text above the episodes runs from one page margin to the other. With the toggle on, each card is that wide, so the cards
    /// line up with it; otherwise they keep their fixed width.
    private func episodeWidth(pageWidth: CGFloat) -> CGFloat {
        model.matchesEpisodeWidthToText ? pageWidth - contentMargin * 2 : metrics.episodeWidth
    }

    private func episodeRow(_ video: Video, width: CGFloat, overviewHeight: CGFloat?) -> some View {
        NavigationLink(value: model.request(for: video)) {
            EpisodeRow(video: video, fraction: model.progressFraction(for: video), watched: model.isWatched(video),
                       artwork: model.backdropURL, score: model.score(for: video), width: width, overviewHeight: overviewHeight)
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
                RatingButtonsRow(item: model.detail.preview)
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
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.small)
                        .padding(.leading, Theme.Spacing.s)
                        .accessibilityLabel("Sort TMDb reviews")
                        .accessibilityValue(reviewSort.rawValue)
                        .accessibilityIdentifier("detail.reviews.sort")
                    }
                    .padding(.horizontal, contentMargin)
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
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
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: metrics.cardSpacing) {
                            ForEach(people) { PersonCardLink(person: $0).reportsShelfEdge(id: $0.id) }
                        }
                        .scrollTargetLayout()
                    }
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
                    ScrollView(.horizontal, showsIndicators: false) {
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
            ScrollView(.horizontal, showsIndicators: false) {
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

/// One TMDb review. Folded, every card is the same height: the text keeps six lines whether or not it fills them, and the button
/// keeps its place whether or not it shows. It shows only when the review runs past those lines.
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
                TruncatingText(text: Text(LocalizedStringKey(review.content)), lineLimit: 6, reservesSpace: true,
                               isExpanded: isExpanded, isTruncated: $isTruncated)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if folds { onToggle() }
            }
            Button(isExpanded ? "Show less" : "Show more", action: onToggle)
                .buttonStyle(.glass)
                .controlSize(.small)
                .opacity(folds ? 1 : 0)
                .allowsHitTesting(folds)
                .accessibilityHidden(!folds)
                .accessibilityIdentifier("detail.review.\(review.id).toggle")
        }
        .padding(16)
        .cardSurface()
    }
}

/// The logo, or the name when there is no logo or it failed to load. While a logo loads, the name is not drawn, so it never flashes
/// before the logo, and the logo's full height is kept, so the text below does not move when it arrives. The logo comes through
/// `ImagePipeline` because `ArtworkImage` only fills its frame.
private struct TitleArt: View {
    let name: String
    let logo: URL?
    let alignment: Alignment
    let compact: Bool
    @State private var image: UIImage?
    @State private var failed = false

    init(name: String, logo: URL?, alignment: Alignment, compact: Bool = false) {
        self.name = name
        self.logo = logo
        self.alignment = alignment
        self.compact = compact
        _image = State(initialValue: logo.flatMap { ImagePipeline.shared.cachedImage(for: $0, maxPixelSize: 800) })
    }

    /// The tallest a logo can be on this page.
    private var logoHeight: CGFloat { compact ? 56 : 150 }
    /// A title with a logo URL keeps the logo's space until the logo arrives or fails.
    private var reservesLogoHeight: Bool { logo != nil && !failed }

    var body: some View {
        Group {
            if let image {
                LogoLayout(imageSize: image.size, maxWidth: compact ? 220 : .infinity, maxHeight: logoHeight) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
                .transition(.opacity)
            } else {
                Text(name)
                    .font(compact ? .title2.bold() : .largeTitle.bold())
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .foregroundStyle(.white)
                    .lineLimit(compact ? 2 : 3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(logo == nil || failed ? 1 : 0)
            }
        }
        // Bottom-aligned, so a logo shorter than the reserved space sits where it did before, just above the controls.
        .frame(minHeight: reservesLogoHeight ? logoHeight : nil, alignment: Alignment(horizontal: alignment.horizontal, vertical: .bottom))
        .task(id: logo) {
            failed = false
            guard let logo else {
                image = nil
                return
            }
            let loaded = try? await ImagePipeline.shared.image(for: logo, maxPixelSize: 800, priority: .high)
            guard !Task.isCancelled else { return }
            guard let loaded else {
                failed = true
                return
            }
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
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
    /// Set for a full-width card: the whole overview shows, in a box this tall (the season's longest), so the cards share a height.
    var overviewHeight: CGFloat?

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
                if let overviewHeight {
                    Text(video.overview ?? "")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: overviewHeight, alignment: .top)
                } else if let overview = video.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
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
