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

    func testTopicDetailCollectionUpdatePlanDefersReloadsForItemsShiftedByDeletion() {
        let current = [
            makeRuntimeItem(id: "a", contentToken: "1"),
            makeRuntimeItem(id: "b", contentToken: "2"),
            makeRuntimeItem(id: "c", contentToken: "3"),
            makeRuntimeItem(id: "d", contentToken: "4"),
            makeRuntimeItem(id: "removed", contentToken: "removed"),
            makeRuntimeItem(id: "shifted", contentToken: "old"),
        ]
        let next = [
            makeRuntimeItem(id: "a", contentToken: "1"),
            makeRuntimeItem(id: "b", contentToken: "2"),
            makeRuntimeItem(id: "c", contentToken: "3"),
            makeRuntimeItem(id: "d", contentToken: "4"),
            makeRuntimeItem(id: "shifted", contentToken: "new"),
        ]

        let plan = fireTopicDetailCollectionUpdatePlan(from: current, to: next)

        XCTAssertEqual(plan.deletions, [IndexPath(item: 4, section: 0)])
        XCTAssertEqual(plan.insertions, [])
        XCTAssertEqual(plan.reloads, [])
        XCTAssertEqual(plan.postUpdateReloads, [IndexPath(item: 4, section: 0)])
    }

    func testTopicDetailCollectionUpdatePlanDefersReloadsForItemsMovedByInsertDeleteDiff() {
        let current = [
            makeRuntimeItem(id: "a", contentToken: "old-a"),
            makeRuntimeItem(id: "b", contentToken: "old-b"),
            makeRuntimeItem(id: "c", contentToken: "old-c"),
        ]
        let next = [
            makeRuntimeItem(id: "b", contentToken: "new-b"),
            makeRuntimeItem(id: "a", contentToken: "old-a"),
            makeRuntimeItem(id: "c", contentToken: "old-c"),
        ]

        let plan = fireTopicDetailCollectionUpdatePlan(from: current, to: next)

        XCTAssertEqual(plan.deletions, [IndexPath(item: 0, section: 0)])
        XCTAssertEqual(plan.insertions, [IndexPath(item: 1, section: 0)])
        XCTAssertEqual(plan.reloads, [])
        XCTAssertEqual(plan.postUpdateReloads, [IndexPath(item: 0, section: 0)])
    }

    func testTopicDetailCollectionUpdatePlanRebuildsFooterWhenStateChanges() {
        let current = [
            makeRuntimeItem(id: "header", kind: .header, contentToken: "header"),
            makeRuntimeItem(
                id: "reply-footer:42:emptyPrompt",
                kind: .replyFooter,
                contentToken: FireTopicDetailRuntimeReplyFooterState.emptyPrompt.contentToken
            ),
        ]
        let next = [
            makeRuntimeItem(id: "header", kind: .header, contentToken: "header"),
            makeRuntimeItem(id: "reply:200:2", kind: .reply, contentToken: "reply"),
            makeRuntimeItem(
                id: "reply-footer:42:endReached",
                kind: .replyFooter,
                contentToken: FireTopicDetailRuntimeReplyFooterState.endReached.contentToken
            ),
        ]

        let plan = fireTopicDetailCollectionUpdatePlan(from: current, to: next)

        XCTAssertEqual(plan.deletions, [IndexPath(item: 1, section: 0)])
        XCTAssertEqual(plan.insertions, [IndexPath(item: 1, section: 0), IndexPath(item: 2, section: 0)])
        XCTAssertEqual(plan.reloads, [])
    }

    func testTopicDetailShouldLoadMoreNearTrailingThreshold() {
        XCTAssertTrue(fireTopicDetailShouldLoadMore(itemCount: 20, visibleMaxItem: 15))
        XCTAssertTrue(fireTopicDetailShouldLoadMore(itemCount: 20, visibleMaxItem: 16))
        XCTAssertFalse(fireTopicDetailShouldLoadMore(itemCount: 20, visibleMaxItem: 14))
        XCTAssertFalse(fireTopicDetailShouldLoadMore(itemCount: 20, visibleMaxItem: 13))
        XCTAssertFalse(fireTopicDetailShouldLoadMore(itemCount: 20, visibleMaxItem: nil))
    }

    func testTopicDetailPaginationSkipsProgrammaticScrollEvaluation() {
        XCTAssertFalse(
            fireTopicDetailShouldEvaluatePagination(
                forceLoadMoreEvaluation: false,
                isScrollInteractionActive: false
            )
        )
        XCTAssertTrue(
            fireTopicDetailShouldEvaluatePagination(
                forceLoadMoreEvaluation: false,
                isScrollInteractionActive: true
            )
        )
        XCTAssertTrue(
            fireTopicDetailShouldEvaluatePagination(
                forceLoadMoreEvaluation: true,
                isScrollInteractionActive: false
            )
        )
    }

    func testTopicDetailLoadMoreProbeTracksItemPositionOnly() {
        let probe = fireTopicDetailLoadMoreProbe(
            itemCount: 20,
            visibleMaxItem: 11
        )

        XCTAssertEqual(
            probe,
            fireTopicDetailLoadMoreProbe(itemCount: 20, visibleMaxItem: 11)
        )
        XCTAssertNotEqual(
            probe,
            fireTopicDetailLoadMoreProbe(itemCount: 20, visibleMaxItem: 12)
        )
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

    func testTopicDetailVisibleNodeUpdateIndicesOnlyMarksInPlaceStateChanges() {
        let current = [
            makeRuntimeItem(id: "reply-a", contentToken: "layout-a", inPlaceUpdateToken: "ui-a"),
            makeRuntimeItem(id: "reply-b", contentToken: "layout-b", inPlaceUpdateToken: "ui-b"),
        ]
        let next = [
            makeRuntimeItem(id: "reply-a", contentToken: "layout-a", inPlaceUpdateToken: "ui-a-2"),
            makeRuntimeItem(id: "reply-b", contentToken: "layout-b", inPlaceUpdateToken: "ui-b"),
        ]

        XCTAssertEqual(
            fireTopicDetailVisibleNodeUpdateIndices(from: current, to: next),
            [0]
        )
    }

    func testTopicDetailVisiblePostRelayoutIndexPathsOnlyKeepsVisiblePostReloads() {
        let items = [
            makeRuntimeItem(id: "header", kind: .header, contentToken: "header"),
            makeRuntimeItem(id: "reply", kind: .reply, contentToken: "reply"),
            makeRuntimeItem(id: "footer", kind: .replyFooter, contentToken: "footer"),
        ]

        let relayouts = fireTopicDetailVisiblePostRelayoutIndexPaths(
            reloads: [
                IndexPath(item: 0, section: 0),
                IndexPath(item: 1, section: 0),
                IndexPath(item: 2, section: 0),
            ],
            nextItems: items,
            visibleIndexPaths: Set([
                IndexPath(item: 0, section: 0),
                IndexPath(item: 1, section: 0),
            ]),
            isPostNode: { _ in true }
        )

        XCTAssertEqual(relayouts, [IndexPath(item: 1, section: 0)])
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

    private func makeRuntimeItem(
        id: String,
        kind: FireTopicDetailRuntimeItemKind = .reply,
        contentToken: String,
        inPlaceUpdateToken: String? = nil
    ) -> FireTopicDetailRuntimeItem {
        FireTopicDetailRuntimeItem(
            id: id,
            kind: kind,
            postID: nil,
            postNumber: nil,
            replyIndex: nil,
            contentToken: AnyHashable(contentToken),
            inPlaceUpdateToken: inPlaceUpdateToken.map(AnyHashable.init)
        )
    }
}
