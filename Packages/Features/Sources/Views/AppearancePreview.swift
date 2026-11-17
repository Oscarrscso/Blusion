#if canImport(UIKit)
import SwiftUI
import StremioKit

/// A preview on one of Appearance's pages: the app's own views (`AppearanceSample`) with sample titles, on the chosen background, in the
/// look being set, a slider's value included while it is dragged. The samples are the real views, not copies, so a preview follows any
/// change made to them. A page shows only the views its choices change, and none where a choice reads plainly from its name.
struct AppearancePreview: View {
    let appearance: AppearancePreferences
    let samples: [AppearanceSample]
    /// Hover's preview: one piece of each sample is drawn lit, beside unlit ones.
    var lightsOnePiece = false
    var contentPadding: CGFloat = 0
    var verticalPadding: CGFloat = Theme.Spacing.l
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.surface * metrics.customised(by: appearance).cornerScale(for: .settingsRows),
                                     style: .continuous)
        SampleStack(samples: samples)
            .padding(contentPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.previewLightsOnePiece, lightsOnePiece)
            .background(appearance.pageBackground)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Theme.separator, lineWidth: 1).allowsHitTesting(false) }
            // The root's animation speed already reaches the preview; applying it again would square it.
            .appearanceLook(appearance, motion: false)
            // A picture of the app, not a working part of it; only Hover's answers the pointer.
            .allowsHitTesting(lightsOnePiece)
            .accessibilityHidden(true)
    }
}

extension AppearanceControls {
    /// The look being set, drawn on `samples` with an explicit vertical padding for compact previews.
    func preview(_ samples: [AppearanceSample], lightsOnePiece: Bool = false, contentPadding: CGFloat = 0,
                 verticalPadding: CGFloat) -> some View {
        AppearancePreview(appearance: current, samples: samples, lightsOnePiece: lightsOnePiece,
                          contentPadding: contentPadding, verticalPadding: verticalPadding)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}

/// The samples one under another, a shelf's spacing apart with Appearance's shelf divider between them, as Home lays out its shelves.
/// Inside the preview's look, so the spacing is the one being set.
private struct SampleStack: View {
    let samples: [AppearanceSample]
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.shelfSpacing) {
            ForEach(samples.indices, id: \.self) { index in
                samples[index].modifier(ShelfDivider(metrics: metrics, isShown: index < samples.count - 1))
            }
        }
    }
}

/// One of the app's views as Appearance previews it.
enum AppearanceSample: View {
    /// A shelf of poster cards under its heading (`MediaRow`, `MediaCard`).
    case posters
    /// Continue Watching's cards, with their progress (`ProgressCard`).
    case continueWatching
    /// The title page's Play row (`TitleActionRow`).
    case playRow
    /// A heading over a title's synopsis (`SectionHeader`, `DetailSynopsis`).
    case text
    /// A shelf heading on its own (`SectionHeader`).
    case heading
    /// A title's synopsis on its own (`DetailSynopsis`).
    case synopsis
    /// The browse filter bar (`BrowseFilterBar`).
    case filters
    /// A review (`ReviewCard`).
    case review
    /// A stream's card (`StreamRow`).
    case stream
    /// The player's menu bar in its glass (`PlayerMenuBar`).
    case playerBar
    /// A watched episode beside one not yet started (`EpisodeRow`), as Hide spoilers shows them.
    case episodes

    /// What one part of Corners rounds. Nil for Settings Rows, which the page is itself made of.
    init?(corners group: AppearancePreferences.CornerGroup) {
        switch group {
        case .artwork: self = .posters
        case .playButton, .actionButtons: self = .playRow
        case .filters: self = .filters
        case .reviews: self = .review
        case .panels: self = .stream
        case .playerControls: self = .playerBar
        case .settingsRows: return nil
        }
    }

    var body: some View {
        switch self {
        case .posters: PosterShelfSample()
        case .continueWatching: ContinueShelfSample()
        case .playRow: PlayRowSample()
        case .text: TextSample()
        case .heading: HeadingSample()
        case .synopsis: SynopsisSample()
        case .filters: FilterBarSample()
        case .review: ReviewSample()
        case .stream: StreamSample()
        case .playerBar: PlayerBarSample()
        case .episodes: EpisodesSample()
        }
    }
}

extension EnvironmentValues {
    /// Set by Hover's preview (`AppearancePreview.lightsOnePiece`): each sample draws one piece lit (`showsHover`).
    @Entry var previewLightsOnePiece = false
}

// MARK: - Samples

private struct PosterShelfSample: View {
    @Environment(\.previewLightsOnePiece) private var lightsOne

    var body: some View {
        MediaRow("Top Picks") {
            ForEach(Samples.items.indices, id: \.self) { index in
                Button {} label: { MediaCard(item: Samples.items[index]) }
                    .buttonStyle(PressableCardStyle.poster)
                    .environment(\.showsHover, lightsOne && index == 1)
            }
        }
    }
}

private struct ContinueShelfSample: View {
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        MediaRow("Continue Watching", aspect: .wide, cardWidth: metrics.continueCardWidth) {
            ForEach(Samples.items.indices, id: \.self) { index in
                let item = Samples.items[index]
                ProgressCard(title: item.name, artwork: item.background, logo: item.logo, fraction: Samples.progress[index], duration: 2580)
            }
        }
    }
}

private struct PlayRowSample: View {
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.previewLightsOnePiece) private var lightsOne

    var body: some View {
        TitleActionRow {
            Button {} label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "play.fill")
                    Text("Play")
                }
            }
            .buttonStyle(.titlePlay(colour: Samples.playColour))
        } circles: {
            NativeDownloadButton(manager: nil, item: nil, glass: CircleActionButton.glass,
                                 progressColour: Samples.playColour ?? .accentColor) {}
            CircleActionButton(title: "Save", systemImage: "bookmark", onColour: Samples.playColour, exactSize: true) {}
                .environment(\.showsHover, lightsOne)
            CircleActionButton(title: "Watched", systemImage: "eye", isOn: true, onColour: Samples.playColour, exactSize: true) {}
            CircleActionButton(title: "Trailer", systemImage: "play.rectangle", onColour: Samples.playColour, exactSize: true) {}
        }
        .padding(.horizontal, metrics.pageMargin)
    }
}

private struct TextSample: View {
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            HeadingSample()
            SynopsisSample()
        }
    }
}

private struct HeadingSample: View {
    var body: some View {
        SectionHeader("Top Picks")
            .padding(.horizontal, layoutMetrics.pageMargin)
    }

    @Environment(\.layoutMetrics) private var layoutMetrics
}

private struct SynopsisSample: View {
    var body: some View {
        DetailSynopsis(description: Samples.synopsis, isExpanded: .constant(false), isTruncated: .constant(false))
            .padding(.horizontal, layoutMetrics.pageMargin)
    }

    @Environment(\.layoutMetrics) private var layoutMetrics
}

private struct FilterBarSample: View {
    @Environment(\.previewLightsOnePiece) private var lightsOne

    var body: some View {
        BrowseFilterBar(kinds: .init(titles: ["All", "Movies", "Series"], selection: .constant(1),
                                     identifier: "settings.appearance.preview.type"),
                        chips: [], identifier: "settings.appearance.preview.filters", clearAll: {}) {
            Button {} label: {
                FilterMenuLabel("Sort", systemImage: "arrow.up.arrow.down", minHeight: BrowseFilterBar<EmptyView>.menuHeight)
            }
            Button {} label: {
                FilterMenuLabel("Genre", systemImage: "tag", minHeight: BrowseFilterBar<EmptyView>.menuHeight)
            }
            .environment(\.showsHover, lightsOne)
        }
        .buttonStyle(.plain)
    }
}

private struct ReviewSample: View {
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        if let review = Samples.review {
            ReviewCard(review: review, isExpanded: false, foldedWidth: metrics.reviewCardWidth, expandedWidth: metrics.reviewCardWidth,
                       onToggle: {})
                .padding(.horizontal, metrics.pageMargin)
        }
    }
}

private struct StreamSample: View {
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        StreamRow(item: Samples.stream, isBest: true, isRemux: Samples.stream.quality.isRemux)
            .padding(.horizontal, metrics.pageMargin)
    }
}

private struct PlayerBarSample: View {
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let corners = metrics.cornerScale(for: .playerControls)
        PlayerMenuBar(tabs: [.subtitles, .audio, .speed, .picture, .info], selection: .constant(nil), cornerScale: corners)
            .fixedSize()
            .playerMenuBarSurface(cornerScale: corners)
            .frame(maxWidth: .infinity)
    }
}

private struct EpisodesSample: View {
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        MediaRow("Episodes", hideTitle: true) {
            ForEach(Samples.episodes.indices, id: \.self) { index in
                EpisodeRow(video: Samples.episodes[index], fraction: nil, watched: index == 0, artwork: Samples.items[0].background,
                           score: nil, runtimeMinutes: 49, width: metrics.episodeWidth)
            }
        }
    }
}

/// Fixed titles keep every preview showing the same artwork.
@MainActor
private enum Samples {
    static let items: [MetaPreview] = [
        ("tt0816692", "Interstellar"),
        ("tt0133093", "The Matrix"),
        ("tt0111161", "The Shawshank Redemption"),
        ("tt0120737", "The Lord of the Rings"),
    ].map { id, name in
        MetaPreview(id: id, type: "movie", name: name,
                    poster: MetahubArtwork.poster(imdbID: id),
                    background: MetahubArtwork.background(imdbID: id),
                    logo: MetahubArtwork.logo(imdbID: id))
    }
    static let progress = [0.62, 0.25, 0.85, 0.4]
    /// A title's Play colour, as `PlayColourStore` reads one from its artwork.
    static let playColour = Theme.playControlColour(hex: "C47A3A")
    static let synopsis = "A team of explorers travels beyond the solar system to find a future for humanity. Their journey takes them "
        + "through a wormhole and across worlds where time passes differently."
    static let review = try? JSONDecoder().decode(TMDbReview.self, from: Data("""
        {"id":"appearance-preview","author":"Alex",
        "content":"A beautiful film with a memorable story and an incredible soundtrack. \
        The pacing never lets up, and the ending stays with you long after the credits roll.",
        "author_details":{"rating":8}}
        """.utf8))
    static let stream: RankedStream = {
        let url = URL(string: "https://example.com/interstellar.mkv")!
        let stream = AddonStream(name: "Torrentio\n4K", description: "Interstellar.2014.2160p.UHD.BluRay.REMUX.HDR.HEVC.Atmos\n💾 62.3 GB",
                                 source: .direct(url))
        return RankedStream(id: "appearance-preview", stream: stream,
                            addon: AddonSummary(id: UUID(), name: "Torrentio", host: "torrentio.example"),
                            quality: StreamQuality.parse(stream), route: .native(url))
    }()
    static let episodes = [
        Video(id: "appearance-preview:1:3", title: "Low Tide", season: 1, episode: 3, released: "2024-01-17",
              thumbnail: MetahubArtwork.background(imdbID: "tt0133093"),
              overview: "The keeper logs the signal for the third night running."),
        Video(id: "appearance-preview:1:4", title: "The Boat That Answered", season: 1, episode: 4, released: "2024-01-24",
              thumbnail: MetahubArtwork.background(imdbID: "tt0120737"),
              overview: "Mara reaches the boat and finds who has been answering her."),
    ]
}
#endif
