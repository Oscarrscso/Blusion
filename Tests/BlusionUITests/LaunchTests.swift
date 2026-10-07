import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesAndShowsRoot() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.staticTexts["Blusion"].waitForExistence(timeout: 10))
        captureScreenshot(app, named: "M0-launch")
    }
}
