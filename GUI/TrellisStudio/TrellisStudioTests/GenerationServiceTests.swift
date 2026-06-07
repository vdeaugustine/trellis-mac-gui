import XCTest
@testable import TrellisStudio

@MainActor
final class GenerationServiceTests: XCTestCase {

    let service = GenerationService.shared

    // MARK: - Initial State

    func testInitialStateIsIdle() {
        // After app launch, no active record should exist
        XCTAssertNil(service.activeRecord)
    }

    func testInitialQueueIsEmpty() {
        XCTAssertTrue(service.queue.isEmpty)
    }

    // MARK: - Process Next Guards

    func testProcessNextDoesNothingWhenQueueEmpty() {
        service.processNext()
        XCTAssertNil(service.activeRecord)
    }
}
