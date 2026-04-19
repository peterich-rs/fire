import XCTest
@testable import Fire

final class FireTopicDetailInteractionTests: XCTestCase {
    func testReplySwipeReservesLeadingEdgeForBackNavigation() {
        let axis = FireTopicReplySwipePolicy.resolvedAxis(
            startLocationX: 12,
            translationWidth: 48,
            translationHeight: 4
        )

        XCTAssertEqual(axis, .reservedForNavigationBack)
    }

    func testReplySwipeStaysHorizontalAwayFromBackNavigationEdge() {
        let axis = FireTopicReplySwipePolicy.resolvedAxis(
            startLocationX: 80,
            translationWidth: 48,
            translationHeight: 4
        )

        XCTAssertEqual(axis, .horizontal)
    }
}