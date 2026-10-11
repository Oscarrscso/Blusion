import CoreGraphics
import Foundation

/// Chooses where the lines of one paragraph break so that, once each line is justified, the gaps between words come out alike and none is
/// extreme. It is a minimum-raggedness dynamic programme over the whole paragraph (a total fit), not a greedy fill: a line is allowed to be
/// a little short if that keeps the next one from being very loose. Words are never split.
enum JustifiedLineBreaker {
    /// The fewest characters a line should hold, spaces between its words included. Tunable. Shorter lines are allowed when nothing else
    /// fits, for instance before a very long word, but they cost more.
    static let defaultMinimumCharacters = 18
    /// The most characters a line may hold, spaces between its words included. Tunable. It keeps lines readable on wide containers.
    /// A single word longer than this still takes a line of its own.
    static let defaultMaximumCharacters = 90

    /// What a short line costs on top of its looseness, so the breaker avoids it unless the alternative is worse.
    private static let shortLinePenalty = 4.0
    /// What a line of one word costs when a second word would have fitted.
    private static let loneWordPenalty = 1.5
    /// What a last line of one short word (a widow) costs.
    private static let widowPenalty = 0.5
    /// A last line of one word with fewer characters than this is a widow.
    private static let widowCharacters = 8
    /// The narrowest a gap between two words may be, as a share of the natural space. A line takes another word before it stretches, as long
    /// as its gaps stay at least this wide. The breaker and the drawing use the same figure, so a line fits the same way in both.
    static let minimumGapFactor: CGFloat = 0.75
    /// The widest a gap may be, as a share of the natural space, on a line that is justified. A line that would need more is drawn
    /// with natural gaps from the leading edge instead of stretched.
    static let maximumGapFactor: CGFloat = 1.9
    /// What a gap stretched past the natural space costs, per unit of stretch cubed (the stretch in natural spaces). Steeper than the
    /// slack, so the breaker prefers lines of alike gaps.
    private static let stretchWeight = 1.0
    /// What a gap compressed under the natural space costs, per unit of compression squared.
    private static let compressWeight = 2.0
    /// What a line costs on top when its gaps would pass `maximumGapFactor`, so it is drawn unstretched.
    private static let overStretchPenalty = 3.0
    /// Costs closer than this are equal, and the tie-break decides.
    private static let epsilon = 1e-9

    /// The word range of each line of one paragraph.
    /// - Parameters:
    ///   - wordWidths: the width of each word on its own.
    ///   - wordCharacters: the number of characters of each word.
    ///   - spaceWidth: the width of the single space between two words on a line.
    ///   - lineWidth: the width a line may take.
    ///   - minimumCharacters: the fewest characters a line should hold; a soft limit.
    ///   - maximumCharacters: the most characters a line may hold, unless it is one word.
    static func breaks(wordWidths: [CGFloat], wordCharacters: [Int], spaceWidth: CGFloat, lineWidth: CGFloat,
                       minimumCharacters: Int, maximumCharacters: Int) -> [Range<Int>] {
        let count = min(wordWidths.count, wordCharacters.count)
        guard count > 0 else { return [] }
        let width = max(lineWidth, 1)

        // Cost and line count of the best layout of words `i..<count`; `next[i]` is where its first line ends.
        var cost = [Double](repeating: 0, count: count + 1)
        var lines = [Int](repeating: 0, count: count + 1)
        var next = [Int](repeating: count, count: count + 1)

        for start in stride(from: count - 1, through: 0, by: -1) {
            var wordsWidth: CGFloat = 0
            var characters = 0
            var bestCost = Double.infinity
            var bestLines = Int.max
            var bestEnd = start + 1
            var end = start
            while end < count {
                wordsWidth += wordWidths[end]
                characters += wordCharacters[end] + (end > start ? 1 : 0)
                end += 1
                let gaps = CGFloat(end - start - 1)
                let natural = wordsWidth + gaps * spaceWidth
                let isSingle = end - start == 1
                // The line fits when its gaps can shrink to the minimum.
                if !isSingle && (wordsWidth + gaps * spaceWidth * minimumGapFactor > width || characters > maximumCharacters) { break }

                var lineCost: Double
                if end == count {
                    lineCost = isSingle && !(natural > width) && wordCharacters[start] < widowCharacters && count > 1 && start > 0
                        ? widowPenalty : 0
                } else {
                    let slack = abs(Double((width - natural) / width))
                    lineCost = slack * slack
                    if !isSingle, spaceWidth > 0 {
                        let ratio = (width - wordsWidth) / (gaps * spaceWidth)
                        let stretch = Double(max(0, ratio - 1))
                        let compress = Double(max(0, 1 - ratio))
                        lineCost += stretchWeight * stretch * stretch * stretch + compressWeight * compress * compress
                        if ratio > maximumGapFactor { lineCost += overStretchPenalty }
                    }
                    if characters < minimumCharacters {
                        lineCost += shortLinePenalty + Double(minimumCharacters - characters) / Double(max(minimumCharacters, 1))
                    }
                    if isSingle, wordFitsWithNext(start, wordWidths, wordCharacters, spaceWidth, width, maximumCharacters) {
                        lineCost += loneWordPenalty
                    }
                }
                let total = lineCost + cost[end]
                let totalLines = 1 + lines[end]
                // Lowest cost, then fewer lines, then the earlier break (the first found, as `end` only grows).
                if total < bestCost - epsilon || (abs(total - bestCost) <= epsilon && totalLines < bestLines) {
                    bestCost = total
                    bestLines = totalLines
                    bestEnd = end
                }
            }
            cost[start] = bestCost
            lines[start] = bestLines
            next[start] = bestEnd
        }

        var result: [Range<Int>] = []
        var start = 0
        while start < count {
            result.append(start..<next[start])
            start = next[start]
        }
        return result
    }

    private static func wordFitsWithNext(_ index: Int, _ widths: [CGFloat], _ characters: [Int], _ space: CGFloat, _ width: CGFloat,
                                         _ maximum: Int) -> Bool {
        guard index + 1 < widths.count else { return false }
        return widths[index] + space * minimumGapFactor + widths[index + 1] <= width && characters[index] + 1 + characters[index + 1] <= maximum
    }
}

/// How wide the gaps of one drawn line are, apart from UIKit so it can be tested.
enum JustifiedSpacing {
    /// The gap between the words of a line of `wordCount` words whose words take `wordsWidth` in all, in a line `lineWidth` wide.
    /// A line too long at the natural space shrinks its gaps, to the minimum at most. A justified line stretches them to fill the line,
    /// unless that takes more than the maximum, and then it keeps the natural space (and is drawn from the leading edge). A line that is
    /// not justified keeps the natural space.
    static func gap(wordsWidth: CGFloat, wordCount: Int, spaceWidth: CGFloat, lineWidth: CGFloat, justified: Bool) -> CGFloat {
        guard wordCount > 1 else { return spaceWidth }
        let fill = (lineWidth - wordsWidth) / CGFloat(wordCount - 1)
        if fill < spaceWidth { return max(fill, spaceWidth * JustifiedLineBreaker.minimumGapFactor) }
        guard justified, fill <= spaceWidth * JustifiedLineBreaker.maximumGapFactor else { return spaceWidth }
        return fill
    }

    /// The width of a line of words at the narrowest gaps: the least it can take.
    static func compressedWidth(wordsWidth: CGFloat, wordCount: Int, spaceWidth: CGFloat) -> CGFloat {
        wordsWidth + spaceWidth * JustifiedLineBreaker.minimumGapFactor * CGFloat(max(0, wordCount - 1))
    }
}

/// The sums behind a justified text's size, apart from UIKit so they can be tested. The height SwiftUI is given comes from a layout at
/// the width it proposed; the text is drawn at the width the view ends up with, which can differ by a pixel after SwiftUI snaps the
/// frame. A different width can break into a different number of lines, and a line the height did not count is cut off. So the drawing
/// uses the layout the size was measured with whenever the two widths are that close.
enum JustifiedSizing {
    /// How far the drawn width may differ from the measured one (pixel snapping) before the text is laid out afresh.
    static let widthTolerance: CGFloat = 1.5

    /// The width to lay the text out at when drawing it in `bounds`.
    static func layoutWidth(measured: CGFloat?, bounds: CGFloat) -> CGFloat {
        guard let measured, measured.isFinite, abs(measured - bounds) <= widthTolerance else { return bounds }
        return max(measured, 1)
    }

    /// The lines drawn: all of them, or the limit.
    static func shownLines(total: Int, lineLimit: Int) -> Int {
        lineLimit > 0 ? min(lineLimit, total) : total
    }

    /// The height of the text: whole lines, and with `reservesSpace` at least the limit.
    static func height(totalLines: Int, lineLimit: Int, reservesSpace: Bool, lineHeight: CGFloat) -> CGFloat {
        let shown = shownLines(total: totalLines, lineLimit: lineLimit)
        let lines = reservesSpace && lineLimit > 0 ? max(shown, lineLimit) : shown
        return ceil(CGFloat(lines) * lineHeight)
    }
}
