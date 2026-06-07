import XCTest
@testable import TrellisStudio

final class AppLoggerTests: XCTestCase {

    var logger: AppLogger!

    override func setUp() {
        super.setUp()
        logger = AppLogger.shared
        // Clear entries for a clean slate
        logger.entries.removeAll()
        logger.dismissError()
    }

    // MARK: - Log Levels

    func testInfoLogging() {
        logger.info("Test info message", context: "UnitTest")
        
        // Need to wait for main queue dispatch
        let expectation = expectation(description: "log appended")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(self.logger.entries.isEmpty)
            let last = self.logger.entries.last
            XCTAssertEqual(last?.level, .info)
            XCTAssertEqual(last?.message, "Test info message")
            XCTAssertEqual(last?.context, "UnitTest")
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWarningLogging() {
        logger.warning("Test warning", context: "UnitTest")

        let expectation = expectation(description: "log appended")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let last = self.logger.entries.last
            XCTAssertEqual(last?.level, .warning)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testErrorLogging() {
        logger.error("Test error", context: "UnitTest")

        let expectation = expectation(description: "log and banner")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let last = self.logger.entries.last
            XCTAssertEqual(last?.level, .error)
            XCTAssertTrue(self.logger.showErrorBanner)
            XCTAssertNotNil(self.logger.lastError)
            XCTAssertTrue(self.logger.lastError!.contains("Test error"))
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testSuccessLogging() {
        logger.success("Test success", context: "UnitTest")

        let expectation = expectation(description: "log appended")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let last = self.logger.entries.last
            XCTAssertEqual(last?.level, .success)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    // MARK: - Error Banner

    func testDismissError() {
        logger.error("Banner error", context: "Test")

        let expectation = expectation(description: "dismiss")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.logger.dismissError()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertFalse(self.logger.showErrorBanner)
                XCTAssertNil(self.logger.lastError)
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 1)
    }

    func testErrorBannerContainsContext() {
        logger.error("Something broke", context: "Daemon")

        let expectation = expectation(description: "context check")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.logger.lastError?.contains("[Daemon]") ?? false)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)
    }
}

// MARK: - LogLevel Tests

final class LogLevelTests: XCTestCase {

    func testSymbolsAreNonEmpty() {
        let levels: [LogLevel] = [.info, .warning, .error, .success]
        for level in levels {
            XCTAssertFalse(level.symbol.isEmpty, "\(level) has empty symbol")
        }
    }

    func testSymbolsAreUnique() {
        let symbols = [LogLevel.info, .warning, .error, .success].map(\.symbol)
        XCTAssertEqual(symbols.count, Set(symbols).count)
    }

    func testRawValues() {
        XCTAssertEqual(LogLevel.info.rawValue, "info")
        XCTAssertEqual(LogLevel.warning.rawValue, "warning")
        XCTAssertEqual(LogLevel.error.rawValue, "error")
        XCTAssertEqual(LogLevel.success.rawValue, "success")
    }
}

// MARK: - LogEntry Tests

final class LogEntryTests: XCTestCase {

    func testLogEntryHasUniqueID() {
        let entry1 = LogEntry(level: .info, context: "Test", message: "msg1")
        let entry2 = LogEntry(level: .info, context: "Test", message: "msg2")
        XCTAssertNotEqual(entry1.id, entry2.id)
    }

    func testLogEntryTimestampIsRecent() {
        let before = Date()
        let entry = LogEntry(level: .warning, context: "Test", message: "msg")
        let after = Date()

        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
        XCTAssertLessThanOrEqual(entry.timestamp, after)
    }

    func testLogEntryFields() {
        let entry = LogEntry(level: .error, context: "Daemon", message: "Failed hard")
        XCTAssertEqual(entry.level, .error)
        XCTAssertEqual(entry.context, "Daemon")
        XCTAssertEqual(entry.message, "Failed hard")
    }
}
