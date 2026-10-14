import Testing
@testable import Features

@Suite struct PlayPaletteTests {
    /// Colours across the range, from very dark to very bright, in every hue family, so the palette is checked on bright and dark art alike.
    private var samples: [PlayPalette.RGB] {
        var colours: [PlayPalette.RGB] = []
        for red in stride(from: 0.0, through: 1.0, by: 0.25) {
            for green in stride(from: 0.0, through: 1.0, by: 0.25) {
                for blue in stride(from: 0.0, through: 1.0, by: 0.25) {
                    colours.append(PlayPalette.RGB(red: red, green: green, blue: blue))
                }
            }
        }
        return colours
    }

    @Test func theLabelReachesFourPointFiveToOneOnEveryBackground() {
        for average in samples {
            let background = PlayPalette.background(for: average)
            let labelIsDark = PlayPalette.labelIsDark(on: background)
            #expect(PlayPalette.contrastRatio(background, labelIsDark: labelIsDark) >= 4.5,
                    "background \(background) with its label contrasts less than 4.5:1")
        }
    }

    @Test func theFillIsTheShowsOwnColour() {
        let colour = PlayPalette.RGB(red: 0.8, green: 0.1, blue: 0.2)
        #expect(PlayPalette.background(for: colour) == colour)
    }

    @Test func aBrightPictureTakesADarkLabelAndADarkPictureAWhiteOne() {
        #expect(PlayPalette.labelIsDark(on: PlayPalette.RGB(red: 1, green: 0.95, blue: 0.2)), "a bright fill takes a black label")
        #expect(!PlayPalette.labelIsDark(on: PlayPalette.RGB(red: 0.05, green: 0.05, blue: 0.1)), "a dark fill takes a white label")
    }
}
