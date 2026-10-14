import CoreGraphics
import StremioKit
import Testing
@testable import Features

@Suite struct WidgetSlotLayoutTests {
    /// Two columns across 340 points: each card is 162 wide and 243 tall, with a 16-point gutter.
    private let layout = WidgetSlotLayout.fitting(width: 340, columns: 2, count: 5)

    @Test func theCardSizeFillsTheWidthBetweenTheGutters() {
        #expect(layout.cardWidth == 162)
        #expect(layout.cardHeight == 243)
        #expect(layout.rows == 3)
        #expect(layout.contentSize == CGSize(width: 340, height: 3 * 243 + 2 * 16))
    }

    @Test func aCardsCentreIsItsOwnSlot() {
        for index in 0..<5 {
            #expect(layout.index(at: layout.center(for: index)) == index, "the centre of slot \(index)")
        }
    }

    @Test func aGutterIsNoSlot() {
        #expect(layout.index(at: CGPoint(x: 170, y: 50)) == nil, "between the two columns")
        #expect(layout.index(at: CGPoint(x: 50, y: 250)) == nil, "between two rows")
    }

    @Test func pastTheLastCardIsTheLastSlot() {
        #expect(layout.index(at: CGPoint(x: 300, y: 600)) == 4, "an empty slot of the short last row")
        #expect(layout.index(at: CGPoint(x: 50, y: 2000)) == 4, "below the grid")
    }

    @Test func outsideTheGridIsNoSlot() {
        #expect(layout.index(at: CGPoint(x: -4, y: 50)) == nil)
        #expect(layout.index(at: CGPoint(x: 50, y: -4)) == nil)
        #expect(layout.index(at: CGPoint(x: 400, y: 50)) == nil, "beyond the right edge")
    }

    @Test func moreColumnsMakeNarrowerCards() {
        let three = WidgetSlotLayout.fitting(width: 340, columns: 3, count: 7)
        let expectedWidth: CGFloat = (340 - 2 * 16) / 3
        #expect(abs(three.cardWidth - expectedWidth) < 0.001)
        #expect(three.rows == 3)
        #expect(three.index(at: three.center(for: 6)) == 6, "the last card of a short row")
    }

    @Test func aMoveForwardAndBackKeepsTheOtherCardsInOrder() {
        #expect(WidgetSlotLayout.moved(["a", "b", "c", "d"], from: 0, to: 2) == ["b", "c", "a", "d"])
        #expect(WidgetSlotLayout.moved(["a", "b", "c", "d"], from: 3, to: 0) == ["d", "a", "b", "c"])
        #expect(WidgetSlotLayout.moved(["a", "b", "c", "d"], from: 1, to: 1) == ["a", "b", "c", "d"])
        #expect(WidgetSlotLayout.moved(["a", "b"], from: 5, to: 0) == ["a", "b"], "an index outside the list changes nothing")
    }
}

@Suite struct WidgetShowcaseTests {
    private func row(_ id: String) -> HomeWidget {
        HomeWidget(id: id, title: id, content: .row(RowConfiguration(source: .tmdbDiscover(TMDbDiscoverQuery()))))
    }

    private func showcase(_ id: String) -> HomeWidget {
        HomeWidget(id: id, title: id, content: .hero(RowConfiguration(source: .tmdbDiscover(TMDbDiscoverQuery()))))
    }

    @Test func theShowcaseIsTheOnlyHeroAndIsRecognised() {
        #expect(WidgetsManagerViewModel.isShowcase(showcase("s")))
        #expect(!WidgetsManagerViewModel.isShowcase(row("r")))
    }

    @Test func theShowcaseComesFirst() {
        let list = [row("a"), showcase("s"), row("b")]
        #expect(WidgetsManagerViewModel.normalisedShowcase(list).map(\.id) == ["s", "a", "b"])
    }

    @Test func onlyTheFirstShowcaseIsKept() {
        let list = [row("a"), showcase("s1"), row("b"), showcase("s2")]
        #expect(WidgetsManagerViewModel.normalisedShowcase(list).map(\.id) == ["s1", "a", "b"], "an import's extra showcase is dropped")
    }

    @Test func aListWithoutAShowcaseIsUnchanged() {
        let list = [row("a"), row("b")]
        #expect(WidgetsManagerViewModel.normalisedShowcase(list).map(\.id) == ["a", "b"])
    }
}
