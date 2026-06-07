import XCTest
import SwiftUI
@testable import TrellisStudio

final class ThemeTests: XCTestCase {

    // MARK: - Color Constants Exist

    func testBackgroundColorExists() {
        let color = Theme.background
        XCTAssertNotNil(color)
    }

    func testSlateGrayExists() {
        XCTAssertNotNil(Theme.slateGray)
    }

    func testAccentIndigoExists() {
        XCTAssertNotNil(Theme.accentIndigo)
    }

    func testAccentVioletExists() {
        XCTAssertNotNil(Theme.accentViolet)
    }

    func testBorderColorExists() {
        XCTAssertNotNil(Theme.border)
    }

    func testLightModeColors() {
        XCTAssertNotNil(Theme.backgroundLight)
        XCTAssertNotNil(Theme.textMutedLight)
        XCTAssertNotNil(Theme.borderLight)
    }

    func testStatusColors() {
        XCTAssertNotNil(Theme.successGreen)
        XCTAssertNotNil(Theme.warningAmber)
        XCTAssertNotNil(Theme.errorRed)
    }

    // MARK: - Spacing Constants

    func testSpacingValues() {
        XCTAssertEqual(Theme.Spacing.xs, 4)
        XCTAssertEqual(Theme.Spacing.sm, 8)
        XCTAssertEqual(Theme.Spacing.md, 12)
        XCTAssertEqual(Theme.Spacing.lg, 16)
        XCTAssertEqual(Theme.Spacing.xl, 24)
        XCTAssertEqual(Theme.Spacing.xxl, 32)
    }

    func testSpacingAscending() {
        XCTAssertLessThan(Theme.Spacing.xs, Theme.Spacing.sm)
        XCTAssertLessThan(Theme.Spacing.sm, Theme.Spacing.md)
        XCTAssertLessThan(Theme.Spacing.md, Theme.Spacing.lg)
        XCTAssertLessThan(Theme.Spacing.lg, Theme.Spacing.xl)
        XCTAssertLessThan(Theme.Spacing.xl, Theme.Spacing.xxl)
    }

    // MARK: - Corner Radius Constants

    func testCornerRadiusValues() {
        XCTAssertEqual(Theme.CornerRadius.button, 8)
        XCTAssertEqual(Theme.CornerRadius.card, 12)
        XCTAssertEqual(Theme.CornerRadius.panel, 20)
    }

    func testCornerRadiusAscending() {
        XCTAssertLessThan(Theme.CornerRadius.button, Theme.CornerRadius.card)
        XCTAssertLessThan(Theme.CornerRadius.card, Theme.CornerRadius.panel)
    }

    // MARK: - Gradient

    func testAccentGradientExists() {
        let gradient = Theme.accentGradient
        XCTAssertNotNil(gradient)
    }

    // MARK: - Color Hex Extension

    func testColorHexBlack() {
        let color = Color(hex: 0x000000)
        XCTAssertNotNil(color)
    }

    func testColorHexWhite() {
        let color = Color(hex: 0xFFFFFF)
        XCTAssertNotNil(color)
    }

    func testColorHexRed() {
        let color = Color(hex: 0xFF0000)
        XCTAssertNotNil(color)
    }

    func testColorHexWithAlpha() {
        let color = Color(hex: 0x5D5CDE, alpha: 0.5)
        XCTAssertNotNil(color)
    }

    func testColorHexDefaultAlpha() {
        // Just verify the default parameter compiles and runs
        let color = Color(hex: 0xABCDEF)
        XCTAssertNotNil(color)
    }
}
