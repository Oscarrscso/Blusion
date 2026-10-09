import Foundation

public enum AudioCodec: String, Sendable, Equatable, Hashable {
    case aac, ac3, eac3, dts, dtsHD, trueHD, flac, opus, mp3

    /// AVPlayer cannot decode these (PLAN §4).
    public var needsFallbackEngine: Bool { self == .dts || self == .dtsHD || self == .trueHD }
}

public enum VideoCodec: String, Sendable, Equatable, Hashable {
    case h264, hevc, av1
}

/// Release source, ordered best to worst by `rank`.
public enum StreamSourceKind: String, Sendable, Equatable, Hashable {
    case bluray, webDL, webRip, hdtv, dvd, cam

    public var rank: Int {
        switch self {
        case .bluray: return 5
        case .webDL: return 4
        case .webRip: return 3
        case .hdtv: return 2
        case .dvd: return 1
        case .cam: return 0
        }
    }
}

/// Which Dolby Atmos a release carries, from the codec of its Atmos track: E-AC-3 (Dolby Digital Plus) with Atmos is the lossy
/// streaming kind, TrueHD with Atmos is the lossless Blu-ray kind.
public enum AtmosFormat: String, Sendable, Equatable, Hashable {
    case streaming, lossless
}

/// Facts guessed from a stream's `name`, `description` and filename. Addons put them in free text, so this is heuristic.
public struct StreamQuality: Sendable, Equatable {
    /// Vertical resolution (2160, 1080, 720, 480, …).
    public var resolution: Int?
    public var isHDR = false
    public var isDolbyVision = false
    public var source: StreamSourceKind?
    public var videoCodec: VideoCodec?
    public var audioCodecs: [AudioCodec] = []
    public var hasAtmos = false
    public var sizeBytes: Int64?

    public init(resolution: Int? = nil, isHDR: Bool = false, isDolbyVision: Bool = false, source: StreamSourceKind? = nil,
                videoCodec: VideoCodec? = nil, audioCodecs: [AudioCodec] = [], hasAtmos: Bool = false, sizeBytes: Int64? = nil) {
        self.resolution = resolution
        self.isHDR = isHDR
        self.isDolbyVision = isDolbyVision
        self.source = source
        self.videoCodec = videoCodec
        self.audioCodecs = audioCodecs
        self.hasAtmos = hasAtmos
        self.sizeBytes = sizeBytes
    }

    /// True when the only audio the text names is something AVPlayer can't decode. A release that also lists AAC or AC-3 is fine,
    /// because the player picks a decodable track.
    public var audioNeedsFallbackEngine: Bool {
        audioCodecs.contains { $0.needsFallbackEngine } && !audioCodecs.contains { !$0.needsFallbackEngine }
    }

    /// The kind of Atmos, read from the audio codec beside it, not from the release's source: TrueHD wins when both are named, since
    /// a lossless track is the one a viewer picks Atmos for. Nil when there is no Atmos, or the codec does not say which kind.
    public var atmosFormat: AtmosFormat? {
        guard hasAtmos else { return nil }
        if audioCodecs.contains(.trueHD) { return .lossless }
        if audioCodecs.contains(.eac3) { return .streaming }
        return nil
    }

    public var resolutionLabel: String? {
        switch resolution {
        case .some(let value) where value >= 2160: return "4K"
        case .some(let value): return "\(value)p"
        case .none: return nil
        }
    }

    public static func parse(from texts: [String?]) -> StreamQuality {
        let text = texts.compactMap { $0 }.joined(separator: " \n ").lowercased()
        var quality = StreamQuality()
        guard !text.isEmpty else { return quality }

        quality.resolution = resolution(in: text)
        quality.isDolbyVision = matches(#"\b(dolby[ .\-]?vision|dovi|dv)\b"#, in: text)
        quality.isHDR = matches(#"\bhdr(10)?\+?\b"#, in: text) || quality.isDolbyVision
        quality.source = source(in: text)
        quality.videoCodec = videoCodec(in: text)
        quality.audioCodecs = audioCodecs(in: text)
        quality.hasAtmos = matches(#"\batmos\b"#, in: text)
        quality.sizeBytes = size(in: text)
        return quality
    }

    public static func parse(_ stream: AddonStream) -> StreamQuality {
        var quality = parse(from: [stream.name, stream.description, stream.behaviorHints.filename])
        if quality.sizeBytes == nil, let size = stream.behaviorHints.videoSize { quality.sizeBytes = size }
        return quality
    }

    // MARK: - Pattern helpers

    private static func resolution(in text: String) -> Int? {
        if matches(#"\b(2160p|4k|uhd)\b"#, in: text) { return 2160 }
        if matches(#"\b1440p\b"#, in: text) { return 1440 }
        if matches(#"\b(1080[pi]|fhd|full[ .\-]?hd)\b"#, in: text) { return 1080 }
        if matches(#"\b(720p|hd720)\b"#, in: text) { return 720 }
        if matches(#"\b576p\b"#, in: text) { return 576 }
        if matches(#"\b(480p|sd)\b"#, in: text) { return 480 }
        if matches(#"\b360p\b"#, in: text) { return 360 }
        // 1920x1080
        if let match = firstMatch(#"\b(\d{3,4})\s?x\s?(\d{3,4})\b"#, in: text), match.count == 3, let height = Int(match[2]), (240...4320).contains(height) {
            return height
        }
        return nil
    }

    private static func source(in text: String) -> StreamSourceKind? {
        if matches(#"\b(hdcam|camrip|cam|telesync|hdts|tsrip)\b"#, in: text) { return .cam }
        if matches(#"\b(blu[ .\-]?ray|bdrip|brrip|remux)\b"#, in: text) { return .bluray }
        if matches(#"\bweb[ .\-]?dl\b"#, in: text) { return .webDL }
        if matches(#"\bweb[ .\-]?rip\b"#, in: text) { return .webRip }
        if matches(#"\bhdtv\b"#, in: text) { return .hdtv }
        if matches(#"\b(dvdrip|dvd)\b"#, in: text) { return .dvd }
        return nil
    }

    private static func videoCodec(in text: String) -> VideoCodec? {
        if matches(#"\b(x265|h[ .]?265|hevc)\b"#, in: text) { return .hevc }
        if matches(#"\b(x264|h[ .]?264|avc)\b"#, in: text) { return .h264 }
        if matches(#"\bav1\b"#, in: text) { return .av1 }
        return nil
    }

    /// Codecs are tested most specific first and each match is blanked out, so "E-AC3" doesn't also read as "AC3" and "DTS-HD" doesn't also read as "DTS".
    private static func audioCodecs(in text: String) -> [AudioCodec] {
        var remaining = text
        var found: [AudioCodec] = []
        func take(_ codec: AudioCodec, _ pattern: String) {
            guard matches(pattern, in: remaining) else { return }
            if !found.contains(codec) { found.append(codec) }
            if let regex = expressions[pattern] {
                remaining = regex.stringByReplacingMatches(in: remaining, range: NSRange(remaining.startIndex..., in: remaining), withTemplate: " ")
            }
        }
        take(.dtsHD, #"\b(dts[ .\-]?hd([ .\-]?ma)?|dts[ .\-]?x)\b"#)
        take(.dts, #"\bdts\b"#)
        take(.trueHD, #"\btrue[ .\-]?hd\b"#)
        take(.eac3, #"\b(e[ .\-]?ac[ .\-]?3|ddp(\d\.\d)?|dd\+)(?=\W|$)"#)
        take(.ac3, #"\b(ac[ .\-]?3|dd5[ .]1|dd2[ .]0|dolby[ .\-]?digital)\b"#)
        take(.aac, #"\baac(\d\.\d)?\b"#)
        take(.flac, #"\bflac\b"#)
        take(.opus, #"\bopus\b"#)
        take(.mp3, #"\bmp3\b"#)
        return found
    }

    private static func size(in text: String) -> Int64? {
        guard let match = firstMatch(#"(\d+(?:[.,]\d+)?)\s?(gb|gib|mb|mib)\b"#, in: text), match.count == 3,
              let value = Double(match[1].replacingOccurrences(of: ",", with: ".")) else { return nil }
        let multiplier: Double = match[2].hasPrefix("g") ? 1_073_741_824 : 1_048_576
        return Int64(value * multiplier)
    }

    /// Fixed release patterns are compiled once and shared safely across parses.
    private static let expressions: [String: NSRegularExpression] = {
        let patterns = [
            #"\b(dolby[ .\-]?vision|dovi|dv)\b"#,
            #"\bhdr(10)?\+?\b"#,
            #"\batmos\b"#,
            #"\b(2160p|4k|uhd)\b"#,
            #"\b1440p\b"#,
            #"\b(1080[pi]|fhd|full[ .\-]?hd)\b"#,
            #"\b(720p|hd720)\b"#,
            #"\b576p\b"#,
            #"\b(480p|sd)\b"#,
            #"\b360p\b"#,
            #"\b(\d{3,4})\s?x\s?(\d{3,4})\b"#,
            #"\b(hdcam|camrip|cam|telesync|hdts|tsrip)\b"#,
            #"\b(blu[ .\-]?ray|bdrip|brrip|remux)\b"#,
            #"\bweb[ .\-]?dl\b"#,
            #"\bweb[ .\-]?rip\b"#,
            #"\bhdtv\b"#,
            #"\b(dvdrip|dvd)\b"#,
            #"\b(x265|h[ .]?265|hevc)\b"#,
            #"\b(x264|h[ .]?264|avc)\b"#,
            #"\bav1\b"#,
            #"\b(dts[ .\-]?hd([ .\-]?ma)?|dts[ .\-]?x)\b"#,
            #"\bdts\b"#,
            #"\btrue[ .\-]?hd\b"#,
            #"\b(e[ .\-]?ac[ .\-]?3|ddp(\d\.\d)?|dd\+)(?=\W|$)"#,
            #"\b(ac[ .\-]?3|dd5[ .]1|dd2[ .]0|dolby[ .\-]?digital)\b"#,
            #"\baac(\d\.\d)?\b"#,
            #"\bflac\b"#,
            #"\bopus\b"#,
            #"\bmp3\b"#,
            #"(\d+(?:[.,]\d+)?)\s?(gb|gib|mb|mib)\b"#,
        ]
        return Dictionary(uniqueKeysWithValues: patterns.compactMap { pattern in
            (try? NSRegularExpression(pattern: pattern)).map { (pattern, $0) }
        })
    }()

    private static func matches(_ pattern: String, in text: String) -> Bool {
        expressions[pattern]?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Whole match followed by capture groups, or nil.
    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = expressions[pattern],
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
