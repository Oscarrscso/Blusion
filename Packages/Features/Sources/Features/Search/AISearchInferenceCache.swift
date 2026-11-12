import Foundation
import StremioKit

/// Reuse successful inference and TMDb's answer for a name, not finished result rows: watched history and database candidates are
/// checked on every search.
actor AISearchInferenceCache {
    static let shared = AISearchInferenceCache()

    struct RankingKey: Hashable, Sendable {
        let request: String
        let references: [String]
        let candidates: [String]
        let watched: [String]
    }

    private struct Entry<Value: Sendable>: Sendable {
        let value: Value
        let date: Date
    }

    private let limit = 32
    private let lifetime: TimeInterval = 900
    private var plans: [String: Entry<AISearchPlan>] = [:]
    private var rankings: [RankingKey: Entry<[Int]>] = [:]
    private var hits: [String: Entry<TMDbSearchHits>] = [:]
    private var lookups: [String: Task<TMDbSearchHits, any Error>] = [:]

    /// TMDb's titles and people for a name, asked once however many parts of a search want them: the results row, the suggestions
    /// and the described search share one request, and a repeat within the lifetime asks nothing. A failure is not kept.
    func hits(for key: String, at date: Date = Date(),
              fetch: @escaping @Sendable () async throws -> TMDbSearchHits) async throws -> TMDbSearchHits {
        if let entry = hits[key], date.timeIntervalSince(entry.date) < lifetime { return entry.value }
        if let running = lookups[key] { return try await running.value }
        let task = Task { try await fetch() }
        lookups[key] = task
        defer { lookups[key] = nil }
        let found = try await task.value
        hits[key] = Entry(value: found, date: date)
        if hits.count > limit, let oldest = hits.min(by: { $0.value.date < $1.value.date })?.key { hits[oldest] = nil }
        return found
    }

    func plan(for request: String, at date: Date = Date()) -> AISearchPlan? {
        guard let entry = plans[request], date.timeIntervalSince(entry.date) < lifetime else { return nil }
        return entry.value
    }

    func store(_ plan: AISearchPlan, for request: String, at date: Date = Date()) {
        plans[request] = Entry(value: plan, date: date)
        if plans.count > limit, let oldest = plans.min(by: { $0.value.date < $1.value.date })?.key { plans[oldest] = nil }
    }

    func ranking(for key: RankingKey, at date: Date = Date()) -> [Int]? {
        guard let entry = rankings[key], date.timeIntervalSince(entry.date) < lifetime else { return nil }
        return entry.value
    }

    func store(_ numbers: [Int], for key: RankingKey, at date: Date = Date()) {
        rankings[key] = Entry(value: numbers, date: date)
        if rankings.count > limit, let oldest = rankings.min(by: { $0.value.date < $1.value.date })?.key { rankings[oldest] = nil }
    }
}
