#if canImport(UIKit)
import SwiftUI
import StremioKit

/// Letterboxd's mark: three small overlapping dots. Drawn, not an image, so it needs no brand assets and stays crisp at any size.
struct LetterboxdMark: View {
    var dot: CGFloat = 8

    var body: some View {
        HStack(spacing: -dot * 0.34) {
            Circle().fill(Color(red: 1.0, green: 0.50, blue: 0.0))
            Circle().fill(Color(red: 0.0, green: 0.88, blue: 0.33))
            Circle().fill(Color(red: 0.25, green: 0.74, blue: 0.96))
        }
        .frame(width: dot * 2.32, height: dot)
        .accessibilityHidden(true)
    }
}

/// "IMDb 9.0" and the Letterboxd mark followed by "9.0", in quiet semibold white. Either may be missing; with neither it draws
/// nothing. Meant to sit on artwork (it assumes a dark backdrop), so it is white whatever the picture is.
struct RatingsLine: View {
    let imdb: String?
    let letterboxd: String?
    var font: Font = .caption.weight(.semibold)

    var body: some View {
        if imdb != nil || letterboxd != nil {
            HStack(spacing: 7) {
                if let imdb {
                    HStack(spacing: 3) {
                        ReviewSiteIcon(site: .imdb, size: 12)
                        Text(imdb)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("IMDb rating \(imdb)")
                }
                if let letterboxd {
                    HStack(spacing: 3) {
                        LetterboxdMark(dot: 7)
                        Text(letterboxd)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Letterboxd rating \(letterboxd)")
                }
            }
            .font(font)
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }
}

/// The ratings of one title over the bottom of its poster: a short black fade, then `RatingsLine`. Reads the environment's
/// `PosterRatingsStore`; draws nothing without one, when the user switched ratings off, or while neither rating is known.
/// Only this view observes the title's entry, so a Letterboxd rating that arrives late redraws one poster.
struct PosterRatingsOverlay: View {
    let item: MetaPreview
    @Environment(PosterRatingsStore.self) private var store: PosterRatingsStore?

    var body: some View {
        if let store, store.isEnabled {
            let ratings = store.ratings(for: item)
            if !ratings.isEmpty {
                RatingsLine(imdb: ratings.imdbText, letterboxd: ratings.letterboxdText)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 7)
                    .padding(.top, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(alignment: .bottom) {
                        LinearGradient(colors: [.black.opacity(0), .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                    }
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
    }
}

/// Local official marks, so opening a screen does not make five extra image requests.
struct ReviewSiteIcon: View {
    let site: ReviewSite
    var size: CGFloat = 24

    var body: some View {
        Image(assetName)
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var assetName: String {
        switch site {
        case .imdb: "ReviewIMDb"
        case .letterboxd: "ReviewLetterboxd"
        case .rottenTomatoes: "ReviewRottenTomatoes"
        case .metacritic: "ReviewMetacritic"
        case .tmdb: "ReviewTMDB"
        }
    }
}

/// The title's scores as small buttons, for the line under its name on the detail page: a site's icon, then its score, in a small
/// glass capsule that opens the title on that site. IMDb is always there (its icon alone until a score arrives, so the link is
/// never lost); every other site appears only once it has a genuine score, so an unrated title shows one button, not five.
/// Meant to sit over artwork, so the text is white.
struct RatingButtonsRow: View {
    let item: MetaPreview
    /// Where the buttons sit when the row is wider than they are.
    var alignment: Alignment = .center
    @Environment(PosterRatingsStore.self) private var store: PosterRatingsStore?

    var body: some View {
        if let store {
            let ratings = store.ratings(for: item)
            buttons(ratings: ratings)
                .task(id: "\(item.identity):\(store.reviewServicesRevision)") { _ = store.ratings(for: item, includeReviews: true) }
        } else {
            buttons(ratings: nil)
        }
    }

    private func buttons(ratings: TitleRatings?) -> some View {
        let sites = ReviewSite.allCases.filter { $0 == .imdb || ratings?.shortText(for: $0) != nil }
        return GlassEffectContainer(spacing: 6) {
            ViewThatFits(in: .horizontal) {
                row(sites, ratings: ratings)
                ScrollView(.horizontal) { row(sites, ratings: ratings) }
                    .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .accessibilityIdentifier("detail.reviews")
    }

    private func row(_ sites: [ReviewSite], ratings: TitleRatings?) -> some View {
        HStack(spacing: 6) {
            ForEach(sites) { site in
                if let url = site.url(for: item, tmdbURL: ratings?.tmdbURL) {
                    RatingButton(site: site, score: ratings?.shortText(for: site), url: url,
                                 isSearch: site.isSearch(for: item, tmdbURL: ratings?.tmdbURL), title: item.name)
                }
            }
        }
    }
}

/// One small rating button: the site's icon, then the score. Without a score it is the icon alone.
struct RatingButton: View {
    let site: ReviewSite
    let score: String?
    let url: URL
    /// True when the link is a search on the site, not the title's own page.
    let isSearch: Bool
    let title: String

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 5) {
                ReviewSiteIcon(site: site, size: 15)
                if let score {
                    Text(score)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, score == nil ? 9 : 10)
            .frame(height: 28)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(Capsule())
            .pointerInteraction(cornerRadius: 999)
        }
        .buttonStyle(.plain)
        .help(isSearch ? "Search \(site.name) for \(title)" : "Open \(title) on \(site.name)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "\(site.name) \($0)" } ?? site.name)
        .accessibilityHint(isSearch ? "Searches \(site.name) for this title" : "Opens this title on \(site.name)")
        .accessibilityAddTraits(.isLink)
        .accessibilityIdentifier("detail.reviews.\(site.rawValue)")
    }
}
#endif
