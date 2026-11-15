#if canImport(UIKit)
import StremioKit
import SwiftUI
import UIKit

// MARK: - Spines

/// `RowLayout.spines`: posters standing side by side like books on a shelf, each showing a slice of its cover as a spine with its name
/// running up it. A tap opens a spine out to its whole cover, and a tap on the open cover opens the title. The first starts open.
struct SpinesLayout: View {
    let items: [MetaPreview]
    let showsRating: Bool
    @State private var openID: String?
    @Environment(\.layoutMetrics) private var metrics

    static func coverWidth(_ metrics: LayoutMetrics) -> CGFloat { (metrics.posterWidth * 1.15).rounded() }
    static func height(_ metrics: LayoutMetrics) -> CGFloat { (coverWidth(metrics) * 1.5).rounded() }
    static func spineWidth(_ metrics: LayoutMetrics) -> CGFloat { max(36, (metrics.posterWidth * 0.32).rounded()) }

    var body: some View {
        let open = openID ?? items.first?.identity
        let coverWidth = Self.coverWidth(metrics)
        let spineWidth = Self.spineWidth(metrics)
        let height = Self.height(metrics)
        ScrollViewReader { proxy in
            ShelfScroll(margin: metrics.pageMargin, spacing: max(3, (metrics.cardSpacing * 0.4).rounded())) {
                ForEach(items, id: \.identity) { item in
                    SpineCard(item: item, isOpen: item.identity == open, coverWidth: coverWidth, spineWidth: spineWidth, height: height,
                              showsRating: showsRating) {
                        Haptics.play(.choices)
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { openID = item.identity }
                    }
                    // Opening a spine redraws only it and the one that closes.
                    .equatable()
                    .reportsShelfEdge(id: item.identity)
                }
            }
            // Brings a cover that opened out past the screen's edge fully into view.
            .onChange(of: openID) { _, id in
                guard let id else { return }
                withAnimation(.snappy(duration: 0.4)) { proxy.scrollTo(id) }
            }
        }
    }
}

private struct SpineCard: View, Equatable {
    let item: MetaPreview
    let isOpen: Bool
    let coverWidth: CGFloat
    let spineWidth: CGFloat
    let height: CGFloat
    let showsRating: Bool
    let onOpenOut: () -> Void
    @Environment(AppRouter.self) private var router
    @Environment(\.zoomScope) private var zoomScope
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.layoutMetrics) private var metrics

    /// `onOpenOut` is left out: it only ever opens this card's own title.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.item == rhs.item && lhs.isOpen == rhs.isOpen && lhs.coverWidth == rhs.coverWidth && lhs.spineWidth == rhs.spineWidth
                && lhs.height == rhs.height && lhs.showsRating == rhs.showsRating
        }
    }

    private var sourceID: String { "\(zoomScope)/\(item.identity)" }

    var body: some View {
        let radius = isOpen ? Theme.Radius.poster : Theme.Radius.poster * 0.45
        Button {
            if isOpen { openTitle() } else { onOpenOut() }
        } label: {
            // The whole cover is always drawn; the spine is its middle, cut to the spine's width.
            LayoutPoster(item: item, width: coverWidth, height: height)
                .frame(width: isOpen ? coverWidth : spineWidth, height: height)
                .clipped()
                .overlay { spineFace.opacity(isOpen ? 0 : 1) }
                .overlay(alignment: .bottom) {
                    if isOpen && showsRating { PosterRatingsOverlay(item: item).transition(.opacity) }
                }
                .contentShape(Rectangle())
                .mediaArtwork(cornerRadius: radius)
                .zoomSource(id: sourceID, in: zoomNamespace, cornerRadius: radius * metrics.cornerScale(for: .artwork))
        }
        .buttonStyle(PressableCardStyle.poster)
        .prewarmsHeroArtwork(item)
        .help(item.name)
        .titleCardMenu(item)
        .accessibilityLabel(item.name)
        // VoiceOver opens the title straight away, open or not.
        .accessibilityAction(.default) { openTitle() }
    }

    /// The spine: shaded like a rounded back, with a pair of rules near each end and the name running up it, the year at its head.
    private var spineFace: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: .black.opacity(0.7), location: 0),
                .init(color: .black.opacity(0.3), location: 0.28),
                .init(color: .white.opacity(0.06), location: 0.45),
                .init(color: .black.opacity(0.32), location: 0.72),
                .init(color: .black.opacity(0.74), location: 1),
            ], startPoint: .leading, endPoint: .trailing)
            VStack {
                rules
                Spacer()
                rules
            }
            .padding(.vertical, 12)
            HStack(spacing: Theme.Spacing.s) {
                Text(item.name)
                    .appFont(.caption, weight: .bold, role: .interface)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                if let year = item.releaseInfo, !year.isEmpty {
                    Text(year)
                        .appFont(.microStrong)
                        .foregroundStyle(Theme.dimText)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
            .frame(width: max(0, height - 52))
            .rotationEffect(.degrees(-90))
        }
        .frame(width: spineWidth, height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var rules: some View {
        VStack(spacing: 3) {
            Rectangle().frame(height: 1)
            Rectangle().frame(height: 1)
        }
        .foregroundStyle(.white.opacity(0.35))
        .padding(.horizontal, 6)
    }

    private func openTitle() {
        Haptics.play(.titles)
        router.homePath.append(TitleDestination(preview: item, sourceID: sourceID))
    }
}
#endif
