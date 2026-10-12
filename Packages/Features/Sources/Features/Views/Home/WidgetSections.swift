#if canImport(UIKit)
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
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        rowBody
            .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var rowBody: some View {
        let widget = section.widget
        let presentation = row.presentation
        if case .loaded(let items) = section.state, !items.isEmpty {
            WidgetGrid(widget.title, hideTitle: widget.hideTitle, aspect: presentation.aspectRatio.cardAspect,
                       size: presentation.cardStyle.cardSize, onSeeAll: { router.homePath.append(seeAllRequest) }) {
                ForEach(Array(items.enumerated()), id: \.element.identity) { index, item in
                    MediaCardLink(item: item, aspect: presentation.aspectRatio.cardAspect, size: presentation.cardStyle.cardSize,
                                  showsRating: presentation.showsRatings, usesBetterPosters: presentation.usesBetterPosters)
                        .stretched()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .topLeading) {
                            if presentation.showsRank { RankBadge(position: index + 1) }
                        }
                }
            }
        } else {
            switch section.state {
            case .idle, .loading:
                RowPlaceholder(header: widget.hideTitle ? .none : .title(widget.title), aspect: presentation.aspectRatio.cardAspect,
                               size: presentation.cardStyle.cardSize, count: row.limit)
            case .failed(let error):
                RowFrame(title: widget.title, hideTitle: widget.hideTitle) {
                    InlineErrorView(error.shortDescription, retry: onRetry)
                        .padding(.horizontal, metrics.pageMargin)
                }
            case .loaded:
                RowFrame(title: widget.title, hideTitle: widget.hideTitle) {
                    if let issue = section.issue {
                        IssueMessage(issue: issue)
                    } else {
                        Text("Nothing here yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, metrics.pageMargin)
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

/// A widget's cards as a vertical grid under its header, so Home reads as one list going down the page rather than shelves to swipe
/// across. The card size sets how many fit across: a phone shows four small, three medium or two large posters a row (one large wide
/// card), and a Mac window as many of that size as its width allows.
struct WidgetGrid<Content: View>: View {
    let title: String
    let hideTitle: Bool
    let aspect: CardAspect
    let size: CardSize
    let onSeeAll: (() -> Void)?
    let content: () -> Content
    /// Keeps the cards' zoom sources unique to this widget, so a title that two widgets share zooms out of the one tapped.
    @State private var zoomScope = UUID().uuidString
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isLandscape) private var isLandscape

    init(_ title: String, hideTitle: Bool = false, aspect: CardAspect, size: CardSize, onSeeAll: (() -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.hideTitle = hideTitle
        self.aspect = aspect
        self.size = size
        self.onSeeAll = onSeeAll
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            if !hideTitle {
                SectionHeader(title, onSeeAll: onSeeAll)
                    .padding(.horizontal, metrics.pageMargin)
            }
            LazyVGrid(columns: homeGridColumns(for: aspect, size: size, metrics: metrics, isLandscape: isLandscape),
                      alignment: .leading, spacing: metrics.cardSpacing) {
                content()
            }
            .padding(.horizontal, metrics.pageMargin)
            .environment(\.zoomScope, zoomScope)
        }
    }
}

/// The columns of a Home widget's grid. A phone fits four small, three medium or two large posters across (one fewer of each wide card),
/// and a Mac window fits as many cards of the chosen size as its width allows. A poster in landscape is drawn wide, so it takes the
/// landscape columns.
private func homeGridColumns(for aspect: CardAspect, size: CardSize, metrics: LayoutMetrics, isLandscape: Bool) -> [GridItem] {
    if isLandscape && aspect == .poster { return metrics.gridColumns(for: aspect, inLandscape: true) }
    if metrics.isRegular {
        let width = size.width(for: aspect, metrics: metrics)
        return [GridItem(.adaptive(minimum: width, maximum: width * 1.25), spacing: metrics.cardSpacing, alignment: .top)]
    }
    let wide = aspect == .wide
    let across = switch size {
    case .small: wide ? 3 : 4
    case .medium: wide ? 2 : 3
    case .large: wide ? 1 : 2
    }
    return Array(repeating: GridItem(.flexible(), spacing: metrics.cardSpacing, alignment: .top), count: across)
}

/// The position of a card in a numbered row, drawn over the card's top-left corner.
struct RankBadge: View {
    let position: Int

    var body: some View {
        Text("\(position)")
            .font(.system(size: 44, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 2)
            .padding(.leading, 6)
            .padding(.top, 2)
            .allowsHitTesting(false)
            .accessibilityLabel("Number \(position)")
            .accessibilityIdentifier("board.rank.\(position)")
    }
}

/// A `.unsupported` widget: a Fusion row type this version cannot show. Kept in the layout, with its title and a plain message.
struct UnsupportedWidgetRow: View {
    let widget: HomeWidget
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        RowFrame(title: widget.title, hideTitle: widget.hideTitle) {
            Text("Blusion can't show this kind of row yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, metrics.pageMargin)
        }
        .accessibilityIdentifier("board.unsupported.\(widget.id)")
    }
}

/// A `.collection` widget: tiles that each open a grid of their sources.
struct CollectionRow: View {
    let widget: HomeWidget
    let items: [CollectionItem]
    @Environment(AppRouter.self) private var router

    var body: some View {
        if !items.isEmpty {
            // The genre shelf's header opens the Search tab's category browser, which lists the same genres.
            WidgetGrid(widget.title, hideTitle: widget.hideTitle, aspect: items.first?.imageAspect.cardAspect ?? .wide, size: .medium,
                       onSeeAll: widget.id == "auto.genres" ? { router.showSearchBrowse() } : nil) {
                ForEach(items) { item in
                    NavigationLink(value: CatalogListRequest(title: item.title, sources: item.sources, presentation: WidgetPresentation())) {
                        CollectionTile(title: item.title, imageURL: item.imageURL, aspect: item.imageAspect.cardAspect, hideTitle: item.hideTitle)
                            .stretched()
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
    let items: [ContinueWatchingEntry]
    let state: HomeViewModel.ContinueState
    let retry: () -> Void
    let onRemove: (ContinueWatchingEntry) -> Void
    var title = "Continue"
    var hideTitle = false
    @Environment(AppRouter.self) private var router
    @Environment(\.layoutMetrics) private var metrics
    @State private var kind = ContinueKind.all
    /// The width of the page the row sits in, read once the page has laid out, so each card can span it between the margins.
    @State private var rowWidth: CGFloat = 0

    var body: some View {
        let shown = items.filter { kind.includes($0.request) }
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if !hideTitle {
                HStack(spacing: Theme.Spacing.s) {
                    Text(title)
                        .font(Theme.Typography.shelfTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .layoutPriority(1)
                        .accessibilityAddTraits(.isHeader)
                    // The kind selector sits right beside the title, as the chevron does after a row title.
                    if !items.isEmpty { ContinueKindSwitch(selection: $kind) }
                    ProgressView()
                        .controlSize(.small)
                        .tint(.gray)
                        .scaleEffect(0.75)
                        .opacity(state == .loading ? 1 : 0)
                        .accessibilityLabel("Refreshing Continue")
                        .accessibilityHidden(state != .loading)
                    if !items.isEmpty {
                        if case .failed(let message) = state {
                            Button(action: retry) { Image(systemName: "arrow.clockwise") }
                                .glassCircleButton(.small)
                                .accessibilityLabel(message + " Retry")
                                .help(message)
                        } else if state == .disconnected {
                            Button { router.showSettings() } label: { Image(systemName: "person.crop.circle.badge.exclamationmark") }
                                .glassCircleButton(.small)
                                .accessibilityLabel("Sign in to Trakt")
                        }
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, metrics.pageMargin)
            }
            if !shown.isEmpty {
                // One card under another, each spanning the page between its margins.
                LazyVStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    ForEach(shown) { item in
                        let artworkID = ContentID(item.request.id).baseID
                        ProgressCard(title: item.request.title, subtitle: item.subtitle,
                                     artwork: MetahubArtwork.background(imdbID: artworkID) ?? item.request.poster,
                                     logo: MetahubArtwork.logo(imdbID: artworkID), fraction: item.fraction,
                                     duration: item.request.expectedDuration, width: cardWidth)
                        .continueWatchingHold(preview: MetaPreview(id: artworkID, type: item.request.type,
                                                                  name: item.request.seriesName ?? item.request.title,
                                                                  poster: item.request.poster, releaseInfo: item.request.year),
                                              request: item.request, onRemove: { onRemove(item) })
                        .id(item.id)
                        .accessibilityIdentifier("board.continue.\(item.id)")
                    }
                }
                .padding(.horizontal, metrics.pageMargin)
            } else if !items.isEmpty {
                // Hold the list's height, so switching to an empty kind does not move the page below.
                Text(kind == .all ? "Nothing in progress" : "Nothing in \(kind.title.lowercased()) in progress")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: metrics.continueCardWidth / CardAspect.wide.ratio, alignment: .top)
                    .padding(.horizontal, metrics.pageMargin)
            } else {
                emptyState
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, metrics.pageMargin)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .animation(.snappy(duration: 0.28), value: kind)
        .accessibilityIdentifier("board.continueWatching")
    }

    /// A card's width: the page's width between its margins. Until the page has been measured, a card keeps the phone's Continue width.
    private var cardWidth: CGFloat? {
        rowWidth > 0 ? rowWidth - 2 * metrics.pageMargin : nil
    }

    @ViewBuilder private var emptyState: some View {
        switch state {
        case .loading:
            EmptyView()
        case .disconnected:
            HStack {
                Text("Sign in to Trakt to see paused movies and episodes.")
                Spacer(minLength: 8)
                Button("Sign In") { router.showSettings() }.buttonStyle(.glass).pointerFeedback()
            }
        case .failed(let message):
            InlineErrorView(message, retry: retry)
        case .ready:
            Text("No paused movies or episodes on Trakt.")
        }
    }
}

/// The grey stand-in for a row while its items load: the header (or a bar where the title will be), then a grid of card shapes in the
/// columns a loaded widget uses, one for each card it will show (`count`), so the page keeps its height when the row fills in.
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
    let count: Int
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isLandscape) private var isLandscape

    var body: some View {
        let landscape = isLandscape && aspect == .poster
        let displayedAspect: CardAspect = landscape ? .wide : aspect
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            switch header {
            case .title(let title):
                SectionHeader(title).padding(.horizontal, metrics.pageMargin)
            case .bar:
                Capsule()
                    .fill(Theme.surfaceStrong)
                    .frame(width: 150, height: 20)
                    .padding(.horizontal, metrics.pageMargin)
            case .none:
                EmptyView()
            }
            LazyVGrid(columns: homeGridColumns(for: aspect, size: size, metrics: metrics, isLandscape: isLandscape),
                      alignment: .leading, spacing: metrics.cardSpacing) {
                ForEach(0..<count, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        RoundedRectangle(cornerRadius: displayedAspect.cornerRadius, style: .continuous)
                            .fill(Theme.surfaceStrong)
                            .aspectRatio(displayedAspect.ratio, contentMode: .fit)
                            .mediaArtwork(cornerRadius: displayedAspect.cornerRadius)
                        if !landscape {
                            VStack(alignment: .leading, spacing: 4) {
                                Capsule().fill(Theme.surfaceStrong).frame(height: 10).padding(.trailing, 40)
                                Capsule().fill(Theme.surfaceStrong).frame(height: 8).padding(.trailing, 90)
                            }
                            .frame(height: 34, alignment: .top)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, metrics.pageMargin)
            .shimmering()
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
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if !hideTitle {
                SectionHeader(title).padding(.horizontal, metrics.pageMargin)
            }
            content()
        }
    }
}

/// Why a row has no items, in one plain sentence. Names no addon, host or catalog: the row's title already says what it is.
struct IssueMessage: View {
    let issue: WidgetSourceError
    @Environment(AppRouter.self) private var router
    @Environment(\.layoutMetrics) private var metrics

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
                    .pointerFeedback()
                    .accessibilityIdentifier("home.openSettings")
            }
        }
        .padding(.horizontal, metrics.pageMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `WidgetSourceError.message` names the host of a missing addon, which Home never shows.
    private var text: String {
        if case .addonMissing = issue { return "The addon for this row isn't installed or is turned off." }
        return issue.message
    }
}
#endif
