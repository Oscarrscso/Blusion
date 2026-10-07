import Foundation

public struct SubtitleCue: Sendable, Equatable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public enum SubtitleFormat: String, Sendable {
    case srt, vtt
}

public enum SubtitleError: Error, Equatable, Sendable {
    case empty
    case unreadable
    case tooLarge
}

/// Parses SRT and WebVTT leniently: real subtitle files have BOMs, CRLF, missing indexes, dots instead of commas, and junk.
public enum SubtitleParser {
    public static let maximumBytes = 4 * 1024 * 1024

    /// Decodes bytes (UTF-8/16 with BOM, UTF-8, else Windows-1252) and parses, detecting WebVTT by its header.
    public static func parse(data: Data) throws -> (cues: [SubtitleCue], format: SubtitleFormat) {
        guard data.count <= maximumBytes else { throw SubtitleError.tooLarge }
        guard let text = decode(data) else { throw SubtitleError.unreadable }
        let trimmed = text.drop { $0.isWhitespace }
        let format: SubtitleFormat = trimmed.hasPrefix("WEBVTT") ? .vtt : .srt
        let cues = format == .vtt ? parseVTT(text) : parseSRT(text)
        guard !cues.isEmpty else { throw SubtitleError.empty }
        return (cues, format)
    }

    public static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        if data.starts(with: [0xFF, 0xFE]) { return String(data: data, encoding: .utf16LittleEndian) }
        if data.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16BigEndian) }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1)
    }

    public static func parseSRT(_ text: String) -> [SubtitleCue] {
        parseBlocks(text, vtt: false)
    }

    public static func parseVTT(_ text: String) -> [SubtitleCue] {
        parseBlocks(text, vtt: true)
    }

    // MARK: - Internals

    private static func parseBlocks(_ text: String, vtt: Bool) -> [SubtitleCue] {
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []
        for block in normalised.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            if vtt, let first = lines.first, first.hasPrefix("NOTE") || first.hasPrefix("STYLE") || first.hasPrefix("REGION") { continue }
            guard let (start, end) = parseTiming(lines[timingIndex]), end >= start else { continue }
            let body = lines[(timingIndex + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = clean(body)
            if !cleaned.isEmpty { cues.append(SubtitleCue(start: start, end: end, text: cleaned)) }
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// `00:01:02,500 --> 00:01:04,000 position:50%`, `01:02.500 --> 01:04.000`
    static func parseTiming(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2, let start = parseTimestamp(parts[0]) else { return nil }
        let endText = parts[1].trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        guard let end = parseTimestamp(endText) else { return nil }
        return (start, end)
    }

    /// `HH:MM:SS.mmm` or `MM:SS.mmm` (comma or dot before the milliseconds). Out-of-range fields are tolerated: real files have them.
    static func parseTimestamp(_ text: String) -> TimeInterval? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let pieces = cleaned.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(pieces.count) else { return nil }
        var total = 0.0
        for piece in pieces {
            guard let value = Double(piece), value >= 0, value.isFinite else { return nil }
            total = total * 60 + value
        }
        return total
    }

    /// Strips markup (`<i>`, `<c.cls>`, `<v Name>`, inline timestamps, `{\an8}`), decodes entities, trims lines.
    static func clean(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: #"\{\\[^}]*\}"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"</?[a-zA-Z][^>]*>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"<\d{1,2}:\d{2}[:.]\d{2,3}(\.\d{1,3})?>"#, with: "", options: .regularExpression)
        for (entity, replacement) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " "), ("&lrm;", ""), ("&rlm;", "")] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

/// Cues sorted by start time, with a shift. Look-ups are O(log n + overlap), cheap enough to run every frame.
public struct SubtitleTimeline: Sendable, Equatable {
    public let cues: [SubtitleCue]
    private let maxDuration: TimeInterval

    public init(cues: [SubtitleCue]) {
        self.cues = cues.sorted { $0.start < $1.start }
        self.maxDuration = cues.map { $0.end - $0.start }.max() ?? 0
    }

    /// Text to show at `position` seconds of playback. `offset` delays the subtitles (positive) or advances them (negative).
    public func text(at position: TimeInterval, offset: TimeInterval = 0) -> String? {
        let time = position - offset
        guard !cues.isEmpty, time >= 0 else { return nil }
        // First cue whose start is > time, then walk back while a cue could still be active.
        var low = 0, high = cues.count
        while low < high {
            let mid = (low + high) / 2
            if cues[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        var active: [String] = []
        var index = low - 1
        while index >= 0, cues[index].start + maxDuration >= time {
            if cues[index].end > time { active.append(cues[index].text) }
            index -= 1
        }
        return active.isEmpty ? nil : active.reversed().joined(separator: "\n")
    }
}
