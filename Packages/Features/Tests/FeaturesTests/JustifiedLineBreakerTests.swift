import CoreGraphics
import Testing
@testable import Features

@Suite struct JustifiedLineBreakerTests {
    /// Words of a sample text, each letter 10 wide and a space 10 wide.
    private struct Sample {
        let widths: [CGFloat]
        let characters: [Int]
        init(_ text: String) {
            let words = text.split(separator: " ").map(String.init)
            characters = words.map(\.count)
            widths = words.map { CGFloat($0.count) * 10 }
        }
    }

    private func breaks(_ sample: Sample, width: CGFloat, minimum: Int = 18, maximum: Int = 90) -> [Range<Int>] {
        JustifiedLineBreaker.breaks(wordWidths: sample.widths, wordCharacters: sample.characters, spaceWidth: 10, lineWidth: width,
                                    minimumCharacters: minimum, maximumCharacters: maximum)
    }

    private func natural(_ range: Range<Int>, _ sample: Sample) -> CGFloat {
        range.reduce(0) { $0 + sample.widths[$1] } + CGFloat(range.count - 1) * 10
    }

    /// The widest gap, in natural spaces, over the multi-word lines but the last.
    private func worstGap(_ lines: [Range<Int>], _ sample: Sample, width: CGFloat) -> CGFloat {
        lines.dropLast().filter { $0.count > 1 }.map { line in
            (width - line.reduce(0) { $0 + sample.widths[$1] }) / CGFloat(line.count - 1) / 10
        }.max() ?? 0
    }

    /// The least a line can take, its gaps at the minimum.
    private func compressed(_ range: Range<Int>, _ sample: Sample) -> CGFloat {
        range.reduce(0) { $0 + sample.widths[$1] } + CGFloat(range.count - 1) * 10 * JustifiedLineBreaker.minimumGapFactor
    }

    /// The largest slack ratio over the lines but the last.
    private func worstSlack(_ lines: [Range<Int>], _ sample: Sample, width: CGFloat) -> CGFloat {
        lines.dropLast().map { (width - natural($0, sample)) / width }.max() ?? 0
    }

    /// Greedy filling, for comparison.
    private func greedy(_ sample: Sample, width: CGFloat) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        while start < sample.widths.count {
            var end = start + 1
            while end < sample.widths.count, natural(start..<(end + 1), sample) <= width { end += 1 }
            result.append(start..<end)
            start = end
        }
        return result
    }

    private let paragraph = "The quick brown fox jumps over the lazy dog while a small bird watches from the old oak tree nearby"

    @Test func everyWordAppearsOnceAndInOrder() {
        let sample = Sample(paragraph)
        let lines = breaks(sample, width: 300)
        #expect(lines.first?.lowerBound == 0)
        #expect(lines.last?.upperBound == sample.widths.count)
        for pair in zip(lines, lines.dropFirst()) { #expect(pair.0.upperBound == pair.1.lowerBound) }
        #expect(lines.allSatisfy { !$0.isEmpty })
    }

    @Test func noLineIsWiderThanTheWidthOrTheMaximumUnlessOneWord() {
        let sample = Sample(paragraph + " supercalifragilisticexpialidocious and more")
        for line in breaks(sample, width: 200, maximum: 20) {
            guard line.count > 1 else { continue }
            #expect(compressed(line, sample) <= 200)
            let characters = line.reduce(0) { $0 + sample.characters[$1] } + line.count - 1
            #expect(characters <= 20)
        }
    }

    @Test func aWordWiderThanTheLineTakesALineOfItsOwn() {
        let sample = Sample("a supercalifragilisticexpialidocious b")
        let lines = breaks(sample, width: 150)
        #expect(lines.contains(1..<2))
    }

    @Test func aLooseGreedyLineBeforeALongWordIsBalanced() {
        let sample = Sample("It was a good one. Incredible movie. So extraordinarilylongword here and then the rest of the story goes on and on")
        let width: CGFloat = 300
        let balanced = breaks(sample, width: width)
        #expect(worstGap(balanced, sample, width: width) < worstGap(greedy(sample, width: width), sample, width: width))
    }

    @Test func balancingNeverMakesTheWorstLineLooserThanGreedyOnOrdinaryText() {
        let sample = Sample(paragraph + " " + paragraph)
        for width in stride(from: CGFloat(260), through: 400, by: 20) {
            let lines = breaks(sample, width: width)
            #expect(worstGap(lines, sample, width: width) <= worstGap(greedy(sample, width: width), sample, width: width) + 1e-9)
        }
    }

    @Test func minimumCharactersAreRespectedWhenFeasible() {
        let sample = Sample(paragraph)
        let lines = breaks(sample, width: 300, minimum: 20)
        for line in lines.dropLast() {
            let characters = line.reduce(0) { $0 + sample.characters[$1] } + line.count - 1
            #expect(characters >= 20)
        }
    }

    @Test func aWidowIsPulledDownWhenPossible() {
        // Greedy leaves "go." alone on the last line at this width.
        let sample = Sample("one two three four five six seven go.")
        let lines = breaks(sample, width: 300)
        #expect((lines.last?.count ?? 0) > 1)
    }

    @Test func emptyAndSingleWordInput() {
        #expect(breaks(Sample(""), width: 100).isEmpty)
        #expect(breaks(Sample("word"), width: 100) == [0..<1])
        #expect(breaks(Sample("wordwordwordwordword"), width: 50) == [0..<1])
    }

    @Test func aLineTakesAnotherWordByCompressingItsGaps() {
        // "aaaa bbbb cccc" is 140 wide at natural gaps and 135 with gaps at 0.75, so it fits a 135 line only compressed.
        let sample = Sample("aaaa bbbb cccc dddd")
        let lines = breaks(sample, width: 135, minimum: 1)
        #expect(lines.first == 0..<3)
        #expect(compressed(0..<3, sample) <= 135)
    }

    @Test func noLineNeedsMoreCompressionThanTheMinimum() {
        let sample = Sample(paragraph + " " + paragraph)
        for width in stride(from: CGFloat(200), through: 400, by: 17) {
            for line in breaks(sample, width: width) where line.count > 1 {
                #expect(compressed(line, sample) <= width + 1e-9)
            }
        }
    }

    @Test func gapsAreStretchedUpToTheCapThenLeftNatural() {
        let space: CGFloat = 10
        // Five words of 20: sum 100 in a 140 line leaves 10 per gap (natural); 160 leaves 15 (stretched); 400 leaves 75 (over the cap).
        #expect(JustifiedSpacing.gap(wordsWidth: 100, wordCount: 5, spaceWidth: space, lineWidth: 160, justified: true) == 15)
        #expect(JustifiedSpacing.gap(wordsWidth: 100, wordCount: 5, spaceWidth: space, lineWidth: 400, justified: true) == space)
        #expect(JustifiedSpacing.gap(wordsWidth: 100, wordCount: 5, spaceWidth: space, lineWidth: 160, justified: false) == space)
        #expect(JustifiedSpacing.gap(wordsWidth: 100, wordCount: 5, spaceWidth: space, lineWidth: 100 + 4 * 19, justified: true) == 19)
    }

    @Test func gapsShrinkToTheMinimumAndNoFurther() {
        let space: CGFloat = 10
        #expect(JustifiedSpacing.gap(wordsWidth: 100, wordCount: 5, spaceWidth: space, lineWidth: 132, justified: true) == 8)
        #expect(JustifiedSpacing.gap(wordsWidth: 100, wordCount: 5, spaceWidth: space, lineWidth: 100, justified: false) == 7.5)
        #expect(JustifiedSpacing.gap(wordsWidth: 100, wordCount: 1, spaceWidth: space, lineWidth: 50, justified: true) == space)
    }

    @Test func aWordWiderThanTheLineStaysOnALineAloneWhateverItsNeighbours() {
        let sample = Sample("see https://example.com/a/very/long/path/that/never/ends now")
        let lines = breaks(sample, width: 200)
        #expect(lines.contains(1..<2))
    }
}
