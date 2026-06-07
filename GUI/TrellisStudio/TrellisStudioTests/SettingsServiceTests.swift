import XCTest
@testable import TrellisStudio

final class SettingsServiceTests: XCTestCase {

    let service = SettingsService.shared

    // MARK: - Default Values

    func testDefaultPipelineType() {
        // When key is missing, default should be "512"
        let value = service.defaultPipelineType
        XCTAssertFalse(value.isEmpty)
    }

    func testDefaultTextureSizeIsPositive() {
        XCTAssertGreaterThan(service.defaultTextureSize, 0)
    }

    func testDefaultSeedIsPositive() {
        XCTAssertGreaterThan(service.defaultSeed, 0)
    }

    func testAdvancedEnvVarsHasDefault() {
        let envVars = service.advancedEnvVars
        XCTAssertFalse(envVars.isEmpty, "Should have a default env var string")
    }

    // MARK: - Persistence

    func testHfTokenPersistsToUserDefaults() {
        let original = service.hfToken
        service.hfToken = "test_token_123"
        XCTAssertEqual(UserDefaults.standard.string(forKey: "hfToken"), "test_token_123")
        service.hfToken = original // restore
    }

    func testPipelineTypePersistsToUserDefaults() {
        let original = service.defaultPipelineType
        service.defaultPipelineType = "1024"
        XCTAssertEqual(UserDefaults.standard.string(forKey: "defaultPipelineType"), "1024")
        service.defaultPipelineType = original
    }

    func testTextureSizePersistsToUserDefaults() {
        let original = service.defaultTextureSize
        service.defaultTextureSize = 2048
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "defaultTextureSize"), 2048)
        service.defaultTextureSize = original
    }

    func testDefaultSeedPersistsToUserDefaults() {
        let original = service.defaultSeed
        service.defaultSeed = 12345
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "defaultSeed"), 12345)
        service.defaultSeed = original
    }

    func testAdvancedEnvVarsPersistsToUserDefaults() {
        let original = service.advancedEnvVars
        service.advancedEnvVars = "FOO=bar"
        XCTAssertEqual(UserDefaults.standard.string(forKey: "advancedEnvVars"), "FOO=bar")
        service.advancedEnvVars = original
    }

    // MARK: - Edge Cases

    func testEmptyHfToken() {
        let original = service.hfToken
        service.hfToken = ""
        XCTAssertEqual(service.hfToken, "")
        service.hfToken = original
    }

    func testSpecialCharactersInEnvVars() {
        let original = service.advancedEnvVars
        service.advancedEnvVars = "KEY=\"value with spaces\"\nANOTHER=123"
        XCTAssertTrue(service.advancedEnvVars.contains("spaces"))
        service.advancedEnvVars = original
    }
}
