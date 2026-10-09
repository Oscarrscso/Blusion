#if canImport(UIKit)
import SwiftUI

/// The TV app's "Up Next" lockup: 16:9 artwork with a thin progress bar inside its bottom edge, and under it the title in
/// semibold footnote and a grey line such as "S2, E5 · 21 min left". `fraction` is the share watched, 0 to 1; values outside
/// that range are clamped, and 0 draws no bar. `width` defaults to the layout's wide card width.
struct ProgressCard: View {
    let title: String
    let subtitle: String?
    let artwork: URL?
    let fraction: Double
    let width: CGFloat?
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.displayScale) private var displayScale

    init(title: String, subtitle: String? = nil, artwork: URL?, fraction: Double, width: CGFloat? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.fraction = fraction
        self.width = width
    }

    var body: some View {
        let progress = min(max(fraction, 0), 1)
        let fixed = width ?? (metrics.isRegular ? 180 : 148)
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Color.clear
                .frame(width: fixed, height: fixed / CardAspect.wide.ratio)
                .overlay { ArtworkImage(url: artwork, title: title, maxPixelSize: min((fixed * displayScale).rounded(.up), 1200)) }
                .overlay(alignment: .bottom) { if progress > 0 { progressBar(progress, width: fixed) } }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.cardTitle)
                    .lineLimit(1)
                Text(subtitleLine)
                    .font(Theme.Typography.cardSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: fixed, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, subtitle, "\(Int((progress * 100).rounded())) percent watched"].compactMap { $0 }
            .filter { !$0.isEmpty }.joined(separator: ", "))
    }

    private var subtitleLine: String {
        guard let subtitle, !subtitle.isEmpty else { return " " }
        return subtitle
    }

    /// The card's width is fixed, so the fill is a plain frame: a GeometryReader per card would cost a layout pass per row item.
    /// A short fade under the bar keeps it legible on a bright still.
    private func progressBar(_ progress: Double, width: CGFloat) -> some View {
        let track = width - 2 * Theme.Spacing.m
        return ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.32))
            Capsule().fill(.white).frame(width: track * progress)
        }
        .frame(width: track, height: 3)
        .padding(.bottom, Theme.Spacing.m - 2)
        .padding(.top, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        }
    }
}
#endif
