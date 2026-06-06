import XCTest
@testable import TrellisStudio

final class TrellisStudioTests: XCTestCase {
    func testOnboardingService() {
        let os = OnboardingService.shared
        XCTAssertNotNil(os)
        
        let space = os.checkDiskSpace()
        XCTAssertGreaterThanOrEqual(space, 0.0)
        
        let invalidPath = "/invalid/path/to/trellis"
        XCTAssertFalse(os.checkTrellisPath(invalidPath))
    }
    
    func testDaemonManager() {
        let dm = DaemonManager.shared
        XCTAssertNotNil(dm)
        XCTAssertTrue(dm.isOffline)
        XCTAssertFalse(dm.isReady)
    }
}
