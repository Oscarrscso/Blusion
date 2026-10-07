import Testing
@testable import Features

@Suite struct BootstrapTests {
    @Test func packageBuildsAndRuns() {
        #expect(FeaturesInfo.name == "Features")
    }
}
