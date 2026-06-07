import XCTest
@testable import TrellisStudio

final class OnboardingServiceTests: XCTestCase {

    let service = OnboardingService.shared

    // MARK: - Disk Space

    func testCheckDiskSpaceReturnsPositive() {
        let space = service.checkDiskSpace()
        XCTAssertGreaterThan(space, 0.0, "Should detect available disk space")
    }

    func testDiskSpaceIsReasonable() {
        let space = service.checkDiskSpace()
        // Should be less than 100 TB (sanity)
        XCTAssertLessThan(space, 100_000.0, "Disk space should be a reasonable value in GB")
    }

    // MARK: - Environment Check

    func testCheckEnvironmentInstalledReturnsBool() {
        let result = service.checkEnvironmentInstalled()
        // Just verifying it returns without crash; value depends on local setup
        XCTAssertNotNil(result)
    }

    // MARK: - Backend Directory

    func testBackendDirectoryURLIsInAppSupport() {
        let url = service.backendDirectoryURL
        XCTAssertTrue(url.path.contains("Application Support"))
        XCTAssertTrue(url.path.contains("com.vinware.trellis-studio"))
        XCTAssertTrue(url.path.hasSuffix("backend"))
    }

    // MARK: - Install Log Types

    func testInstallLogEntryCreation() {
        let entry = InstallLogEntry(.info, "Test message")
        XCTAssertEqual(entry.level, .info)
        XCTAssertEqual(entry.message, "Test message")
        XCTAssertNotNil(entry.id)
    }

    func testInstallLogLevels() {
        XCTAssertEqual(InstallLogLevel.info.rawValue, "INFO")
        XCTAssertEqual(InstallLogLevel.warning.rawValue, "WARN")
        XCTAssertEqual(InstallLogLevel.error.rawValue, "ERROR")
        XCTAssertEqual(InstallLogLevel.success.rawValue, "OK")
    }

    func testInstallLogEntryTimestampIsRecent() {
        let before = Date()
        let entry = InstallLogEntry(.warning, "Warn")
        let after = Date()

        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
        XCTAssertLessThanOrEqual(entry.timestamp, after)
    }

    // MARK: - Install Status

    func testInstallStatusEquatable() {
        XCTAssertEqual(InstallStatus.idle, InstallStatus.idle)
        XCTAssertEqual(InstallStatus.installing, InstallStatus.installing)
        XCTAssertEqual(InstallStatus.succeeded, InstallStatus.succeeded)
        XCTAssertEqual(InstallStatus.failed("err"), InstallStatus.failed("err"))
        XCTAssertNotEqual(InstallStatus.idle, InstallStatus.installing)
        XCTAssertNotEqual(InstallStatus.failed("a"), InstallStatus.failed("b"))
    }

    // MARK: - Onboarding Persistence

    func testIsCompletedPersistsToUserDefaults() {
        let originalValue = service.isCompleted

        service.isCompleted = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "onboardingCompleted"))

        // Restore original
        service.isCompleted = originalValue
    }
}
