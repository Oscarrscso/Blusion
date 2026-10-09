#if canImport(UIKit)
import SwiftUI
import StremioKit

/// The shape of a card's artwork. `ratio` is width / height.
enum CardAspect: String, CaseIterable, Sendable {
    case poster, wide, square

    var ratio: CGFloat {
        switch self {
        case .poster: 2.0 / 3.0
        case .wide: 16.0 / 9.0
        case .square: 1
        }
    }

    /// Posters and square artwork use the poster radius, wide artwork the card radius.
    var cornerRadius: CGFloat {
        self == .wide ? Theme.Radius.card : Theme.Radius.poster
    }

    /// Whether a card of this shape carries its name underneath by default. Posters do not: the art carries the title, as in the
    /// TV app's poster shelves. Landscape and square cards do.
    var showsCaptionByDefault: Bool {
        self != .poster
    }
}

/// How big a card is within its aspect: a scale of the layout's base width (`LayoutMetrics.posterWidth` and friends), so
/// `.medium` is the TV app's own size on every platform.
enum CardSize: String, CaseIterable, Sendable {
    case small, medium, large

    var scale: CGFloat {
        switch self {
        case .small: 0.82
        case .medium: 1
        case .large: 1.22
        }
    }

    /// The card's width in points. Without `metrics` the phone layout's numbers.
    func width(for aspect: CardAspect, metrics: LayoutMetrics = .compact) -> CGFloat {
        let base: CGFloat = switch aspect {
        case .poster: metrics.posterWidth
        case .wide: metrics.wideCardWidth
        case .square: metrics.squareWidth
        }
        return (base * scale).rounded()
    }
}

/// One title: artwork with continuous rounded corners and, for landscape and square cards, its name and a grey line underneath.
/// Poster and square cards show `item.poster`; wide cards show `item.background`, falling back to the poster.
///
/// The card is `width` wide, or `size`'s width when `width` is nil. `stretched()` lets a grid give it a column's width instead.
/// `showsTitle` nil means the aspect's default (no caption under a poster, a caption under wide and square cards); pass a Bool to
/// force either. With `showsRating`, posters carry the IMDb and Letterboxd ratings from the environment's `PosterRatingsStore`.
struct MediaCard: View {
    let item: MetaPreview
    let aspect: CardAspect
    let size: CardSize
    let showsTitle: Bool?
    let showsRating: Bool
    let width: CGFloat?
    let subtitle: String?
    private var stretches = false
    private var zoomID: String?
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.displayScale) private var displayScale

    init(item: MetaPreview, aspect: CardAspect = .poster, size: CardSize = .medium, showsTitle: Bool? = nil, showsRating: Bool = true,
         width: CGFloat? = nil, subtitle: String? = nil) {
        self.item = item
        self.aspect = aspect
        self.size = size
        self.showsTitle = showsTitle
        self.showsRating = showsRating
        self.width = width
        self.subtitle = subtitle
    }

    var body: some View {
        let fixed = resolvedWidth
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            artwork
            if showsCaption { captions }
        }
        // The caption is laid out inside the artwork's width and never widens the card: it is cut off instead.
        .frame(minWidth: stretches ? 0 : fixed, idealWidth: fixed, maxWidth: stretches ? .infinity : fixed, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenName)
        .accessibilityIdentifier("poster.\(item.id)")
    }

    /// The card takes whatever width it is offered rather than its fixed width. Only a grid column offers a real width; a row does not.
    func stretched() -> MediaCard {
        var copy = self
        copy.stretches = true
        return copy
    }

    /// Makes the artwork the place a pushed screen zooms out of (see `TitleDestination`).
    func zoomSource(_ id: String) -> MediaCard {
        var copy = self
        copy.zoomID = id
        return copy
    }

    private var resolvedWidth: CGFloat {
        width ?? size.width(for: aspect, metrics: metrics)
    }

    private var showsCaption: Bool {
        showsTitle ?? aspect.showsCaptionByDefault
    }

    private var artwork: some View {
        artworkSpace
            .overlay { ArtworkImage(url: artworkURL, title: item.name, maxPixelSize: pixelSize) }
            .overlay(alignment: .bottom) {
                if showsRating && aspect != .wide { PosterRatingsOverlay(item: item) }
            }
            .clipShape(RoundedRectangle(cornerRadius: aspect.cornerRadius, style: .continuous))
            .zoomSource(id: zoomID ?? "", in: zoomID == nil ? nil : zoomNamespace)
    }

    /// The artwork's box. A fixed card already knows its width, so its height is set outright: an aspect-ratio box would take
    /// its height from whatever the enclosing row proposes, and cards after the first in a row came out squeezed. Only a grid
    /// column stretches, and it offers a real width, so the ratio can work there.
    @ViewBuilder
    private var artworkSpace: some View {
        if stretches {
            Color.clear.aspectRatio(aspect.ratio, contentMode: .fit)
        } else {
            let fixed = resolvedWidth
            Color.clear.frame(width: fixed, height: fixed / aspect.ratio)
        }
    }

    /// Decoded no larger than the card is drawn, so a long shelf stays light in memory.
    private var pixelSize: CGFloat {
        let fixed = resolvedWidth
        return min((max(fixed, fixed / aspect.ratio) * displayScale).rounded(.up), 1200)
    }

    /// One title line and one grey line, always: cards of one kind share a height (a row takes its height from its first card, see
    /// `MediaRow`), and the grey line sits right under the name. A long name is cut off rather than wrapped, as in the TV app.
    private var captions: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(subtitleLine)
                .font(Theme.Typography.cardSubtitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Drama · 2008": a blank line when there is nothing to say, so the grey lines of a row still line up.
    private var subtitleLine: String {
        if let subtitle, !subtitle.isEmpty { return subtitle }
        let line = [item.genres.first, item.releaseInfo].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return line.isEmpty ? " " : line
    }

    private var artworkURL: URL? {
        switch aspect {
        case .wide: item.background ?? item.poster
        case .poster, .square: item.poster
        }
    }

    private var spokenName: String {
        [item.name, item.releaseInfo].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// `MediaCard` that opens the title: `NavigationLink(value: item)` with `PressableCardStyle`.
struct MediaCardLink: View {
    let item: MetaPreview
    let aspect: CardAspect
    let size: CardSize
    let showsTitle: Bool?
    let showsRating: Bool
    let width: CGFloat?
    let subtitle: String?
    private var stretches = false
    @Environment(\.zoomScope) private var zoomScope
    @Environment(TitleActions.self) private var actions: TitleActions?

    init(item: MetaPreview, aspect: CardAspect = .poster, size: CardSize = .medium, showsTitle: Bool? = nil, showsRating: Bool = true,
         width: CGFloat? = nil, subtitle: String? = nil) {
        self.item = item
        self.aspect = aspect
        self.size = size
        self.showsTitle = showsTitle
        self.showsRating = showsRating
        self.width = width
        self.subtitle = subtitle
    }

    var body: some View {
        // The row's scope makes the id unique on screen, so the title's screen zooms out of this card and not a twin in another row.
        let sourceID = "\(zoomScope)/\(item.identity)"
        let card = MediaCard(item: item, aspect: aspect, size: size, showsTitle: showsTitle, showsRating: showsRating, width: width,
                             subtitle: subtitle)
            .zoomSource(sourceID)
        NavigationLink(value: TitleDestination(preview: item, sourceID: sourceID)) {
            stretches ? card.stretched() : card
        }
        .buttonStyle(PressableCardStyle())
        .titleTapHaptic()
        .help(item.name)
        .contextMenu {
            if let actions {
                Button(actions.isSaved(item) ? "Remove from Library" : "Add to Library", systemImage: "bookmark") {
                    Task { await actions.toggleSaved(item) }
                }
                if item.type == "movie" {
                    Button(actions.isWatched(item) ? "Mark as Unwatched" : "Mark as Watched", systemImage: "checkmark.circle") {
                        Task { await actions.setWatched(!actions.isWatched(item), for: item) }
                    }
                } else if item.type == "series" {
                    Button("Mark All Episodes as Watched", systemImage: "checkmark.circle") {
                        Task { await actions.setSeriesWatched(true, for: item) }
                    }
                    if actions.hasWatchedEpisodes(item) {
                        Button("Mark All Episodes as Unwatched", systemImage: "xmark.circle") {
                            Task { await actions.setSeriesWatched(false, for: item) }
                        }
                    }
                }
                if item.id.hasPrefix("tt"), item.id.dropFirst(2).allSatisfy(\.isNumber),
                   let url = URL(string: "https://www.imdb.com/title/\(item.id)/") {
                    ShareLink(item: url)
                }
            }
        }
    }

    /// The link takes the width it is offered, as a grid column does. See `MediaCard.stretched()`.
    func stretched() -> MediaCardLink {
        var copy = self
        copy.stretches = true
        return copy
    }
}

/// How cards answer a touch or a pointer: pressed, they dim and shrink a little with a quick spring; under a pointer (Mac, iPad
/// trackpad) they lift slightly and highlight. Reduce Motion keeps the card still.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableCardLabel(configuration: configuration)
    }
}

/// A view of its own because the hover state needs somewhere to live.
private struct PressableCardLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
            .pointerInteraction(lifts: !configuration.isPressed)
    }
}
#endif
