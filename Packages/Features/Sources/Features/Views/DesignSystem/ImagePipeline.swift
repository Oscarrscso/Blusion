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
    private var inFlight: [String: Task<UIImage, Error>] = [:]

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
    func image(for url: URL, maxPixelSize: CGFloat) async throws -> UIImage {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ImagePipelineError.unsupportedURL
        }
        let size = min(max(maxPixelSize.rounded(), 1), 4096)
        let key = Self.key(url, maxPixelSize: maxPixelSize)
        if let cached = decoded.object(forKey: key as NSString) { return cached }
        if let pending = inFlight[key] { return try await pending.value }

        let session = session
        let task = Task<UIImage, Error> {
            try await Self.fetch(url, maxPixelSize: size, session: session)
        }
        inFlight[key] = task
        do {
            let image = try await task.value
            decoded.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
            if inFlight[key] == task { inFlight[key] = nil }
            return image
        } catch {
            if inFlight[key] == task { inFlight[key] = nil }
            throw error
        }
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
