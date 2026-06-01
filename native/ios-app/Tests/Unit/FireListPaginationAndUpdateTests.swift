import UIKit
import XCTest
@testable import Fire

final class FireListPaginationAndUpdateTests: XCTestCase {
    func testTopicDetailCollectionUpdatePlanReloadsOnlyChangedItems() {
        let current = [
            makeRuntimeItem(id: "a", contentToken: "1"),
            makeRuntimeItem(id: "b", contentToken: "2"),
            makeRuntimeItem(id: "c", contentToken: "3"),
        ]
        let next = [
            makeRuntimeItem(id: "a", contentToken: "1"),
            makeRuntimeItem(id: "b", contentToken: "updated"),
            makeRuntimeItem(id: "c", contentToken: "3"),
        ]

        let plan = fireTopicDetailCollectionUpdatePlan(from: current, to: next)

        XCTAssertEqual(plan.deletions, [])
        XCTAssertEqual(plan.insertions, [])
        XCTAssertEqual(plan.reloads, [IndexPath(item: 1, section: 0)])
    }

    func testTopicDetailCollectionUpdatePlanTracksInsertionsAndDeletions() {
        let current = [
            makeRuntimeItem(id: "a", contentToken: "1"),
            makeRuntimeItem(id: "b", contentToken: "2"),
            makeRuntimeItem(id: "d", contentToken: "4"),
        ]
        let next = [
            makeRuntimeItem(id: "a", contentToken: "1"),
            makeRuntimeItem(id: "c", contentToken: "3"),
            makeRuntimeItem(id: "d", contentToken: "4"),
            makeRuntimeItem(id: "e", contentToken: "5"),
        ]

        let plan = fireTopicDetailCollectionUpdatePlan(from: current, to: next)

        XCTAssertEqual(plan.deletions, [IndexPath(item: 1, section: 0)])
        XCTAssertEqual(plan.insertions, [IndexPath(item: 1, section: 0), IndexPath(item: 3, section: 0)])
        XCTAssertEqual(plan.reloads, [])
    }

    func testTopicDetailShouldLoadMoreNearTrailingThreshold() {
        XCTAssertTrue(fireTopicDetailShouldLoadMore(itemCount: 20, visibleMaxItem: 13))
        XCTAssertFalse(fireTopicDetailShouldLoadMore(itemCount: 20, visibleMaxItem: 11))
        XCTAssertFalse(fireTopicDetailShouldLoadMore(itemCount: 20, visibleMaxItem: nil))
    }

    func testTopicDetailHoldsLoadingFooterWhileContinuousPagingWillContinue() {
        XCTAssertTrue(fireTopicDetailShouldHoldLoadingFooter(
            previousFooterState: .loadingFooter,
            nextFooterState: .loadMore,
            itemCount: 24,
            visibleMaxItem: 17
        ))

        XCTAssertFalse(fireTopicDetailShouldHoldLoadingFooter(
            previousFooterState: .loadingFooter,
            nextFooterState: .loadMore,
            itemCount: 24,
            visibleMaxItem: 12
        ))

        XCTAssertFalse(fireTopicDetailShouldHoldLoadingFooter(
            previousFooterState: .loadMore,
            nextFooterState: .loadMore,
            itemCount: 24,
            visibleMaxItem: 17
        ))
    }

    func testTopicDetailCollectionUpdatePlanNoopsForIdenticalItems() {
        let current = [
            makeRuntimeItem(id: "header", contentToken: "same"),
            makeRuntimeItem(id: "reply", contentToken: "same"),
        ]
        let next = [
            makeRuntimeItem(id: "header", contentToken: "same"),
            makeRuntimeItem(id: "reply", contentToken: "same"),
        ]

        XCTAssertTrue(fireTopicDetailCollectionUpdatePlan(from: current, to: next).isEmpty)
    }

    func testHomePaginationRequestsNextPageWhenStillNearBottom() {
        let metrics = FireCollectionScrollMetrics(
            remainingDistanceToBottom: 120,
            contentHeight: 2_400,
            visibleHeight: 760
        )

        XCTAssertTrue(fireHomeShouldRequestNextPage(
            nextTopicsPage: 3,
            lastTriggeredTopicsPage: 2,
            isLoadingTopics: false,
            metrics: metrics,
            paginationPrefetchDistance: 480,
            didPrefetchToFillViewport: false
        ))

        XCTAssertFalse(fireHomeShouldRequestNextPage(
            nextTopicsPage: 3,
            lastTriggeredTopicsPage: 3,
            isLoadingTopics: false,
            metrics: metrics,
            paginationPrefetchDistance: 480,
            didPrefetchToFillViewport: false
        ))
    }

    func testHomePaginationRequestsNextPageWhenViewportStillUnderfilled() {
        let metrics = FireCollectionScrollMetrics(
            remainingDistanceToBottom: 0,
            contentHeight: 520,
            visibleHeight: 760
        )

        XCTAssertTrue(fireHomeShouldRequestNextPage(
            nextTopicsPage: 2,
            lastTriggeredTopicsPage: nil,
            isLoadingTopics: false,
            metrics: metrics,
            paginationPrefetchDistance: 480,
            didPrefetchToFillViewport: false
        ))

        XCTAssertFalse(fireHomeShouldRequestNextPage(
            nextTopicsPage: 2,
            lastTriggeredTopicsPage: nil,
            isLoadingTopics: false,
            metrics: metrics,
            paginationPrefetchDistance: 480,
            didPrefetchToFillViewport: true
        ))
    }

    func testCollectionUpdatePolicyAllowsPagingFooterDuringRegularScroll() {
        XCTAssertFalse(fireCollectionShouldDeferSectionUpdate(
            updatePolicy: .deferDuringRefresh,
            isActivelyScrolling: true,
            isInRefreshLifecycle: false,
            hasCurrentSections: true
        ))

        XCTAssertTrue(fireCollectionShouldDeferSectionUpdate(
            updatePolicy: .deferDuringRefresh,
            isActivelyScrolling: false,
            isInRefreshLifecycle: true,
            hasCurrentSections: true
        ))

        XCTAssertTrue(fireCollectionShouldDeferSectionUpdate(
            updatePolicy: .deferWhileScrolling,
            isActivelyScrolling: true,
            isInRefreshLifecycle: false,
            hasCurrentSections: true
        ))
    }

    private func makeRuntimeItem(id: String, contentToken: String) -> FireTopicDetailRuntimeItem {
        FireTopicDetailRuntimeItem(
            id: id,
            kind: .reply,
            postID: nil,
            postNumber: nil,
            replyIndex: nil,
            contentToken: AnyHashable(contentToken)
        )
    }
}
