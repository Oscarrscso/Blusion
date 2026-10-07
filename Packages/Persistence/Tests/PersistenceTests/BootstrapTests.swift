import Testing
@testable import Persistence

@Suite struct BootstrapTests {
    @Test func packageBuildsAndRuns() {
        #expect(PersistenceInfo.name == "Persistence")
    }
}
