import XCTest

extension XCTestCase {
    /// Attaches a screenshot to the result bundle and, when `UITEST_SHOT_DIR` is set (verify.sh does this),
    /// also writes `<name>.png` there so milestone screenshots can be reviewed and committed.
    @MainActor
    func captureScreenshot(_ app: XCUIApplication, named name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["UITEST_SHOT_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: url)
        }
    }
}
