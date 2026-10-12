#if canImport(UIKit)
import SwiftUI
import StremioKit

/// One stream as a card, in the title page's design: a "Best match" label for the stream Auto Pick recommends, small badges for sharpness,
/// REMUX and source, the release name in up to two lines, one grey line of facts (size, codec, audio), and a note when the stream opens
/// elsewhere or Blusion cannot play it. A round mark at the trailing edge says what a tap does. The technical details fold away in a
/// section of their own, so tapping the card always plays.
struct StreamRow: View {
    let item: RankedStream
    /// True for the stream Auto Pick recommends, shown with a "Best match" label.
    var isBest = false
    /// True when the release name says REMUX. Found in the name, the same way Auto Pick finds it.
    var isRemux = false

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if isBest {
                    Label("Best match", systemImage: "sparkles")
                        .font(Theme.Typography.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .accessibilityIdentifier("stream.bestMatch")
                }
                if hasBadges {
                    HStack(spacing: Theme.Spacing.xs) {
                        if let label = item.quality.resolutionLabel {
                            QualityBadge.resolution(label, is4K: (item.quality.resolution ?? 0) >= 2160)
                        }
                        if item.quality.isHDR || item.quality.isDolbyVision { QualityBadge.hdr(dolbyVision: item.quality.isDolbyVision) }
                        if isRemux { QualityBadge.remux }
                        if let source = item.quality.source { QualityBadge.source(source) }
                    }
                }
                Text(Self.headline(for: item))
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !facts.isEmpty {
                    Text(facts)
                        .font(Theme.Typography.metaLine)
                        .foregroundStyle(Theme.metaText)
                        .lineLimit(1)
                }
                if let routeNote {
                    Label(routeNote.text, systemImage: routeNote.symbol)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(routeNote.isWarning ? Color.orange : Color.white.opacity(0.62))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            routeGlyph
        }
        .padding(Theme.Spacing.l)
        .contentShape(Rectangle())
        .help(item.route.handoffTarget.map { "Play in \($0.player.displayName)" } ?? "Choose this stream")
    }

    /// Whether any badge applies, so the badge row is left out for a stream with none and takes no spacing.
    private var hasBadges: Bool {
        item.quality.resolutionLabel != nil || item.quality.isHDR || item.quality.isDolbyVision || isRemux || item.quality.source != nil
    }

    /// Keep the release name, not the badges' resolution/HDR: the file name when the addon gives one, else the name of the file it links to.
    /// The technical details use it too, to avoid repeating the description's first line when that is the headline.
    static func headline(for item: RankedStream) -> String {
        if let filename = item.stream.behaviorHints.filename?.trimmingCharacters(in: .whitespacesAndNewlines), !filename.isEmpty {
            return (filename as NSString).lastPathComponent
        }
        if case .direct(let url) = item.stream.source, !url.pathExtension.isEmpty {
            return url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        }
        return item.stream.description?.split(whereSeparator: \.isNewline).first.map(String.init) ?? item.title
    }

    /// The grey line of facts: "38.2 GB · HEVC · Atmos TrueHD". The parts the stream does not give are left out.
    private var facts: String {
        var parts: [String] = []
        if let size = item.quality.sizeBytes { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        if let codec = item.quality.videoCodec { parts.append(codec.label) }
        if let audio = audioText { parts.append(audio) }
        return parts.joined(separator: " · ")
    }

    /// The audio as the release names it. Lossless Atmos (TrueHD) and streaming Atmos (DD+) each read as one name, and the codec they
    /// already name is left out of it. Otherwise "Atmos" when the marker is there, and the first audio codec the release names.
    private var audioText: String? {
        switch item.quality.atmosFormat {
        case .lossless: return "Atmos TrueHD"
        case .streaming: return "Atmos DD+"
        case nil:
            let parts = [item.quality.hasAtmos ? "Atmos" : nil, item.quality.audioCodecs.first?.label].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
    }

    /// The round mark at the trailing edge: it shows what a tap does with this stream. It is not a control of its own, so it is hidden
    /// from VoiceOver, which reads the card's hint instead.
    private var routeGlyph: some View {
        Image(systemName: routeMark.symbol)
            .font(.footnote.weight(.bold))
            .foregroundStyle(routeMark.tint)
            .frame(width: 36, height: 36)
            .background(Theme.surfaceStrong, in: Circle())
            .accessibilityHidden(true)
    }

    private var routeMark: (symbol: String, tint: Color) {
        switch item.route {
        case .native, .fallback, .hidden: ("play.fill", .white)
        case .handoff, .external: ("arrow.up.forward", .white)
        case .unsupported: ("exclamationmark.triangle.fill", .orange)
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

/// The card's own section for the technical details: every fact the addon and the file name give (seeders, size, hash, trackers and the rest,
/// see `StreamFacts`), then the addon's description. Folded away until asked for, so the list stays about choosing.
struct StreamTechnicalDetails: View {
    let item: RankedStream
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1)
                .padding(.horizontal, Theme.Spacing.l)
                .accessibilityHidden(true)
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("Technical details")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.m)
                .contentShape(Rectangle())
                .pointerInteraction(cornerRadius: Theme.Radius.surface)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("stream.details.\(item.title)")
            if isExpanded, !facts.isEmpty || description != nil {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    if !facts.isEmpty { factGrid }
                    if let description {
                        Text(description)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.l)
                .transition(.opacity)
            }
        }
    }

    private var facts: [StreamFacts.Fact] { StreamFacts(item).rows }

    /// Label in grey, value beside it. Hashes are monospaced so they can be read and selected.
    private var factGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.m, verticalSpacing: Theme.Spacing.xs) {
            ForEach(facts, id: \.label) { fact in
                GridRow(alignment: .firstTextBaseline) {
                    Text(fact.label)
                        .foregroundStyle(.secondary)
                    Text(fact.value)
                        .font(fact.isIdentifier ? .footnote.monospaced() : .footnote)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// The addon's description. Its first line goes when it is the headline already shown above the details.
    private var description: String? {
        guard let text = item.stream.description, !text.isEmpty else { return nil }
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let rest = lines.first.map(String.init) == StreamRow.headline(for: item) ? lines.dropFirst() : lines[...]
        let kept = rest.joined(separator: "\n")
        return kept.isEmpty ? nil : kept
    }
}

/// Grey stand-ins for stream cards while the first answers are on their way, so the screen has its shape at once.
struct StreamRowsSkeleton: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.Radius.surface, style: .continuous)
                    .fill(Theme.surface)
                    .frame(height: 132)
            }
        }
        .shimmering()
        .accessibilityHidden(true)
    }
}
#endif
