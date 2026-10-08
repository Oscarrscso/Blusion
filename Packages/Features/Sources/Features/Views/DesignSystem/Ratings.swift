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

/// All five sites stay usable without API keys. Only genuine scores are shown; unmatched pages are labeled Search.
struct ReviewSitesRow: View {
    let item: MetaPreview
    @Environment(PosterRatingsStore.self) private var store: PosterRatingsStore?

    var body: some View {
        if let store {
            let ratings = store.ratings(for: item)
            links(ratings: ratings)
                .task(id: "\(item.identity):\(store.reviewServicesRevision)") { _ = store.ratings(for: item, includeReviews: true) }
        } else {
            links(ratings: nil)
        }
    }

    private func links(ratings: TitleRatings?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(ReviewSite.allCases) { site in
                        if let url = site.url(for: item, tmdbURL: ratings?.tmdbURL) {
                            let search = site.isSearch(for: item, tmdbURL: ratings?.tmdbURL)
                            Link(destination: url) {
                                HStack(spacing: 7) {
                                    ReviewSiteIcon(site: site)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(site.name).font(.caption.weight(.semibold))
                                        Text(subtitle(site: site, ratings: ratings, search: search))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.glassCapsule)
                            .hoverEffect(.highlight)
                            .help(search ? "Search \(site.name) for \(item.name)" : "Open \(item.name) on \(site.name)")
                            .accessibilityIdentifier("detail.reviews.\(site.rawValue)")
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            if ratings?.rottenTomatoes != nil || ratings?.metacritic != nil {
                Text("Critic scores supplied by OMDb.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("detail.reviews")
    }

    private func subtitle(site: ReviewSite, ratings: TitleRatings?, search: Bool) -> String {
        if let score = ratings?.text(for: site) { return search ? "\(score) · Search" : score }
        return search ? "Search" : "Reviews"
    }
}
#endif
