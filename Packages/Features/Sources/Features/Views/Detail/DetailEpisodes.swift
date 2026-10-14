#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// A series' seasons and episodes: the season picker and the episode-width toggle, then the episodes of the selected season, each a row
/// with its still, progress and watched mark.
struct DetailEpisodes: View {
    let model: DetailViewModel
    let pageWidth: CGFloat
    let contentMargin: CGFloat
    /// True while an episode's menu is open, so the page can blur behind it. Cleared when this view leaves the screen.
    @Binding var isHoldingEpisode: Bool
    /// Shuffle and a tapped episode hand their episode to the page's stream flow, the one Play uses, saying which of them asked: the
    /// streams take the details' place once they are ready.
    let play: (StreamRequest, StreamTrigger) -> Void
    /// The request whose streams are loading, from Play, Shuffle or an episode. Shuffle and the episodes take no taps then, since a tap
    /// would call that lookup off or start a second one.
    var loadingRequest: StreamRequest?
    /// What asked for the loading streams. Only that control shows a spinner: Shuffle in place of its symbol, an episode on its card.
    var loadingTrigger: StreamTrigger?

    private var isLoadingStreams: Bool { loadingRequest != nil }
    @Environment(\.layoutMetrics) private var metrics
    @Environment(TitleActions.self) private var titleActions
    /// Handed on to an episode's menu preview, which is drawn outside the page and does not get the page's environment.
    @Environment(PosterRatingsStore.self) private var ratings: PosterRatingsStore?

    /// The height of the season picker and of the episode-width toggle, so the two sit level on one line.
    private static let secondaryControlHeight: CGFloat = 36
    /// The space inside an episode's menu preview, so the menu's rounded corners do not cut into the still or the text.
    private static let previewPadding: CGFloat = Theme.Spacing.m
    /// The corner radius of the panel the system draws an episode's menu preview in: 32 pt, measured on an iPhone on iOS 27. The system
    /// does not say what it is and does not let a preview set it. The preview's hairline uses it, so it follows the panel's edge.
    private static let previewPanelRadius: CGFloat = 32
    /// The still's corner radius in the preview: the panel's less the padding between them, so the two corners share a centre and the
    /// gap between the still and the panel is the same round the corner as along the sides. With the panel's own radius the gap grew
    /// at the corners, which read as slightly off.
    private static let previewStillRadius: CGFloat = previewPanelRadius - previewPadding

    var body: some View {
        let width = episodeWidth(pageWidth: pageWidth)
        return VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.m) {
                seasonMenu
                shuffleButton
                Spacer(minLength: 0)
                episodeWidthToggle
            }
            .padding(.horizontal, contentMargin)
            if model.isLoading && model.episodes.isEmpty {
                SkeletonRow(aspect: .wide)
            }
            ShelfScroll(margin: contentMargin, spacing: metrics.cardSpacing,
                        resetKey: "\(model.selectedSeason ?? -1)|\(model.matchesEpisodeWidthToText)|\(Int(width))") {
                ForEach(model.episodes) { episode in
                    episodeRow(episode, width: width)
                        .id(episode.id).reportsShelfEdge(id: episode.id)
                }
            }
            .animation(.snappy, value: model.matchesEpisodeWidthToText)
        }
        // A page that is left never stays blurred, even if its episode's menu was still open.
        .onDisappear { isHoldingEpisode = false }
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

    /// Shuffle, beside the season picker: a random episode that has aired, whose streams show as Play's do. While they load, a thin
    /// spinner takes the place of its symbol, at the same size. It is dimmed while there is nothing to pick, and takes no taps while any
    /// streams are loading. Only shown for a series, as this whole list is.
    private var shuffleButton: some View {
        let isShuffling = loadingTrigger == .shuffle
        return Button {
            if let request = model.shuffledRequest() { play(request, .shuffle) }
        } label: {
            Image(systemName: "shuffle")
                .font(.body.weight(.semibold))
                .opacity(isShuffling ? 0 : 1)
                .overlay {
                    if isShuffling {
                        Spinner()
                            .controlSize(.small)
                            .transition(.opacity)
                    }
                }
                .animation(.smooth(duration: 0.2), value: isShuffling)
                // The same grey as the trailer's symbol beside the title's other buttons.
                .foregroundStyle(.white.opacity(0.6))
        }
        .glassCircleButton(.regular)
        .frame(width: Self.secondaryControlHeight, height: Self.secondaryControlHeight)
        .disabled(!model.canShuffle)
        .opacity(model.canShuffle ? 1 : 0.4)
        .allowsHitTesting(!isLoadingStreams)
        .titleTapHaptic()
        .help("Shuffle")
        .accessibilityLabel("Shuffle")
        .accessibilityHint("Picks a random episode that has aired")
        .accessibilityIdentifier("detail.shuffleButton")
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
                .foregroundStyle(.white.opacity(0.6))
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
        let airsLater = !video.hasAired()
        let request = model.request(for: video)
        return Button {
            // As Shuffle does: the episode's streams load on this page, with a spinner on its card only, and replace the details once
            // ready. One lookup at a time, so a second tap does not call it off or open another.
            guard !isLoadingStreams else { return }
            play(request, .episode)
        } label: {
            episodeCard(video, width: width, airsLater: airsLater,
                        isLoadingStreams: loadingTrigger == .episode && loadingRequest?.id == request.id)
        }
        .buttonStyle(PressableCardStyle())
        .allowsHitTesting(!isLoadingStreams)
        // An episode that has not aired cannot be opened: its card shows the air date instead.
        .disabled(airsLater)
        .titleTapHaptic()
        .contextMenu {
            let watched = model.isWatched(video)
            Button(watched ? "Mark as not watched" : "Mark as watched", systemImage: watched ? "xmark.circle" : "checkmark.circle") {
                Task {
                    await model.setWatched(!watched, for: model.request(for: video))
                    await titleActions.refresh()
                }
            }
        } preview: {
            // The same card, the full width between the page margins, inset by its padding so the menu's corners do not cut into it. Its
            // still's corners follow the panel's, and the panel gets the hairline the app's glass cards have. The preview is on screen
            // only while the menu is open.
            episodeCard(video, width: pageWidth - contentMargin * 2 - Self.previewPadding * 2, airsLater: airsLater,
                        stillRadius: Self.previewStillRadius)
                .padding(Self.previewPadding)
                .glassHairline(RoundedRectangle(cornerRadius: Self.previewPanelRadius, style: .continuous))
                // Without the store the IMDb mark forgot the coloured-logos setting and changed colour while the card was held.
                .environment(ratings)
                .onAppear { isHoldingEpisode = true }
                .onDisappear { isHoldingEpisode = false }
        }
        .accessibilityIdentifier("detail.episode.\(video.id)")
        // IMDb's episode scores come from OMDb, a season at a time, asked for when its first card comes on screen (and again if the key changes).
        .task(id: "\(video.id):\(model.reviewServicesRevision):\(model.isLoading):\(model.hasSettledHero)") {
            guard model.hasSettledHero else { return }
            await model.episodeAppeared(video)
        }
    }

    /// One episode's card at `width`: the card in the list, and the menu's preview at the page's full width.
    private func episodeCard(_ video: Video, width: CGFloat, airsLater: Bool, isLoadingStreams: Bool = false,
                             stillRadius: CGFloat = Theme.Radius.small) -> EpisodeRow {
        EpisodeRow(video: video, fraction: model.progressFraction(for: video), watched: model.isWatched(video),
                   artwork: model.backdropURL, score: model.score(for: video), width: width,
                   showsWholeOverview: model.matchesEpisodeWidthToText, airsLater: airsLater, isLoadingStreams: isLoadingStreams,
                   stillRadius: stillRadius)
    }
}

/// One episode: its still with the progress line or watched mark over it, the numbered title, the air date and rating, and the
/// overview: three lines in a fixed-width card, all of it when the list is set to full width.
private struct EpisodeRow: View {
    let video: Video
    let fraction: Double?
    let watched: Bool
    let artwork: URL?
    let score: DetailViewModel.EpisodeScore?
    let width: CGFloat
    /// Set for a full-width card: the whole overview shows at its own height, so the rating sits under this episode's own text.
    var showsWholeOverview = false
    /// Set for an episode that has not aired: its still is dimmed, and the card cannot be opened.
    var airsLater = false
    /// Set while this episode's streams load: a spinner over its still, as Play has one.
    var isLoadingStreams = false
    /// The still's corner radius. The menu's preview gives it one that follows its panel's, which is rounder than a card's.
    var stillRadius: CGFloat = Theme.Radius.small

    /// How far the progress line and the watched mark move in from the still's edges, so a rounder corner does not cut into them.
    private var overlayInset: CGFloat { max(0, stillRadius - Theme.Radius.small) * 0.3 }

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
            .opacity(airsLater ? 0.45 : 1)
            .overlay {
                if !watched, let fraction {
                    PlaybackProgressOverlay(fraction: fraction, width: width, inset: overlayInset)
                }
            }
            .overlay(alignment: .topTrailing) {
                if watched { checkmark.padding(overlayInset) }
            }
            .overlay {
                if isLoadingStreams {
                    ZStack {
                        Color.black.opacity(0.35)
                        Spinner()
                            .controlSize(.large)
                    }
                    .transition(.opacity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Loading streams")
                }
            }
            .animation(.smooth(duration: 0.25), value: isLoadingStreams)
            .mediaArtwork(cornerRadius: stillRadius)
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
