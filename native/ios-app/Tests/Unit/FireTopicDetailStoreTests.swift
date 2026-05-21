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

    func testActiveScrollTargetIsNotExhaustedUntilWholeStreamHasBeenCovered() {
        let window = FireTopicDetailWindowState(
            anchorPostNumber: 88,
            requestedRange: 40..<70,
            loadedIndices: IndexSet(integersIn: 40..<70),
            loadedPostNumbers: Set((40..<70).map(UInt32.init)),
            pendingScrollTarget: 88
        )
        let orderedPostIDs = Array(1...120).map(UInt64.init)
        let loadedPostIDs = Set(orderedPostIDs[40..<70])

        XCTAssertFalse(FireTopicDetailStore.scrollTargetIsExhausted(
            postNumber: 88,
            window: window,
            orderedPostIDs: orderedPostIDs,
            loadedPostIDs: loadedPostIDs
        ))
    }

    func testScrollTargetIsExhaustedAfterWholeStreamCoveredWithoutTarget() {
        let window = FireTopicDetailWindowState(
            anchorPostNumber: 88,
            requestedRange: 0..<5,
            loadedIndices: IndexSet(integersIn: 0..<5),
            loadedPostNumbers: Set<UInt32>([1, 2, 3, 4, 5]),
            pendingScrollTarget: 88
        )
        let orderedPostIDs = Array(1...5).map(UInt64.init)
        let loadedPostIDs = Set(orderedPostIDs)

        XCTAssertTrue(FireTopicDetailStore.scrollTargetIsExhausted(
            postNumber: 88,
            window: window,
            orderedPostIDs: orderedPostIDs,
            loadedPostIDs: loadedPostIDs
        ))
    }

    func testUnresolvedScrollTargetSearchJumpsNearEstimatedPostNumber() {
        let nextRange = FireTopicDetailStore.nextRequestedRangeForUnresolvedTarget(
            postNumber: 500,
            current: 0..<30,
            totalCount: 1_000,
            loadedPostNumbersInCurrentRange: Array(1...30).map(UInt32.init)
        )

        XCTAssertNotNil(nextRange)
        XCTAssertTrue(nextRange?.contains(499) == true)
    }

    func testUnresolvedScrollTargetSearchMovesBackwardWhenWindowIsPastTarget() {
        let nextRange = FireTopicDetailStore.nextRequestedRangeForUnresolvedTarget(
            postNumber: 500,
            current: 480..<510,
            totalCount: 1_000,
            loadedPostNumbersInCurrentRange: Array(700...729).map(UInt32.init)
        )

        XCTAssertEqual(nextRange, 450..<510)
    }

    func testUnresolvedScrollTargetSearchSlidesForwardAtWindowCap() {
        let nextRange = FireTopicDetailStore.nextRequestedRangeForUnresolvedTarget(
            postNumber: 500,
            current: 400..<600,
            totalCount: 1_000,
            loadedPostNumbersInCurrentRange: Array(300...499).map(UInt32.init)
        )

        XCTAssertEqual(nextRange, 430..<630)
    }
}
