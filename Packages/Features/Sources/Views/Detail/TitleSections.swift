#if canImport(UIKit)
import SwiftUI

/// The line between a title page's sections, inset by the page's margin: Home's shelf line, or the title pages' own (Appearance →
/// Title Pages). Turned off it keeps its place, so the sections stay as far apart.
struct TitleSectionLine: View {
    let contentMargin: CGFloat
    @Environment(\.appAppearance) private var appearance

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(appearance.effectiveShowsTitleDividers ? appearance.effectiveTitleDividerOpacity : 0))
            .frame(height: appearance.effectiveTitleDividerThickness)
            .padding(.horizontal, appearance.effectiveTitleDividerFullWidth ? 0 : contentMargin)
            .accessibilityHidden(true)
    }
}

/// A title page's sections, one under another, with a faint line between each two. The line sits `titleRatingsGap` from the section on
/// each side, as the one under the ratings does. Only the sections that show count, so a hidden one leaves no line behind.
struct TitleSections<Content: View>: View {
    let contentMargin: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { sections in
                ForEach(sections) { section in
                    if section.id != sections.first?.id {
                        TitleSectionLine(contentMargin: contentMargin)
                            .padding(.vertical, metrics.titleRatingsGap)
                    }
                    section
                }
            }
        }
    }
}
#endif
