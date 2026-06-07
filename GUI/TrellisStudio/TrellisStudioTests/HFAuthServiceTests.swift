import XCTest
@testable import TrellisStudio

final class HFAuthServiceTests: XCTestCase {

    let service = HFAuthService.shared

    // MARK: - Initial State

    func testInitialState() {
        // Can't guarantee empty since it's a singleton, but check non-nil
        XCTAssertNotNil(service.username)
        XCTAssertFalse(service.isValidating)
    }

    // MARK: - Gated Models

    func testGatedModelsCountIsAtLeastTwo() {
        XCTAssertGreaterThanOrEqual(service.gatedModels.count, 2)
    }

    func testGatedModelsHaveDINOv3() {
        let dino = service.gatedModels.first { $0.id == "dinov3" }
        XCTAssertNotNil(dino)
        XCTAssertEqual(dino?.repoId, "facebook/dinov3-vitl16-pretrain-lvd1689m")
        XCTAssertEqual(dino?.displayName, "DINOv3 (Meta)")
    }

    func testGatedModelsHaveRMBG() {
        let rmbg = service.gatedModels.first { $0.id == "rmbg" }
        XCTAssertNotNil(rmbg)
        XCTAssertEqual(rmbg?.repoId, "briaai/RMBG-2.0")
        XCTAssertEqual(rmbg?.displayName, "RMBG-2.0 (BRIA AI)")
    }

    func testGatedModelsHaveValidURLs() {
        for model in service.gatedModels {
            XCTAssertTrue(
                model.requestURL.absoluteString.starts(with: "https://huggingface.co/"),
                "Model \(model.id) has invalid URL: \(model.requestURL)"
            )
        }
    }

    // MARK: - Token Detection

    func testDetectExistingTokenReturnsNilOrToken() {
        let result = service.detectExistingToken()
        // Can be nil if no HF token on system, or a non-empty string
        if let token = result {
            XCTAssertFalse(token.isEmpty)
        }
    }

    // MARK: - Validate Token (Edge Cases)

    func testValidateEmptyTokenReturnsNil() async {
        let result = await service.validateToken("")
        XCTAssertNil(result)
    }

    // MARK: - Check Model Access

    func testCheckModelAccessWithEmptyToken() async {
        let status = await service.checkModelAccess(token: "", repoId: "test/repo")
        if case .error(let msg) = status {
            XCTAssertEqual(msg, "No token")
        } else {
            XCTFail("Expected .error, got \(status)")
        }
    }

    // MARK: - Computed Properties

    func testAllGatedAccessGrantedWithUnknownStatus() {
        // Default status is .unknown, so should be false
        XCTAssertFalse(service.allGatedAccessGranted)
    }

    func testIsCheckingAccessDefaultIsFalse() {
        // Default status is .unknown, not .checking
        XCTAssertFalse(service.isCheckingAccess)
    }

    // MARK: - Static Properties

    func testCreateTokenURLIsValid() {
        let url = HFAuthService.createTokenURL
        XCTAssertTrue(url.absoluteString.contains("huggingface.co"))
        XCTAssertTrue(url.absoluteString.contains("tokens"))
    }

    // MARK: - GatedModelStatus

    func testGatedModelStatusEquatable() {
        XCTAssertEqual(GatedModelStatus.unknown, GatedModelStatus.unknown)
        XCTAssertEqual(GatedModelStatus.checking, GatedModelStatus.checking)
        XCTAssertEqual(GatedModelStatus.granted, GatedModelStatus.granted)
        XCTAssertEqual(GatedModelStatus.denied, GatedModelStatus.denied)
        XCTAssertEqual(GatedModelStatus.error("x"), GatedModelStatus.error("x"))
        XCTAssertNotEqual(GatedModelStatus.granted, GatedModelStatus.denied)
        XCTAssertNotEqual(GatedModelStatus.error("a"), GatedModelStatus.error("b"))
    }

    // MARK: - GatedModelInfo

    func testGatedModelInfoIdentifiable() {
        let model = GatedModelInfo(
            id: "test",
            repoId: "org/model",
            displayName: "Test Model",
            requestURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(model.id, "test")
        XCTAssertEqual(model.status, .unknown)
    }
}
