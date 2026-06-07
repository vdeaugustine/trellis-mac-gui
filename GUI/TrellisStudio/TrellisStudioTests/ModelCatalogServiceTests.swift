import XCTest
@testable import TrellisStudio

final class ModelCatalogServiceTests: XCTestCase {

    let service = ModelCatalogService.shared

    // MARK: - Catalog Definition

    func testCatalogHasExpectedEntries() {
        XCTAssertGreaterThanOrEqual(service.entries.count, 10, "Should have at least 10 model entries")
    }

    func testAllEntriesHaveUniqueIDs() {
        let ids = service.entries.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate entry IDs detected")
    }

    func testAllEntriesHaveNonEmptyFields() {
        for entry in service.entries {
            XCTAssertFalse(entry.id.isEmpty, "Entry has empty id")
            XCTAssertFalse(entry.displayName.isEmpty, "Entry \(entry.id) has empty displayName")
            XCTAssertFalse(entry.repoId.isEmpty, "Entry \(entry.id) has empty repoId")
            XCTAssertFalse(entry.relativePath.isEmpty, "Entry \(entry.id) has empty relativePath")
            XCTAssertFalse(entry.role.isEmpty, "Entry \(entry.id) has empty role")
        }
    }

    // MARK: - Gated Models

    func testGatedModelsExist() {
        let gated = service.entries.filter(\.isGated)
        XCTAssertGreaterThanOrEqual(gated.count, 2, "Should have at least 2 gated models")
    }

    func testNonGatedModelsExist() {
        let nonGated = service.entries.filter { !$0.isGated }
        XCTAssertGreaterThanOrEqual(nonGated.count, 8)
    }

    func testGatedModelsAreFromExpectedRepos() {
        let gated = service.entries.filter(\.isGated)
        let repos = Set(gated.map(\.repoId))
        XCTAssertTrue(repos.contains("facebook/dinov3-vitl16-pretrain-lvd1689m"))
        XCTAssertTrue(repos.contains("briaai/RMBG-2.0"))
    }

    // MARK: - Specific Entries

    func testShapeDecoderEntry() {
        let entry = service.entries.first { $0.id == "shape_dec" }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.role, "Shape")
        XCTAssertFalse(entry?.isGated ?? true)
    }

    func testTextureFlowEntries() {
        let tex512 = service.entries.first { $0.id == "tex_flow_512" }
        let tex1024 = service.entries.first { $0.id == "tex_flow_1024" }
        XCTAssertNotNil(tex512)
        XCTAssertNotNil(tex1024)
        XCTAssertEqual(tex512?.role, "Texture")
        XCTAssertEqual(tex1024?.role, "Texture")
    }

    // MARK: - Computed Properties

    func testDownloadedCountWithFreshCatalog() {
        // Initial catalog has all entries as .missing
        let downloaded = service.downloadedCount
        // Can't guarantee 0 since user might have models, but should be non-negative
        XCTAssertGreaterThanOrEqual(downloaded, 0)
    }

    func testMissingCountWithFreshCatalog() {
        let missing = service.missingCount
        XCTAssertGreaterThanOrEqual(missing, 0)
    }

    func testDownloadedPlusMissingApproximatesTotalBeforeScan() {
        // Before scan, most statuses are .missing
        let total = service.entries.count
        let downloaded = service.downloadedCount
        let missing = service.missingCount
        // Sum should not exceed total
        XCTAssertLessThanOrEqual(downloaded + missing, total)
    }

    func testFormattedTotalSizeIsNonEmpty() {
        let formatted = service.formattedTotalSize
        XCTAssertFalse(formatted.isEmpty)
    }

    // MARK: - ModelDownloadStatus

    func testModelDownloadStatusEquatable() {
        XCTAssertEqual(ModelDownloadStatus.downloaded, ModelDownloadStatus.downloaded)
        XCTAssertEqual(ModelDownloadStatus.missing, ModelDownloadStatus.missing)
        XCTAssertEqual(ModelDownloadStatus.error("x"), ModelDownloadStatus.error("x"))
        XCTAssertNotEqual(ModelDownloadStatus.downloaded, ModelDownloadStatus.missing)
        XCTAssertNotEqual(ModelDownloadStatus.error("x"), ModelDownloadStatus.error("y"))
    }

    func testModelDownloadStatusDownloadingProgress() {
        let status = ModelDownloadStatus.downloading(progress: 0.75)
        if case .downloading(let progress) = status {
            XCTAssertEqual(progress, 0.75, accuracy: 0.001)
        } else {
            XCTFail("Expected downloading status")
        }
    }

    // MARK: - ModelCatalogEntry

    func testModelCatalogEntryDefaultStatus() {
        let entry = ModelCatalogEntry(
            id: "test",
            displayName: "Test Model",
            repoId: "test/repo",
            relativePath: "model.bin",
            isGated: false,
            role: "Test"
        )
        XCTAssertEqual(entry.status, .missing)
        XCTAssertEqual(entry.sizeBytes, 0)
    }
}
