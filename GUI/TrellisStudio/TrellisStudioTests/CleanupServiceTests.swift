import XCTest
@testable import TrellisStudio

final class CleanupServiceTests: XCTestCase {

    let service = CleanupService.shared

    // MARK: - Path Catalogue

    func testAppSupportURLContainsBundleID() {
        let url = service.appSupportURL
        XCTAssertTrue(url.path.contains("com.vinware.trellis-studio"))
    }

    func testBackendURLIsUnderAppSupport() {
        let backendPath = service.backendURL.path
        let appSupportPath = service.appSupportURL.path
        XCTAssertTrue(backendPath.hasPrefix(appSupportPath))
        XCTAssertTrue(backendPath.hasSuffix("backend"))
    }

    func testGenerationsURLIsUnderAppSupport() {
        let gensPath = service.generationsURL.path
        let appSupportPath = service.appSupportURL.path
        XCTAssertTrue(gensPath.hasPrefix(appSupportPath))
        XCTAssertTrue(gensPath.hasSuffix("Generations"))
    }

    func testHuggingFaceCacheURLContainsHub() {
        let path = service.huggingFaceCacheURL.path
        XCTAssertTrue(path.contains(".cache/huggingface/hub"))
    }

    func testPreferencesPlistPath() {
        let path = service.preferencesPlistURL.path
        XCTAssertTrue(path.hasSuffix("com.vinware.trellis-studio.plist"))
    }

    func testSwiftDataStoreURL() {
        let path = service.swiftDataStoreURL.path
        XCTAssertTrue(path.hasSuffix("default.store"))
    }

    // MARK: - Size Helpers

    func testSizeOfNonexistentDirectory() {
        let fakeURL = URL(fileURLWithPath: "/nonexistent/path/\(UUID().uuidString)")
        let size = service.sizeOfDirectory(at: fakeURL)
        XCTAssertEqual(size, 0)
    }

    func testSizeOfTempDirectory() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleanup_test_\(UUID().uuidString)")
        let fm = FileManager.default

        // Create dir with a known-size file
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let testData = Data(repeating: 0xFF, count: 1024)
        let testFile = tempDir.appendingPathComponent("test.bin")
        try? testData.write(to: testFile)

        let size = service.sizeOfDirectory(at: tempDir)
        XCTAssertGreaterThanOrEqual(size, 1024)

        // Cleanup
        try? fm.removeItem(at: tempDir)
    }

    // MARK: - Formatted Size

    func testFormattedSizeZero() {
        let result = service.formattedSize(0)
        XCTAssertFalse(result.isEmpty)
    }

    func testFormattedSizeKilobytes() {
        let result = service.formattedSize(2048)
        XCTAssertFalse(result.isEmpty)
    }

    func testFormattedSizeGigabytes() {
        let result = service.formattedSize(15_000_000_000)
        XCTAssertTrue(result.contains("GB") || result.contains("G"))
    }

    // MARK: - Remove Non-Existent Paths (No-Op)

    func testRemoveBackendNoOpWhenMissing() {
        // Shouldn't throw when path doesn't exist
        XCTAssertNoThrow(try service.removeBackend())
    }

    func testRemoveGenerationsNoOpWhenMissing() {
        XCTAssertNoThrow(try service.removeGenerations())
    }

    func testRemoveTrellisModelCacheNoOpWhenMissing() {
        // May not throw even if .cache/huggingface/hub doesn't exist
        XCTAssertNoThrow(try service.removeTrellisModelCache())
    }

    func testRemoveSwiftDataStoreNoOpWhenMissing() {
        XCTAssertNoThrow(try service.removeSwiftDataStore())
    }

    // MARK: - Preferences Cleanup

    func testRemovePreferencesDoesNotCrash() {
        service.removePreferences()
        // Verify keys are cleared
        XCTAssertNil(UserDefaults.standard.string(forKey: "onboardingCompleted"))
    }
}
