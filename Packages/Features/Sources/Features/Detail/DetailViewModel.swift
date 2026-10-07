import Foundation
import Observation
import StremioKit

/// Detail: starts from the catalog preview, upgrades to the addon's full `meta` when it arrives.
@MainActor
@Observable
public final class DetailViewModel {
    public let preview: MetaPreview
    public private(set) var detail: MetaDetail
    public private(set) var isLoading = true
    /// True when no addon returned `meta` and Detail is built from the catalog preview alone.
    public private(set) var isFallback = false
    public var selectedSeason: Int?

    private let services: AppServices

    public init(preview: MetaPreview, services: AppServices) {
        self.preview = preview
        self.detail = .fallback(from: preview)
        self.services = services
    }

    public func load() async {
        isLoading = true
        let result = await services.browse.detail(for: preview)
        detail = result.detail
        isFallback = result.isFallback
        if selectedSeason == nil { selectedSeason = detail.seasons.first }
        isLoading = false
    }

    public var isSeries: Bool { detail.type == "series" || !detail.videos.isEmpty }
    public var seasons: [Int] { detail.seasons }
    public var episodes: [Video] { selectedSeason.map { detail.episodes(inSeason: $0) } ?? [] }

    /// What "Play" asks addons for: the movie itself.
    public var movieRequest: StreamRequest { StreamRequest(movie: detail.preview.type.isEmpty ? preview : detail.preview) }

    public func request(for video: Video) -> StreamRequest { StreamRequest(episode: video, of: detail) }

    public var subtitle: String {
        [detail.preview.releaseInfo, detail.preview.runtime, detail.preview.imdbRating.map { String(format: "★ %.1f", $0) }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
