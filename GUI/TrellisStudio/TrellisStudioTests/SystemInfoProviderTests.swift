import XCTest
@testable import TrellisStudio

final class SystemInfoProviderTests: XCTestCase {

    func testChipNameIsNonEmpty() {
        let chip = SystemInfoProvider.chipName
        XCTAssertFalse(chip.isEmpty, "Chip name should be populated from sysctl")
    }

    func testChipNameContainsApple() {
        let chip = SystemInfoProvider.chipName
        XCTAssertTrue(
            chip.lowercased().contains("apple"),
            "Expected Apple silicon chip name, got: \(chip)"
        )
    }

    func testMemoryStringIsNonEmpty() {
        let mem = SystemInfoProvider.memoryString
        XCTAssertFalse(mem.isEmpty)
    }

    func testMemoryStringContainsGB() {
        let mem = SystemInfoProvider.memoryString
        XCTAssertTrue(mem.contains("GB"), "Memory string should contain 'GB', got: \(mem)")
    }

    func testMemoryStringContainsUnifiedMemory() {
        let mem = SystemInfoProvider.memoryString
        XCTAssertTrue(mem.contains("Unified Memory"))
    }

    func testMacOSVersionIsNonEmpty() {
        let version = SystemInfoProvider.macOSVersion
        XCTAssertFalse(version.isEmpty)
    }

    func testMacOSVersionStartsWithMacOS() {
        let version = SystemInfoProvider.macOSVersion
        XCTAssertTrue(version.hasPrefix("macOS "), "Expected 'macOS X.Y', got: \(version)")
    }

    func testMacOSVersionContainsDot() {
        let version = SystemInfoProvider.macOSVersion
        XCTAssertTrue(version.contains("."), "Version should contain major.minor separator")
    }
}
