import XCTest
@testable import TrellisStudio

/// Smoke tests for singleton service availability and basic state.
final class TrellisStudioTests: XCTestCase {

    func testOnboardingServiceExists() {
        let os = OnboardingService.shared
        XCTAssertNotNil(os)
    }

    func testOnboardingDiskSpaceReturnsNonNegative() {
        let space = OnboardingService.shared.checkDiskSpace()
        XCTAssertGreaterThanOrEqual(space, 0.0)
    }

    func testDaemonManagerExists() {
        let dm = DaemonManager.shared
        XCTAssertNotNil(dm)
        XCTAssertTrue(dm.isOffline)
        XCTAssertFalse(dm.isReady)
    }

    func testSettingsServiceExists() {
        XCTAssertNotNil(SettingsService.shared)
    }

    func testCleanupServiceExists() {
        XCTAssertNotNil(CleanupService.shared)
    }

    func testAppLoggerExists() {
        XCTAssertNotNil(AppLogger.shared)
    }

    func testHistoryServiceExists() {
        XCTAssertNotNil(HistoryService.shared)
    }

    func testModelCatalogServiceExists() {
        XCTAssertNotNil(ModelCatalogService.shared)
    }

    func testHFAuthServiceExists() {
        XCTAssertNotNil(HFAuthService.shared)
    }

    @MainActor
    func testGenerationServiceExists() {
        XCTAssertNotNil(GenerationService.shared)
    }
}
