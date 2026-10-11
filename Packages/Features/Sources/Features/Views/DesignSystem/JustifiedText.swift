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

    /// A line is loose when UIKit would have to add more than this much to each gap between its words, as a fraction of the font size.
    /// A loose line is not left to UIKit, which would spread the letters of a line with few words. The gaps take the stretch instead.
    static let looseGapEm: CGFloat = 0.5
    /// The most a gap between words is stretched on a loose line, as a fraction of the font size. A line that needs more is left ragged.
    static let maxGapStretchEm: CGFloat = 1.0
    /// Taken off the stretch of a loose line, so rounding can never push its last word to the next line.
    private static let stretchMargin: CGFloat = 0.5

    private var look: Look?
    /// The text as `render` builds it: font, colour, justified paragraph style. The label shows it, or a shaped copy of it.
    private var baseText = NSAttributedString()
    /// The width `attributedText` was shaped for; nil when it shows `baseText` as it is.
    private var shapedWidth: CGFloat?

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
        shape(forWidth: width)
        return sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    override func layoutSubviews() {
        shape(forWidth: bounds.width)
        super.layoutSubviews()
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
        baseText = text
        shapedWidth = nil
        attributedText = text
        accessibilityLabel = text.string
        setNeedsLayout()
    }

    /// Shows the text shaped for `width`, unless it already is (within half a point). An unbounded or empty width shows the base text.
    private func shape(forWidth width: CGFloat) {
        guard width.isFinite, width > 0, width < 1_000_000 else {
            if shapedWidth != nil {
                shapedWidth = nil
                attributedText = baseText
            }
            return
        }
        if let shapedWidth, abs(shapedWidth - width) <= 0.5 { return }
        shapedWidth = width
        attributedText = Self.shaped(baseText, width: width)
    }

    /// `base` laid out at `width`, with each loose line (not the last of its paragraph) taking its stretch in the gaps between words:
    /// the interior spaces get a kern of the line's slack divided by the gaps, at most `maxGapStretchEm`, and the trailing space becomes
    /// U+2028 so UIKit ends the line there instead of justifying it. A line is loose when it has no gap, or its gaps would each stretch
    /// by more than `looseGapEm`. The other lines are left to UIKit's justification. One character replaces one, so ranges stay valid.
    static func shaped(_ base: NSAttributedString, width: CGFloat) -> NSAttributedString {
        let length = base.length
        guard length > 0, width > 0 else { return base }
        let em = (base.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize ?? UIFont.systemFontSize

        // The base breaks lines by truncating, which would lay out one line; measure with word wrap and no justification.
        let measured = NSMutableAttributedString(attributedString: base)
        let natural = NSMutableParagraphStyle()
        natural.alignment = .natural
        natural.lineBreakMode = .byWordWrapping
        measured.addAttribute(.paragraphStyle, value: natural, range: NSRange(location: 0, length: length))
        let storage = NSTextStorage(attributedString: measured)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)

        let string = storage.string as NSString
        var lines: [NSRange] = []
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, glyphRange, _ in
            lines.append(layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil))
        }

        let result = NSMutableAttributedString(attributedString: base)
        for line in lines where line.length > 1 {
            let lastIndex = line.location + line.length - 1
            // The last line of a paragraph is not justified by UIKit.
            if lastIndex == length - 1 || string.character(at: lastIndex) == 0x0A { continue }
            // Without a trailing space the line broke inside a word or at a hyphen: leave it.
            guard string.character(at: lastIndex) == 0x20 else { continue }
            let body = NSRange(location: line.location, length: line.length - 1)
            let used = ceil(measured.attributedSubstring(from: body)
                .boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                              options: [.usesLineFragmentOrigin], context: nil).width)
            let slack = max(0, width - used)
            var gaps: [Int] = []
            for index in body.location..<(body.location + body.length) where string.character(at: index) == 0x20 {
                gaps.append(index)
            }
            if !gaps.isEmpty, slack / CGFloat(gaps.count) <= looseGapEm * em { continue }
            if !gaps.isEmpty {
                let count = CGFloat(gaps.count)
                let kern = max(0, (min(slack / count, maxGapStretchEm * em) * count - stretchMargin) / count)
                for index in gaps { result.addAttribute(.kern, value: kern, range: NSRange(location: index, length: 1)) }
            }
            let separator = NSAttributedString(string: "\u{2028}", attributes: base.attributes(at: lastIndex, effectiveRange: nil))
            result.replaceCharacters(in: NSRange(location: lastIndex, length: 1), with: separator)
        }
        return result
    }
}
#endif
