#if canImport(UIKit)
import StremioKit
import SwiftUI

/// Every shared component on one screen, for looking at the design system in one place.
/// Reached with the launch route `gallery` or `gallery:<section>` (`scripts/snapshot.sh gallery:cards out.png`); not linked from
/// the app's own UI. A section name shows only that section, so each one fits a phone-sized picture.
struct DesignGalleryView: View {
    var section: String?

    private static let sectionNames = ["cards", "rows", "chips", "states"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                if shows("cards") { cards }
                if shows("rows") { rows }
                if shows("chips") { chips }
                if shows("states") { states }
                if let section, !Self.sectionNames.contains(section.lowercased()) {
                    Text("No gallery section named \"\(section)\". Sections: \(Self.sectionNames.joined(separator: ", ")).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.screenPadding)
                }
            }
            .padding(.vertical, Theme.Spacing.l)
        }
        .screenBackground()
        .navigationTitle("Gallery")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shows(_ name: String) -> Bool {
        guard let section else { return true }
        return section.lowercased() == name
    }

    // MARK: - Cards

    /// Each row is either all titled or all untitled, and lists its tallest card first: a row takes its height from its first card.
    private var cards: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            sectionTitle("Cards")
            caption("Posters with title: large, medium with rating, small")
            MediaRow("Posters", hideTitle: true) {
                MediaCard(item: Sample.interstellar, aspect: .poster, size: .large)
                MediaCard(item: Sample.inception, aspect: .poster, size: .medium, showsRating: true)
                MediaCard(item: Sample.oppenheimer, aspect: .poster, size: .small)
            }
            caption("Posters without title: large, medium with rating, small")
            MediaRow("Posters without title", hideTitle: true) {
                MediaCard(item: Sample.interstellar, aspect: .poster, size: .large, showsTitle: false)
                MediaCard(item: Sample.inception, aspect: .poster, size: .medium, showsTitle: false, showsRating: true)
                MediaCard(item: Sample.darkKnight, aspect: .poster, size: .small, showsTitle: false)
            }
            caption("Wide with title: large, medium with rating, small without title")
            MediaRow("Wide", hideTitle: true) {
                MediaCard(item: Sample.breakingBad, aspect: .wide, size: .large)
                MediaCard(item: Sample.darkKnight, aspect: .wide, size: .medium, showsRating: true)
                MediaCard(item: Sample.inception, aspect: .wide, size: .small, showsTitle: false)
            }
            caption("Square: large with title and rating, medium and small without title")
            MediaRow("Square", hideTitle: true) {
                MediaCard(item: Sample.gameOfThrones, aspect: .square, size: .large, showsRating: true)
                MediaCard(item: Sample.oppenheimer, aspect: .square, size: .medium, showsTitle: false)
                MediaCard(item: Sample.interstellar, aspect: .square, size: .small, showsTitle: false)
            }
            caption("Progress cards")
            MediaRow("Progress", hideTitle: true) {
                ProgressCard(title: "Inception", subtitle: "Resume at 52 min", artwork: Sample.artwork("tt1375666", "background"), fraction: 0.35)
                ProgressCard(title: "Breaking Bad", subtitle: "S2 E5 · 21 min left", artwork: Sample.artwork("tt0903747", "background"), fraction: 0.82)
            }
            caption("Collection tiles: poster, square with image, wide without and with image")
            MediaRow("Collections", hideTitle: true) {
                CollectionTile(title: "Crime", aspect: .poster)
                CollectionTile(title: "2010s", imageURL: Sample.artwork("tt1375666", "poster"), aspect: .square, hideTitle: true)
                CollectionTile(title: "Action")
                CollectionTile(title: "Drama", imageURL: Sample.artwork("tt0944947", "background"))
            }
        }
    }

    // MARK: - Rows

    private var rows: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            sectionTitle("Rows")
            MediaRow("Popular", subtitle: "Most watched this week", onSeeAll: {}) {
                ForEach(Sample.all) { MediaCardLink(item: $0) }
            }
            MediaRow("Recently added") {
                ForEach(Sample.all) { MediaCardLink(item: $0, aspect: .wide, showsRating: true) }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                caption("SkeletonRow while a row loads")
                SkeletonRow()
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                caption("MediaGrid, six titles")
                MediaGrid(items: Sample.all)
            }
        }
    }

    // MARK: - Chips

    private var chips: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            sectionTitle("Chips")
            caption("Glass chips: the selected one is tinted")
            ChipRow {
                GlassChip("All", isSelected: true) {}
                GlassChip("Movies", systemImage: "film") {}
                GlassChip("Series", systemImage: "tv") {}
                GlassChip("Documentary") {}
            }
            block("Badges") {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(spacing: Theme.Spacing.s) {
                        Badge("Watched", systemImage: "checkmark")
                        Badge("New", style: .accent)
                        Badge("Slow addon", style: .warning)
                    }
                    HStack(spacing: Theme.Spacing.s) {
                        Badge("4K", style: .quality)
                        Badge("HDR", style: .quality)
                        Badge("Dolby Vision", style: .quality)
                    }
                }
            }
            block("Rating on artwork") {
                ZStack(alignment: .topLeading) {
                    ArtworkImage(url: Sample.artwork("tt0468569", "background"), title: "The Dark Knight")
                        .frame(width: 240, height: 135)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    RatingBadge(9.0).padding(Theme.Spacing.s)
                }
            }
            block("Metadata line: nil parts are skipped") {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    MetaLine(["2023", "2 h 49 min", "★ 8.4"])
                    MetaLine(["2008–2013", nil, "★ 9.5"])
                }
            }
            block("Buttons: one primary action per screen, glass for the rest") {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Button {} label: { Label("Play", systemImage: "play.fill") }
                        .buttonStyle(.primaryAction)
                    HStack(spacing: Theme.Spacing.m) {
                        Button {} label: { Label("Resume", systemImage: "play.fill") }
                            .buttonStyle(.primaryActionCompact)
                        Button {} label: { Label("Save", systemImage: "bookmark") }
                            .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    // MARK: - States

    private var states: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            sectionTitle("States")
            caption("Empty state with an action")
            EmptyStateView("Nothing saved yet", systemImage: "bookmark", message: "Titles you save appear here.",
                           actionTitle: "Browse", action: {})
            caption("Inline error with retry")
            InlineErrorView("Cinemeta did not answer in time.", retry: {})
                .padding(.horizontal, Theme.screenPadding)
            caption("Error chips")
            WrappingStack {
                ErrorChip(text: "Torrentio: 503 Service Unavailable")
                ErrorChip(text: "Cinemeta: timed out")
            }
            .padding(.horizontal, Theme.screenPadding)
            caption("Offline")
            OfflineBanner()
            caption("No addons yet")
            EmptyAddonsView(onOpenAddons: {})
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.screenPadding)
            .accessibilityAddTraits(.isHeader)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.screenPadding)
    }

    /// A caption over content that is inset to the screen margin. The caption insets itself, so only the content is padded here.
    private func block<Content: View>(_ text: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            caption(text)
            content()
                .padding(.horizontal, Theme.screenPadding)
        }
    }
}

/// Real titles and artwork from Stremio's metadata host, so the gallery looks the way the app does with data.
private enum Sample {
    static let darkKnight = title("tt0468569", "movie", "The Dark Knight", "2008", 9.0, ["Action", "Crime"], "152 min")
    static let inception = title("tt1375666", "movie", "Inception", "2010", 8.8, ["Action", "Sci-Fi"], "148 min")
    static let interstellar = title("tt0816692", "movie", "Interstellar", "2014", 8.7, ["Sci-Fi", "Drama"], "169 min")
    static let breakingBad = title("tt0903747", "series", "Breaking Bad", "2008–2013", 9.5, ["Crime", "Drama"], nil)
    static let oppenheimer = title("tt15398776", "movie", "Oppenheimer", "2023", 8.3, ["Biography", "Drama"], "180 min")
    static let gameOfThrones = title("tt0944947", "series", "Game of Thrones", "2011–2019", 9.2, ["Fantasy", "Drama"], nil)

    static let all = [darkKnight, inception, interstellar, breakingBad, oppenheimer, gameOfThrones]

    static func title(_ id: String, _ type: String, _ name: String, _ year: String, _ rating: Double, _ genres: [String],
                      _ runtime: String?) -> MetaPreview {
        MetaPreview(id: id, type: type, name: name, poster: artwork(id, "poster"), background: artwork(id, "background"),
                    releaseInfo: year, imdbRating: rating, genres: genres, runtime: runtime)
    }

    static func artwork(_ id: String, _ kind: String) -> URL? {
        URL(string: "https://images.metahub.space/\(kind)/medium/\(id)/img")
    }
}
#endif
