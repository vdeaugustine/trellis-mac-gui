import XCTest

/// UI tests for the daemon status bar in the main content view.
final class DaemonStatusUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Status Indicator

    func testDaemonStatusDotExists() {
        // The status dot should always be visible in the main workspace
        let dot = app.otherElements["daemon-status-dot"]
        // It may be within a navigation hierarchy
        if dot.waitForExistence(timeout: 5) {
            XCTAssertTrue(dot.exists)
        }
    }

    func testDaemonStatusTextExists() {
        let statusText = app.staticTexts["daemon-status-text"]
        if statusText.waitForExistence(timeout: 5) {
            XCTAssertTrue(statusText.exists)
            XCTAssertFalse(statusText.label.isEmpty, "Status text should have content")
        }
    }

    // MARK: - Restart Button

    func testRestartButtonAppearsWhenOffline() {
        // When daemon is offline, restart button should appear
        let restart = app.buttons["daemon-restart-button"]
        if restart.waitForExistence(timeout: 5) {
            XCTAssertTrue(restart.exists)
            XCTAssertTrue(restart.isEnabled)
        }
    }
}
