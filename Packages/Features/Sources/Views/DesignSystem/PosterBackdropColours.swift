#if canImport(UIKit)
import CoreImage
import UIKit

/// Repairs only a dark bottom edge, before the shared Home/title backdrop renderer samples it.
enum PosterBackdropColours {
    private final class Rendering {
        weak var source: UIImage?
        let picture: CIImage
        init(source: UIImage, picture: CIImage) {
            self.source = source
            self.picture = picture
        }
    }

    // NSCache synchronizes access internally; rendering is deliberately outside the main actor.
    nonisolated(unsafe) private static let cache: NSCache<NSString, Rendering> = {
        let cache = NSCache<NSString, Rendering>()
        cache.totalCostLimit = 32 << 20
        return cache
    }()

    static func repair(_ picture: CIImage, source: UIImage, context: CIContext) -> CIImage {
        let key = "\(UInt(bitPattern: ObjectIdentifier(source)))" as NSString
        if let cached = cache.object(forKey: key), cached.source === source { return cached.picture }
        let repaired = repair(picture, context: context)
        cache.setObject(Rendering(source: source, picture: repaired), forKey: key,
                        cost: Int(picture.extent.width * picture.extent.height) * 4)
        return repaired
    }

    private static func repair(_ picture: CIImage, context: CIContext) -> CIImage {
        let width = min(64, Int(picture.extent.width)), height = Int(picture.extent.height)
        guard width > 0, height > 2 else { return picture }
        // Keep every source row, including a one-pixel black line. Reduce only the horizontal sampling cost.
        let small = picture.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / picture.extent.width, y: 1))
        guard let image = context.createCGImage(small, from: CGRect(x: 0, y: 0, width: width, height: height)) else { return picture }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let bitmap = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return picture }
        let brightness = (0..<height).map { row in
            (0..<width).reduce(0.0) { sum, column in
                let i = (row * width + column) * 4
                return sum + Double(max(pixels[i], pixels[i + 1], pixels[i + 2])) / 255
            } / Double(width)
        }
        // Side/top bars alone do not qualify. An already dark poster also has no brighter colours to continue.
        let peak = brightness[(height / 2)..<height].max() ?? 0
        guard peak > 0.16, brightness[height - 1] < min(0.12, peak * 0.45) else { return picture }
        var start = height - 1
        while start > height / 2, brightness[start - 1] < peak * 0.95 { start -= 1 }
        guard start > 0 else { return picture }

        for column in 0..<width {
            let rows = max(0, start - 8)..<start
            let colour = (0..<3).map { channel in
                rows.reduce(0.0) { $0 + Double(pixels[($1 * width + column) * 4 + channel]) } / Double(rows.count)
            }
            for row in start..<height {
                let t = Double(row - start + 1) / Double(height - start)
                let blend = t * t * (3 - 2 * t)
                let variation = 1 - 0.03 * t + 0.015 * sin(Double(column) * 0.7) * t
                let index = (row * width + column) * 4
                for channel in 0..<3 {
                    let edge = Double(pixels[((start - 1) * width + column) * 4 + channel])
                    let value = edge * (1 - blend) + colour[channel] * variation * blend
                    pixels[index + channel] = UInt8(clamping: Int(value.rounded()))
                }
                pixels[index + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let replacement = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return picture }
        let repairedBand = CIImage(cgImage: replacement)
            .transformed(by: CGAffineTransform(scaleX: picture.extent.width / CGFloat(width), y: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: picture.extent.width, height: CGFloat(height - start)))
        return repairedBand.composited(over: picture).cropped(to: picture.extent)
    }
}
#endif
