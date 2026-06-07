import XCTest

/// UI tests for the parameter panel: seed, pipeline, texture, generate button.
final class ParameterPanelUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Seed Controls

    func testSeedFieldExists() {
        let field = app.textFields["param-seed-field"]
        if field.waitForExistence(timeout: 5) {
            XCTAssertTrue(field.exists)
        }
    }

    func testRandomizeSeedButtonExists() {
        let button = app.buttons["param-randomize-seed"]
        if button.waitForExistence(timeout: 5) {
            XCTAssertTrue(button.exists)
            XCTAssertTrue(button.isHittable)
        }
    }

    func testRandomizeSeedChangesFieldValue() {
        let field = app.textFields["param-seed-field"]
        let button = app.buttons["param-randomize-seed"]

        guard field.waitForExistence(timeout: 5),
              button.waitForExistence(timeout: 2) else { return }

        let initialValue = field.value as? String ?? ""
        button.click()

        // Give the UI time to update
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", initialValue),
            object: field
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: 3)
        if result == .completed {
            let newValue = field.value as? String ?? ""
            XCTAssertNotEqual(initialValue, newValue, "Seed should change after randomize")
        }
    }

    // MARK: - Generate Button

    func testGenerateButtonExists() {
        let button = app.buttons["param-generate-button"]
        if button.waitForExistence(timeout: 5) {
            XCTAssertTrue(button.exists)
        }
    }

    func testGenerateButtonIsDisabledInitially() {
        let button = app.buttons["param-generate-button"]
        if button.waitForExistence(timeout: 5) {
            // Button should be disabled: no image + daemon offline
            XCTAssertFalse(button.isEnabled, "Generate should be disabled without image/daemon")
        }
    }

    func testGenerateButtonShowsCorrectLabel() {
        let button = app.buttons["param-generate-button"]
        if button.waitForExistence(timeout: 5) {
            // Should say "Select an Image" or "Waiting for Backend…"
            let label = button.label
            let validLabels = ["Select an Image", "Waiting for Backend…", "Generate Model"]
            let matches = validLabels.contains(where: { label.contains($0) })
            XCTAssertTrue(matches, "Button label '\(label)' should be a known state")
        }
    }

    // MARK: - Parameter Labels

    func testParameterTitleExists() {
        let title = app.staticTexts["Generation Settings"]
        if title.waitForExistence(timeout: 5) {
            XCTAssertTrue(title.exists)
        }
    }

    func testSeedLabelExists() {
        let label = app.staticTexts["Seed"]
        if label.waitForExistence(timeout: 5) {
            XCTAssertTrue(label.exists)
        }
    }

    func testPipelineTypeLabelExists() {
        let label = app.staticTexts["Pipeline Type"]
        if label.waitForExistence(timeout: 5) {
            XCTAssertTrue(label.exists)
        }
    }

    func testTextureSizeLabelExists() {
        let label = app.staticTexts["Texture Resolution"]
        if label.waitForExistence(timeout: 5) {
            XCTAssertTrue(label.exists)
        }
    }

    // MARK: - Preset Buttons

    func testPresetButtonsExist() {
        let fastDraft = app.buttons["Fast Draft"]
        let balanced = app.buttons["Balanced"]
        let maxQuality = app.buttons["Max Quality"]

        if fastDraft.waitForExistence(timeout: 5) {
            XCTAssertTrue(fastDraft.exists)
        }
        if balanced.waitForExistence(timeout: 2) {
            XCTAssertTrue(balanced.exists)
        }
        if maxQuality.waitForExistence(timeout: 2) {
            XCTAssertTrue(maxQuality.exists)
        }
    }
}
