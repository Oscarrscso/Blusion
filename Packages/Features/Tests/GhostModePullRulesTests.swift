import Testing
@testable import Features

@Suite struct GhostModePullRulesTests {
    @Test func progressFillsFromTheArmMarkToTheLockDistance() {
        #expect(GhostModePullRules.progress(pull: GhostModePullRules.armPull) == 0)
        #expect(GhostModePullRules.progress(pull: GhostModePullRules.armPull + GhostModePullRules.lockDistance / 2) == 0.5)
        #expect(GhostModePullRules.progress(pull: GhostModePullRules.armPull + GhostModePullRules.lockDistance) == 1)
        #expect(GhostModePullRules.progress(pull: 0) == 0)
        #expect(GhostModePullRules.progress(pull: .nan) == 0)
    }

    @Test func locksPastTheSameDistanceThePlayerUsesFor2x() {
        #expect(GhostModePullRules.lockDistance == SpeedHoldRules.lockDistance)
        #expect(!GhostModePullRules.locks(pull: GhostModePullRules.armPull + GhostModePullRules.lockDistance))
        #expect(GhostModePullRules.locks(pull: GhostModePullRules.armPull + GhostModePullRules.lockDistance + 1))
        #expect(!GhostModePullRules.locks(pull: .nan))
    }
}
