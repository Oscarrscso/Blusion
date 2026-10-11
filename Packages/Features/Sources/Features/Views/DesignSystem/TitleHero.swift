#if canImport(UIKit)
import SwiftUI

/// The portrait hero's numbers, shared by Home's spotlight and the title page so that opening a title from one looks the same on the
/// other: the same picture size, fade, logo and placement. Both screens read them; change one here and both move together.
enum TitleHero {
    /// The share of the picture's height that the bottom fade covers.
    static let fadeLength = 0.42
    static let fadeStrength = 1.0
    /// The tallest logo, bottom-aligned above the bottom gap.
    static let logoMaxHeight: CGFloat = 150
    /// The gap between the bottom of the logo and the bottom of the picture.
    static let logoBottomGap = Theme.Spacing.xl
    /// The longest edge the picture is decoded to. Smaller than full screen, so the neighbouring pages keep it in the image cache.
    static let portraitPixelSize: CGFloat = 2048
    static let imageAlignment = Alignment.top
    /// The poster stands in unblurred, so it matches the picture that replaces it.
    static let placeholderBlur: CGFloat = 0
    /// The band under the picture on Home that holds the metadata line. The title page has no band; its picture is the same height.
    static let captionBelow: CGFloat = 72

    /// The height of the portrait picture on a screen `width` wide.
    static func height(width: CGFloat, metrics: LayoutMetrics) -> CGFloat {
        min(width * 1.5, metrics.heroMaxHeight)
    }
}
#endif
