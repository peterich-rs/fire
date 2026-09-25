import XCTest
@testable import Fire

final class FireUserCardChromeTests: XCTestCase {
    func testCompactDetentStaysShorterThanHalfSheet() {
        XCTAssertLessThan(FireUserCardChrome.compactDetentHeight, 360)
        XCTAssertGreaterThan(FireUserCardChrome.compactDetentHeight, 220)
        XCTAssertEqual(
            FireUserCardChrome.compactDetentIdentifier.rawValue,
            "fire.user-card.compact"
        )
    }

    func testActionButtonsUseCompactInsetsAndTypeSize() {
        let insets = FireUserCardChrome.actionContentInsets
        XCTAssertEqual(insets.top, 7)
        XCTAssertEqual(insets.bottom, 7)
        XCTAssertLessThan(insets.top + insets.bottom, 18)
        XCTAssertEqual(FireUserCardChrome.actionTitleFont.pointSize, 13)
        XCTAssertEqual(FireUserCardChrome.actionSymbolSize, 12)
    }
}
