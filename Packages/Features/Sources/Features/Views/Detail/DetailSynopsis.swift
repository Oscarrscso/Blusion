#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// The synopsis, folded to `foldedLines` lines (three unless a page gives more) when it runs past them. A tap on the text opens it or folds it
/// again. Its state belongs to the page, so it survives a rotation.
struct DetailSynopsis: View {
    let description: String?
    @Binding var isExpanded: Bool
    @Binding var isTruncated: Bool
    /// How many lines the synopsis shows while folded.
    var foldedLines = 3

    @ViewBuilder
    var body: some View {
        if let description = description, !description.isEmpty {
            // Folded when it runs past its folded lines; one that fits has nothing to fold, so a tap does nothing.
            let folds = isExpanded || isTruncated
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                JustifiedText(text: description, color: UIColor.white.withAlphaComponent(0.85), lineLimit: isExpanded ? 0 : foldedLines,
                              isTruncated: $isTruncated)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    // A tap on the text folds or opens it.
                    .onTapGesture {
                        if folds { toggleDescription() }
                    }
                    .pointerFeedback(folds)
                    .accessibilityAddTraits(folds ? .isButton : [])
                    .accessibilityHint(folds ? (isExpanded ? "Collapses the synopsis" : "Expands the synopsis") : "")
            }
        }
    }

    private func toggleDescription() {
        withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() }
    }
}
#endif
