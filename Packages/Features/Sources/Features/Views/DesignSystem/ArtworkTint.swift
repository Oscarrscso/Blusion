#if canImport(UIKit)
import CoreImage
import SwiftUI
import UIKit

/// The colours of a title's Play button, from its picture: a subtle shade of the show's colour and a label that contrasts with it (see
/// `PlayPalette`). Nil until the picture has loaded, or when it cannot be read.
enum ArtworkTint {
    struct Palette: Equatable {
        let background: Color
        let label: Color
    }

    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func palette(for url: URL?) async -> Palette? {
        guard let url, let average = await averageColour(of: url) else { return nil }
        let background = PlayPalette.background(for: average)
        let labelIsDark = PlayPalette.labelIsDark(on: background)
        return Palette(background: Color(red: background.red, green: background.green, blue: background.blue),
                       label: labelIsDark ? .black : .white)
    }

    /// The picture's average colour, as sRGB components from 0 to 1.
    private static func averageColour(of url: URL) async -> PlayPalette.RGB? {
        guard let image = try? await ImagePipeline.shared.image(for: url, maxPixelSize: 64, priority: .low),
              let input = CIImage(image: image),
              let average = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input, kCIInputExtentKey: input.extent])?.outputImage
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        return PlayPalette.RGB(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }
}
#endif
