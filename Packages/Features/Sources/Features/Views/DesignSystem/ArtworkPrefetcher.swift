#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// Loads the posters just off screen in a long grid ahead of time and holds them, so scrolling shows the picture in the card's first
/// frame. A grid owns one (as `@State`) and tells it which requests it wants after every change of what is visible. Loads run at low
/// priority and are cancelled when the request is no longer wanted. The decoded images are held strongly while they are wanted, so
/// the buffer does not empty when the shared cache trims; they are released when they leave the buffer.
@MainActor
final class ArtworkPrefetcher {
    /// One image as a card asks for it: the pipeline's cache key is this URL and size.
    struct Request: Hashable, Sendable {
        let url: URL
        let maxPixelSize: CGFloat
    }

    private var wanted: Set<Request> = []
    private var tasks: [Request: Task<Void, Never>] = [:]
    private var held: [Request: UIImage] = [:]

    /// Makes `wanted` the set that is loaded and held: starts what is new, cancels and releases what is gone.
    func update(wanted newWanted: [Request]) {
        let newSet = Set(newWanted)
        for request in wanted.subtracting(newSet) {
            tasks.removeValue(forKey: request)?.cancel()
            held.removeValue(forKey: request)
        }
        wanted = newSet
        for request in newWanted where tasks[request] == nil && held[request] == nil {
            if let cached = ImagePipeline.shared.cachedImage(for: request.url, maxPixelSize: request.maxPixelSize) {
                held[request] = cached
                continue
            }
            tasks[request] = Task { [weak self] in
                let image = try? await ImagePipeline.shared.image(for: request.url, maxPixelSize: request.maxPixelSize, priority: .low)
                guard !Task.isCancelled, let image else { return }
                self?.finish(request, image: image)
            }
        }
    }

    func cancelAll() {
        update(wanted: [])
    }

    private func finish(_ request: Request, image: UIImage) {
        // A request dropped while it was loading is not held.
        guard wanted.contains(request) else { return }
        tasks[request] = nil
        held[request] = image
    }

    /// The images a grid card for `item` asks `ImagePipeline` for, with the same URLs and sizes. This mirrors `MediaCard` (its
    /// `resolvedWidth`, `pixelSize`, `artworkURL` and the `LandscapeArtwork` branch) for a `.medium` card without a fixed width, which
    /// is what `MediaGrid` draws. Keep the two in step.
    static func requests(for item: MetaPreview, aspect: CardAspect, metrics: LayoutMetrics, isLandscape: Bool,
                         displayScale: CGFloat) -> [Request] {
        let landscapePoster = isLandscape && aspect == .poster
        let width = landscapePoster ? metrics.landscapePosterWidth.rounded() : CardSize.medium.width(for: aspect, metrics: metrics)
        let ratio = (landscapePoster ? CardAspect.wide : aspect).ratio
        let size = min((max(width, width / ratio) * displayScale).rounded(.up), 1200)
        if landscapePoster {
            var requests: [Request] = []
            if let artwork = item.background ?? MetahubArtwork.background(imdbID: item.id) ?? item.poster {
                requests.append(Request(url: artwork, maxPixelSize: size))
            }
            if let logo = item.logo ?? MetahubArtwork.logo(imdbID: item.id) {
                requests.append(Request(url: logo, maxPixelSize: 400))
            }
            return requests
        }
        let url: URL? = aspect == .wide ? item.background ?? item.poster : item.poster
        return url.map { [Request(url: $0, maxPixelSize: size)] } ?? []
    }
}
#endif
