import Foundation
import StremioKit

public struct SubtitleOption: Sendable, Equatable, Identifiable {
    public enum Source: Sendable, Equatable {
        case stream
        case addon(String)
    }

    public let id: String
    /// Canonical ISO 639-2 code (`eng`).
    public let language: String
    public let title: String
    public let url: URL
    public let source: Source

    public init(id: String, language: String, title: String, url: URL, source: Source) {
        self.id = id
        self.language = language
        self.title = title
        self.url = url
        self.source = source
    }
}

/// Finds and loads external subtitles: those bundled with the stream, and those from addons that offer the `subtitles` resource.
public final class SubtitleService: Sendable {
    private let registry: AddonRegistry
    private let client: AddonClient

    public init(registry: AddonRegistry, client: AddonClient) {
        self.registry = registry
        self.client = client
    }

    /// Asks every addon that supports `subtitles` for this request, in parallel, passing the stream's hash, size and filename when known.
    public func fetch(for candidate: PlaybackCandidate, request: StreamRequest) async -> AsyncStream<AddonResponse<[SubtitleItem]>> {
        let addons = await registry.addons(for: .subtitles, type: request.type, id: request.id)
        var extras: [ExtraParam] = []
        if let hash = candidate.videoHash { extras.append(ExtraParam("videoHash", hash)) }
        if let size = candidate.videoSize { extras.append(ExtraParam("videoSize", String(size))) }
        if let filename = candidate.filename { extras.append(ExtraParam("filename", filename)) }
        let client = self.client
        let finalExtras = extras
        return FanOut.run(over: addons) { addon in
            try await client.subtitles(base: addon.baseURL, type: request.type, id: request.id, extras: finalExtras)
        }
    }

    /// Options from stream-bundled subtitles.
    public static func options(from streamSubtitles: [SubtitleItem]) -> [SubtitleOption] {
        streamSubtitles.map { option(from: $0, source: .stream) }
    }

    public static func options(from items: [SubtitleItem], addon: String) -> [SubtitleOption] {
        items.map { option(from: $0, source: .addon(addon)) }
    }

    private static func option(from item: SubtitleItem, source: SubtitleOption.Source) -> SubtitleOption {
        let language = LanguageCodes.normalise(item.lang)
        var title = LanguageCodes.displayName(item.lang)
        if case .addon(let name) = source { title += " · \(name)" }
        return SubtitleOption(id: "\(item.id)|\(item.url.absoluteString)", language: language, title: title, url: item.url, source: source)
    }

    /// Appends `new` options, dropping any whose URL is already present.
    public static func merge(_ existing: [SubtitleOption], _ new: [SubtitleOption]) -> [SubtitleOption] {
        var seen = Set(existing.map(\.url))
        return existing + new.filter { seen.insert($0.url).inserted }
    }

    /// The option matching the preferred language; stream-bundled subtitles win over addon ones, then list order.
    public static func defaultOption(in options: [SubtitleOption], preferredLanguage: String?) -> SubtitleOption? {
        guard let preferredLanguage, !preferredLanguage.isEmpty else { return nil }
        let matching = options.filter { LanguageCodes.matches($0.language, preferred: preferredLanguage) }
        return matching.first { $0.source == .stream } ?? matching.first
    }

    /// Downloads (capped at 4 MB) and parses an option.
    public func load(_ option: SubtitleOption) async throws -> SubtitleTimeline {
        let result = try await client.get(option.url, limits: FetchLimits(maxBytes: SubtitleParser.maximumBytes))
        return SubtitleTimeline(cues: try SubtitleParser.parse(data: result.data).cues)
    }
}
