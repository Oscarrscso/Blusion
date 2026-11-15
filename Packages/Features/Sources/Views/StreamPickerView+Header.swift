#if canImport(UIKit)
import Persistence
import PlayerKit
import StremioKit
import SwiftUI
import UIKit

extension StreamPickerView {
    // MARK: header

    /// The title's own artwork, stretched, blurred and faded into the page behind the header: the picker belongs to the title it opened
    /// from, the way the TV app tints a screen with its poster. It runs up under the navigation bar.
    @ViewBuilder
    var ambientBackdrop: some View {
        if !isLandscape, let poster = model.request.poster {
            ArtworkImage(url: poster, maxPixelSize: 240)
                .frame(height: 520)
                .scaleEffect(1.4)
                .blur(radius: 46)
                .saturation(1.25)
                .opacity(0.5)
                .overlay { BottomFade(length: 0.85) }
                .clipped()
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Poster, then what is being picked: for an episode "Time · S1E3", for a film its year over its name. On a phone it is centred, as
    /// the title page is; in a wide window it reads from the left.
    var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            if let poster = model.request.poster {
                PosterImage(url: poster, title: model.request.title)
                    .frame(width: 44, height: 66)
            }
            VStack(alignment: .leading, spacing: 2) {
                if episodeHeading == nil, let year = model.request.year {
                    Text(year)
                        .appFont(.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                if let episodeHeading {
                    episodeLine(episodeHeading, lineLimit: 2)
                } else {
                    Text(model.request.title)
                        .appFont(.headline)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, streamMargin)
        .padding(.top, Theme.Spacing.xs)
    }

    /// The widest the list runs. On a Mac the streams take the page's width, in columns (see `groups`); elsewhere 760 points.
    var columnWidth: CGFloat {
        #if targetEnvironment(macCatalyst)
        isEmbedded ? .infinity : 1_400
        #else
        760
        #endif
    }

    /// On a Mac, the widest the header runs (Auto Pick, the best disc, the filters, and the notes under the streams). Under a title
    /// page's hero it is the title column's width, so it shares the logo and the metadata line's edges. Nil elsewhere: the column.
    var headerWidth: CGFloat? {
        #if targetEnvironment(macCatalyst)
        (isEmbedded ? TitleHero.macBlockWidth : 760) + streamMargin * 2
        #else
        nil
        #endif
    }

    /// A Mac's stream cards: columns at least this wide, so a card's tags stay on one line, and at most this wide, so a narrow window
    /// keeps one column of readable cards rather than one stretched across it.
    static let macCardColumns = [GridItem(.adaptive(minimum: 520, maximum: 760), spacing: Theme.Spacing.m, alignment: .top)]

    /// Whether the embedded header has an episode to show. A film's is empty.
    var embeddedHeaderShowsText: Bool { episodeHeading != nil }

    /// The header of a title page that shows these streams in place of its details: which episode. The page above
    /// already has the poster, the title and the picture, so there is no poster here. A series' page has the episode switcher, centred,
    /// in place of the heading text.
    var embeddedHeader: some View {
        let switches = episodeSwitcher != nil && episodeHeading != nil
        return HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: switches ? .center : .leading, spacing: 2) {
                if let episodeSwitcher, let season = model.request.season, let episode = model.request.episode {
                    episodeSwitcherRow(episodeSwitcher, season: season, episode: episode)
                } else if let episodeHeading {
                    // Under the title page's hero, so this is one line: a longer text is cut short rather than wrapped.
                    episodeLine(episodeHeading, lineLimit: 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: switches ? .center : .leading)
        }
        .padding(.horizontal, streamMargin)
    }

    /// "‹ Episode title · S1E1 [IMDb] 89 ›": the episode, its score right before the next chevron, and a small round glass chevron each
    /// side that loads the episode before or after in place, as its card would. A chevron with no episode to go to (the first episode,
    /// the last, or one that has not aired) is dimmed. A score that arrives later fades in.
    private func episodeSwitcherRow(_ switcher: EpisodeSwitcher, season: Int, episode: Int) -> some View {
        let episodeNumber = "S\(season)E\(episode)"
        let heading = episodeTitle.map { "\($0) · \(episodeNumber)" } ?? episodeNumber
        return HStack(alignment: .center, spacing: Theme.Spacing.m) {
            episodeStepButton(systemImage: "chevron.left", label: "Previous episode", to: switcher.previous, step: switcher.step)
                .accessibilityIdentifier("stream.previousEpisode")
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                Text(heading)
                    .appFont(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let episodeScore {
                    scoreLabel(episodeScore)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            // The middle fills the row, keeping both chevrons at the stream controls' outer edges.
            .frame(maxWidth: .infinity)
            .animation(Theme.Motion.fade, value: episodeScore)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(episodeAccessibilityLabel(heading))
            .accessibilityAddTraits(.isHeader)
            episodeStepButton(systemImage: "chevron.right", label: "Next episode", to: switcher.next, step: switcher.step)
                .accessibilityIdentifier("stream.nextEpisode")
        }
    }

    /// One of the switcher's chevrons: about two thirds as tall as Auto Pick, in Play's tinted glass, with the app's light tap.
    private func episodeStepButton(systemImage: String, label: String, to request: StreamRequest?,
                                   step: @escaping (StreamRequest) -> Void) -> some View {
        // A new episode's picker has not measured Auto Pick yet, so it starts from the last height measured, and the chevrons keep their size.
        let side = (autoPickButtonHeight > 0 ? autoPickButtonHeight : Self.lastAutoPickHeight ?? 34) * 0.68
        return Button {
            guard let request else { return }
            Haptics.play(.buttons)
            step(request)
        } label: {
            Image(systemName: systemImage)
                .font(.caption.bold())
                .foregroundStyle(Theme.faintText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .glassCircleButton(.small, glass: .regular.interactive().tint((Theme.playControlColour(hex: playColourHex) ?? .clear)))
        .frame(width: side, height: side)
        .animation(Theme.Motion.standard, value: playColourHex)
        .disabled(request == nil)
        .opacity(request == nil ? 0.4 : 1)
        .accessibilityLabel(label)
        .help(label)
    }

    /// The episode's name and number, falling back to the series name. Nothing for a film.
    private var episodeHeading: String? {
        guard let season = model.request.season, let episode = model.request.episode else { return nil }
        // A request without the series' name has it at the front of its title, which is "Series · Episode".
        let series = model.request.seriesName ?? model.request.title.components(separatedBy: " · ").first ?? model.request.title
        return "\(episodeTitle ?? series) · S\(season)E\(episode)"
    }

    /// The episode portion of “Series · Episode”, shown between the switcher's chevrons.
    private var episodeTitle: String? {
        let parts = model.request.title.components(separatedBy: " · ")
        guard parts.count > 1 else { return nil }
        let title = parts.dropFirst().joined(separator: " · ")
        return title.isEmpty ? nil : title
    }

    /// The episode's heading, then its score right after the season and episode: the IMDb mark and a whole number, as its card shows it
    /// (a star when the score is not IMDb's). A long series name is cut short, never the score. A score that arrives later fades in at
    /// the end of the line, so nothing before it moves.
    private func episodeLine(_ heading: String, lineLimit: Int) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            Text(heading)
                .appFont(.headline)
                .multilineTextAlignment(.leading)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
            if let episodeScore {
                scoreLabel(episodeScore)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.fade, value: episodeScore)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(episodeAccessibilityLabel(heading))
        .accessibilityAddTraits(.isHeader)
    }

    /// IMDb's episode rating is an actionable link to that episode's reviews.
    @ViewBuilder
    private func scoreLabel(_ score: DetailViewModel.EpisodeScore) -> some View {
        if score.isIMDb, model.request.season != nil, model.request.episode != nil {
            Button {
                let request = model.request
                Task { await EpisodeIMDbReviews.open(request, ratings: services.posterRatings) }
            } label: {
                scoreContent(score)
            }
            .buttonStyle(.hoverPlain)
            .accessibilityLabel("Open IMDb episode reviews")
            .accessibilityIdentifier("streams.episodeIMDbReviews")
        } else {
            scoreContent(score)
        }
    }

    private func scoreContent(_ score: DetailViewModel.EpisodeScore) -> some View {
        HStack(spacing: 4) {
            if score.isIMDb {
                ReviewSiteIcon(site: .imdb, size: 16)
            } else {
                Image(systemName: "star.fill").font(.system(size: 11, weight: .bold))
            }
            Text(score.text)
                .appFont(.headline)
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .fixedSize()
    }

    /// What VoiceOver reads for the episode: its heading, then its score.
    private func episodeAccessibilityLabel(_ heading: String) -> String {
        [heading, episodeScore.map { "\($0.isIMDb ? "IMDb rating" : "Rating") \($0.text)" }].compactMap { $0 }.joined(separator: ", ")
    }
}
#endif
