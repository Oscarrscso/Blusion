import Foundation
import StremioKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What several of a title's reviews praise and complain about, as short phrases taken from their text.
public struct ReviewConsensus: Sendable, Equatable {
    public var praise: [String]
    public var complaints: [String]

    public init(praise: [String] = [], complaints: [String] = []) {
        self.praise = praise
        self.complaints = complaints
    }

    /// "Praised for its performances and cinematography. Common complaints: its slow pacing and its ending." Nil when there is neither.
    public var text: String? {
        var sentences: [String] = []
        if let praised = Self.list(praise) { sentences.append("Praised for \(praised).") }
        if let complained = Self.list(complaints) { sentences.append("Common complaints: \(complained).") }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    private static func list(_ phrases: [String]) -> String? {
        let phrases = phrases.map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(["."])) }.filter { !$0.isEmpty }
        switch phrases.count {
        case 0: return nil
        case 1: return phrases[0]
        default: return phrases.dropLast().joined(separator: ", ") + " and " + phrases[phrases.count - 1]
        }
    }

    /// Keeps the phrases the reviews' own words support: each must share a word of four letters or more with the reviews, so a phrase the
    /// model made up from nothing is dropped. A phrase of more than five words is a sentence, not a point, and two phrases about the
    /// same thing ("amazing performances", "powerful performances") are one. At most three of each.
    func grounded(in reviews: [String]) -> ReviewConsensus {
        let words = Set(reviews.joined(separator: " ").lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        func supported(_ phrases: [String]) -> [String] {
            var kept: [String] = []
            var subjects = Set<String>()
            for phrase in phrases {
                let parts = phrase.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
                guard (1...5).contains(parts.count), parts.contains(where: { $0.count >= 4 && words.contains($0) }),
                      let subject = parts.last, subjects.insert(subject).inserted else { continue }
                kept.append(phrase)
            }
            return Array(kept.prefix(3))
        }
        return ReviewConsensus(praise: supported(praise), complaints: supported(complaints))
    }
}

/// Sums up what a title's reviews say. Nil when there is too little to go on, or no model.
public protocol ReviewSummarizing: Sendable {
    func consensus(of reviews: [String]) async -> ReviewConsensus?
}

enum ReviewConsensusReader {
    /// Lines already read this run, by the reviews they were read from, so reopening a title does not ask the model again.
    @MainActor static var cache: [[String]: String] = [:]
    static let minimumReviews = 3
    static let minimumCharacters = 800
    static let charactersPerReview = 700
    static let totalCharacters = 6_000

    /// The reviews' text to sum up, each cut to a length the on-device model can take together. Nil with fewer than three reviews or
    /// too little text: a consensus of one or two reviews is not one.
    static func excerpts(_ reviews: [TMDbReview]) -> [String]? {
        let texts = reviews.map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard texts.count >= minimumReviews, texts.reduce(0, { $0 + $1.count }) >= minimumCharacters else { return nil }
        var total = 0
        var excerpts: [String] = []
        for text in texts {
            let excerpt = String(text.prefix(charactersPerReview))
            guard total + excerpt.count <= totalCharacters else { break }
            total += excerpt.count
            excerpts.append(excerpt)
        }
        return excerpts.count >= minimumReviews ? excerpts : nil
    }

    /// The line for a title's reviews, from the cache when this run read them already. Nil with too few reviews, no summarizer, or
    /// nothing the reviews agree on that their own words support.
    @MainActor static func line(for reviews: [TMDbReview], using summarizer: (any ReviewSummarizing)?) async -> String? {
        guard let summarizer, let excerpts = excerpts(reviews) else { return nil }
        let key = reviews.map(\.id)
        if let cached = cache[key] { return cached }
        let consensus = await summarizer.consensus(of: excerpts)
        guard !Task.isCancelled, let line = consensus?.grounded(in: excerpts).text else { return nil }
        cache[key] = line
        return line
    }

    /// The summarizer for this device, or nil where Apple Intelligence is not available: then no consensus is shown.
    static func available() -> (any ReviewSummarizing)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            return ModelReviewSummarizer()
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
struct ModelReviewSummarizer: ReviewSummarizing {
    private static let instructions = """
        You read viewers' reviews of one film or series and say what several of them praise and what several complain about. Use only \
        what the reviews say: never add an opinion, a score or a fact of your own, and leave a list empty when the reviews do not agree.
        """

    func consensus(of reviews: [String]) async -> ReviewConsensus? {
        let prompt = reviews.enumerated().map { "Review \($0.offset + 1): \($0.element)" }.joined(separator: "\n\n")
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let answer = try await session.respond(to: prompt, generating: GeneratedConsensus.self,
                                                   options: GenerationOptions(samplingMode: .greedy)).content
            return ReviewConsensus(praise: answer.praise, complaints: answer.complaints)
        } catch {
            return nil
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedConsensus {
    @Guide(description: """
        Up to three things several reviews praise, each a noun phrase of two to four words naming what is good, such as the \
        performances, the cinematography or the score
        """, .maximumCount(3))
    var praise: [String]
    @Guide(description: """
        Up to three things several reviews complain about, each a noun phrase of two to four words naming what is weak, such as \
        the slow pacing, the ending or the runtime
        """, .maximumCount(3))
    var complaints: [String]
}
#endif
