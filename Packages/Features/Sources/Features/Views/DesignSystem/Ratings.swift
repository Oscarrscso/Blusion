#if canImport(UIKit)
import SwiftUI
import StremioKit

/// Letterboxd's mark: three small overlapping dots. Drawn, not an image, so it needs no brand assets and stays crisp at any size.
struct LetterboxdMark: View {
    var dot: CGFloat = 8
    @Environment(PosterRatingsStore.self) private var store: PosterRatingsStore?

    var body: some View {
        HStack(spacing: -dot * 0.34) {
            mark(Color(red: 1.0, green: 0.50, blue: 0.0))
            mark(Color(red: 0.0, green: 0.88, blue: 0.33))
            mark(Color(red: 0.25, green: 0.74, blue: 0.96))
        }
        .frame(width: dot * 2.32, height: dot)
        .accessibilityHidden(true)
    }

    /// Its own colour when coloured logos are on; otherwise the surrounding text colour, with a thin edge so the overlapping dots stay apart.
    @ViewBuilder private func mark(_ colour: Color) -> some View {
        if store?.showsColouredLogos ?? false {
            Circle().fill(colour)
        } else {
            Circle().overlay(Circle().stroke(.black.opacity(0.35), lineWidth: dot * 0.08))
        }
    }
}

/// The first two available scores, with their site's mark. Meant to sit on artwork over a dark backdrop.
struct RatingsLine: View {
    let ratings: TitleRatings
    var font: Font = .caption.weight(.semibold)

    var body: some View {
        if !ratings.isEmpty {
            HStack(spacing: 7) {
                ForEach(ratings.posterSites) { site in
                    if let score = ratings.shortText(for: site) {
                        HStack(spacing: 3) {
                            if site == .letterboxd {
                                LetterboxdMark(dot: 7)
                            } else {
                                ReviewSiteIcon(site: site, size: 12)
                            }
                            Text(score)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(site.name) rating \(score)")
                    }
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
/// `PosterRatingsStore`; draws nothing without one, when ratings are switched off, or while no scores are known.
/// Only this view observes the title's entry, so a rating that arrives late redraws one poster.
struct PosterRatingsOverlay: View {
    let item: MetaPreview
    @Environment(PosterRatingsStore.self) private var store: PosterRatingsStore?

    var body: some View {
        if let store, store.isEnabled {
            let ratings = store.ratings(for: item)
            ZStack {
                if !ratings.isEmpty {
                    RatingsLine(ratings: ratings)
                        .padding(.horizontal, 3)
                        .padding(.bottom, 2)
                        .padding(.top, 18)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .background(alignment: .bottom) {
                            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                        }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .task(id: "\(item.identity):\(store.reviewServicesRevision)") {
                _ = store.ratings(for: item)
            }
        }
    }
}

/// Local official marks, so opening a screen does not make five extra image requests.
struct ReviewSiteIcon: View {
    let site: ReviewSite
    var size: CGFloat = 24
    @Environment(PosterRatingsStore.self) private var store: PosterRatingsStore?

    /// The official colours only when the user asks for them; otherwise the mark takes the surrounding text colour.
    var body: some View {
        Image(assetName)
            .resizable()
            .renderingMode(store?.showsColouredLogos ?? false ? .original : .template)
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
            VStack(spacing: 8) {
                buttons(ratings: ratings)
                if let issue = store.reviewServiceIssue {
                    Text(issue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("detail.reviews.issue")
                }
            }
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
                    .foregroundStyle(.white)
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
