import Foundation
import Testing
@testable import Features

@Suite struct LazyLoadLookaheadTests {
    private func defaults(saving level: Int? = nil) -> UserDefaults {
        let name = "LazyLoadLookaheadTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        if let level { defaults.set(level, forKey: LazyLoadLookahead.defaultsKey) }
        return defaults
    }

    @Test func titlesPerLevel() {
        #expect(LazyLoadLookahead.levels.map(\.titles) == [3, 9, 18])
        #expect(LazyLoadLookahead.levels.map(\.label) == ["Near", "Balanced", "Far"])
        #expect([1, 2, 3].map { LazyLoadLookahead.titles(atLevel: $0) } == [3, 9, 18])
    }

    @Test func defaultsToBalancedWhenNothingIsSaved() {
        #expect(LazyLoadLookahead.level(in: defaults()) == 2)
        #expect(LazyLoadLookahead.titlesAhead(in: defaults()) == 9)
    }

    @Test func savedLevelIsClampedToTheRange() {
        #expect(LazyLoadLookahead.level(in: defaults(saving: 1)) == 1)
        #expect(LazyLoadLookahead.level(in: defaults(saving: 3)) == 3)
        #expect(LazyLoadLookahead.level(in: defaults(saving: 0)) == 1)
        #expect(LazyLoadLookahead.level(in: defaults(saving: -4)) == 1)
        #expect(LazyLoadLookahead.level(in: defaults(saving: 9)) == 3)
        #expect(LazyLoadLookahead.titles(atLevel: 0) == 3)
        #expect(LazyLoadLookahead.titles(atLevel: 7) == 18)
    }

    @Test func triggerIndexPerLevel() {
        #expect(LazyLoadLookahead.triggerIndex(count: 100, in: defaults(saving: 1)) == 96)
        #expect(LazyLoadLookahead.triggerIndex(count: 100, in: defaults(saving: 2)) == 90)
        #expect(LazyLoadLookahead.triggerIndex(count: 100, in: defaults(saving: 3)) == 81)
    }

    @Test func triggerIndexOfShortListsIsTheStart() {
        #expect(LazyLoadLookahead.triggerIndex(count: 0, in: defaults(saving: 3)) == 0)
        #expect(LazyLoadLookahead.triggerIndex(count: 5, in: defaults(saving: 3)) == 0)
        #expect(LazyLoadLookahead.triggerIndex(count: 19, in: defaults(saving: 3)) == 0)
        #expect(LazyLoadLookahead.triggerIndex(count: 20, in: defaults(saving: 3)) == 1)
    }

    @Test func bufferRangeSurroundsTheVisibleTitles() {
        #expect(LazyLoadLookahead.bufferRange(visible: 30...41, count: 100, titles: 9) == 21...50)
        #expect(LazyLoadLookahead.bufferRange(visible: 30...41, count: 100, titles: 18) == 12...59)
    }

    @Test func bufferRangeIsClampedToTheList() {
        #expect(LazyLoadLookahead.bufferRange(visible: 0...5, count: 100, titles: 9) == 0...14)
        #expect(LazyLoadLookahead.bufferRange(visible: 90...99, count: 100, titles: 18) == 72...99)
        #expect(LazyLoadLookahead.bufferRange(visible: 0...2, count: 4, titles: 3) == 0...3)
    }

    @Test func bufferRangeIsNilWithoutTitles() {
        #expect(LazyLoadLookahead.bufferRange(visible: 0...2, count: 0, titles: 3) == nil)
        #expect(LazyLoadLookahead.bufferRange(visible: 50...60, count: 10, titles: 3) == nil)
    }
}
