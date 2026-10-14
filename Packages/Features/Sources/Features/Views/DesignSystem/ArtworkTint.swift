#if canImport(UIKit)
import CoreImage
import SwiftUI
import UIKit

/// The average colour of a title's picture, for a faint tint on its Play button so the glass takes on the show's colours. Nil until the
/// picture has loaded, or when it cannot be read.
enum ArtworkTint {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func color(for url: URL?) async -> Color? {
        guard let url, let image = try? await ImagePipeline.shared.image(for: url, maxPixelSize: 64, priority: .low),
              let input = CIImage(image: image),
              let average = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input, kCIInputExtentKey: input.extent])?.outputImage
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        return Color(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }
}
#endif
