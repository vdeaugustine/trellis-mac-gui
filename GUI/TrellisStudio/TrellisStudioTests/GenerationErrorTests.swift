import XCTest
@testable import TrellisStudio

final class GenerationErrorTests: XCTestCase {

    // MARK: - User Messages

    func testInputNotFoundMessage() {
        let error = GenerationError.inputNotFound("/path/to/image.png")
        XCTAssertTrue(error.userMessage.contains("/path/to/image.png"))
        XCTAssertTrue(error.userMessage.contains("not found"))
    }

    func testDaemonNotReadyMessage() {
        let error = GenerationError.daemonNotReady
        XCTAssertTrue(error.userMessage.contains("not ready"))
    }

    func testOutputDirectoryFailedMessage() {
        let error = GenerationError.outputDirectoryFailed("/output/dir")
        XCTAssertTrue(error.userMessage.contains("/output/dir"))
        XCTAssertTrue(error.userMessage.contains("output directory"))
    }

    // MARK: - Error Conformance

    func testConformsToError() {
        let error: Error = GenerationError.daemonNotReady
        XCTAssertNotNil(error)
    }

    func testInputNotFoundIncludesPath() {
        let path = "/Users/test/Documents/photo.heic"
        let error = GenerationError.inputNotFound(path)
        XCTAssertTrue(error.userMessage.contains(path))
    }

    // MARK: - Message Uniqueness

    func testEachCaseHasDistinctMessage() {
        let messages = [
            GenerationError.inputNotFound("x").userMessage,
            GenerationError.daemonNotReady.userMessage,
            GenerationError.outputDirectoryFailed("y").userMessage,
        ]
        XCTAssertEqual(messages.count, Set(messages).count, "Messages should be unique")
    }
}
