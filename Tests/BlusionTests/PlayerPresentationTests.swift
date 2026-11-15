import AVFoundation
import Testing
import UIKit
import PlayerKit
import StremioKit
@testable import Features

@MainActor
@Suite struct PlayerPresentationTests {
    /// The bar under the timeline is the system segmented control: a segment per menu, none selected until one opens.
    @Test func menuBarHasASegmentPerMenuAndKeepsTheOpenOneWhileItsContentChanges() {
        let control = PlayerMenuSegmentedControl(frame: .zero)
        let tabs: [PlayerPanelTab] = [.subtitles, .speed, .picture, .info]
        control.configure(tabs: tabs, speedLabel: nil, subtitlesOn: false)
        #expect(control.numberOfSegments == 4)
        #expect(control.selectedSegmentIndex == UISegmentedControl.noSegment)
        for (index, tab) in tabs.enumerated() {
            #expect(control.imageForSegment(at: index)?.accessibilityLabel == tab.title)
        }
        control.selectedSegmentIndex = 1
        control.configure(tabs: tabs, speedLabel: "1.5×", subtitlesOn: true)
        #expect(control.titleForSegment(at: 1) == "1.5×")
        #expect(control.imageForSegment(at: 1) == nil)
        #expect(control.selectedSegmentIndex == 1, "a changing rate keeps the open menu selected")
        control.configure(tabs: tabs, speedLabel: nil, subtitlesOn: true)
        #expect(control.titleForSegment(at: 1) == nil)
        #expect(control.imageForSegment(at: 1)?.accessibilityLabel == "Speed")
        let withChapters: [PlayerPanelTab] = [.subtitles, .speed, .chapters, .picture, .info]
        control.configure(tabs: withChapters, speedLabel: nil, subtitlesOn: true)
        #expect(control.numberOfSegments == 5)
        #expect(control.imageForSegment(at: 2)?.accessibilityLabel == "Chapters")
    }

    @Test func videoSurfaceInputsChangeOnlyForPlaybackConfiguration() {
        let pip = PiPProxy()
        let original = PlayerSurface(engine: nil, pip: pip)
        let clockOrControlUpdate = PlayerSurface(engine: nil, pip: pip)
        let fill = PlayerSurface(engine: nil, pip: pip, layout: VideoLayout(fit: .fill))
        #expect(original == clockOrControlUpdate)
        #expect(original != fill)
    }

    @Test func playerLayerViewRendersExactRectanglesAcrossRotationResolutionChangesAndSuperResolution() throws {
        let phone = CGRect(x: 0, y: 0, width: 852, height: 393)
        let portrait = CGRect(x: 0, y: 0, width: 393, height: 852)
        let hd = CGSize(width: 1920, height: 1080)

        let surface = PlayerLayerView(frame: phone)
        let superResLayer = AVSampleBufferDisplayLayer()
        surface.host(superResolution: superResLayer)
        surface.sourceSize = hd
        surface.layout = VideoLayout(zoomMode: .crop, aspectRatio: .widescreenA)
        surface.layoutIfNeeded()

        let expected185 = try #require(VideoGeometry(bounds: phone.size, source: hd, layout: surface.layout))
        #expect(surface.playerLayer.videoGravity == .resize, "once source size is known, AVPlayerLayer must not add implicit gravity crop/fit")
        #expect(surface.videoView.transform == .identity, "scale transforms must never accumulate")
        #expect(abs(surface.clipView.frame.width - expected185.visible.width) < 0.01)
        #expect(abs(surface.clipView.frame.height - expected185.visible.height) < 0.01)
        let pictureInSurface = surface.clipView.convert(surface.videoView.frame, to: surface)
        #expect(abs(pictureInSurface.minX - expected185.picture.minX) < 0.01)
        #expect(abs(pictureInSurface.minY - expected185.picture.minY) < 0.01)
        #expect(abs(pictureInSurface.width - expected185.picture.width) < 0.01)
        #expect(abs(pictureInSurface.height - expected185.picture.height) < 0.01)
        #expect(superResLayer.frame == surface.videoView.bounds && superResLayer.videoGravity == .resize)

        // Rotate to portrait, switch resolution to UHD, embed a fallback view, then return to native landscape 1.85:1.
        surface.frame = portrait
        surface.sourceSize = CGSize(width: 3840, height: 2160)
        surface.layout = VideoLayout(zoomMode: .fill, aspectRatio: .widescreenB)
        surface.layoutIfNeeded()
        #expect(surface.videoView.transform == .identity)

        let fallback = UIView()
        surface.embed(fallback)
        surface.layoutIfNeeded()
        #expect(fallback.frame == portrait)
        surface.embed(nil)

        surface.frame = phone
        surface.sourceSize = hd
        surface.layout = VideoLayout(zoomMode: .crop, aspectRatio: .widescreenA)
        surface.layoutIfNeeded()
        let returned = surface.clipView.convert(surface.videoView.frame, to: surface)
        #expect(abs(surface.clipView.frame.width - expected185.visible.width) < 0.01)
        #expect(abs(returned.height - expected185.picture.height) < 0.01)
        #expect(surface.videoView.transform == .identity)
    }

    @Test func posterBackgroundSummaryAndBackdropContrast() throws {
        var appearance = AppearancePreferences()
        #expect(!appearance.titlePagesSummary.contains("Poster background"))
        appearance.blursBackground = true
        #expect(appearance.titlePagesSummary.contains("Poster background"))
        #expect(!appearance.titlePagesSummary.contains("Blurred background"))

        let white = try solidImage(red: 1, green: 1, blue: 1)
        let whiteBackdrop = try #require(TitleBackdropRequest(
            image: white, frame: CGSize(width: 390, height: 520), visibleBottom: 520, alignsTop: true, pageWidth: 390, scale: 1
        ).render())
        let whiteRGB = try middleRGB(of: whiteBackdrop)
        #expect(whiteRGB.red <= 0.35 && whiteRGB.green <= 0.35 && whiteRGB.blue <= 0.35)
        #expect(whiteRGB.red >= 0.15)

        let red = try solidImage(red: 1, green: 0, blue: 0)
        let redBackdrop = try #require(TitleBackdropRequest(
            image: red, frame: CGSize(width: 390, height: 520), visibleBottom: 520, alignsTop: true, pageWidth: 390, scale: 1
        ).render())
        let redRGB = try middleRGB(of: redBackdrop)
        #expect(redRGB.red - redRGB.green > 0.15 && redRGB.red - redRGB.blue > 0.15)
    }

    @Test func episodeExtendedArtworkHasNoGreyBandAtSeam() throws {
        let black = try solidImage(red: 0, green: 0, blue: 0, size: CGSize(width: 320, height: 180))
        let rendered = try #require(ExtendedArtworkRenderer.render(black, size: CGSize(width: 320, height: 320), scale: 1))
        let cgImage = try #require(rendered.cgImage)
        #expect(cgImage.width == 320 && cgImage.height == 320)

        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let white = try #require(CGColor(colorSpace: colorSpace, components: [1, 1, 1, 1]))
            context.setFillColor(white)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let x = width / 2
        func rowRGB(_ y: Int) -> (red: Double, green: Double, blue: Double) {
            let offset = (y * width + x) * 4
            return (Double(bytes[offset]) / 255, Double(bytes[offset + 1]) / 255, Double(bytes[offset + 2]) / 255)
        }

        let upperStillEnd = Int(180 * 0.75)
        for y in 0...upperStillEnd {
            let rgb = rowRGB(y)
            #expect(rgb.red <= 0.01 && rgb.green <= 0.01 && rgb.blue <= 0.01)
        }

        for y in upperStillEnd..<(height - 1) {
            let current = rowRGB(y)
            let next = rowRGB(y + 1)
            #expect(current.red <= next.red + 0.01)
            #expect(current.green <= next.green + 0.01)
            #expect(current.blue <= next.blue + 0.01)
        }

        for y in 170...195 {
            let current = rowRGB(y)
            let below = rowRGB(y + 10)
            #expect(current.red <= below.red + 0.01)
            #expect(current.green <= below.green + 0.01)
            #expect(current.blue <= below.blue + 0.01)
        }

        let bottom = rowRGB(height - 1)
        #expect(abs(bottom.red - 0.3 * 0.68) <= 0.02)
        #expect(abs(bottom.green - 0.3 * 0.68) <= 0.02)
        #expect(abs(bottom.blue - 0.3 * 0.68) <= 0.02)
    }

    @Test func macPageNavigationTopInsetScalesWithCardSpacing() {
        #expect(MacPageNavigation.topInset(spacing: 12) == MacPageNavigation.inset + MacPageNavigation.controlHeight + 12)
        #expect(MacPageNavigation.topInset(spacing: 24) == MacPageNavigation.inset + MacPageNavigation.controlHeight + 24)
    }

    private func solidImage(red: CGFloat, green: CGFloat, blue: CGFloat, size: CGSize = CGSize(width: 80, height: 120)) throws -> UIImage {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let width = Int(size.width), height = Int(size.height)
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let color = try #require(CGColor(colorSpace: colorSpace, components: [red, green, blue, 1]))
        context.setFillColor(color)
        context.fill(CGRect(origin: .zero, size: size))
        return UIImage(cgImage: try #require(context.makeImage()))
    }

    private func middleRGB(of image: UIImage) throws -> (red: Double, green: Double, blue: Double) {
        let cgImage = try #require(image.cgImage)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        let offset = (width / 2) * 4
        return (Double(bytes[offset]) / 255, Double(bytes[offset + 1]) / 255, Double(bytes[offset + 2]) / 255)
    }
}
