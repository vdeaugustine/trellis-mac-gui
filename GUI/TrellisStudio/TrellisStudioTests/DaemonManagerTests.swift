import XCTest
@testable import TrellisStudio

final class DaemonManagerTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let dm = DaemonManager.shared
        XCTAssertTrue(dm.isOffline)
        XCTAssertFalse(dm.isReady)
        XCTAssertFalse(dm.isWarmingUp)
        XCTAssertNil(dm.lastDaemonError)
        XCTAssertEqual(dm.errorKind, .none)
    }

    // MARK: - Callback Management

    func testRegisterCallback() {
        let dm = DaemonManager.shared
        dm.clearCallbacks()

        var callbackFired = false
        dm.registerCallback { _ in
            callbackFired = true
        }

        // Verify callback was registered (indirectly by clearing)
        dm.clearCallbacks()
        XCTAssertFalse(callbackFired, "Callback should not fire until invoked")
    }

    func testClearCallbacks() {
        let dm = DaemonManager.shared
        dm.registerCallback { _ in }
        dm.registerCallback { _ in }
        dm.clearCallbacks()
        // No crash = success; callbacks array cleared
    }

    // MARK: - Send Request Without Daemon

    func testSendRequestWithoutDaemonDoesNotCrash() {
        let dm = DaemonManager.shared
        // Sending when no daemon running should log error, not crash
        dm.sendRequest(command: ["command": "test"])
    }

    // MARK: - Start With Invalid Paths

    func testStartWithInvalidPythonPath() {
        let dm = DaemonManager.shared

        dm.startDaemon(trellisPath: "/nonexistent/path")

        let expectation = expectation(description: "error set")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Should have set error because python binary not found
            XCTAssertNotNil(dm.lastDaemonError)
            XCTAssertTrue(dm.isOffline)
            XCTAssertFalse(dm.isReady)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    // MARK: - Dry Run Flag

    func testDryRunFlagDefaultsFalse() {
        let dm = DaemonManager.shared
        XCTAssertFalse(dm.isDryRun)
    }
}
