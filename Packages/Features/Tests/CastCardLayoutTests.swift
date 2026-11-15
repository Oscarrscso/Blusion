import Foundation
import Testing
@testable import Features

@Suite struct CastCardLayoutTests {
    /// The title page's margin and card gap on an iPhone held upright, and today's card width there.
    private let margin = 16.0
    private let spacing = 12.0
    private let today = 128.0

    @Test(arguments: [375.0, 390, 393, 402, 414, 428, 430, 440])
    func fourWholeCardsFitAcrossEveryIPhoneHeldUpright(screenWidth: Double) {
        let width = CastCardLayout.cardWidth(pageWidth: screenWidth, margin: margin, spacing: spacing, maximum: today)
        let fourthCardEnd = margin + width * 4 + spacing * 3
        #expect(fourthCardEnd <= screenWidth - margin, "the fourth card ends inside the right margin on a \(screenWidth) pt screen")
        #expect(screenWidth - margin - fourthCardEnd < 4, "the four cards fill the row, give or take the rounding")
        #expect(width >= 75 && width < today, "smaller than today, still a readable card")
    }

    @Test func aWideWindowKeepsTodaysSize() {
        #expect(CastCardLayout.cardWidth(pageWidth: 1400, margin: 40, spacing: 16, maximum: 180) == 180)
        #expect(CastCardLayout.cardWidth(pageWidth: 932, margin: 59, spacing: 12, maximum: 128) == 128, "an iPhone held sideways")
    }

    @Test func aPageTooNarrowForAnyCardGivesNone() {
        #expect(CastCardLayout.cardWidth(pageWidth: 40, margin: 12, spacing: 12, maximum: 128) == 0)
        #expect(CastCardLayout.cardWidth(pageWidth: .nan, margin: 12, spacing: 12, maximum: 128) == 0)
    }

    @Test func shelfCardsAreALittleSmallerThanTheFourAcrossWidth() {
        let fitting = CastCardLayout.cardWidth(pageWidth: 390, margin: margin, spacing: spacing, maximum: today)
        let shelf = CastCardLayout.shelfCardWidth(pageWidth: 390, margin: margin, spacing: spacing, maximum: today)
        #expect(shelf == fitting * 0.8)
        #expect(CastCardLayout.shelfCardWidth(pageWidth: 1400, margin: 40, spacing: 16, maximum: 180) == 144)
    }

    @Test func macCastAndSeasonControlsAreHalfACastCard() {
        let shelf = CastCardLayout.shelfCardWidth(pageWidth: 1400, margin: 40, spacing: 16, maximum: 180)
        #expect(CastCardLayout.controlWidth(shelfCardWidth: shelf, halfCard: true) == shelf / 2)
        #expect(CastCardLayout.controlWidth(shelfCardWidth: shelf, halfCard: true) == 72)
        #expect(CastCardLayout.controlWidth(shelfCardWidth: shelf, halfCard: false) == shelf)
    }

    @Test func aMissingCardGivesNoControl() {
        #expect(CastCardLayout.shelfCardWidth(pageWidth: 40, margin: 12, spacing: 12, maximum: 128) == 0)
        #expect(CastCardLayout.controlWidth(shelfCardWidth: 0, halfCard: true) == 0)
        #expect(CastCardLayout.controlWidth(shelfCardWidth: .nan, halfCard: false) == 0)
        #expect(CastCardLayout.controlWidth(shelfCardWidth: .infinity, halfCard: true) == 0)
    }
}
