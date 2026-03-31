import AppKit
import XCTest
@testable import VibeMDCore

final class ReaderThemeTests: XCTestCase {
    func testSidebarThemeUsesFixedDarkerSurfaceTokens() {
        XCTAssertEqual(ReaderTheme.sidebarBackgroundHex, "#212427")
        XCTAssertEqual(ReaderTheme.sidebarSelectionHex, "#1C2023")
        XCTAssertEqual(ReaderTheme.sidebarHoverAlpha, 0.028, accuracy: 0.0001)
        XCTAssertLessThan(
            luminance(of: ReaderTheme.sidebarBackgroundColor),
            luminance(of: ReaderTheme.backgroundColor)
        )
        XCTAssertTrue(ReaderTheme.styleSheet.contains("overflow-x: hidden;"))
    }

    private func luminance(of color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        return (0.2126 * rgb.redComponent) + (0.7152 * rgb.greenComponent) + (0.0722 * rgb.blueComponent)
    }
}
