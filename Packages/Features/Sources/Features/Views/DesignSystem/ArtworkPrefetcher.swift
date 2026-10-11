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
    /// Everything the last update named, wanted or visible: what the prefetcher is answerable for evicting once it is no longer named.
    private var tracked: Set<Request> = []
    private var tasks: [Request: Task<Void, Never>] = [:]
    private var held: [Request: UIImage] = [:]

    /// Makes `wanted` the set that is loaded and held: starts what is new, cancels and releases what is gone. `visible` are the requests of
    /// the cards on screen right now; they load as cards, are never held here, and are never evicted. A request that is named by neither
    /// is dropped from the decoded cache too, so memory stays at the visible posters plus the buffer. A poster shown elsewhere keeps its
    /// picture through its own view's state and simply reloads from the URL cache on disk the next time it is asked for.
    func update(wanted newWanted: [Request], visible: [Request] = []) {
        let newSet = Set(newWanted)
        let newTracked = newSet.union(visible)
        for request in wanted.subtracting(newSet) {
            tasks.removeValue(forKey: request)?.cancel()
            held.removeValue(forKey: request)
        }
        for request in tracked.subtracting(newTracked) {
            ImagePipeline.shared.evict(request.url, maxPixelSize: request.maxPixelSize)
        }
        wanted = newSet
        tracked = newTracked
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

    /// Stops all loading and lets go of the held images, but leaves the decoded cache alone: the grid may come straight back.
    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        held = [:]
        wanted = []
        tracked = []
    }

    private func finish(_ request: Request, image: UIImage) {
        // A request dropped while it was loading is not held.
        guard wanted.contains(request) else { return }
        tasks[request] = nil
        held[request] = image
    }
}
#endif
