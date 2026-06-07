import XCTest
@testable import TrellisStudio

final class GenerationRecordTests: XCTestCase {

    // MARK: - Initialization

    func testDefaultInitSetsExpectedDefaults() {
        let record = GenerationRecord(
            inputImagePath: "/tmp/test.png",
            seed: 42,
            pipelineType: "512",
            textureSize: 1024
        )

        XCTAssertEqual(record.inputImagePath, "/tmp/test.png")
        XCTAssertEqual(record.seed, 42)
        XCTAssertEqual(record.pipelineType, "512")
        XCTAssertEqual(record.textureSize, 1024)
        XCTAssertEqual(record.status, .queued)
        XCTAssertNil(record.outputGLBPath)
        XCTAssertNil(record.outputOBJPath)
        XCTAssertNil(record.thumbnailPath)
        XCTAssertNil(record.vertexCount)
        XCTAssertNil(record.triangleCount)
        XCTAssertNil(record.generationTimeSeconds)
        XCTAssertNil(record.errorMessage)
    }

    func testCustomUUID() {
        let customID = UUID()
        let record = GenerationRecord(
            id: customID,
            inputImagePath: "/img.png",
            seed: 1,
            pipelineType: "1024",
            textureSize: 512
        )
        XCTAssertEqual(record.id, customID)
    }

    func testCreatedAtDefaultsToNow() {
        let before = Date()
        let record = GenerationRecord(
            inputImagePath: "/img.png",
            seed: 1,
            pipelineType: "512",
            textureSize: 1024
        )
        let after = Date()

        XCTAssertGreaterThanOrEqual(record.createdAt, before)
        XCTAssertLessThanOrEqual(record.createdAt, after)
    }

    func testCustomCreatedAt() {
        let customDate = Date(timeIntervalSince1970: 1_000_000)
        let record = GenerationRecord(
            inputImagePath: "/img.png",
            seed: 1,
            pipelineType: "512",
            textureSize: 1024,
            createdAt: customDate
        )
        XCTAssertEqual(record.createdAt, customDate)
    }

    // MARK: - Mutable Properties

    func testSettingOutputPaths() {
        let record = GenerationRecord(
            inputImagePath: "/img.png",
            seed: 1,
            pipelineType: "512",
            textureSize: 1024
        )

        record.outputGLBPath = "/output/model.glb"
        record.outputOBJPath = "/output/model.obj"
        record.thumbnailPath = "/output/thumb.png"

        XCTAssertEqual(record.outputGLBPath, "/output/model.glb")
        XCTAssertEqual(record.outputOBJPath, "/output/model.obj")
        XCTAssertEqual(record.thumbnailPath, "/output/thumb.png")
    }

    func testSettingMeshStats() {
        let record = GenerationRecord(
            inputImagePath: "/img.png",
            seed: 1,
            pipelineType: "512",
            textureSize: 1024
        )

        record.vertexCount = 12345
        record.triangleCount = 24690
        record.generationTimeSeconds = 42.5

        XCTAssertEqual(record.vertexCount, 12345)
        XCTAssertEqual(record.triangleCount, 24690)
        XCTAssertEqual(record.generationTimeSeconds, 42.5)
    }

    func testStatusTransitions() {
        let record = GenerationRecord(
            inputImagePath: "/img.png",
            seed: 1,
            pipelineType: "512",
            textureSize: 1024
        )

        XCTAssertEqual(record.status, .queued)

        record.status = .samplingStructure
        XCTAssertEqual(record.status, .samplingStructure)

        record.status = .complete
        XCTAssertEqual(record.status, .complete)
    }

    func testFailureWithErrorMessage() {
        let record = GenerationRecord(
            inputImagePath: "/img.png",
            seed: 1,
            pipelineType: "512",
            textureSize: 1024
        )

        record.status = .failed
        record.errorMessage = "GPU out of memory"

        XCTAssertEqual(record.status, .failed)
        XCTAssertEqual(record.errorMessage, "GPU out of memory")
    }

    func testWatchdogFailure() {
        let record = GenerationRecord(
            inputImagePath: "/img.png",
            seed: 1,
            pipelineType: "512",
            textureSize: 1024
        )

        record.status = .failedWatchdog
        record.errorMessage = "[watchdog] GPU timeout"

        XCTAssertEqual(record.status, .failedWatchdog)
    }

    // MARK: - Edge Cases

    func testEmptyInputPath() {
        let record = GenerationRecord(
            inputImagePath: "",
            seed: 0,
            pipelineType: "",
            textureSize: 0
        )
        XCTAssertEqual(record.inputImagePath, "")
        XCTAssertEqual(record.seed, 0)
    }

    func testNegativeSeed() {
        let record = GenerationRecord(
            inputImagePath: "/img.png",
            seed: -1,
            pipelineType: "512",
            textureSize: 1024
        )
        XCTAssertEqual(record.seed, -1)
    }

    func testLargeTextureSize() {
        let record = GenerationRecord(
            inputImagePath: "/img.png",
            seed: 42,
            pipelineType: "1024",
            textureSize: 8192
        )
        XCTAssertEqual(record.textureSize, 8192)
    }
}
