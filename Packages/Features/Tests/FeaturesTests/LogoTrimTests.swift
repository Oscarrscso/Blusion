import CoreGraphics
import Testing
@testable import Features

@Suite struct LogoTrimTests {
    /// A width x height RGBA image, clear except for an opaque block at `block` (pixels from the top left).
    private func image(width: Int, height: Int, block: CGRect?, alpha: CGFloat = 1) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        if let block {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
            // Core Graphics counts from the bottom, so flip to describe the block from the top.
            context.fill(CGRect(x: block.minX, y: CGFloat(height) - block.maxY, width: block.width, height: block.height))
        }
        return context.makeImage()
    }

    @Test func boundsAreTheVisiblePixelsFromTheTopLeft() throws {
        let source = try #require(image(width: 40, height: 30, block: CGRect(x: 5, y: 8, width: 20, height: 10)))
        #expect(LogoTrim.visibleBounds(of: source) == CGRect(x: 5, y: 8, width: 20, height: 10))
        let trimmed = LogoTrim.trimmed(source)
        #expect(trimmed.width == 20 && trimmed.height == 10)
    }

    @Test func aFullyTransparentImageIsLeftAlone() throws {
        let source = try #require(image(width: 10, height: 10, block: nil))
        #expect(LogoTrim.visibleBounds(of: source) == nil)
        #expect(LogoTrim.trimmed(source) === source)
    }

    @Test func anImageWithNoPaddingIsLeftAlone() throws {
        let source = try #require(image(width: 10, height: 6, block: CGRect(x: 0, y: 0, width: 10, height: 6)))
        #expect(LogoTrim.visibleBounds(of: source) == nil)
        #expect(LogoTrim.trimmed(source) === source)
    }

    @Test func faintPixelsBelowTheThresholdDoNotCount() throws {
        let source = try #require(image(width: 20, height: 20, block: CGRect(x: 2, y: 2, width: 16, height: 16), alpha: 0.02))
        #expect(LogoTrim.visibleBounds(of: source) == nil)
    }
}
