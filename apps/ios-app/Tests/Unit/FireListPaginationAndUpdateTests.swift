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
                id: "reply-footer:42",
                kind: .replyFooter,
                contentToken: FireTopicDetailRuntimeReplyFooterState.emptyPrompt.contentToken
            ),
        ]
        let next = [
            makeRuntimeItem(id: "header", kind: .header, contentToken: "header"),
            makeRuntimeItem(id: "reply:200:2", kind: .reply, contentToken: "reply"),
            makeRuntimeItem(
                id: "reply-footer:42",
                kind: .replyFooter,
                contentToken: FireTopicDetailRuntimeReplyFooterState.endReached.contentToken
            ),
        ]

        let plan = fireTopicDetailCollectionUpdatePlan(from: current, to: next)

        XCTAssertEqual(plan.deletions, [])
        XCTAssertEqual(plan.insertions, [IndexPath(item: 1, section: 0)])
        XCTAssertEqual(plan.postUpdateReloads, [IndexPath(item: 2, section: 0)])
    }

    func testTopicDetailShouldLoadMoreNearTrailingThreshold() {
        XCTAssertTrue(fireTopicDetailShouldEvaluatePagination(forceLoadMoreEvaluation: true, isScrollInteractionActive: false))
        XCTAssertFalse(fireTopicDetailShouldEvaluatePagination(forceLoadMoreEvaluation: false, isScrollInteractionActive: false))
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

    func testTopicDetailLikeInPlaceTokenDoesNotCreateReloads() {
        let current = [
            makeRuntimeItem(id: "reply", contentToken: "layout", inPlaceUpdateToken: "heart-3"),
        ]
        let next = [
            makeRuntimeItem(id: "reply", contentToken: "layout", inPlaceUpdateToken: "heart-4"),
        ]

        XCTAssertTrue(fireTopicDetailCollectionUpdatePlan(from: current, to: next).isEmpty)
        XCTAssertEqual(fireTopicDetailVisibleNodeUpdateIndices(from: current, to: next), [0])
        XCTAssertTrue(
            fireTopicDetailCanReuseCurrentSnapshot(
                previousInvalidationToken: "same",
                nextInvalidationToken: "same",
                hasCurrentItems: true,
                itemsHaveSameRenderedContent: true
            )
        )
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

    func testVisibleNodeUpdatesSurviveAnInsertion() {
        let current = [
            makeRuntimeItem(id: "reply-a", contentToken: "layout-a", inPlaceUpdateToken: "ui-a"),
        ]
        let next = [
            makeRuntimeItem(id: "reply-new", contentToken: "layout-new"),
            makeRuntimeItem(id: "reply-a", contentToken: "layout-a", inPlaceUpdateToken: "ui-a-2"),
        ]

        XCTAssertEqual(fireTopicDetailVisibleNodeUpdateIndices(from: current, to: next), [0])
        let plan = fireTopicDetailCollectionUpdatePlan(from: current, to: next)
        XCTAssertEqual(plan.insertions, [IndexPath(item: 0, section: 0)])
        XCTAssertTrue(plan.reloads.isEmpty)
        XCTAssertTrue(plan.postUpdateReloads.isEmpty)
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

    func testTopicListChipKeepsContentWidthInsteadOfExpandingAcrossRow() {
        let chip = FireTopicListChipLabel(
            text: "公告",
            textColor: .label,
            backgroundColor: .tertiarySystemFill
        )

        let textWidth = ("公告" as NSString).size(
            withAttributes: [.font: chip.font as Any]
        ).width

        XCTAssertEqual(chip.contentHuggingPriority(for: .horizontal), .required)
        XCTAssertEqual(chip.intrinsicContentSize.width, textWidth + 12, accuracy: 1)
        XCTAssertLessThan(chip.intrinsicContentSize.width, 100)
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

    func testCommitGateHoldsWhileBusyAndDiffsCommittedToLatest() {
        let committed = [
            makeRuntimeItem(id: "a", contentToken: "1"),
        ]
        let inflight = [
            makeRuntimeItem(id: "a", contentToken: "1"),
            makeRuntimeItem(id: "b", contentToken: "2"),
        ]
        let latest = [
            makeRuntimeItem(id: "a", contentToken: "1"),
            makeRuntimeItem(id: "b", contentToken: "2"),
            makeRuntimeItem(id: "c", contentToken: "3"),
        ]

        XCTAssertEqual(
            fireTopicDetailCommitDecision(committed: committed, latest: inflight, isCommitting: true),
            .holdWhileBusy
        )
        switch fireTopicDetailCommitDecision(committed: committed, latest: latest, isCommitting: false) {
        case .commitBatch(let plan):
            XCTAssertEqual(plan.insertions, [
                IndexPath(item: 1, section: 0),
                IndexPath(item: 2, section: 0),
            ])
            XCTAssertTrue(plan.deletions.isEmpty)
        default:
            XCTFail("expected a coalesced batch from committed A to latest C")
        }
    }

    func testLikeOnThousandRowsOnlyMarksChangedIndex() {
        let current = (0..<1000).map { index in
            makeRuntimeItem(
                id: "reply-\(index)",
                contentToken: "layout",
                inPlaceUpdateToken: "heart-1"
            )
        }
        var next = current
        next[777] = makeRuntimeItem(
            id: "reply-777",
            contentToken: "layout",
            inPlaceUpdateToken: "heart-2"
        )

        XCTAssertEqual(fireTopicDetailVisibleNodeUpdateIndices(from: current, to: next), [777])
        XCTAssertTrue(fireTopicDetailCollectionUpdatePlan(from: current, to: next).isEmpty)
        XCTAssertEqual(
            fireTopicDetailCommitDecision(committed: current, latest: next, isCommitting: false),
            .applyInPlace(indices: [777])
        )
    }

    func testReplyFooterIdentityStaysStableAcrossStates() {
        XCTAssertEqual(
            makeRuntimeItem(
                id: "reply-footer:42",
                kind: .replyFooter,
                contentToken: FireTopicDetailRuntimeReplyFooterState.loadingFooter.contentToken
            ).id,
            "reply-footer:42"
        )
        XCTAssertEqual(
            makeRuntimeItem(
                id: "reply-footer:42",
                kind: .replyFooter,
                contentToken: FireTopicDetailRuntimeReplyFooterState.endReached.contentToken
            ).id,
            "reply-footer:42"
        )
    }

    func testDeferredCollectionApplyOnlyHoldsScrollPlusBatch() {
        XCTAssertTrue(
            fireTopicDetailShouldDeferCollectionApply(
                isScrollInteractionActive: true,
                hasBatchUpdates: true
            )
        )
        XCTAssertFalse(
            fireTopicDetailShouldDeferCollectionApply(
                isScrollInteractionActive: true,
                hasBatchUpdates: false
            )
        )
        XCTAssertFalse(
            fireTopicDetailShouldDeferCollectionApply(
                isScrollInteractionActive: false,
                hasBatchUpdates: true
            )
        )
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
