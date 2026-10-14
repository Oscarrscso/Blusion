import CoreGraphics
import Testing
@testable import Features

@Suite struct PlayColourTests {
    private func pixels(_ count: Int, red: Double, green: Double, blue: Double, alpha: Double = 1) -> [PlayColour.Pixel] {
        Array(repeating: PlayColour.Pixel(red: red, green: green, blue: blue, alpha: alpha), count: count)
    }

    @Test func aMonochromePosterHasNoColour() {
        #expect(PlayColour.pick(from: pixels(864, red: 0.5, green: 0.5, blue: 0.5)) == nil, "grey never becomes the button's colour")
    }

    @Test func tooFewVividPixelsAreNotEnoughForAColour() {
        let poster = pixels(854, red: 0.5, green: 0.5, blue: 0.5) + pixels(9, red: 0.9, green: 0.1, blue: 0.1)
        #expect(PlayColour.pick(from: poster) == nil)
    }

    @Test func theHeaviestHueIsTheColour() throws {
        let poster = pixels(300, red: 0.9, green: 0.1, blue: 0.1) + pixels(200, red: 0.1, green: 0.8, blue: 0.2)
        let colour = try #require(PlayColour.pick(from: poster))
        #expect(colour.hue < 0.05 || colour.hue > 0.95, "red has more of the poster than green")
    }

    @Test func theColourIsCappedToARichSaturationAndBrightness() throws {
        let colour = try #require(PlayColour.pick(from: pixels(864, red: 0.9, green: 0.05, blue: 0.05)))
        #expect(colour.saturation == PlayColour.saturationRange.upperBound, "a neon red is brought down to the rich end")
        #expect(colour.brightness == PlayColour.brightnessRange.upperBound, "a bright red is brought down to the rich end")
    }

    @Test func aColourLowerThanTheRangeIsRaisedToIt() throws {
        let colour = try #require(PlayColour.pick(from: pixels(864, red: 0.3, green: 0.25, blue: 0.2)))
        #expect(PlayColour.saturationRange.contains(colour.saturation))
        #expect(PlayColour.brightnessRange.contains(colour.brightness))
    }

    @Test func tooDarkAndTooBrightPixelsDoNotCount() {
        #expect(PlayColour.pick(from: pixels(864, red: 0.1, green: 0.02, blue: 0.02)) == nil, "too dark to tell its hue")
        #expect(PlayColour.pick(from: pixels(864, red: 1, green: 0.3, blue: 0.3)) == nil, "too bright to tell its hue")
    }

    @Test func transparentPixelsAreIgnored() {
        #expect(PlayColour.pick(from: pixels(864, red: 0.1, green: 0.3, blue: 0.9, alpha: 0)) == nil)
    }

    @Test func hsbRoundTripsThroughRGB() {
        let pixel = PlayColour.Pixel(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        let back = PlayColour.rgb(PlayColour.HSB(pixel))
        #expect(abs(back.red - 0.2) < 0.0001)
        #expect(abs(back.green - 0.5) < 0.0001)
        #expect(abs(back.blue - 0.8) < 0.0001)
    }

    @Test func aPictureIsSampledAtTheSampleSizeAndReadsItsColour() throws {
        let context = try #require(CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        let picture = try #require(context.makeImage())
        let sample = try #require(PlayColour.pixels(of: picture))
        #expect(sample.count == PlayColour.sampleWidth * PlayColour.sampleHeight)
        let colour = try #require(PlayColour.pick(from: sample))
        #expect(colour.hue < 0.05 || colour.hue > 0.95, "a red picture gives a red button")
    }
}
