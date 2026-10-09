import Foundation

/// Opt-in release comparison. This estimates quality from addon metadata, without changing manual listing order.
public enum AutoStreamRanking {
    public struct Assessment: Sendable {
        public let item: RankedStream
        public let qualityScore: Double
        public let bitrateMbps: Double?
        public let seeders: Int?
        public let isRemux: Bool
    }

    public static func assess(_ item: RankedStream, duration: TimeInterval?) -> Assessment {
        let text = [item.stream.name, item.stream.description, item.stream.behaviorHints.filename].compactMap { $0 }
            .joined(separator: " ").lowercased()
        let remux = expressions[#"\bremux\b"#]?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        var bitrate = number(#"([0-9]+(?:\.[0-9]+)?)\s*(?:mbps|mb/s|mbit/s)\b"#, in: text)
        if bitrate == nil, let bytes = item.quality.sizeBytes, bytes > 0, let duration, duration > 0 {
            bitrate = Double(bytes) * 8 / duration / 1_000_000
        }
        let seeds = number(#"(?:seeders?\s*[:=]?\s*|[👤👥🌱]\s*)([0-9]+)\b"#, in: text)
            ?? number(#"\b([0-9]+)\s*seeders?\b"#, in: text)
        let quality = item.quality
        let resolution = quality.resolution ?? 0
        var score: Double = resolution >= 2160 ? 16 : resolution >= 1080 ? 10 : resolution >= 720 ? 2 : 0
        switch quality.source {
        case .bluray: score += 26
        case .webDL: score += 20
        case .webRip: score += 12
        case .hdtv: score += 8
        case .dvd: score += 2
        case .cam: score -= 30
        case nil: break
        }
        if remux { score += 10 }
        if let bitrate, resolution > 0 {
            // More pixels need more data; HEVC/AV1 use less than H.264 for comparable fidelity.
            let pixels = resolution >= 2160 ? 2.8 : resolution >= 1080 ? 1.0 : 0.5
            let codec = quality.videoCodec == .av1 ? 0.55 : quality.videoCodec == .hevc ? 0.65 : 1.0
            let target = 16 * pixels * codec
            score += max(-22, min(12, (bitrate / target - 1) * 18))
        }
        if quality.isHDR { score += 4 }
        if quality.isDolbyVision { score += 1 }
        if quality.audioCodecs.contains(where: { [.trueHD, .dtsHD, .flac].contains($0) }) { score += 3 }
        if quality.hasAtmos { score += 2 }
        let seeders = seeds.flatMap { $0 >= 0 && $0 < Double(Int.max) ? Int($0) : nil }
        return Assessment(item: item, qualityScore: score, bitrateMbps: bitrate, seeders: seeders, isRemux: remux)
    }

    public static func best(from items: [RankedStream], duration: TimeInterval?) -> Assessment? {
        let ranked = items.map { assess($0, duration: duration) }.sorted {
            if $0.qualityScore != $1.qualityScore { return $0.qualityScore > $1.qualityScore }
            return StreamRanking.isOrdered($0.item, before: $1.item)
        }
        guard let best = ranked.first else { return nil }
        // Known-dead torrents lose to available alternatives; unknown counts remain eligible.
        let available = ranked.filter { $0.seeders != 0 }
        let leader = best.seeders == 0 ? (available.first ?? best) : best
        let close = ranked.filter { $0.qualityScore >= leader.qualityScore - 6 && ($0.seeders ?? -1) >= 5 }
        if let seeds = leader.seeders, seeds < 5, let healthy = close.first { return healthy }
        // Within a very small quality difference, use a known healthy swarm as the tie-breaker.
        return close.filter { $0.qualityScore >= leader.qualityScore - 2 }.max {
            ($0.seeders ?? 0) < ($1.seeders ?? 0)
        } ?? leader
    }

    private static let expressions: [String: NSRegularExpression] = {
        let patterns = [
            #"\bremux\b"#,
            #"([0-9]+(?:\.[0-9]+)?)\s*(?:mbps|mb/s|mbit/s)\b"#,
            #"(?:seeders?\s*[:=]?\s*|[👤👥🌱]\s*)([0-9]+)\b"#,
            #"\b([0-9]+)\s*seeders?\b"#,
        ]
        return Dictionary(uniqueKeysWithValues: patterns.compactMap { pattern in
            (try? NSRegularExpression(pattern: pattern)).map { (pattern, $0) }
        })
    }()

    private static func number(_ pattern: String, in text: String) -> Double? {
        guard let regex = expressions[pattern],
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text), let value = Double(text[range]), value.isFinite else { return nil }
        return value
    }
}
