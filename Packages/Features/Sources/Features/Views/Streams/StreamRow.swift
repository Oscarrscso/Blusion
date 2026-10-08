#if canImport(UIKit)
import SwiftUI
import StremioKit

/// One stream as a card of its own: the label of the picker's button, so the whole card is one target. A tile on the left says how
/// sharp it is, the headline says what the picture is, one grey line gives the facts a viewer picks by (size, source, codecs), and the
/// addon's own notes sit quietly underneath. The icon at the trailing edge says what a tap does: play here, open another app, or warn
/// that Blusion cannot play it.
struct StreamRow: View {
    let item: RankedStream
    /// True for the stream "Play Best" would start: it carries a small mark so the top of the list explains itself.
    var isBest = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                ResolutionTile(quality: item.quality)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        Text(headline)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if isBest { Badge("Best", style: .accent) }
                    }
                    if !facts.isEmpty {
                        Text(facts.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let routeNote {
                        Label(routeNote.text, systemImage: routeNote.symbol)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(routeNote.isWarning ? Color.orange : Color.white.opacity(0.62))
                    }
                }
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: glyph)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(glyphColor)
                    .accessibilityHidden(true)
            }
            if !detailLines.isEmpty || !item.alsoProvidedBy.isEmpty { notes }
        }
        .padding(Theme.Spacing.m + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: shape)
        .overlay { shape.strokeBorder(isBest ? Color.white.opacity(0.34) : Theme.separator, lineWidth: isBest ? 1.2 : 1) }
        .contentShape(shape)
        .help(item.route.handoffTarget.map { "Play in \($0.player.displayName)" } ?? "Choose this stream")
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.surface, style: .continuous) }

    /// What the addon wrote about the file, line by line, under a hairline: seeders, languages, the release name. Quieter than the summary
    /// above it, since it is the addon's wording and often full of its own symbols.
    private var notes: some View {
        VStack(alignment: .leading, spacing: 3) {
            Divider().overlay(Theme.separator).padding(.bottom, Theme.Spacing.xs)
            ForEach(detailLines.indices, id: \.self) { index in
                Text(detailLines[index])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if !item.alsoProvidedBy.isEmpty {
                Text("Also from \(item.alsoProvidedBy.map(\.name).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    /// "4K Dolby Vision", "1080p HDR", "720p". With nothing to say about the picture, the addon's own name for the stream.
    private var headline: String {
        var parts: [String] = []
        if let resolution = item.quality.resolutionLabel { parts.append(resolution) }
        if item.quality.isDolbyVision { parts.append("Dolby Vision") } else if item.quality.isHDR { parts.append("HDR") }
        return parts.isEmpty ? item.title : parts.joined(separator: " ")
    }

    /// The facts a viewer picks a stream by, in the order they usually decide: size, where the file came from, how it is encoded, what the
    /// sound is and what holds it.
    private var facts: [String] {
        var parts: [String] = []
        if let size = item.quality.sizeBytes { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        if let source = item.quality.source { parts.append(source.label) }
        if let codec = item.quality.videoCodec { parts.append(codec.label) }
        if let audio = item.quality.audioCodecs.first {
            parts.append(item.quality.hasAtmos ? "\(audio.label) Atmos" : audio.label)
        } else if item.quality.hasAtmos {
            parts.append("Atmos")
        }
        if let container = item.container { parts.append(container.fileExtension.uppercased()) }
        return parts
    }

    private var routeNote: (text: String, symbol: String, isWarning: Bool)? {
        switch item.route {
        case .handoff(let player, _): ("Opens in \(player.displayName)", "arrow.up.forward.app", false)
        case .unsupported: ("Blusion can't play this yet", "exclamationmark.triangle", true)
        case .native, .fallback, .external, .hidden: nil
        }
    }

    /// The addon's description, line by line as the addon wrote it: its first line is left out when that line already is the title (the addon
    /// gave no name). Three lines at most, so a long release note cannot take over the card.
    private var detailLines: [String] {
        guard let description = item.stream.description else { return [] }
        var lines = description.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if item.stream.name == nil, !lines.isEmpty { lines.removeFirst() }
        return Array(lines.prefix(3))
    }

    private var glyph: String {
        switch item.route {
        case .native, .fallback: return "play.circle.fill"
        case .handoff, .external: return "arrow.up.forward.circle.fill"
        case .unsupported: return "exclamationmark.triangle.fill"
        case .hidden: return "eye.slash.circle.fill"
        }
    }

    private var glyphColor: Color {
        switch item.route {
        case .native, .fallback: return .white
        case .handoff, .external: return .white.opacity(0.78)
        case .unsupported: return .orange
        case .hidden: return .secondary
        }
    }
}

/// The square on the left of a stream: its resolution as large type, and under it the dynamic range when there is one. Without a
/// resolution it shows a film symbol, so every card keeps the same left edge.
private struct ResolutionTile: View {
    let quality: StreamQuality

    var body: some View {
        VStack(spacing: 1) {
            if let label = quality.resolutionLabel {
                Text(label)
                    .font(.system(size: label.count <= 2 ? 21 : 16, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if let range {
                    Text(range)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                Image(systemName: "film").font(.title3.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 54, height: 54)
        .background(Theme.surfaceStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }

    private var range: String? {
        if quality.isDolbyVision { return "DV" }
        return quality.isHDR ? "HDR" : nil
    }
}

private extension StreamSourceKind {
    var label: String {
        switch self {
        case .bluray: "Blu-ray"
        case .webDL: "WEB-DL"
        case .webRip: "WEBRip"
        case .hdtv: "HDTV"
        case .dvd: "DVD"
        case .cam: "CAM"
        }
    }
}

private extension VideoCodec {
    var label: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        case .av1: "AV1"
        }
    }
}

private extension AudioCodec {
    var label: String {
        switch self {
        case .aac: "AAC"
        case .ac3: "Dolby Digital"
        case .eac3: "Dolby Digital+"
        case .dts: "DTS"
        case .dtsHD: "DTS-HD"
        case .trueHD: "TrueHD"
        case .flac: "FLAC"
        case .opus: "Opus"
        case .mp3: "MP3"
        }
    }
}

/// Grey stand-ins for stream cards while the first answers are on their way, so the screen has its shape at once.
struct StreamRowsSkeleton: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.s + 2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.Radius.surface, style: .continuous)
                    .fill(Theme.surface)
                    .frame(height: 118)
            }
        }
        .shimmering()
        .accessibilityHidden(true)
    }
}
#endif
