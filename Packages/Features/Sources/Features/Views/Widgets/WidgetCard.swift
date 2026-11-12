#if canImport(UIKit)
import os
import StremioKit
import SwiftUI
import UIKit
// The second-finger scroll sets its own recognizer state, which only this part of UIKit allows.
// swiftlint:disable:next duplicate_imports
import UIKit.UIGestureRecognizerSubclass

/// A widget as a card: a 2x2 collage of its own posters under a dark gradient, its name and style, and a delete button. Tapping the card
/// opens the widget's settings, where every setting of it is.
struct WidgetCard: View {
    @Environment(\.layoutMetrics) private var metrics
    let widget: HomeWidget
    let services: AppServices
    /// Nil for Continue Watching, which has no delete button: Home always shows it.
    let onDelete: (() -> Void)?
    /// Puts a copy straight after this card. Nil for Continue Watching and the showcase, which are one of a kind.
    let onDuplicate: (() -> Void)?
    /// The posters the card shows, read when the card first appears.
    @State private var items: [MetaPreview] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            collage
            LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0.35), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 4) {
                Text(widget.title.isEmpty ? "Untitled" : widget.title)
                    .font(.system(size: Self.titleSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(styleName)
                    .font(Theme.Typography.large)
                    .foregroundStyle(Theme.dimmerText)
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28 * metrics.cornerScale(for: .panels), style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            // Duplicate sits before Delete, the same size, so the card's two buttons read as one pair.
            HStack(spacing: 8) {
                if let onDuplicate {
                    Button(action: onDuplicate) {
                        Image(systemName: "plus.square.on.square")
                            .font(.system(size: Self.trashSize * 0.39, weight: .semibold))
                            .frame(width: Self.trashSize, height: Self.trashSize)
                    }
                    .buttonStyle(.hoverGlass)
                    .buttonBorderShape(metrics.includesCircularButtons ? .roundedRectangle(radius: 22 * metrics.circularButtonScale(for: .actionButtons)) : .circle)
                    .accessibilityLabel("Duplicate \(widget.title)")
                    .accessibilityIdentifier("widgets.menu.duplicate.\(widget.id)")
                }
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: Self.trashSize * 0.39, weight: .semibold))
                            .frame(width: Self.trashSize, height: Self.trashSize)
                    }
                    .buttonStyle(.hoverGlass)
                    .buttonBorderShape(metrics.includesCircularButtons ? .roundedRectangle(radius: 22 * metrics.circularButtonScale(for: .actionButtons)) : .circle)
                    .accessibilityLabel("Delete \(widget.title)")
                    .accessibilityIdentifier("widgets.menu.delete.\(widget.id)")
                }
            }
            .padding(12)
        }
        #if targetEnvironment(macCatalyst)
        // A right click on the Mac. iPhone has no menu here: its long press lifts the card, and a menu under the finger with Delete in it
        // was one slide away from removing the card.
        .contextMenu {
            if let onDuplicate {
                Button(action: onDuplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            }
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("widgets.row.\(widget.id)")
        .task(id: widget.id) { await loadItems() }
    }

    /// The name's size, and the delete button's: a little smaller on the Mac, where the cards are.
    private static var titleSize: CGFloat {
        #if targetEnvironment(macCatalyst)
        20
        #else
        30
        #endif
    }

    private static var trashSize: CGFloat {
        #if targetEnvironment(macCatalyst)
        36
        #else
        44
        #endif
    }

    /// Two rows of two with a thin gap: the top row the widget's backdrops, the bottom row its posters. Empty tiles stay the card's colour.
    private var collage: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 2
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    tile(0, backdrop: true)
                    tile(1, backdrop: true)
                }
                HStack(spacing: gap) {
                    tile(2, backdrop: false)
                    tile(3, backdrop: false)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(white: 0.14))
    }

    /// The first four tiles of a collection, which its card shows as pictures.
    private var collectionTiles: [CollectionItem] {
        guard case .collection(let tiles) = widget.content else { return [] }
        return Array(tiles.prefix(4))
    }

    /// One picture of the collage, small enough to load quickly. A backdrop falls back to the poster when the title has none. A streaming
    /// service's tile in a collection shows the service's logo.
    @ViewBuilder
    private func tile(_ index: Int, backdrop: Bool) -> some View {
        if collectionTiles.indices.contains(index), let provider = StreamProvider(tileTitle: collectionTiles[index].title) {
            StreamProviderTile(provider: provider)
        } else {
            let item = items.indices.contains(index) ? items[index] : nil
            let url = item.flatMap { backdrop ? ($0.background ?? $0.poster) : $0.poster }
            ArtworkImage(url: url, title: item?.name ?? "", maxPixelSize: 300, contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }

    /// The widget's style, as its editor names it.
    private var styleName: String {
        switch widget.content {
        case .hero: "Showcase"
        case .banner: "Carousel"
        case .row(let row): row.layout.map { WidgetStyle($0).rawValue } ?? (row.presentation.showsRank ? "Row Numbered" : "Row Classic")
        case .collection: "Collection"
        case .continueWatching: "Continue Watching"
        case .blusionTV: "Blusion TV"
        case .unsupported: "Unsupported"
        }
    }

    /// The posters a row or banner shows, from the copy Home keeps when there is one, else a short fetch from the same source. Continue
    /// Watching shows its newest four titles, from the progress saved on this device (Trakt's paused titles are kept there too).
    private func loadItems() async {
        if case .continueWatching = widget.content {
            items = ContinueWatchingEntry.cardItems(from: ContinueWatchingEntry.merge(local: await services.progress.all(), remote: []))
            return
        }
        // Blusion TV shows the first shows of its channels.
        if case .blusionTV = widget.content {
            items = Array(BlusionTVModel.shared(services: services).allChannels.flatMap(\.shows).prefix(4))
            return
        }
        guard let row = rowConfiguration else { return }
        if let known = await services.widgetContent.lastKnownItems(for: row.source, limit: 4), !known.isEmpty {
            items = Array(known.prefix(4))
            return
        }
        if let fresh = try? await services.widgetContent.items(for: row.source, limit: 4, cacheTTL: row.cacheTTL) {
            items = Array(fresh.prefix(4))
        }
    }

    private var rowConfiguration: RowConfiguration? {
        switch widget.content {
        case .hero(let row), .banner(let row), .row(let row): row
        default: nil
        }
    }
}

/// A group of rows on the widgets page: an optional heading over rows on one rounded surface, as a settings list draws them.
struct WidgetsPageGroup<Content: View>: View {
    @Environment(\.layoutMetrics) private var metrics
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let title {
                Text(title).subheadingStyle().accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }
                .buttonStyle(.hoverPlain)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.surface * metrics.cornerScale(for: .panels), style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One row of a `WidgetsPageGroup`: a symbol, a title and an optional control at the trailing edge. The whole row takes taps.
struct WidgetsPageRow<Trailing: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let trailing: Trailing

    /// Where the title starts, which the dividers between rows line up with.
    static var textInset: CGFloat { Theme.Spacing.l + 28 + Theme.Spacing.m }

    init(_ title: String, systemImage: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .frame(width: 28)
                .foregroundStyle(.tint)
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}
#endif
