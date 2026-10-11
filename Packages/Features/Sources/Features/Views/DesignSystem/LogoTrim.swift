import CoreGraphics

/// Finds the visible part of a title logo. Logo files carry different amounts of transparent padding, which would make the gap between
/// a logo and the text under it differ from title to title; the loader crops each logo to this box so the logo itself sets its size.
enum LogoTrim {
    /// Alpha (of 255) at or below which a pixel counts as empty.
    static let alphaThreshold: UInt8 = 10

    /// The bounding box, in pixels from the top left, of the pixels whose alpha is above the threshold. Nil when nothing is visible, the
    /// image cannot be read, or the whole image is visible (nothing to trim).
    static func visibleBounds(of image: CGImage, threshold: UInt8 = alphaThreshold) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where pixels[row + x] > threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                maxY = y
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        return box.width == CGFloat(width) && box.height == CGFloat(height) ? nil : box
    }

    /// The image cropped to its visible pixels, or the image itself when there is nothing to trim.
    static func trimmed(_ image: CGImage) -> CGImage {
        guard let box = visibleBounds(of: image), let cropped = image.cropping(to: box) else { return image }
        return cropped
    }
}
