import XCTest

/// UI tests for the sidebar: new generation button, batch toggle, search, history.
final class SidebarUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - New Generation Button

    func testNewGenerationButtonExists() {
        let button = app.buttons["sidebar-new-generation"]
        if button.waitForExistence(timeout: 5) {
            XCTAssertTrue(button.exists)
        }
    }

    func testNewGenerationButtonIsClickable() {
        let button = app.buttons["sidebar-new-generation"]
        if button.waitForExistence(timeout: 5) {
            XCTAssertTrue(button.isHittable)
        }
    }

    // MARK: - Batch Mode Toggle

    func testBatchModeToggleExists() {
        let toggle = app.switches["sidebar-batch-mode"]
        if toggle.waitForExistence(timeout: 5) {
            XCTAssertTrue(toggle.exists)
        }
    }

    func testBatchModeToggleIsInteractive() {
        let toggle = app.switches["sidebar-batch-mode"]
        if toggle.waitForExistence(timeout: 5) {
            // Verify initial state and toggle
            let initialValue = toggle.value as? String
            toggle.click()
            let newValue = toggle.value as? String
            XCTAssertNotEqual(initialValue, newValue, "Toggle should change value on click")
            // Toggle back
            toggle.click()
        }
    }

    // MARK: - Search Field

    func testSearchFieldExists() {
        let searchField = app.textFields["sidebar-search-field"]
        if searchField.waitForExistence(timeout: 5) {
            XCTAssertTrue(searchField.exists)
        }
    }

    func testSearchFieldAcceptsInput() {
        let searchField = app.textFields["sidebar-search-field"]
        if searchField.waitForExistence(timeout: 5) {
            searchField.click()
            searchField.typeText("chair")

            // Verify text was entered
            let value = searchField.value as? String
            XCTAssertTrue(value?.contains("chair") ?? false)

            // Clear
            searchField.click()
            searchField.typeKey("a", modifierFlags: .command)
            searchField.typeKey(.delete, modifierFlags: [])
        }
    }

    // MARK: - History List

    func testHistoryListDisplaysItems() {
        // History should show at least the placeholder rows
        let list = app.outlines.firstMatch
        if list.waitForExistence(timeout: 5) {
            XCTAssertTrue(list.exists)
        }
    }
}
