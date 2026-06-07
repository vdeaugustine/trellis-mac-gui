import XCTest
@testable import TrellisStudio

final class GenerationStatusTests: XCTestCase {

    // MARK: - Raw Values

    func testAllCasesHaveUniqueRawValues() {
        let rawValues = GenerationStatus.allCases.map(\.rawValue)
        XCTAssertEqual(rawValues.count, Set(rawValues).count, "Duplicate raw values detected")
    }

    func testRawValueRoundTrip() {
        for status in GenerationStatus.allCases {
            let decoded = GenerationStatus(rawValue: status.rawValue)
            XCTAssertEqual(decoded, status, "Round-trip failed for \(status)")
        }
    }

    func testExpectedRawValues() {
        XCTAssertEqual(GenerationStatus.queued.rawValue, "queued")
        XCTAssertEqual(GenerationStatus.warmingUp.rawValue, "warmingUp")
        XCTAssertEqual(GenerationStatus.loadingPipeline.rawValue, "loadingPipeline")
        XCTAssertEqual(GenerationStatus.samplingStructure.rawValue, "samplingStructure")
        XCTAssertEqual(GenerationStatus.samplingShape.rawValue, "samplingShape")
        XCTAssertEqual(GenerationStatus.samplingTexture.rawValue, "samplingTexture")
        XCTAssertEqual(GenerationStatus.decodingShape.rawValue, "decodingShape")
        XCTAssertEqual(GenerationStatus.decodingTexture.rawValue, "decodingTexture")
        XCTAssertEqual(GenerationStatus.extractingMesh.rawValue, "extractingMesh")
        XCTAssertEqual(GenerationStatus.bakingTexture.rawValue, "bakingTexture")
        XCTAssertEqual(GenerationStatus.complete.rawValue, "complete")
        XCTAssertEqual(GenerationStatus.failed.rawValue, "failed")
        XCTAssertEqual(GenerationStatus.failedWatchdog.rawValue, "failedWatchdog")
        XCTAssertEqual(GenerationStatus.shutdown.rawValue, "shutdown")
    }

    // MARK: - Display Names

    func testDisplayNamesAreNonEmpty() {
        for status in GenerationStatus.allCases {
            XCTAssertFalse(status.displayName.isEmpty, "\(status) has empty displayName")
        }
    }

    func testSpecificDisplayNames() {
        XCTAssertEqual(GenerationStatus.queued.displayName, "Queued")
        XCTAssertEqual(GenerationStatus.warmingUp.displayName, "Warming Up")
        XCTAssertEqual(GenerationStatus.loadingPipeline.displayName, "Loading Pipeline")
        XCTAssertEqual(GenerationStatus.complete.displayName, "Complete")
        XCTAssertEqual(GenerationStatus.failed.displayName, "Failed")
        XCTAssertEqual(GenerationStatus.failedWatchdog.displayName, "Failed (Watchdog)")
        XCTAssertEqual(GenerationStatus.shutdown.displayName, "Shutdown")
    }

    // MARK: - Case Count

    func testAllCasesCount() {
        XCTAssertEqual(GenerationStatus.allCases.count, 14, "Expected 14 generation stages")
    }

    // MARK: - Codable

    func testJSONEncodeDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for status in GenerationStatus.allCases {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(GenerationStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }

    func testDecodeFromRawString() throws {
        let json = Data("\"complete\"".utf8)
        let decoded = try JSONDecoder().decode(GenerationStatus.self, from: json)
        XCTAssertEqual(decoded, .complete)
    }

    func testDecodeInvalidRawValueThrows() {
        let json = Data("\"nonExistent\"".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(GenerationStatus.self, from: json))
    }
}
