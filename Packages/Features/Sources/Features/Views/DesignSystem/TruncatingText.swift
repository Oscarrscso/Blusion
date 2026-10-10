#if canImport(UIKit)
import SwiftUI

/// Text cut off after `lineLimit` lines that says whether anything was cut, so a "More" button shows only when there is more to
/// read. The whole text is laid out behind it, unseen, at the same width: when that is taller than the cut text, some is hidden.
/// Expanded, the two are the same height, so the answer from the cut state stands.
///
/// With `reservesSpace` the cut text always takes `lineLimit` lines, so cards holding texts of different lengths share a height.
/// Font and colour come from the environment, so set them on this view.
struct TruncatingText: View {
    let text: Text
    let lineLimit: Int
    var reservesSpace = false
    let isExpanded: Bool
    @Binding var isTruncated: Bool
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    var body: some View {
        // One modifier for both states, so opening and folding animate as a change of height. Expanded, the limit is out of reach.
        text
            .lineLimit(isExpanded ? 10_000 : lineLimit, reservesSpace: reservesSpace && !isExpanded)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
            .background(alignment: .top) {
                text
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
            }
            .onChange(of: shownHeight) { measure() }
            .onChange(of: fullHeight) { measure() }
    }

    private func measure() {
        guard !isExpanded, shownHeight > 0, fullHeight > 0 else { return }
        let truncated = fullHeight > shownHeight + 1
        if truncated != isTruncated { isTruncated = truncated }
    }
}
/// The round glass button under a text that folds: a chevron that opens it and, turned over, folds it again.
struct FoldButton: View {
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .fontWeight(.semibold)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .glassCircleButton(.small)
        .accessibilityLabel(isExpanded ? "Less" : "More")
    }
}
#endif
