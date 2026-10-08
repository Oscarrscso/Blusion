#if canImport(UIKit)
import SwiftUI
import StremioKit

/// One stream as a row on its own surface: the label of the picker's button, so the whole row is one target. The icon at the trailing
/// edge says what a tap does: play here, open another app, or warn that Blusion cannot play it.
struct StreamRow: View {
    let item: RankedStream

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(item.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                badges
                if !detailLines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(detailLines.indices, id: \.self) { index in
                            Text(detailLines[index])
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                if !item.alsoProvidedBy.isEmpty {
                    Text("Also from \(item.alsoProvidedBy.map(\.name).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Spacing.s)
            Image(systemName: glyph)
                .font(.title3)
                .foregroundStyle(glyphColor)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .cardSurface()
    }

    /// The facts a viewer picks a stream by, as small badges: the other player, resolution, HDR, size and container. They sit in a row
    /// when they fit and stack when Dynamic Type takes the room.
    private var badges: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xs) { badgeViews }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) { badgeViews }
        }
    }

    @ViewBuilder
    private var badgeViews: some View {
        if let target = item.route.handoffTarget {
            Badge(target.player.displayName)
        }
        if let resolution = item.quality.resolutionLabel {
            Badge(resolution, style: .quality)
        }
        if item.quality.isDolbyVision {
            Badge("Dolby Vision")
        } else if item.quality.isHDR {
            Badge("HDR")
        }
        if let size = item.quality.sizeBytes {
            Badge(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let container = item.container {
            Badge(container.fileExtension.uppercased())
        }
    }

    /// The addon's description, line by line as the addon wrote it: its first line is left out when that line already is the title (the addon
    /// gave no name). Six lines at most, so a long release note cannot take over the row.
    private var detailLines: [String] {
        guard let description = item.stream.description else { return [] }
        var lines = description.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if item.stream.name == nil, !lines.isEmpty { lines.removeFirst() }
        return Array(lines.prefix(6))
    }

    private var glyph: String {
        switch item.route {
        case .native, .fallback: return "play.circle.fill"
        case .handoff, .external: return "arrow.up.forward.app"
        case .unsupported: return "exclamationmark.triangle"
        case .hidden: return "eye.slash"
        }
    }

    private var glyphColor: Color {
        switch item.route {
        case .native, .fallback: return .accentColor
        case .handoff, .external, .unsupported, .hidden: return .secondary
        }
    }
}

/// Grey stand-ins for stream rows while the first answers are on their way, so the screen has its shape at once.
struct StreamRowsSkeleton: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.surface)
                    .frame(height: 96)
            }
        }
        .shimmering()
        .accessibilityHidden(true)
    }
}
#endif
