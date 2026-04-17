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

    func testClearingTransientAnchorPreservesWindowShape() {
        let window = FireTopicDetailWindowState(
            anchorPostNumber: 88,
            requestedRange: 40..<70,
            loadedIndices: IndexSet(integersIn: 42...50),
            loadedPostNumbers: Set<UInt32>([41, 42, 43]),
            exhaustedPostIDs: Set<UInt64>([9001]),
            pendingScrollTarget: 88
        )

        let cleared = window.clearingTransientAnchor()

        XCTAssertNil(cleared.anchorPostNumber)
        XCTAssertNil(cleared.pendingScrollTarget)
        XCTAssertNil(cleared.activeAnchorPostNumber)
        XCTAssertEqual(cleared.requestedRange, 40..<70)
        XCTAssertEqual(cleared.loadedIndices, IndexSet(integersIn: 42...50))
        XCTAssertEqual(cleared.loadedPostNumbers, Set<UInt32>([41, 42, 43]))
        XCTAssertEqual(cleared.exhaustedPostIDs, Set<UInt64>([9001]))
    }

    func testInitialRequestedRangeCentersOnAnchorAndIncludesLoadedSpan() {
        let range = FireTopicDetailStore.initialRequestedRange(
            totalCount: 120,
            anchorIndex: 60,
            loadedIndices: IndexSet(integersIn: 58...62)
        )

        XCTAssertTrue(range.contains(60))
        XCTAssertLessThanOrEqual(range.lowerBound, 58)
        XCTAssertGreaterThanOrEqual(range.upperBound, 63)
        XCTAssertGreaterThanOrEqual(range.upperBound - range.lowerBound, 30)
    }

    func testInitialRequestedRangeFallsBackToLeadingPageWithoutAnchor() {
        let range = FireTopicDetailStore.initialRequestedRange(
            totalCount: 120,
            anchorIndex: nil,
            loadedIndices: IndexSet()
        )

        XCTAssertEqual(range, 0..<30)
    }

    func testExpandedRequestedRangeGrowsForwardAroundAnchor() {
        let range = FireTopicDetailStore.expandedRequestedRange(
            current: 45..<75,
            totalCount: 200,
            expandBackward: false,
            expandForward: true,
            anchorIndex: 60
        )

        XCTAssertEqual(range, 45..<105)
    }

    func testBoundedRequestedRangeKeepsAnchorInsideWindowCap() {
        let range = FireTopicDetailStore.boundedRequestedRange(
            lowerBound: 0,
            upperBound: 260,
            totalCount: 400,
            anchorIndex: 180
        )

        XCTAssertEqual(range.upperBound - range.lowerBound, FireTopicDetailWindowState.maxWindowSize)
        XCTAssertTrue(range.contains(180))
    }
}
