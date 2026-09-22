import XCTest
@testable import Fire

final class FireTopicDetailStoreTests: XCTestCase {
    func testWindowStateActiveAnchorPrefersPendingScrollTarget() {
        let window = FireTopicDetailWindowState(
            anchorPostNumber: 72,
            requestedRange: 60..<90,
            loadedIndices: IndexSet(integersIn: 60...70),
            pendingScrollTarget: 88
        )

        XCTAssertEqual(window.activeAnchorPostNumber, 88)
    }
}
