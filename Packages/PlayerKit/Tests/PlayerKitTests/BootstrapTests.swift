import Testing
@testable import PlayerKit

@Suite struct BootstrapTests {
    @Test func packageBuildsAndRuns() {
        #expect(PlayerKitInfo.name == "PlayerKit")
    }
}
