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
                ForEach(Array(items.enumerated()), id: \.element.identity) { index, item in
                    MediaCardLink(item: item, aspect: presentation.aspectRatio.cardAspect, size: presentation.cardStyle.cardSize,
                                  showsRating: presentation.showsRatings)
                        .overlay(alignment: .topLeading) {
                            if presentation.showsRank { RankBadge(position: index + 1) }
                        }
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

    var body: some View {
        RowFrame(title: widget.title, hideTitle: widget.hideTitle) {
            Text("Blusion can't show this kind of row yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.screenPadding)
        }
        .accessibilityIdentifier("board.unsupported.\(widget.id)")
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
    let items: [ContinueWatchingEntry]
    let state: HomeViewModel.ContinueState
    let retry: () -> Void
    var title = "Continue"
    var hideTitle = false
    @Environment(AppRouter.self) private var router
    @Environment(\.layoutMetrics) private var metrics
    @State private var kind = ContinueKind.all

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
                                .accessibilityLabel(message + " Retry")
                                .help(message)
                        } else if state == .disconnected {
                            Button { router.showSettings() } label: { Image(systemName: "person.crop.circle.badge.exclamationmark") }
                                .accessibilityLabel("Sign in to Trakt")
                        }
                    }
                    Spacer(minLength: 0)
                    if !items.isEmpty { ContinueKindSwitch(selection: $kind) }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.screenPadding)
            }
            if !shown.isEmpty {
                MediaRow(title, hideTitle: true) {
                    ForEach(shown) { item in
                        let artworkID = ContentID(item.request.id).baseID
                        NavigationLink(value: item.request) {
                            ProgressCard(title: item.request.title, subtitle: item.subtitle,
                                         artwork: MetahubArtwork.background(imdbID: artworkID) ?? item.request.poster,
                                         logo: MetahubArtwork.logo(imdbID: artworkID), fraction: item.fraction,
                                         duration: item.request.expectedDuration)
                        }
                        .buttonStyle(PressableCardStyle())
                        .titleTapHaptic()
                        .accessibilityIdentifier("board.continue.\(item.id)")
                    }
                }
            } else if !items.isEmpty {
                // Hold the rail's height, so switching to an empty kind does not move the page below.
                Text(kind == .all ? "Nothing in progress" : "Nothing in \(kind.title.lowercased()) in progress")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: (metrics.isRegular ? 180 : 148) / CardAspect.wide.ratio, alignment: .top)
                    .padding(.horizontal, Theme.screenPadding)
            } else {
                emptyState
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.screenPadding)
            }
        }
        .animation(.snappy(duration: 0.28), value: kind)
        .accessibilityIdentifier("board.continueWatching")
    }

    @ViewBuilder private var emptyState: some View {
        switch state {
        case .loading:
            EmptyView()
        case .disconnected:
            HStack {
                Text("Sign in to Trakt to see paused movies and episodes.")
                Spacer(minLength: 8)
                Button("Sign In") { router.showSettings() }.buttonStyle(.glass)
            }
        case .failed(let message):
            InlineErrorView(message, retry: retry)
        case .ready:
            Text("No paused movies or episodes on Trakt.")
        }
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
                                .mediaArtwork(cornerRadius: aspect.cornerRadius)
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
