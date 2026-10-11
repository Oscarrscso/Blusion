#if canImport(UIKit)
import CoreText
import SwiftUI
import UIKit

/// Text set justified, which SwiftUI's `Text` cannot do. It is laid out and drawn by `JustifiedLabel` in the body font of `textStyle`
/// (it follows Dynamic Type). Lines break where `JustifiedLineBreaker` puts them so the word gaps come out alike, and every line but the
/// last of a paragraph is justified by widening only the gaps between words. A word is never split or cut.
///
/// `lineLimit` shows that many lines of the same layout, the last one ending in an ellipsis after a whole word; zero shows every line.
/// With `isTruncated` it says whether the cut text leaves some out. Pass `lineLimit` zero (expanded) and it leaves the answer as it was.
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
    /// The fewest and most characters a line should hold; see `JustifiedLineBreaker`.
    var minimumLineCharacters = JustifiedLineBreaker.defaultMinimumCharacters
    var maximumLineCharacters = JustifiedLineBreaker.defaultMaximumCharacters

    func makeUIView(context: Context) -> JustifiedLabel {
        let label = JustifiedLabel(frame: .zero)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: JustifiedLabel, context: Context) {
        configure(label)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: JustifiedLabel, context: Context) -> CGSize? {
        configure(label)
        // One layout for this width answers both the whole text and the limited one.
        let measured = label.measure(width: proposal.width ?? .greatestFiniteMagnitude)
        if let isTruncated, lineLimit > 0 {
            report(truncated: measured.totalLines > lineLimit, to: isTruncated)
        }
        let height = JustifiedSizing.height(totalLines: measured.totalLines, lineLimit: lineLimit, reservesSpace: reservesSpace,
                                            lineHeight: measured.lineHeight)
        return CGSize(width: proposal.width ?? measured.widestLine, height: height)
    }

    private func configure(_ label: JustifiedLabel) {
        label.show(text: text, textStyle: textStyle, color: color, isMarkdown: isMarkdown)
        label.lineLimit = lineLimit
        label.minimumLineCharacters = minimumLineCharacters
        label.maximumLineCharacters = maximumLineCharacters
    }

    /// Sets the answer after the layout pass, and only when it changed, so the state never changes during a layout.
    private func report(truncated: Bool, to binding: Binding<Bool>) {
        guard binding.wrappedValue != truncated else { return }
        let set: @MainActor (Bool) -> Void = { binding.wrappedValue = $0 }
        Task { @MainActor in set(truncated) }
    }
}

/// The view behind `JustifiedText`. It measures each word once, keeps the line layouts of the last few widths, and draws the lines with
/// Core Text, so a container that animates its width pays for a layout only at widths it has not met.
final class JustifiedLabel: UIView {
    private struct Look: Equatable {
        let text: String
        let textStyle: UIFont.TextStyle
        let color: UIColor
        let isMarkdown: Bool
        let category: UIContentSizeCategory
        let style: UIUserInterfaceStyle
    }

    /// A word, ready to draw. Its attributes may change inside it (a bold part), and it keeps those of its last character for an ellipsis.
    private struct Word {
        let line: CTLine
        let width: CGFloat
        let characters: Int
        let endAttributes: [NSAttributedString.Key: Any]
    }

    /// The measured text: its paragraphs of words and the metrics of the base font.
    private struct Content {
        let paragraphs: [[Word]]
        let font: UIFont
        let spaceWidth: CGFloat
        let plain: String
    }

    /// One line of a layout: the words it takes from its paragraph, and whether it is that paragraph's last line (which is not justified).
    private struct Line {
        let paragraph: Int
        let words: Range<Int>
        let isParagraphEnd: Bool
    }

    private final class Layout {
        let lines: [Line]
        let widestLine: CGFloat
        init(lines: [Line], widestLine: CGFloat) {
            self.lines = lines
            self.widestLine = widestLine
        }
    }

    private struct LayoutKey: Equatable {
        let halfPoints: Int
        let minimum: Int
        let maximum: Int
    }

    /// How many widths keep their layout.
    private static let cachedLayouts = 4
    /// The width used when none is proposed: wide enough that only the character limit and newlines break lines.
    private static let unboundedWidth: CGFloat = 100_000

    private var look: Look?
    private var content: Content?
    private var layouts: [(key: LayoutKey, layout: Layout)] = []
    /// The width of the last measurement. Drawing uses that layout when the view's width is within a pixel of it (see `JustifiedSizing`).
    private var measuredWidth: CGFloat?

    /// The lines shown; zero shows them all.
    var lineLimit = 0 {
        didSet { if lineLimit != oldValue { setNeedsDisplay() } }
    }
    var minimumLineCharacters = JustifiedLineBreaker.defaultMinimumCharacters {
        didSet { if minimumLineCharacters != oldValue { setNeedsDisplay() } }
    }
    var maximumLineCharacters = JustifiedLineBreaker.defaultMaximumCharacters {
        didSet { if maximumLineCharacters != oldValue { setNeedsDisplay() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .redraw
        isOpaque = false
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitUserInterfaceStyle.self]) { (label: JustifiedLabel, _) in
            label.rebuildForTraits()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("JustifiedLabel is made in code only")
    }

    /// Sets the text and its look, when either differs from what is shown.
    func show(text: String, textStyle: UIFont.TextStyle, color: UIColor, isMarkdown: Bool) {
        let next = Look(text: text, textStyle: textStyle, color: color, isMarkdown: isMarkdown,
                        category: traitCollection.preferredContentSizeCategory, style: traitCollection.userInterfaceStyle)
        guard next != look else { return }
        look = next
        content = build(next)
        layouts = []
        accessibilityLabel = content?.plain
        setNeedsDisplay()
        invalidateIntrinsicContentSize()
    }

    /// What the text takes at `width`: its lines in all, the widest of them, and the height of one line.
    func measure(width: CGFloat) -> (totalLines: Int, widestLine: CGFloat, lineHeight: CGFloat) {
        guard let content else { return (0, 0, UIFont.preferredFont(forTextStyle: .body).lineHeight) }
        measuredWidth = width
        let layout = layout(forWidth: width)
        return (layout.lines.count, layout.widestLine, content.font.lineHeight)
    }

    private func rebuildForTraits() {
        guard let look else { return }
        self.look = nil
        show(text: look.text, textStyle: look.textStyle, color: look.color, isMarkdown: look.isMarkdown)
    }

    // MARK: Building the words

    private func build(_ look: Look) -> Content {
        let font = UIFont.preferredFont(forTextStyle: look.textStyle, compatibleWith: traitCollection)
        let color = look.color.resolvedColor(with: traitCollection)
        let text = attributed(look, font: font, color: color)
        let string = text.string as NSString
        let space = CTLineCreateWithAttributedString(NSAttributedString(string: " ", attributes: attributes(font: font, color: color)))
        let spaceWidth = CGFloat(CTLineGetTypographicBounds(space, nil, nil, nil))

        var paragraphs: [[Word]] = []
        var words: [Word] = []
        var wordStart: Int?
        func endWord(at end: Int) {
            guard let start = wordStart else { return }
            wordStart = nil
            let range = NSRange(location: start, length: end - start)
            let piece = text.attributedSubstring(from: range)
            let line = CTLineCreateWithAttributedString(piece)
            words.append(Word(line: line, width: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)),
                              characters: piece.string.count,
                              endAttributes: piece.attributes(at: piece.length - 1, effectiveRange: nil)))
        }
        for index in 0..<string.length {
            switch string.character(at: index) {
            case 0x0A:
                endWord(at: index)
                paragraphs.append(words)
                words = []
            case 0x20, 0x09, 0x0D:
                endWord(at: index)
            default:
                if wordStart == nil { wordStart = index }
            }
        }
        endWord(at: string.length)
        paragraphs.append(words)
        while paragraphs.count > 1, paragraphs.last?.isEmpty == true { paragraphs.removeLast() }
        if paragraphs.count == 1, paragraphs[0].isEmpty { paragraphs = [] }
        return Content(paragraphs: paragraphs, font: font, spaceWidth: spaceWidth, plain: text.string)
    }

    private func attributes(font: UIFont, color: UIColor) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor]
    }

    /// The text in the base font and colour. Markdown keeps its bold and italic as traits of that font; links and code are plain text.
    private func attributed(_ look: Look, font: UIFont, color: UIColor) -> NSAttributedString {
        let base = attributes(font: font, color: color)
        guard look.isMarkdown,
              let parsed = try? AttributedString(markdown: look.text,
                                                 options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        else { return NSAttributedString(string: look.text, attributes: base) }
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            var traits: UIFontDescriptor.SymbolicTraits = []
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                if intent.contains(.emphasized) { traits.insert(.traitItalic) }
            }
            var runFont = font
            if !traits.isEmpty, let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                runFont = UIFont(descriptor: descriptor, size: font.pointSize)
            }
            var runAttributes = base
            runAttributes[.font] = runFont
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: runAttributes))
        }
        return result
    }

    // MARK: Layout

    private func layout(forWidth proposed: CGFloat) -> Layout {
        let width = proposed.isFinite && proposed < Self.unboundedWidth ? max(proposed, 1) : Self.unboundedWidth
        let key = LayoutKey(halfPoints: Int((width * 2).rounded(.down)), minimum: minimumLineCharacters, maximum: maximumLineCharacters)
        if let index = layouts.firstIndex(where: { $0.key == key }) {
            let entry = layouts.remove(at: index)
            layouts.append(entry)
            return entry.layout
        }
        // Rounded down to the half point, so a line is never wider than the view.
        let layout = makeLayout(width: max(1, CGFloat(key.halfPoints) / 2), key: key)
        layouts.append((key, layout))
        if layouts.count > Self.cachedLayouts { layouts.removeFirst() }
        return layout
    }

    private func makeLayout(width: CGFloat, key: LayoutKey) -> Layout {
        guard let content else { return Layout(lines: [], widestLine: 0) }
        var lines: [Line] = []
        var widest: CGFloat = 0
        for (index, words) in content.paragraphs.enumerated() {
            if words.isEmpty {
                lines.append(Line(paragraph: index, words: 0..<0, isParagraphEnd: true))
                continue
            }
            let ranges = JustifiedLineBreaker.breaks(wordWidths: words.map(\.width), wordCharacters: words.map(\.characters),
                                                     spaceWidth: content.spaceWidth, lineWidth: width,
                                                     minimumCharacters: key.minimum, maximumCharacters: key.maximum)
            for (offset, range) in ranges.enumerated() {
                lines.append(Line(paragraph: index, words: range, isParagraphEnd: offset == ranges.count - 1))
                widest = max(widest, naturalWidth(words[range], content.spaceWidth))
            }
        }
        return Layout(lines: lines, widestLine: min(widest, width))
    }

    private func naturalWidth(_ words: ArraySlice<Word>, _ space: CGFloat) -> CGFloat {
        words.reduce(0) { $0 + $1.width } + space * CGFloat(max(0, words.count - 1))
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let content, let context = UIGraphicsGetCurrentContext(), bounds.width > 0 else { return }
        // The layout the height was measured with, so every line it counted is drawn.
        let layout = layout(forWidth: JustifiedSizing.layoutWidth(measured: measuredWidth, bounds: bounds.width))
        let width = bounds.width
        let total = layout.lines.count
        let shown = JustifiedSizing.shownLines(total: total, lineLimit: lineLimit)
        let isCut = lineLimit > 0 && total > lineLimit
        let scale = max(contentScaleFactor, 1)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for index in 0..<shown {
            let line = layout.lines[index]
            let words = Array(content.paragraphs[line.paragraph][line.words])
            guard !words.isEmpty else { continue }
            let baseline = ((CGFloat(index) * content.font.lineHeight + content.font.ascender) * scale).rounded() / scale
            let cut = isCut && index == shown - 1
            drawLine(words, in: context, content: content, width: width, baseline: baseline, scale: scale,
                     justified: cut || !line.isParagraphEnd, ellipsis: cut)
        }
    }

    /// Draws one line. Justified, the gaps between words share the slack equally; otherwise the words keep single spaces from the leading
    /// edge. A word wider than the line is drawn scaled down to fit. With `ellipsis`, trailing words are dropped until the mark fits.
    private func drawLine(_ words: [Word], in context: CGContext, content: Content, width: CGFloat, baseline: CGFloat, scale: CGFloat,
                          justified: Bool, ellipsis: Bool) {
        var kept = words
        var mark: (line: CTLine, width: CGFloat)?
        if ellipsis, let last = words.last {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: last.endAttributes))
            mark = (line, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
            while kept.count > 1, naturalWidth(kept[...], content.spaceWidth) + (mark?.width ?? 0) > width { kept.removeLast() }
        }
        let markWidth = mark?.width ?? 0
        let widths = kept.enumerated().map { $0.element.width + ($0.offset == kept.count - 1 ? markWidth : 0) }
        let sum = widths.reduce(0, +)
        let natural = sum + content.spaceWidth * CGFloat(kept.count - 1)
        var gap = content.spaceWidth
        var factor: CGFloat = 1
        if natural > width {
            factor = width / natural
        } else if justified, kept.count > 1 {
            gap = (width - sum) / CGFloat(kept.count - 1)
        }
        context.saveGState()
        context.scaleBy(x: factor, y: 1)
        var x: CGFloat = 0
        for (offset, word) in kept.enumerated() {
            context.textPosition = CGPoint(x: (x * scale).rounded() / scale, y: baseline)
            CTLineDraw(word.line, context)
            if offset == kept.count - 1, let mark {
                context.textPosition = CGPoint(x: ((x + word.width) * scale).rounded() / scale, y: baseline)
                CTLineDraw(mark.line, context)
            }
            x += widths[offset] + gap
        }
        context.restoreGState()
    }
}
#endif
