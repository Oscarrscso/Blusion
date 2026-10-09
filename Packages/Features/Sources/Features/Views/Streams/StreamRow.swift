#if canImport(UIKit)
import SwiftUI
import StremioKit

/// One stream as a card. The top of it is the button that plays the stream: small badges for sharpness, REMUX and source, the release
/// name in up to two lines, and one grey line of facts (size, codec, audio). A note underneath says when the stream opens elsewhere or
/// Blusion cannot play it. The technical details fold away in a section of their own, so tapping the card always plays.
struct StreamRow: View {
    let item: RankedStream
    /// True for the stream Auto Pick recommends: a quiet "Best match" over the badges, and nothing else on the card changes.
    var isBest = false
    /// True when the release name says REMUX. Found in the name, the same way Auto Pick finds it.
    var isRemux = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs + 2) {
            HStack(spacing: Theme.Spacing.xs) {
                if let label = item.quality.resolutionLabel {
                    QualityBadge.resolution(label, is4K: (item.quality.resolution ?? 0) >= 2160)
                }
                if item.quality.isHDR || item.quality.isDolbyVision { QualityBadge.hdr(dolbyVision: item.quality.isDolbyVision) }
                if isRemux { QualityBadge.remux }
                if let source = item.quality.source { QualityBadge.source(source) }
            }
            Text(headline)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            metadataRow
            if let routeNote {
                Label(routeNote.text, systemImage: routeNote.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(routeNote.isWarning ? Color.orange : Color.white.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        .contentShape(shape)
        .help(item.route.handoffTarget.map { "Play in \($0.player.displayName)" } ?? "Choose this stream")
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous) }

    /// Keep the release name, not the badges' resolution/HDR: the file name when the addon gives one, else the name of the file it links to.
    private var headline: String {
        if let filename = item.stream.behaviorHints.filename?.trimmingCharacters(in: .whitespacesAndNewlines), !filename.isEmpty {
            return (filename as NSString).lastPathComponent
        }
        if case .direct(let url) = item.stream.source, !url.pathExtension.isEmpty {
            return url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        }
        return item.stream.description?.split(whereSeparator: \.isNewline).first.map(String.init) ?? item.title
    }

    /// Size and video codec in grey, then the audio: lossless Atmos as a small badge, lossy Atmos as text, and "Best match" at the
    /// trailing edge of the stream Auto Pick would start.
    private var metadataRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            if !sizeAndCodec.isEmpty {
                Text(sizeAndCodec)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            audio
            Spacer(minLength: 0)
            if isBest {
                Label("Best match", systemImage: "sparkles")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .accessibilityIdentifier("stream.bestMatch")
            }
        }
    }

    /// "38.2 GB · HEVC": the facts a viewer picks a stream by after its sharpness and source.
    private var sizeAndCodec: String {
        var parts: [String] = []
        if let size = item.quality.sizeBytes { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        if let codec = item.quality.videoCodec { parts.append(codec.label) }
        return parts.joined(separator: " · ")
    }

    /// The audio as tags, as the codec says it is. Lossless Atmos (TrueHD) and streaming Atmos (DD+) each get their own tag, and the codec
    /// they already name is left out of it. Otherwise the first audio codec the release names, and "Atmos" when only the marker is there.
    @ViewBuilder private var audio: some View {
        HStack(spacing: Theme.Spacing.xs) {
            switch item.quality.atmosFormat {
            case .lossless:
                QualityBadge("Atmos · TrueHD", symbol: "waveform")
            case .streaming:
                QualityBadge("Atmos · DD+", symbol: "speaker.wave.3")
            case nil:
                if item.quality.hasAtmos { QualityBadge("Atmos", symbol: "speaker.wave.3") }
                if let codec = item.quality.audioCodecs.first { QualityBadge(codec.label, symbol: "speaker.wave.2") }
            }
        }
    }

    private var routeNote: (text: String, symbol: String, isWarning: Bool)? {
        switch item.route {
        case .handoff(let player, _): ("Opens in \(player.displayName)", "arrow.up.forward.app", false)
        case .unsupported: ("Blusion can't play this yet", "exclamationmark.triangle", true)
        case .native, .fallback, .external, .hidden: nil
        }
    }
}

/// The card's own section for the technical details: the file name, the addon's description, the container and where else the stream
/// came from. Folded away until asked for, so the list stays about choosing.
struct StreamTechnicalDetails: View {
    let item: RankedStream
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.horizontal, Theme.Spacing.m)
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("Technical details")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("stream.details.\(item.title)")
            if isExpanded, !lines.isEmpty {
                Text(lines.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.s)
            }
        }
    }

    private var lines: [String] {
        [item.stream.behaviorHints.filename,
         item.container.map { "Container \($0.fileExtension.uppercased())" },
         item.stream.description,
         item.alsoProvidedBy.isEmpty ? nil : "Also from \(item.alsoProvidedBy.map(\.name).joined(separator: ", "))"]
            .compactMap { $0 }
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
        case .ac3: "DD"
        case .eac3: "DD+"
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
        VStack(spacing: Theme.Spacing.s) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.surface)
                    .frame(height: 84)
            }
        }
        .shimmering()
        .accessibilityHidden(true)
    }
}
#endif
