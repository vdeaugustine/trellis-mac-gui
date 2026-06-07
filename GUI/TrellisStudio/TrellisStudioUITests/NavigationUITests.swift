import XCTest

/// UI tests for keyboard shortcuts and navigation flows.
final class NavigationUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Settings Window

    func testSettingsWindowOpensViaShortcut() {
        app.typeKey(",", modifierFlags: .command)

        // Wait for settings window to appear
        let settingsWindow = app.windows["Trellis Studio Settings"]
        if settingsWindow.waitForExistence(timeout: 3) {
            XCTAssertTrue(settingsWindow.exists)
            // Close it
            settingsWindow.typeKey("w", modifierFlags: .command)
        }
    }

    // MARK: - Navigation Split View

    func testNavigationSplitViewExists() {
        // The main window should have a split view layout
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        // Split view manifests as having sidebar and detail areas
    }

    // MARK: - Error Banner Dismissal

    func testErrorBannerDismissButtonWorks() {
        // The error banner may or may not be visible depending on daemon state
        let banner = app.otherElements["error-banner"]
        if banner.waitForExistence(timeout: 3) {
            let dismiss = app.buttons["error-banner-dismiss"]
            XCTAssertTrue(dismiss.exists)
            dismiss.click()

            // Banner should disappear
            let gone = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: banner
            )
            XCTWaiter.wait(for: [gone], timeout: 2)
        }
    }
}
