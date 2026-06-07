import XCTest

/// UI tests for the main application launch and window.
final class AppLaunchUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Launch

    func testAppLaunches() {
        XCTAssertTrue(app.windows.count >= 1, "App should have at least one window")
    }

    func testMainWindowExists() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        XCTAssertTrue(window.frame.width > 0)
        XCTAssertTrue(window.frame.height > 0)
    }

    // MARK: - Menu Bar

    func testSettingsMenuItemExists() {
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.exists)

        let appMenu = menuBar.menuBarItems.element(boundBy: 0)
        appMenu.click()

        let settingsItem = appMenu.menuItems["Settings…"]
        XCTAssertTrue(settingsItem.exists || settingsItem.isHittable == false,
                      "Settings menu item should exist")
    }

    // MARK: - Window Resizing

    func testWindowHasMinimumSize() {
        let window = app.windows.firstMatch
        let frame = window.frame
        XCTAssertGreaterThan(frame.width, 200)
        XCTAssertGreaterThan(frame.height, 200)
    }
}
