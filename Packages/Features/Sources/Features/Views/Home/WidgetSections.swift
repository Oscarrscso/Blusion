#if canImport(UIKit)
import PlayerKit
import StremioKit
import SwiftUI

extension WidgetPresentation.AspectRatio {
    var cardAspect: CardAspect {
        switch self {
        case .poster: .poster
        case .wide: .wide
        case .square: .square
        }
    }
}

extension WidgetPresentation.CardStyle {
    var cardSize: CardSize {
        switch self {
        case .small: .small
        case .medium: .medium
        case .large: .large
        }
    }
}

/// A `.row` widget: a titled row of cards once its items have loaded. Until then, and when it has nothing to show, the same header
/// sits over a placeholder, a message or a retry, so the layout does not move when the cards arrive.
struct WidgetRow: View {
    let section: HomeViewModel.Section
    let row: RowConfiguration
    let onRetry: () -> Void
    @Environment(AppRouter.self) private var router

    var body: some View {
        rowBody
            .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var rowBody: some View {
        let widget = section.widget
        let presentation = row.presentation
        if case .loaded(let items) = section.state, !items.isEmpty {
            MediaRow(widget.title, hideTitle: widget.hideTitle, onSeeAll: { router.homePath.append(seeAllRequest) }) {
                ForEach(items, id: \.identity) { item in
                    MediaCardLink(item: item, aspect: presentation.aspectRatio.cardAspect, size: presentation.cardStyle.cardSize,
                                  showsRating: presentation.showsRatings)
                }
            }
        } else {
            switch section.state {
            case .idle, .loading:
                RowPlaceholder(header: widget.hideTitle ? .none : .title(widget.title), aspect: presentation.aspectRatio.cardAspect,
                               size: presentation.cardStyle.cardSize)
            case .failed(let error):
                RowFrame(title: widget.title, hideTitle: widget.hideTitle) {
                    InlineErrorView(error.shortDescription, retry: onRetry)
                        .padding(.horizontal, Theme.screenPadding)
                }
            case .loaded:
                RowFrame(title: widget.title, hideTitle: widget.hideTitle) {
                    if let issue = section.issue {
                        IssueMessage(issue: issue)
                    } else {
                        Text("Nothing here yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.screenPadding)
                    }
                }
            }
        }
    }

    private var seeAllRequest: CatalogListRequest {
        CatalogListRequest(title: section.widget.title, sources: [row.source], presentation: row.presentation)
    }

    /// The catalog's id for an addon row, which is what UI tests look for; the widget's id for the other kinds of row.
    private var identifier: String {
        if case .addonCatalog(let reference) = row.source { return "board.row.\(reference.catalogID)" }
        return "board.row.\(section.widget.id)"
    }
}

/// A `.collection` widget: tiles that each open a grid of their sources.
struct CollectionRow: View {
    let widget: HomeWidget
    let items: [CollectionItem]

    var body: some View {
        if !items.isEmpty {
            MediaRow(widget.title, hideTitle: widget.hideTitle) {
                ForEach(items) { item in
                    NavigationLink(value: CatalogListRequest(title: item.title, sources: item.sources, presentation: WidgetPresentation())) {
                        CollectionTile(title: item.title, imageURL: item.imageURL, aspect: item.imageAspect.cardAspect, hideTitle: item.hideTitle)
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
            .accessibilityIdentifier("board.row.\(widget.id)")
        }
    }
}

/// The titles to resume, as wide cards with their progress. Each opens its streams, where the player resumes.
struct ContinueWatchingRow: View {
    let items: [WatchProgress]

    var body: some View {
        if !items.isEmpty {
            MediaRow("Continue Watching") {
                ForEach(items) { item in
                    NavigationLink(value: LibraryViewModel.request(for: item)) {
                        ProgressCard(title: item.title, subtitle: Self.remaining(item), artwork: item.poster, fraction: item.fraction)
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityIdentifier("board.continue.\(item.id)")
                }
            }
            .accessibilityIdentifier("board.continueWatching")
        }
    }

    /// "S2 E5 · 52 min left", or "Almost done" under a minute. nil when the runtime is unknown.
    static func remaining(_ item: WatchProgress) -> String? {
        guard item.duration > 0 else { return nil }
        let left = item.duration - item.position
        let timeLeft: String
        if left < 60 {
            timeLeft = "Almost done"
        } else {
            let minutes = Int(left / 60)
            timeLeft = minutes >= 60
                ? (minutes % 60 == 0 ? "\(minutes / 60) h left" : "\(minutes / 60) h \(minutes % 60) min left")
                : "\(minutes) min left"
        }
        guard let season = item.season, let episode = item.episode else { return timeLeft }
        return "S\(season) E\(episode) · \(timeLeft)"
    }
}

/// The grey stand-in for a row while its items load: the header (or a bar where the title will be), then card shapes of the
/// size and height a real card has, so the rows below do not move when the row fills in.
struct RowPlaceholder: View {
    enum Header {
        case title(String)
        /// A grey bar of a title's height, for a loading screen that does not know the row's name yet.
        case bar
        case none
    }

    let header: Header
    let aspect: CardAspect
    let size: CardSize

    var body: some View {
        let width = size.width(for: aspect)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            switch header {
            case .title(let title):
                SectionHeader(title).padding(.horizontal, Theme.screenPadding)
            case .bar:
                Capsule()
                    .fill(Theme.surfaceStrong)
                    .frame(width: 150, height: 20)
                    .padding(.horizontal, Theme.screenPadding)
            case .none:
                EmptyView()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.cardSpacing) {
                    ForEach(0..<6, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            RoundedRectangle(cornerRadius: aspect.cornerRadius, style: .continuous)
                                .fill(Theme.surfaceStrong)
                                .frame(width: width, height: width / aspect.ratio)
                            VStack(alignment: .leading, spacing: 4) {
                                Capsule().fill(Theme.surfaceStrong).frame(width: width * 0.75, height: 10)
                                Capsule().fill(Theme.surfaceStrong).frame(width: width * 0.4, height: 8)
                            }
                            .frame(height: 34, alignment: .top)
                        }
                    }
                }
                .shimmering()
            }
            .scrollDisabled(true)
            .contentMargins(.horizontal, Theme.screenPadding, for: .scrollContent)
            .scrollClipDisabled()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// A row's header over whatever stands in for its cards: a message, a retry or nothing to show.
private struct RowFrame<Content: View>: View {
    let title: String
    let hideTitle: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if !hideTitle {
                SectionHeader(title).padding(.horizontal, Theme.screenPadding)
            }
            content()
        }
    }
}

/// Why a row has no items, in one plain sentence. Names no addon, host or catalog: the row's title already says what it is.
struct IssueMessage: View {
    let issue: WidgetSourceError
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if issue == .needsTraktClientID {
                Button("Open Settings") { router.showSettings() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .accessibilityIdentifier("home.openSettings")
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `WidgetSourceError.message` names the host of a missing addon, which Home never shows.
    private var text: String {
        if case .addonMissing = issue { return "The addon for this row isn't installed or is turned off." }
        return issue.message
    }
}
#endif
