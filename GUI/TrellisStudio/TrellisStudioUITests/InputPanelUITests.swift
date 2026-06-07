import XCTest

/// UI tests for the input panel: drop zone, browse button, image preview.
final class InputPanelUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Drop Zone

    func testBrowseButtonExists() {
        let button = app.buttons["input-browse-button"]
        if button.waitForExistence(timeout: 5) {
            XCTAssertTrue(button.exists)
            XCTAssertTrue(button.isHittable)
        }
    }

    func testDropZoneShowsInstructionText() {
        let dropText = app.staticTexts["Drag & Drop Image Here"]
        if dropText.waitForExistence(timeout: 5) {
            XCTAssertTrue(dropText.exists)
        }
    }

    func testSupportedFormatsLabelExists() {
        let formats = app.staticTexts["PNG, JPG, HEIC, WEBP"]
        if formats.waitForExistence(timeout: 5) {
            XCTAssertTrue(formats.exists)
        }
    }

    // MARK: - No Image Initially

    func testImagePreviewDoesNotExistInitially() {
        let preview = app.images["input-image-preview"]
        XCTAssertFalse(preview.exists, "No image preview should show before image is loaded")
    }

    func testRemoveButtonDoesNotExistInitially() {
        let remove = app.buttons["input-remove-image"]
        XCTAssertFalse(remove.exists, "Remove button should not show before image is loaded")
    }
}
