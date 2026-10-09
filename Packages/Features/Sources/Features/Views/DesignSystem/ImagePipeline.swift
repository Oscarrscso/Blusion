#if canImport(UIKit)
import Foundation
import ImageIO
import UIKit

/// Loads, downsamples and caches artwork for `ArtworkImage`. Images are decoded at the size they are shown, not at the size
/// of the file, so a long row of posters keeps a few megabytes decoded rather than hundreds.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let session: URLSession
    /// `NSCache` is thread-safe, which is what lets `cachedImage` answer without hopping onto the actor.
    private nonisolated(unsafe) let decoded = NSCache<NSString, UIImage>()
    /// Downloads and decodes still running, keyed like the cache, so two views asking for one poster share one request.
    private struct Pending {
        let task: Task<UIImage, Error>
        var consumers: Set<UUID>
    }
    private var inFlight: [String: Pending] = [:]
    private var activeDownloads = 0
    private var waiting: [(id: UUID, priority: TaskPriority, continuation: CheckedContinuation<Void, Error>)] = []

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
        // Artwork rarely changes, so a cached copy is served without asking the server again.
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
        decoded.totalCostLimit = 64 * 1024 * 1024
    }

    /// A picture that is already decoded, without waiting. A card that scrolls back into view shows its artwork in the same
    /// frame instead of flashing its placeholder.
    nonisolated func cachedImage(for url: URL, maxPixelSize: CGFloat) -> UIImage? {
        decoded.object(forKey: Self.key(url, maxPixelSize: maxPixelSize) as NSString)
    }

    /// The size is part of the key: a 44 pt thumbnail and a full-width backdrop of one title are different images.
    private static func key(_ url: URL, maxPixelSize: CGFloat) -> String {
        "\(Int(min(max(maxPixelSize.rounded(), 1), 4096)))|\(url.absoluteString)"
    }

    /// The image at `url`, decoded no larger than `maxPixelSize` on its long edge. Memory-cached; concurrent requests for
    /// the same URL and size share one download. Only http and https URLs are loaded.
    func image(for url: URL, maxPixelSize: CGFloat, priority: TaskPriority = .medium) async throws -> UIImage {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ImagePipelineError.unsupportedURL
        }
        let size = min(max(maxPixelSize.rounded(), 1), 4096)
        try Task.checkCancellation()
        let key = Self.key(url, maxPixelSize: maxPixelSize)
        if let cached = decoded.object(forKey: key as NSString) { return cached }
        let consumer = UUID()
        let task: Task<UIImage, Error>
        if var pending = inFlight[key] {
            pending.consumers.insert(consumer)
            inFlight[key] = pending
            task = pending.task
        } else {
            task = Task(priority: priority) {
                try await acquireDownloadSlot(priority: priority)
                defer { releaseDownloadSlot() }
                try Task.checkCancellation()
                return try await Self.fetch(url, maxPixelSize: size, session: session)
            }
            inFlight[key] = Pending(task: task, consumers: [consumer])
        }
        return try await withTaskCancellationHandler {
            defer { releaseConsumer(consumer, for: key) }
            let image = try await task.value
            try Task.checkCancellation()
            decoded.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
            return image
        } onCancel: {
            Task { await self.releaseConsumer(consumer, for: key) }
        }
    }

    private func releaseConsumer(_ consumer: UUID, for key: String) {
        guard var pending = inFlight[key], pending.consumers.remove(consumer) != nil else { return }
        if pending.consumers.isEmpty {
            pending.task.cancel()
            inFlight[key] = nil
        } else { inFlight[key] = pending }
    }

    private func acquireDownloadSlot(priority: TaskPriority) async throws {
        try Task.checkCancellation()
        // Keep one of the six slots available for title logos, even when posters fill the queue.
        if activeDownloads < (priority >= .high ? 6 : 5) { activeDownloads += 1; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let index = waiting.firstIndex { $0.priority < priority } ?? waiting.endIndex
                waiting.insert((id, priority, continuation), at: index)
            }
        } onCancel: {
            Task { await self.cancelWaitingDownload(id) }
        }
    }

    private func cancelWaitingDownload(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func releaseDownloadSlot() {
        activeDownloads -= 1
        guard let next = waiting.first, activeDownloads < (next.priority >= .high ? 6 : 5) else { return }
        activeDownloads += 1
        waiting.removeFirst().continuation.resume()
    }

    /// Runs off the actor, so a slow download or decode never blocks requests for other images.
    private nonisolated static func fetch(_ url: URL, maxPixelSize: CGFloat, session: URLSession) async throws -> UIImage {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ImagePipelineError.httpStatus(http.statusCode)
        }
        guard let image = decode(data, maxPixelSize: maxPixelSize) else {
            throw ImagePipelineError.undecodable
        }
        return image
    }

    /// ImageIO builds the thumbnail straight from the compressed data, so the full-size bitmap is never created.
    private nonisolated static func decode(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

enum ImagePipelineError: Error, Sendable {
    case unsupportedURL
    case httpStatus(Int)
    case undecodable
}
#endif
