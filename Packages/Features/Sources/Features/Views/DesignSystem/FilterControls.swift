#if canImport(UIKit)
import SwiftUI

/// The label of a filter menu: a Liquid Glass capsule with a chevron, tinted when a filter in it is active. Used by the Library and
/// Discover, so their filter rows look the same.
struct FilterMenuLabel: View {
    let title: String
    let systemImage: String?
    let tint: Color
    let isActive: Bool

    init(_ title: String, systemImage: String? = nil, tint: Color = .primary, isActive: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isActive = isActive
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.caption) }
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: 44)
        .glassEffect(.regular.tint(tint.opacity(isActive ? 0.25 : 0.08)).interactive(), in: .capsule)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// One active filter shown as a removable chip. Tapping it calls `remove`.
struct ActiveFilterChip: Identifiable {
    let id: String
    let label: String
    let remove: () -> Void
}

/// The active filters as removable chips, wrapped left-aligned, with a "Clear all" chip after the last one. Each chip's identifier is
/// `<identifier>.chip.<id>`, and the clear chip's is `<identifier>.chip.clear`.
struct ActiveFilterChips: View {
    let chips: [ActiveFilterChip]
    let identifier: String
    let clearAll: () -> Void

    var body: some View {
        FlowLayout(spacing: Theme.Spacing.s) {
            ForEach(chips) { chip in
                GlassChip(chip.label, systemImage: "xmark", isCompact: true, action: chip.remove)
                    .accessibilityIdentifier("\(identifier).chip.\(chip.id)")
            }
            GlassChip("Clear all", systemImage: "xmark.circle", isCompact: true, action: clearAll)
                .accessibilityIdentifier("\(identifier).chip.clear")
        }
    }
}
#endif
