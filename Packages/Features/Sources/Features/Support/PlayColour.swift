import CoreGraphics
import Foundation

/// The colour a title's Play button takes from its poster: the poster's most common vivid hue, kept rich and never grey. Pure arithmetic
/// over a small sample of the picture, so it runs off the main thread and can be tested without a picture.
enum PlayColour {
    /// One sampled pixel, each channel from 0 to 1, not premultiplied.
    struct Pixel: Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double
    }

    /// A colour in HSB, each component from 0 to 1.
    struct HSB: Equatable {
        var hue: Double
        var saturation: Double
        var brightness: Double
    }

    /// The poster is sampled at this size, which is a few hundred pixels: enough for the colour, cheap to read.
    static let sampleWidth = 24
    static let sampleHeight = 36
    /// The hues are grouped into this many buckets, and the heaviest bucket's colour is the poster's.
    static let hueBuckets = 12
    /// A pixel counts as vivid when it is at least this saturated and this bright, and not too bright to tell its hue.
    static let minimumVividSaturation = 0.25
    static let vividBrightness = 0.15...0.95
    /// Fewer vivid pixels than this and the poster is monochrome: no colour, so the button keeps its own style.
    static let minimumVividPixels = 10
    /// The button's colour, however vivid the poster: rich enough to read as a colour, never neon or grey.
    static let saturationRange = 0.55...0.85
    static let brightnessRange = 0.40...0.60

    /// The button's colour for the pixels of a poster, or nil when no vivid colour survives.
    static func pick(from pixels: [Pixel]) -> HSB? {
        var weights = [Double](repeating: 0, count: hueBuckets)
        var sums = [(red: Double, green: Double, blue: Double)](repeating: (0, 0, 0), count: hueBuckets)
        var vividCount = 0
        for pixel in pixels where pixel.alpha >= 0.5 {
            let hsb = HSB(pixel)
            guard hsb.saturation >= minimumVividSaturation, vividBrightness.contains(hsb.brightness) else { continue }
            vividCount += 1
            let bucket = min(hueBuckets - 1, Int(hsb.hue * Double(hueBuckets)))
            weights[bucket] += hsb.saturation
            sums[bucket].red += pixel.red * hsb.saturation
            sums[bucket].green += pixel.green * hsb.saturation
            sums[bucket].blue += pixel.blue * hsb.saturation
        }
        guard vividCount >= minimumVividPixels,
              let heaviest = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[heaviest] > 0 else { return nil }
        let weight = weights[heaviest]
        var colour = HSB(red: sums[heaviest].red / weight, green: sums[heaviest].green / weight, blue: sums[heaviest].blue / weight)
        colour.saturation = min(max(colour.saturation, saturationRange.lowerBound), saturationRange.upperBound)
        colour.brightness = min(max(colour.brightness, brightnessRange.lowerBound), brightnessRange.upperBound)
        return colour
    }

    /// The pixels of a picture drawn at the sample size, not premultiplied. Nil when the sample cannot be drawn.
    static func pixels(of image: CGImage) -> [Pixel]? {
        let width = sampleWidth
        let height = sampleHeight
        var raw = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = raw.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return stride(from: 0, to: raw.count, by: 4).map { index in
            let alpha = Double(raw[index + 3]) / 255
            guard alpha > 0 else { return Pixel(red: 0, green: 0, blue: 0, alpha: 0) }
            return Pixel(red: min(Double(raw[index]) / 255 / alpha, 1), green: min(Double(raw[index + 1]) / 255 / alpha, 1),
                         blue: min(Double(raw[index + 2]) / 255 / alpha, 1), alpha: alpha)
        }
    }

    /// The colour as sRGB components from 0 to 1.
    static func rgb(_ colour: HSB) -> (red: Double, green: Double, blue: Double) {
        let sector = (colour.hue - floor(colour.hue)) * 6
        let chroma = colour.brightness * colour.saturation
        let secondary = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let offset = colour.brightness - chroma
        let (red, green, blue): (Double, Double, Double)
        switch Int(sector) % 6 {
        case 0: (red, green, blue) = (chroma, secondary, 0)
        case 1: (red, green, blue) = (secondary, chroma, 0)
        case 2: (red, green, blue) = (0, chroma, secondary)
        case 3: (red, green, blue) = (0, secondary, chroma)
        case 4: (red, green, blue) = (secondary, 0, chroma)
        default: (red, green, blue) = (chroma, 0, secondary)
        }
        return (red + offset, green + offset, blue + offset)
    }
}

extension PlayColour.HSB {
    init(_ pixel: PlayColour.Pixel) {
        self.init(red: pixel.red, green: pixel.green, blue: pixel.blue)
    }

    init(red: Double, green: Double, blue: Double) {
        let high = max(red, green, blue)
        let range = high - min(red, green, blue)
        brightness = high
        saturation = high == 0 ? 0 : range / high
        if range == 0 {
            hue = 0
        } else if high == red {
            var sector = (green - blue) / range
            if sector < 0 { sector += 6 }
            hue = sector / 6
        } else if high == green {
            hue = ((blue - red) / range + 2) / 6
        } else {
            hue = ((red - green) / range + 4) / 6
        }
    }
}
