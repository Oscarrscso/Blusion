import Testing
@testable import StremioKit

@Suite struct BootstrapTests {
    @Test func packageBuildsAndRuns() {
        #expect(StremioKitInfo.userAgent.hasPrefix("Blusion/"))
    }
}
