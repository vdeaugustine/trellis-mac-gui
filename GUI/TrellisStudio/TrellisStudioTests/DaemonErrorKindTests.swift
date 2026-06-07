import XCTest
@testable import TrellisStudio

final class DaemonErrorKindTests: XCTestCase {

    // MARK: - classifyError (via reflection approach)

    func testClassifyGatedRepoError() {
        let message = "Access to model is restricted. You must visit https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m to accept"
        let kind = DaemonManager.classifyError(message)
        if case .gatedAccess = kind {
            // Expected
        } else {
            XCTFail("Expected gatedAccess, got \(kind)")
        }
    }

    func testClassifyRestrictedError() {
        let message = "Model is restricted and requires approval"
        let kind = DaemonManager.classifyError(message)
        if case .gatedAccess = kind {
            // Expected
        } else {
            XCTFail("Expected gatedAccess, got \(kind)")
        }
    }

    func testClassifyAuthError401() {
        let message = "HTTP 401 Unauthorized"
        let kind = DaemonManager.classifyError(message)
        XCTAssertEqual(kind, .authRequired)
    }

    func testClassifyAuthErrorUnauthorized() {
        let message = "User is unauthorized to access this resource"
        let kind = DaemonManager.classifyError(message)
        XCTAssertEqual(kind, .authRequired)
    }

    func testClassifyAuthErrorNotLoggedIn() {
        let message = "User is not logged in"
        let kind = DaemonManager.classifyError(message)
        XCTAssertEqual(kind, .authRequired)
    }

    func testClassifyGenericError() {
        let message = "Something went wrong with CUDA"
        let kind = DaemonManager.classifyError(message)
        XCTAssertEqual(kind, .generic)
    }

    func testClassifyEmptyMessage() {
        let kind = DaemonManager.classifyError("")
        XCTAssertEqual(kind, .generic)
    }

    // MARK: - Equatable

    func testNoneEquality() {
        XCTAssertEqual(DaemonErrorKind.none, DaemonErrorKind.none)
    }

    func testGatedAccessEquality() {
        XCTAssertEqual(
            DaemonErrorKind.gatedAccess(repo: "facebook/dino"),
            DaemonErrorKind.gatedAccess(repo: "facebook/dino")
        )
    }

    func testGatedAccessInequality() {
        XCTAssertNotEqual(
            DaemonErrorKind.gatedAccess(repo: "facebook/dino"),
            DaemonErrorKind.gatedAccess(repo: "briaai/RMBG")
        )
    }

    func testDifferentKindsNotEqual() {
        XCTAssertNotEqual(DaemonErrorKind.none, DaemonErrorKind.generic)
        XCTAssertNotEqual(DaemonErrorKind.authRequired, DaemonErrorKind.generic)
        XCTAssertNotEqual(DaemonErrorKind.none, DaemonErrorKind.authRequired)
    }
}
