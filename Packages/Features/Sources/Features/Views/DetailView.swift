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
    @Environment(\.openURL) private var openURL
    @Environment(\.layoutMetrics) private var metrics
    @Environment(TitleActions.self) private var titleActions

    init(preview: MetaPreview, services: AppServices) {
        _model = State(initialValue: DetailViewModel(preview: preview, services: services))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                info
                    .frame(maxWidth: .infinity, alignment: metrics.isRegular ? .leading : .center)
                    .padding(.horizontal, metrics.pageMargin)
                if model.isSeries {
                    episodesSection
                }
                credits
                    .padding(.horizontal, metrics.pageMargin)
                    .padding(.top, Theme.Spacing.xxl)
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .screenBackground()
        // The scroll view runs under the navigation bar, so the backdrop runs under it too. A soft edge fades the bar's blur
        // into the artwork instead of stopping at a hard line.
        .ignoresSafeArea(.container, edges: .top)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(model.detail.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onAppear { Task { await model.refreshUserState() } }
        .accessibilityIdentifier("detail.scroll")
    }

    // MARK: - Header

    /// The backdrop runs under the navigation bar. The logo, or the name, sits low on it, over a fade into the page.
    private var header: some View {
        BackdropLayout(isRegular: metrics.isRegular) {
            ZStack(alignment: metrics.isRegular ? .bottomLeading : .bottom) {
                ArtworkImage(url: model.backdropURL, maxPixelSize: metrics.isRegular ? 1800 : 1200)
                BottomFade(length: 0.65)
                TitleArt(name: model.detail.name, logo: model.logoURL, alignment: metrics.isRegular ? .leading : .center)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.detail.name)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("detail.title")
                    .padding(.horizontal, metrics.pageMargin)
                    .padding(.bottom, Theme.Spacing.l)
            }
            .clipped()
        }
    }

    // MARK: - Under the header

    /// The part inside the screen margins: from the metadata line down to the synopsis.
    private var info: some View {
        VStack(alignment: metrics.isRegular ? .leading : .center, spacing: Theme.Spacing.l) {
            MetaLine([model.detail.preview.genres.first] + model.metaParts.map { Optional($0) })
                .multilineTextAlignment(metrics.isRegular ? .leading : .center)
            actionRow
            synopsis
                .frame(maxWidth: metrics.readableWidth, alignment: .leading)
            ReviewSitesRow(item: model.detail.preview)
            if model.isFallback && !model.isLoading {
                Label("Only basic details are available for this title.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("detail.fallbackNote")
            }
        }
        .padding(.top, Theme.Spacing.s)
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

    /// Play and the circle actions on one line, tops aligned: Play is as tall as the circles, and takes the width they leave.
    private var actionRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            primaryAction
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: metrics.isRegular ? 280 : .infinity)
            GlassEffectContainer(spacing: Theme.Spacing.s) {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    saveAction
                    if !model.isSeries { watchedAction }
                    if let trailer = model.trailerURL { trailerAction(trailer) }
                }
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity)
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
        .sensoryFeedback(.success, trigger: model.isInLibrary)
    }

    private var watchedAction: some View {
        let request = model.movieRequest
        let watched = model.isWatched(request)
        return CircleActionButton(title: "Watched", systemImage: "eye", isOn: watched) {
            Task {
                await model.setWatched(!watched, for: request)
                await titleActions.refresh()
            }
        }
        .accessibilityValue(watched ? "Watched" : "Not watched")
        .accessibilityIdentifier("detail.watchedButton")
        .sensoryFeedback(.success, trigger: watched)
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
                    ForEach(model.episodes) { episodeRow($0) }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, metrics.pageMargin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
        .padding(.top, Theme.Spacing.xxl)
    }

    private func episodeRow(_ video: Video) -> some View {
        NavigationLink(value: model.request(for: video)) {
            EpisodeRow(video: video, fraction: model.progressFraction(for: video), watched: model.isWatched(video),
                       artwork: model.backdropURL)
        }
        .buttonStyle(PressableCardStyle())
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
            if !model.detail.cast.isEmpty {
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

    @ViewBuilder
    private func information(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(title) { Text(value).foregroundStyle(.primary) }
                .font(.footnote)
        }
    }
}

// MARK: - Pieces

/// Keeps artwork tall on a phone and wide in a Mac window without measuring every child.
private struct BackdropLayout: Layout {
    let isRegular: Bool
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return CGSize(width: width, height: min(width * (isRegular ? 0.56 : 1.25), isRegular ? 600 : 480))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }
}

/// The logo, or the name while the logo loads and whenever there is none. The logo comes through `ImagePipeline` because
/// `ArtworkImage` only fills its frame.
private struct TitleArt: View {
    let name: String
    let logo: URL?
    let alignment: Alignment
    @State private var image: UIImage?

    init(name: String, logo: URL?, alignment: Alignment) {
        self.name = name
        self.logo = logo
        self.alignment = alignment
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280, maxHeight: 90, alignment: alignment)
                    .transition(.opacity)
            } else {
                Text(name)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
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
                MetaLine([AirDate.text(video.released), ratingText])
                if let overview = video.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
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
            .overlay(alignment: .bottom) { progressBar }
            .overlay(alignment: .topTrailing) {
                if watched { checkmark }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }

    /// Only for an episode that is partly watched: a thin line along the bottom edge of the still.
    @ViewBuilder
    private var progressBar: some View {
        if let fraction, !watched {
            Rectangle()
                .fill(.white.opacity(0.25))
                .frame(width: metrics.episodeWidth, height: 3)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.white)
                        .frame(width: metrics.episodeWidth * min(max(fraction, 0), 1), height: 3)
                }
        }
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

    private var ratingText: String? {
        guard let rating = video.rating, rating > 0 else { return nil }
        return "★ \(rating.formatted(.number.precision(.fractionLength(1))))"
    }
}

/// Air dates as addons send them (ISO 8601, usually with fractional seconds), written the way the locale writes a date.
private enum AirDate {
    static func text(_ released: String?) -> String? {
        guard let released, !released.isEmpty else { return nil }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        guard let date = (try? fractional.parse(released)) ?? (try? Date.ISO8601FormatStyle().parse(released)) else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
#endif
