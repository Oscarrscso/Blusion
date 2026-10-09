#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// The title page, drawn the way Apple's TV app draws one: artwork under the navigation bar with the logo low on it, one quiet
/// metadata line, the main action, round secondary actions, the synopsis, then for a series its seasons and episodes, and last
/// the credits.
struct DetailView: View {
    @State private var model: DetailViewModel
    @State private var isDescriptionExpanded = false
    @State private var isConfirmingUnmarkShow = false
    /// How far the page has been pulled down past its top. The portrait hero stretches by this much, like a refresh.
    @State private var scrollPull: CGFloat = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isLandscape) private var isLandscape
    @Environment(TitleActions.self) private var titleActions

    init(preview: MetaPreview, services: AppServices, artwork: TMDbArtwork? = nil) {
        _model = State(initialValue: DetailViewModel(preview: preview, services: services, artwork: artwork))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    feature(in: geometry.size)
                    if model.isSeries { episodesSection.reportsSectionEdge(id: "episodes") }
                    credits
                        .padding(.horizontal, metrics.pageMargin)
                        .padding(.top, Theme.Spacing.l)
                        .reportsSectionEdge(id: "credits")
                    if !model.relatedTitles.isEmpty {
                        related
                            .padding(.horizontal, metrics.pageMargin)
                            .padding(.top, Theme.Spacing.xl)
                            .reportsSectionEdge(id: "related")
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .verticalScrollFeel()
            .onScrollGeometryChange(for: CGFloat.self) { max(0, -($0.contentOffset.y + $0.contentInsets.top)) } action: { _, value in
                scrollPull = value
            }
        }
        .screenBackground()
        .ignoresSafeArea(.container, edges: isLandscape ? [] : .top)
        .scrollEdgeEffectHidden(true, for: .top)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onAppear { Task { await model.refreshUserState() } }
        .accessibilityIdentifier("detail.scroll")
    }

    // MARK: - Header

    @ViewBuilder
    private func feature(in size: CGSize) -> some View {
        if isLandscape {
            let artworkWidth = max(120, (size.width - metrics.pageMargin * 2 - Theme.Spacing.xl) * 0.48)
            HStack(alignment: .center, spacing: Theme.Spacing.xl) {
                ArtworkImage(url: model.backdropURL, maxPixelSize: 4096, contentMode: .fit,
                             placeholderURL: model.preview.poster ?? MetahubArtwork.poster(imdbID: model.preview.id), placeholderBlur: 1)
                    .frame(width: artworkWidth, height: artworkWidth * 9 / 16)
                    .overlay(alignment: .bottomTrailing) { PosterRatingsOverlay(item: model.preview, isLandscape: true) }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.surface, style: .continuous))
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    titleArt(alignment: .leading)
                    controls
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, metrics.pageMargin)
            .padding(.vertical, Theme.Spacing.m)
            synopsis
                .padding(.horizontal, metrics.pageMargin)
                .padding(.top, Theme.Spacing.s)
        } else {
            let height = min(size.width * 1.5, metrics.heroMaxHeight)
            // The layout keeps the hero's height. The artwork is an overlay that stretches downward only when the page is pulled past its
            // top: its top stays at the screen's top and its bottom follows the finger. Scrolling leaves it where it is.
            Color.clear
                .frame(width: size.width, height: height)
                .overlay(alignment: .top) {
                    ZStack(alignment: .bottom) {
                        ArtworkImage(url: model.portraitArtworkURL, maxPixelSize: 4096, contentMode: .fill,
                                     placeholderURL: model.preview.poster ?? MetahubArtwork.poster(imdbID: model.preview.id), placeholderBlur: 1)
                        BottomFade(length: 0.42)
                    }
                    .frame(width: size.width, height: height + scrollPull)
                    .clipped()
                    .offset(y: -scrollPull)
                }
                .overlay(alignment: .bottom) {
                    titleArt(alignment: .center)
                        .padding(.horizontal, metrics.pageMargin)
                        .padding(.bottom, Theme.Spacing.l)
                }
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                controls
                synopsis
            }
            .padding(.horizontal, metrics.pageMargin)
            .padding(.top, Theme.Spacing.s)
        }
    }

    private func titleArt(alignment: Alignment) -> some View {
        TitleArt(name: model.detail.name, logo: model.logoURL, alignment: alignment, compact: isLandscape)
            .frame(maxWidth: .infinity, alignment: alignment)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.detail.name)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("detail.title")
    }

    private var controls: some View {
        VStack(alignment: isLandscape ? .leading : .center, spacing: Theme.Spacing.m) {
            RatingButtonsRow(item: model.detail.preview, alignment: isLandscape ? .leading : .center)
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

    /// Opens the trailer on YouTube, in the YouTube app when it is installed.
    private func trailerAction(_ url: URL) -> some View {
        CircleActionButton(title: "Trailer", systemImage: "play.rectangle") {
            openURL(url)
        }
        .accessibilityIdentifier("detail.trailerButton")
    }

    @ViewBuilder
    private var synopsis: some View {
        if let description = model.detail.preview.description, !description.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(isDescriptionExpanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                // A rough test: four lines of body text hold about 150 characters at phone width, so anything longer may be cut off.
                if description.count > 120 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { isDescriptionExpanded.toggle() }
                    } label: {
                        Text(isDescriptionExpanded ? "Less" : "More")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Series

    /// The season chips and the episodes of the selected season, each a row with its still, progress and watched mark.
    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
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
            .buttonStyle(.plain)
            .padding(.horizontal, metrics.pageMargin)
            .accessibilityIdentifier("detail.seasonPicker")
            if model.isLoading && model.episodes.isEmpty {
                SkeletonRow(aspect: .wide)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: metrics.cardSpacing) {
                    ForEach(model.episodes) { episode in
                        episodeRow(episode).id(episode.id).reportsShelfEdge(id: episode.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, metrics.pageMargin, for: .scrollContent)
            .softSnappingScroll()
            .scrollClipDisabled()
        }
        .padding(.top, Theme.Spacing.xxl)
        // IMDb's per-episode scores come from OMDb, a season at a time as the viewer picks one (and again if the key changes).
        .task(id: "\(model.selectedSeason.map(String.init) ?? "-"):\(model.reviewServicesRevision):\(model.isLoading)") {
            await model.loadEpisodeScores(season: model.selectedSeason)
        }
    }

    private func episodeRow(_ video: Video) -> some View {
        NavigationLink(value: model.request(for: video)) {
            EpisodeRow(video: video, fraction: model.progressFraction(for: video), watched: model.isWatched(video),
                       artwork: model.backdropURL, score: model.score(for: video))
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

    private var credits: some View {
        VStack(alignment: .leading, spacing: metrics.shelfSpacing) {
            if !model.reviews.isEmpty {
                VStack(alignment: .leading, spacing: metrics.headerSpacing) {
                    SectionHeader("TMDb Reviews")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: metrics.cardSpacing) {
                            ForEach(model.reviews) { review in
                                ReviewCard(review: review)
                                    .frame(width: metrics.isRegular ? 340 : 280)
                            }
                        }
                    }
                }
            }
            if let people = model.castAndCrew, !people.isEmpty {
                // TMDb's cast and key crew, with photos. Each photo loads as its card scrolls on, behind the rest of the page.
                SectionHeader("Cast & Crew")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: metrics.cardSpacing) {
                        ForEach(people) { PersonCardLink(person: $0).reportsShelfEdge(id: $0.id) }
                    }
                    .scrollTargetLayout()
                }
                .softSnappingScroll(loosened: true)
                .accessibilityIdentifier("detail.castCarousel")
            } else if !model.detail.cast.isEmpty {
                // Without TMDb (no read token, or it did not answer) the addon's names still show, as initials, and open nothing.
                SectionHeader("Cast & Crew")
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
                        }
                    }
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
        }
    }

    /// Titles TMDb recommends for this one, at the bottom of the page. Each opens its own page.
    private var related: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            SectionHeader("More Like This")
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
            .scrollClipDisabled()
            .softSnappingScroll(loosened: true)
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

private struct ReviewCard: View {
    let review: TMDbReview
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text(review.author).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                if let rating = review.rating {
                    Label(rating.formatted(.number.precision(.fractionLength(0...1))), systemImage: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(LocalizedStringKey(review.content))
                .font(.subheadline)
                .lineLimit(isExpanded ? nil : 6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                isExpanded.toggle()
            } label: {
                Text(isExpanded ? "Show less" : "Show more")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("detail.review.\(review.id).toggle")
        }
        .padding(16)
        .cardSurface()
    }
}

/// The logo, or the name while the logo loads and whenever there is none. The logo comes through `ImagePipeline` because
/// `ArtworkImage` only fills its frame.
private struct TitleArt: View {
    let name: String
    let logo: URL?
    let alignment: Alignment
    let compact: Bool
    @State private var image: UIImage?

    init(name: String, logo: URL?, alignment: Alignment, compact: Bool = false) {
        self.name = name
        self.logo = logo
        self.alignment = alignment
        self.compact = compact
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: compact ? 220 : 280, maxHeight: compact ? 56 : 80, alignment: alignment)
                    .transition(.opacity)
            } else {
                Text(name)
                    .font(compact ? .title2.bold() : .largeTitle.bold())
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .foregroundStyle(.white)
                    .lineLimit(compact ? 2 : 3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: logo) {
            guard let logo else {
                image = nil
                return
            }
            let loaded = try? await ImagePipeline.shared.image(for: logo, maxPixelSize: 600)
            guard !Task.isCancelled, let loaded else { return }
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}

/// One episode: its still with the progress line or watched mark over it, the numbered title, the air date and rating, and the
/// overview in a few lines.
private struct EpisodeRow: View {
    let video: Video
    let fraction: Double?
    let watched: Bool
    let artwork: URL?
    let score: DetailViewModel.EpisodeScore?
    @Environment(\.layoutMetrics) private var metrics

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
                    Text(overview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                dateAndScore
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: metrics.episodeWidth, alignment: .leading)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
    }

    /// The episode's own still, or the series' backdrop when the addon sent none.
    private var still: some View {
        ArtworkImage(url: video.thumbnail ?? artwork, maxPixelSize: metrics.episodeWidth * 3)
            .frame(width: metrics.episodeWidth, height: metrics.episodeWidth / CardAspect.wide.ratio)
            .overlay {
                if !watched, let fraction {
                    PlaybackProgressOverlay(fraction: fraction, width: metrics.episodeWidth)
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
