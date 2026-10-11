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
            var natural: CGFloat = 0
            var characters = 0
            var bestCost = Double.infinity
            var bestLines = Int.max
            var bestEnd = start + 1
            var end = start
            while end < count {
                natural += wordWidths[end] + (end > start ? spaceWidth : 0)
                characters += wordCharacters[end] + (end > start ? 1 : 0)
                end += 1
                let isSingle = end - start == 1
                if !isSingle && (natural > width || characters > maximumCharacters) { break }

                var lineCost: Double
                if end == count {
                    lineCost = isSingle && !(natural > width) && wordCharacters[start] < widowCharacters && count > 1 && start > 0
                        ? widowPenalty : 0
                } else {
                    let slack = max(0, Double((width - natural) / width))
                    lineCost = slack * slack
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
        return widths[index] + space + widths[index + 1] <= width && characters[index] + 1 + characters[index + 1] <= maximum
    }
}
