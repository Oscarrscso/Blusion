import Foundation

/// The colours of a title's Play button, from the average colour of its picture: the show's own colour as the fill, and a black or white
/// label chosen by contrast. Pure arithmetic, so it can be tested without a picture.
enum PlayPalette {
    struct RGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double
    }

    /// The button's fill: the show's colour as its picture shows it, so the button reads as a clear colour of the show.
    static func background(for average: RGB) -> RGB { average }

    /// Whether the label is black. It is black or white, whichever contrasts more with the background. The better of the two is always at
    /// least 4.5:1, since black and white only fall short of that on a background in a narrow band of mid tones, where the other reaches it.
    static func labelIsDark(on background: RGB) -> Bool {
        contrastRatio(background, labelIsDark: true) >= contrastRatio(background, labelIsDark: false)
    }

    /// The WCAG contrast ratio of a label (black or white) against a background.
    static func contrastRatio(_ background: RGB, labelIsDark: Bool) -> Double {
        let backgroundLuminance = relativeLuminance(background)
        let labelLuminance = labelIsDark ? 0.0 : 1.0
        let lighter = max(backgroundLuminance, labelLuminance)
        let darker = min(backgroundLuminance, labelLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// The WCAG relative luminance of an sRGB colour.
    static func relativeLuminance(_ colour: RGB) -> Double {
        func linear(_ channel: Double) -> Double {
            let value = min(max(channel, 0), 1)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(colour.red) + 0.7152 * linear(colour.green) + 0.0722 * linear(colour.blue)
    }
}
