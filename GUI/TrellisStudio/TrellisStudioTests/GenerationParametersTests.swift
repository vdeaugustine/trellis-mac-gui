import XCTest
@testable import TrellisStudio

final class GenerationParametersTests: XCTestCase {

    // MARK: - Default Values

    func testDefaultValues() {
        let params = GenerationParameters()
        XCTAssertEqual(params.seed, 42)
        XCTAssertEqual(params.pipelineType, "512")
        XCTAssertEqual(params.textureSize, 1024)
        XCTAssertFalse(params.noTexture)
        XCTAssertNil(params.steps)
    }

    // MARK: - Randomize Seed

    func testRandomizeSeedChangesValue() {
        let params = GenerationParameters()
        let originalSeed = params.seed

        // Run multiple times to reduce flaky chance
        var changed = false
        for _ in 0..<20 {
            params.randomizeSeed()
            if params.seed != originalSeed {
                changed = true
                break
            }
        }
        XCTAssertTrue(changed, "Seed should change after randomization")
    }

    func testRandomizeSeedRange() {
        let params = GenerationParameters()
        for _ in 0..<100 {
            params.randomizeSeed()
            XCTAssertGreaterThanOrEqual(params.seed, 1)
            XCTAssertLessThanOrEqual(params.seed, 999999)
        }
    }

    func testRandomizeSeedProducesDifferentValues() {
        let params = GenerationParameters()
        var seeds = Set<Int>()
        for _ in 0..<50 {
            params.randomizeSeed()
            seeds.insert(params.seed)
        }
        // With 50 random draws from 1-999999, we expect many unique values
        XCTAssertGreaterThan(seeds.count, 10, "Expected diverse seed values")
    }

    // MARK: - Mutability

    func testPipelineTypeCanBeChanged() {
        let params = GenerationParameters()
        params.pipelineType = "1024"
        XCTAssertEqual(params.pipelineType, "1024")

        params.pipelineType = "1024_cascade"
        XCTAssertEqual(params.pipelineType, "1024_cascade")
    }

    func testTextureSizeCanBeChanged() {
        let params = GenerationParameters()
        params.textureSize = 512
        XCTAssertEqual(params.textureSize, 512)

        params.textureSize = 2048
        XCTAssertEqual(params.textureSize, 2048)
    }

    func testNoTextureToggle() {
        let params = GenerationParameters()
        XCTAssertFalse(params.noTexture)

        params.noTexture = true
        XCTAssertTrue(params.noTexture)

        params.noTexture = false
        XCTAssertFalse(params.noTexture)
    }

    func testStepsOptional() {
        let params = GenerationParameters()
        XCTAssertNil(params.steps)

        params.steps = 50
        XCTAssertEqual(params.steps, 50)

        params.steps = nil
        XCTAssertNil(params.steps)
    }

    // MARK: - Edge Cases

    func testSeedCanBeSetManually() {
        let params = GenerationParameters()
        params.seed = 999999
        XCTAssertEqual(params.seed, 999999)

        params.seed = 1
        XCTAssertEqual(params.seed, 1)
    }

    func testZeroTextureSize() {
        let params = GenerationParameters()
        params.textureSize = 0
        XCTAssertEqual(params.textureSize, 0)
    }
}
