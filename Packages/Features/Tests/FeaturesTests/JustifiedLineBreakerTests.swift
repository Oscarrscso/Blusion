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
            #expect(natural(line, sample) <= 200)
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
        #expect(worstSlack(balanced, sample, width: width) < worstSlack(greedy(sample, width: width), sample, width: width))
    }

    @Test func balancingNeverMakesTheWorstLineLooserThanGreedyOnOrdinaryText() {
        let sample = Sample(paragraph + " " + paragraph)
        for width in stride(from: CGFloat(260), through: 400, by: 20) {
            let lines = breaks(sample, width: width)
            #expect(worstSlack(lines, sample, width: width) <= worstSlack(greedy(sample, width: width), sample, width: width) + 1e-9)
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
}
