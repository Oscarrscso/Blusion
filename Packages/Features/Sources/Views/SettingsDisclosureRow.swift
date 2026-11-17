#if canImport(UIKit)
import SwiftUI

/// Expandable Settings controls share the navigation rows' label and trailing chevron.
struct SettingsDisclosureRow: View {
    let title: String
    let summary: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            Haptics.play(.buttons)
            isExpanded.toggle()
        } label: {
            HStack {
                SettingsRow(title: title, summary: summary)
                    .foregroundStyle(.primary)
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.forward")
                    .font(Theme.Typography.smallStrong)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}
#endif
