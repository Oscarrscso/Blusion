import Foundation
import Testing
import StremioKit
@testable import Features

@Suite struct ReviewConsensusTests {
    private func reviews(_ texts: [String]) throws -> [TMDbReview] {
        let json = try JSONSerialization.data(withJSONObject: texts.enumerated().map { ["id": "r\($0.offset)", "author": "a", "content": $0.element] })
        return try JSONDecoder().decode([TMDbReview].self, from: json)
    }

    private let long = String(repeating: "The performances are superb and the cinematography is gorgeous, but the pacing drags. ", count: 4)

    @Test func theLineReadsAsTwoSentences() {
        #expect(ReviewConsensus(praise: ["its performances", "the cinematography"], complaints: ["its slow pacing"]).text
                == "Praised for its performances and the cinematography. Common complaints: its slow pacing.")
        #expect(ReviewConsensus(praise: ["a", "b", "c"]).text == "Praised for a, b and c.")
        #expect(ReviewConsensus().text == nil, "nothing agreed: no line")
    }

    @Test func aPhraseTheReviewsDoNotSupportIsDropped() {
        let consensus = ReviewConsensus(praise: ["its performances", "an Oscar-winning score"], complaints: ["its pacing", "the 3D"])
        let grounded = consensus.grounded(in: ["Great performances throughout.", "The pacing is slow."])
        #expect(grounded.praise == ["its performances"], "no review mentions an Oscar or a score")
        #expect(grounded.complaints == ["its pacing"])
    }

    private actor Count { var calls = 0; func add() { calls += 1 } }

    private struct Summarizer: ReviewSummarizing {
        let count: Count
        func consensus(of reviews: [String]) async -> ReviewConsensus? {
            await count.add()
            return ReviewConsensus(praise: ["its performances", "a perfect score"], complaints: ["its pacing"])
        }
    }

    @MainActor @Test func aTitlesLineIsReadOnceAndKeepsOnlyWhatTheReviewsSay() async throws {
        let count = Count()
        let texts = try reviews([long + "A", long + "B", long + "C"])
        let line = await ReviewConsensusReader.line(for: texts, using: Summarizer(count: count))
        #expect(line == "Praised for its performances. Common complaints: its pacing.")
        #expect(await ReviewConsensusReader.line(for: texts, using: Summarizer(count: count)) == line)
        #expect(await count.calls == 1, "reopening the title reads the cached line")
        #expect(await ReviewConsensusReader.line(for: texts, using: nil) == nil, "no model, no line")
    }

    @Test func repeatedSubjectsAndSentencesAreNotPoints() {
        let consensus = ReviewConsensus(praise: ["amazing performances", "powerful performances", "tight plot"],
                                        complaints: ["not entirely sure it was really Best Picture worthy", "the pacing"])
        let grounded = consensus.grounded(in: ["Amazing performances and a tight plot.", "Powerful performances, slow pacing, not Best Picture worthy."])
        #expect(grounded.praise == ["amazing performances", "tight plot"])
        #expect(grounded.complaints == ["the pacing"])
    }

    @Test func tooFewReviewsOrTooLittleTextHasNoConsensus() throws {
        #expect(ReviewConsensusReader.excerpts(try reviews([long, long])) == nil, "two reviews are not a consensus")
        #expect(ReviewConsensusReader.excerpts(try reviews(["Good.", "Bad.", "Fine."])) == nil, "too little text")
        let excerpts = try #require(ReviewConsensusReader.excerpts(try reviews([long, long, long, String(repeating: "x", count: 5_000)])))
        #expect(excerpts.count == 4 && excerpts.allSatisfy { $0.count <= ReviewConsensusReader.charactersPerReview })
    }
}
