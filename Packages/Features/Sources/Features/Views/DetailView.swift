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

    init(preview: MetaPreview, services: AppServices) {
        _model = State(initialValue: DetailViewModel(preview: preview, services: services))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                info
                    .padding(.horizontal, Theme.screenPadding)
                if model.isSeries {
                    episodesSection
                }
                credits
                    .padding(.horizontal, Theme.screenPadding)
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
        BackdropLayout {
            ZStack(alignment: .bottomLeading) {
                ArtworkImage(url: model.backdropURL, maxPixelSize: 900)
                LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: Theme.background, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                TitleArt(name: model.detail.name, logo: model.logoURL)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.detail.name)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("detail.title")
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, Theme.Spacing.l)
            }
            .clipped()
        }
    }

    // MARK: - Under the header

    /// The part inside the screen margins: from the metadata line down to the synopsis.
    private var info: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            MetaLine(model.metaParts)
            genres
            primaryAction
            secondaryActions
            synopsis
            if model.isFallback && !model.isLoading {
                Label("Only basic details are available for this title.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("detail.fallbackNote")
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    @ViewBuilder
    private var genres: some View {
        let names = model.detail.preview.genres
        if !names.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(names, id: \.self) { Badge($0) }
                }
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

    private var secondaryActions: some View {
        GlassEffectContainer(spacing: Theme.Spacing.l) {
            HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                saveAction
                if !model.isSeries { watchedAction }
                if let trailer = model.trailerURL { trailerAction(trailer) }
            }
        }
    }

    private var saveAction: some View {
        RoundAction(title: model.isInLibrary ? "Saved" : "Save",
                    systemImage: model.isInLibrary ? "bookmark.fill" : "bookmark",
                    value: model.isInLibrary ? "Saved" : "Not saved",
                    identifier: "detail.libraryButton") {
            Task { await model.toggleLibrary() }
        }
        .sensoryFeedback(.success, trigger: model.isInLibrary)
    }

    private var watchedAction: some View {
        let request = model.movieRequest
        let watched = model.isWatched(request)
        return RoundAction(title: "Watched",
                           systemImage: watched ? "checkmark.circle.fill" : "checkmark.circle",
                           value: watched ? "Watched" : "Not watched",
                           identifier: "detail.watchedButton") {
            Task { await model.setWatched(!watched, for: request) }
        }
        .sensoryFeedback(.success, trigger: watched)
    }

    /// Opens the trailer on YouTube, in the YouTube app when it is installed.
    private func trailerAction(_ url: URL) -> some View {
        RoundAction(title: "Trailer", systemImage: "play.rectangle", value: nil, identifier: "detail.trailerButton") {
            openURL(url)
        }
    }

    @ViewBuilder
    private var synopsis: some View {
        if let description = model.detail.preview.description, !description.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(isDescriptionExpanded ? nil : 4)
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
            SectionHeader("Episodes")
                .padding(.horizontal, Theme.screenPadding)
            if model.seasons.count > 1 {
                ChipRow {
                    ForEach(model.seasons, id: \.self) { season in
                        GlassChip(season == 0 ? "Specials" : "Season \(season)", isSelected: model.selectedSeason == season) {
                            model.selectedSeason = season
                        }
                    }
                }
                .accessibilityIdentifier("detail.seasonPicker")
            }
            if model.isLoading && model.episodes.isEmpty {
                EpisodeSkeleton()
                    .padding(.horizontal, Theme.screenPadding)
            }
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                ForEach(model.episodes) { episodeRow($0) }
            }
            .padding(.horizontal, Theme.screenPadding)
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
                Task { await model.setWatched(!watched, for: model.request(for: video)) }
            }
        }
        .accessibilityIdentifier("detail.episode.\(video.id)")
    }

    // MARK: - Credits

    private var credits: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            credit("Cast", model.detail.cast)
            credit("Director", model.detail.director)
            credit("Writers", model.detail.writers)
        }
    }

    @ViewBuilder
    private func credit(_ title: LocalizedStringKey, _ names: [String]) -> some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(names.joined(separator: ", "))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Pieces

/// The backdrop's frame: the full width it is offered, and 1.25 times that as height, never more than 420 pt.
private struct BackdropLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return CGSize(width: width, height: min(width * 1.25, 420))
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
    @State private var image: UIImage?

    init(name: String, logo: URL?) {
        self.name = name
        self.logo = logo
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280, maxHeight: 90, alignment: .leading)
                    .transition(.opacity)
            } else {
                Text(name)
                    .font(.largeTitle.bold())
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

/// A round glass button with a symbol and its short name under it. VoiceOver reads the name and its value, never the symbol.
private struct RoundAction: View {
    let title: LocalizedStringKey
    let systemImage: String
    let value: String?
    let identifier: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text(title))
            .accessibilityValue(value ?? "")
            .accessibilityIdentifier(identifier)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

/// The size of an episode still: 16:9, at a width that leaves the text room beside it.
private enum EpisodeStill {
    static let width: CGFloat = 132
    static let height: CGFloat = 74
}

/// One episode: its still with the progress line or watched mark over it, the numbered title, the air date and rating, and the
/// overview in a few lines.
private struct EpisodeRow: View {
    let video: Video
    let fraction: Double?
    let watched: Bool
    let artwork: URL?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            still
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(numberedTitle)
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
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
    }

    /// The episode's own still, or the series' backdrop when the addon sent none.
    private var still: some View {
        ArtworkImage(url: video.thumbnail ?? artwork, maxPixelSize: 300)
            .frame(width: EpisodeStill.width, height: EpisodeStill.height)
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
                .frame(width: EpisodeStill.width, height: 3)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.brandGradient)
                        .frame(width: EpisodeStill.width * min(max(fraction, 0), 1), height: 3)
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

    private var numberedTitle: String {
        guard let episode = video.episode else { return video.title }
        return "\(episode). \(video.title)"
    }

    private var ratingText: String? {
        guard let rating = video.rating, rating > 0 else { return nil }
        return "★ \(rating.formatted(.number.precision(.fractionLength(1))))"
    }
}

/// Grey stand-ins for episode rows while the addon's episodes arrive. One shimmer sweeps all of them.
private struct EpisodeSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(Theme.surfaceStrong)
                        .frame(width: EpisodeStill.width, height: EpisodeStill.height)
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.surfaceStrong)
                            .frame(width: 150, height: 12)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.surfaceStrong)
                            .frame(width: 110, height: 9)
                    }
                }
            }
        }
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading episodes")
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
