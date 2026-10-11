#if canImport(UIKit)
import SwiftUI
import UIKit

/// Text set justified, which SwiftUI's `Text` cannot do. A `UILabel` in the body font of `textStyle` (it follows Dynamic Type), with a
/// justified paragraph style. `lineLimit` cuts the text after that many lines with a tail ellipsis, as `Text` does; zero shows every line.
///
/// With `isTruncated` it says whether the cut text leaves some out, measured the way `TruncatingText` measures: the whole text against
/// the cut one, at the same width. Pass `lineLimit` zero (expanded) and it leaves the answer as it was.
struct JustifiedText: UIViewRepresentable {
    let text: String
    var textStyle: UIFont.TextStyle = .body
    var color: UIColor = .label
    /// Read as inline Markdown, as `Text(LocalizedStringKey)` reads it. Plain otherwise, as `Text(String)` shows it.
    var isMarkdown = false
    /// The lines shown; zero shows them all.
    var lineLimit = 0
    /// With a line limit, the cut text always takes that many lines, so cards holding texts of different lengths share a height.
    var reservesSpace = false
    var isTruncated: Binding<Bool>?

    func makeUIView(context: Context) -> JustifiedLabel {
        let label = JustifiedLabel(frame: .zero)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: JustifiedLabel, context: Context) {
        label.show(text: text, textStyle: textStyle, color: color, isMarkdown: isMarkdown)
        label.numberOfLines = lineLimit
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: JustifiedLabel, context: Context) -> CGSize? {
        label.show(text: text, textStyle: textStyle, color: color, isMarkdown: isMarkdown)
        let width = proposal.width ?? .greatestFiniteMagnitude
        let whole = label.measure(width: width, lines: 0)
        // Measured last, so the label is left with the line limit it shows.
        let shown = label.measure(width: width, lines: lineLimit)
        if let isTruncated, lineLimit > 0 {
            report(truncated: whole.height > shown.height + 1, to: isTruncated)
        }
        var height = shown.height
        if reservesSpace, lineLimit > 0 {
            height = max(height, UIFont.preferredFont(forTextStyle: textStyle).lineHeight * CGFloat(lineLimit))
        }
        return CGSize(width: proposal.width ?? shown.width, height: height)
    }

    /// Sets the answer after the layout pass, and only when it changed, so the state never changes during a layout.
    private func report(truncated: Bool, to binding: Binding<Bool>) {
        guard binding.wrappedValue != truncated else { return }
        let set: @MainActor (Bool) -> Void = { binding.wrappedValue = $0 }
        Task { @MainActor in set(truncated) }
    }
}

/// The label behind `JustifiedText`. It keeps its text and look, and rebuilds the attributed text when the Dynamic Type size changes.
final class JustifiedLabel: UILabel {
    private struct Look: Equatable {
        let text: String
        let textStyle: UIFont.TextStyle
        let color: UIColor
        let isMarkdown: Bool
    }

    private var look: Look?

    override init(frame: CGRect) {
        super.init(frame: frame)
        numberOfLines = 0
        lineBreakMode = .byTruncatingTail
    }

    required init?(coder: NSCoder) {
        fatalError("JustifiedLabel is made in code only")
    }

    /// Sets the text and its look, when either differs from what is shown.
    func show(text: String, textStyle: UIFont.TextStyle, color: UIColor, isMarkdown: Bool) {
        let next = Look(text: text, textStyle: textStyle, color: color, isMarkdown: isMarkdown)
        guard next != look else { return }
        look = next
        render(next)
    }

    /// The size the text takes at `width` in `lines` lines (zero for all of them). The label is left at those lines.
    func measure(width: CGFloat, lines: Int) -> CGSize {
        numberOfLines = lines
        return sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory,
              let look else { return }
        render(look)
    }

    private func render(_ look: Look) {
        let font = UIFont.preferredFont(forTextStyle: look.textStyle, compatibleWith: traitCollection)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        paragraph.lineBreakMode = .byTruncatingTail
        let text: NSMutableAttributedString
        if look.isMarkdown,
           let parsed = try? NSAttributedString(markdown: look.text,
                                                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            text = NSMutableAttributedString(attributedString: parsed)
        } else {
            text = NSMutableAttributedString(string: look.text)
        }
        text.addAttributes([.font: font, .foregroundColor: look.color, .paragraphStyle: paragraph],
                           range: NSRange(location: 0, length: text.length))
        attributedText = text
    }
}
#endif
