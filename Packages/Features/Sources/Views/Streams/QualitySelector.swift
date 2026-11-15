#if canImport(UIKit)
import StremioKit
import SwiftUI

/// The system's segmented control for media types and quality filters.
struct QualitySelector: View {
    let titles: [String]
    @Binding var selection: Int
    var symbols: [String] = []
    var showsTitles = true
    var accessibilityID = "streams.filter"

    var body: some View {
        CornerSegmentedPicker("Show", options: Array(titles.indices), selection: $selection,
                              symbols: symbols, showsTitles: showsTitles) { index in
            titles[index]
        }
        .frame(width: showsTitles ? nil : CGFloat(titles.count * 44))
        .accessibilityIdentifier(accessibilityID)
        .onChange(of: selection) { _, _ in Haptics.play(.choices) }
    }
}
#endif
