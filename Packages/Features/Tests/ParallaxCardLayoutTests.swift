import Foundation
import Testing
@testable import Features

@Suite struct ParallaxCardLayoutTests {
    @Test func portraitPhoneKeepsThePeekingCard() {
        // 390 − 32 − 28. The next card still peeks, and the height is that width over 1.5.
        #expect(width(container: 390, margin: 16, scale: 1, regular: false, compact: false) == 330)
        #expect(height(container: 390, margin: 16, scale: 1, regular: false, compact: false) == 220)
        #expect(width(container: 393, margin: 16, scale: 1, regular: false, compact: false) == 333)
        #expect(width(container: 440, margin: 16, scale: 1, regular: false, compact: false) == 380)
        #expect(height(container: 440, margin: 16, scale: 1, regular: false, compact: false) == 253)
    }

    @Test func portraitCardScaleStillClampsToThePage() {
        // 330 × 1.2 is wider than the 358 pt page, so the card stays the page.
        #expect(width(container: 390, margin: 16, scale: 1.2, regular: false, compact: false) == 358)
        #expect(height(container: 390, margin: 16, scale: 1.2, regular: false, compact: false) == 239)
    }

    @Test func landscapePhoneIsShorterThanThePortraitFormula() {
        // A sideways iPhone: full width 874, page margin grown by the 59 pt side inset.
        let landscape = width(container: 874, margin: 75, scale: 1, regular: false, compact: true)
        let portraitFormula = width(container: 874, margin: 75, scale: 1, regular: false, compact: false)
        #expect(landscape == 360)
        #expect(height(container: 874, margin: 75, scale: 1, regular: false, compact: true) == 240)
        #expect(landscape < portraitFormula)
    }

    @Test func uprightWideWindowKeepsTheRegularCard() {
        #expect(width(container: 1024, margin: 20, scale: 1, regular: true, compact: false) == 560)
        #expect(height(container: 1024, margin: 20, scale: 1, regular: true, compact: false) == 373)
    }

    @Test func wideMacAndLandscapeAreSmallerThanTheRegularCard() {
        let compact = width(container: 1440, margin: 20, scale: 1, regular: true, compact: true)
        let regular = width(container: 1440, margin: 20, scale: 1, regular: true, compact: false)
        #expect(compact == 360)
        #expect(height(container: 1440, margin: 20, scale: 1, regular: true, compact: true) == 240)
        #expect(regular == 560)
        #expect(compact < regular)
    }

    @Test func aNarrowWindowDoesNotGrowOrShrink() {
        // 62% of the page is already under the 360 pt cap, so landscape/Mac matches the wide-window card.
        let compact = width(container: 500, margin: 20, scale: 1, regular: true, compact: true)
        let regular = width(container: 500, margin: 20, scale: 1, regular: true, compact: false)
        #expect(compact == 285)
        #expect(compact == regular)
    }

    @Test func cardScaleAppliesAfterTheLandscapeCap() {
        #expect(width(container: 874, margin: 75, scale: 1.2, regular: false, compact: true) == 432)
        #expect(height(container: 874, margin: 75, scale: 1.2, regular: false, compact: true) == 288)
    }

    @Test func heightIsTheCardSoAPinnedShelfMatchesIt() {
        let card = width(container: 874, margin: 75, scale: 1, regular: false, compact: true)
        #expect(height(container: 874, margin: 75, scale: 1, regular: false, compact: true) == (card / 1.5).rounded())
    }

    @Test func aCardNeverWiderThanThePage() {
        #expect(width(container: 40, margin: 16, scale: 1, regular: false, compact: false) == 8)
        #expect(height(container: 40, margin: 16, scale: 1, regular: false, compact: false) == 5)
    }

    private func width(container: Double, margin: Double, scale: Double, regular: Bool, compact: Bool) -> Double {
        ParallaxCardLayout.cardWidth(containerWidth: container, pageMargin: margin, cardScale: scale, isRegular: regular,
                                     compactCards: compact)
    }

    private func height(container: Double, margin: Double, scale: Double, regular: Bool, compact: Bool) -> Double {
        ParallaxCardLayout.height(containerWidth: container, pageMargin: margin, cardScale: scale, isRegular: regular,
                                  compactCards: compact)
    }
}
