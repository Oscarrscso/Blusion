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
}

/// How big a card is within its aspect. The widths are in points.
enum CardSize: String, CaseIterable, Sendable {
    case small, medium, large

    func width(for aspect: CardAspect) -> CGFloat {
        switch (aspect, self) {
        case (.poster, .small): 104
        case (.poster, .medium): 128
        case (.poster, .large): 156
        case (.wide, .small): 200
        case (.wide, .medium): 260
        case (.wide, .large): 320
        case (.square, .small): 112
        case (.square, .medium): 140
        case (.square, .large): 168
        }
    }
}

/// One title: artwork with continuous rounded corners, and optionally its name and year underneath.
/// Poster and square cards show `item.poster`; wide cards show `item.background`, falling back to the poster.
///
/// The card is `width` wide, or `size`'s width when `width` is nil. `stretched()` lets a grid give it a column's width instead.
struct MediaCard: View {
    let item: MetaPreview
    let aspect: CardAspect
    let size: CardSize
    let showsTitle: Bool
    let showsRating: Bool
    let width: CGFloat?
    private var stretches = false
    private var zoomID: String?
    @Environment(\.zoomNamespace) private var zoomNamespace

    init(item: MetaPreview, aspect: CardAspect = .poster, size: CardSize = .medium, showsTitle: Bool = true, showsRating: Bool = false,
         width: CGFloat? = nil) {
        self.item = item
        self.aspect = aspect
        self.size = size
        self.showsTitle = showsTitle
        self.showsRating = showsRating
        self.width = width
    }

    var body: some View {
        let fixed = width ?? size.width(for: aspect)
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            artwork
            if showsTitle { titles }
        }
        // The title block is laid out inside the artwork's width and never widens the card: it wraps instead.
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

    private var artwork: some View {
        artworkSpace
            .overlay { ArtworkImage(url: artworkURL, title: item.name, maxPixelSize: aspect == .wide ? 800 : 480) }
            .clipShape(RoundedRectangle(cornerRadius: aspect.cornerRadius, style: .continuous))
            .zoomSource(id: zoomID ?? "", in: zoomID == nil ? nil : zoomNamespace)
            .overlay(alignment: .topLeading) {
                if showsRating, let rating = item.imdbRating {
                    RatingBadge(rating).padding(Theme.Spacing.s)
                }
            }
    }

    /// The artwork's box. A fixed card already knows its width, so its height is set outright: an aspect-ratio box would take
    /// its height from whatever the enclosing row proposes, and cards after the first in a row came out squeezed. Only a grid
    /// column stretches, and it offers a real width, so the ratio can work there.
    @ViewBuilder
    private var artworkSpace: some View {
        if stretches {
            Color.clear.aspectRatio(aspect.ratio, contentMode: .fit)
        } else {
            let fixed = width ?? size.width(for: aspect)
            Color.clear.frame(width: fixed, height: fixed / aspect.ratio)
        }
    }

    /// One title line and one year line, always: cards of one size share a height (a row takes its height from its first card,
    /// see `MediaRow`), and the year sits right under the name. A long name is cut off rather than wrapped, as in Apple's TV app.
    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(yearLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A blank line when there is no year, so the year lines of a row still line up.
    private var yearLine: String {
        guard let year = item.releaseInfo, !year.isEmpty else { return " " }
        return year
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
    let showsTitle: Bool
    let showsRating: Bool
    let width: CGFloat?
    private var stretches = false
    @Environment(\.zoomScope) private var zoomScope

    init(item: MetaPreview, aspect: CardAspect = .poster, size: CardSize = .medium, showsTitle: Bool = true, showsRating: Bool = false,
         width: CGFloat? = nil) {
        self.item = item
        self.aspect = aspect
        self.size = size
        self.showsTitle = showsTitle
        self.showsRating = showsRating
        self.width = width
    }

    var body: some View {
        // The row's scope makes the id unique on screen, so the title's screen zooms out of this card and not a twin in another row.
        let sourceID = "\(zoomScope)/\(item.identity)"
        let card = MediaCard(item: item, aspect: aspect, size: size, showsTitle: showsTitle, showsRating: showsRating, width: width)
            .zoomSource(sourceID)
        NavigationLink(value: TitleDestination(preview: item, sourceID: sourceID)) {
            stretches ? card.stretched() : card
        }
        .buttonStyle(PressableCardStyle())
    }

    /// The link takes the width it is offered, as a grid column does. See `MediaCard.stretched()`.
    func stretched() -> MediaCardLink {
        var copy = self
        copy.stretches = true
        return copy
    }
}

/// Cards respond to touch by scaling to 0.96 and dimming slightly, with a quick spring.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

/// A wide "continue watching" card: artwork, the title and a subtitle over a bottom gradient, and a thin progress bar along the
/// bottom edge. `fraction` is the share watched, 0 to 1; values outside that range are clamped.
struct ProgressCard: View {
    let title: String
    let subtitle: String?
    let artwork: URL?
    let fraction: Double
    let width: CGFloat

    init(title: String, subtitle: String? = nil, artwork: URL?, fraction: Double, width: CGFloat = 260) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.fraction = fraction
        self.width = width
    }

    var body: some View {
        let progress = min(max(fraction, 0), 1)
        Color.clear
            .frame(width: width, height: width / CardAspect.wide.ratio)
            .overlay { ArtworkImage(url: artwork, title: title, maxPixelSize: 800) }
            .overlay(alignment: .bottom) { caption }
            .overlay(alignment: .bottom) { progressBar(progress) }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([title, subtitle, "\(Int((progress * 100).rounded())) percent watched"].compactMap { $0 }
                .filter { !$0.isEmpty }.joined(separator: ", "))
    }

    private var caption: some View {
        ArtworkCaption {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
        }
    }

    /// The card's width is fixed, so the fill is a plain frame: a GeometryReader per card would cost a layout pass per row item.
    private func progressBar(_ progress: Double) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(.white.opacity(0.22))
            Rectangle()
                .fill(Theme.brandGradient)
                .frame(width: width * progress)
        }
        .frame(width: width, height: 3)
    }
}

/// A tile that stands for a whole collection (a genre, a streaming service, a decade). With an image: the image, plus the title
/// over a bottom gradient unless `hideTitle`. Without one: a gradient derived from the title, so "Action" always gets the same
/// colours, with the title large and bold. `hideTitle` is ignored then, because the title is the tile's only content.
struct CollectionTile: View {
    let title: String
    let imageURL: URL?
    let aspect: CardAspect
    let hideTitle: Bool
    let width: CGFloat

    init(title: String, imageURL: URL? = nil, aspect: CardAspect = .wide, hideTitle: Bool = false, width: CGFloat? = nil) {
        self.title = title
        self.imageURL = imageURL
        self.aspect = aspect
        self.hideTitle = hideTitle
        self.width = width ?? Self.defaultWidth(for: aspect)
    }

    var body: some View {
        Color.clear
            .frame(width: width, height: width / aspect.ratio)
            .overlay { face }
            .overlay(alignment: .bottom) { label }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
    }

    @ViewBuilder
    private var face: some View {
        if let imageURL {
            ArtworkImage(url: imageURL, title: title, maxPixelSize: aspect == .wide ? 800 : 480)
        } else {
            ZStack {
                LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: width)
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        if imageURL == nil {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(Theme.Spacing.m + Theme.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !hideTitle {
            ArtworkCaption {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
            }
        }
    }

    private var palette: [Color] {
        let hue = Double(Self.seed(for: title) % 360) / 360
        return [
            Color(hue: hue, saturation: 0.72, brightness: 0.74),
            Color(hue: (hue + 0.09).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 0.34),
        ]
    }

    private static func defaultWidth(for aspect: CardAspect) -> CGFloat {
        switch aspect {
        case .wide: 200
        case .poster: 128
        case .square: 140
        }
    }

    /// FNV-1a over the scalars. `Hasher` is seeded per launch, so it would recolour every tile after each restart.
    private static func seed(for text: String) -> UInt64 {
        text.unicodeScalars.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1.value)) &* 0x0000_0100_0000_01b3 }
    }
}

extension CardAspect {
    /// Posters and square tiles use the poster radius, wide artwork the card radius (style guide: posters 14 pt, cards 20 pt).
    var cornerRadius: CGFloat {
        self == .wide ? Theme.Radius.card : Theme.Radius.poster
    }
}

/// Text laid over the bottom of artwork, on a gradient that keeps it legible whatever the picture is.
private struct ArtworkCaption<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.xxl)
            .padding(.bottom, Theme.Spacing.m + Theme.Spacing.xs)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            }
    }
}
#endif
