import XCTest
@testable import TrellisStudio

final class HistoryServiceTests: XCTestCase {

    // MARK: - Export GLB

    func testExportGLBThrowsWhenNoPath() {
        let record = GenerationRecord(
            inputImagePath: "/img.png",
            seed: 42,
            pipelineType: "512",
            textureSize: 1024
        )
        // outputGLBPath is nil

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_test.glb")

        XCTAssertThrowsError(try HistoryService.shared.exportGLB(record, to: destination)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "HistoryService")
            XCTAssertEqual(nsError.code, 404)
        }
    }

    func testExportGLBThrowsWhenFileDoesNotExist() {
        let record = GenerationRecord(
            inputImagePath: "/img.png",
            seed: 42,
            pipelineType: "512",
            textureSize: 1024
        )
        record.outputGLBPath = "/nonexistent/model.glb"

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_test_\(UUID().uuidString).glb")

        XCTAssertThrowsError(try HistoryService.shared.exportGLB(record, to: destination))
    }

    func testExportGLBSucceedsWithRealFile() throws {
        // Create a temp GLB file
        let tempDir = FileManager.default.temporaryDirectory
        let glbSource = tempDir.appendingPathComponent("test_\(UUID().uuidString).glb")
        try Data("fake glb data".utf8).write(to: glbSource)

        let record = GenerationRecord(
            inputImagePath: "/img.png",
            seed: 42,
            pipelineType: "512",
            textureSize: 1024
        )
        record.outputGLBPath = glbSource.path

        let destination = tempDir.appendingPathComponent("exported_\(UUID().uuidString).glb")

        try HistoryService.shared.exportGLB(record, to: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        // Verify content
        let exportedData = try Data(contentsOf: destination)
        XCTAssertEqual(String(data: exportedData, encoding: .utf8), "fake glb data")

        // Cleanup
        try? FileManager.default.removeItem(at: glbSource)
        try? FileManager.default.removeItem(at: destination)
    }

    func testExportGLBOverwritesExistingFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let glbSource = tempDir.appendingPathComponent("src_\(UUID().uuidString).glb")
        try Data("new data".utf8).write(to: glbSource)

        let destination = tempDir.appendingPathComponent("dst_\(UUID().uuidString).glb")
        try Data("old data".utf8).write(to: destination)

        let record = GenerationRecord(
            inputImagePath: "/img.png",
            seed: 42,
            pipelineType: "512",
            textureSize: 1024
        )
        record.outputGLBPath = glbSource.path

        try HistoryService.shared.exportGLB(record, to: destination)

        let result = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertEqual(result, "new data")

        // Cleanup
        try? FileManager.default.removeItem(at: glbSource)
        try? FileManager.default.removeItem(at: destination)
    }
}
