import XCTest
@testable import Fire

final class FireDiffableListControllerTests: XCTestCase {
    func testLayoutUpdateHelperSkipsIdenticalVersions() {
        XCTAssertFalse(fireCollectionNeedsLayoutUpdate(currentVersion: 1, incomingVersion: 1))
        XCTAssertTrue(fireCollectionNeedsLayoutUpdate(currentVersion: 1, incomingVersion: 2))
        XCTAssertTrue(fireCollectionNeedsLayoutUpdate(currentVersion: nil, incomingVersion: 0))
    }

    func testSectionUpdateHelperSkipsIdenticalSnapshots() {
        let current = [
            FireListSectionModel<Int, Int>(id: 0, items: [1, 2, 3])
        ]
        XCTAssertFalse(fireCollectionNeedsSectionUpdate(current: current, incoming: current))
        XCTAssertTrue(
            fireCollectionNeedsSectionUpdate(
                current: current,
                incoming: [FireListSectionModel(id: 0, items: [1, 2, 3, 4])]
            )
        )
    }

    func testCommonItemsHelperReturnsStableIdentifiersForReconfigure() {
        let current = [
            FireListSectionModel<Int, Int>(id: 0, items: [1, 2, 3])
        ]
        let incoming = [
            FireListSectionModel<Int, Int>(id: 0, items: [3, 2, 4])
        ]

        XCTAssertEqual(fireCollectionCommonItems(current: current, incoming: incoming), [3, 2])
    }

    func testChangedItemsHelperOnlyReturnsCommonItemsWithMutatedTokens() {
        let current = [
            FireListSectionModel<Int, Int>(id: 0, items: [1, 2, 3])
        ]
        let incoming = [
            FireListSectionModel<Int, Int>(id: 0, items: [3, 2, 4])
        ]
        let previousTokens: [Int: AnyHashable] = [1: "a", 2: "b", 3: "c"]
        let currentTokens: [Int: AnyHashable] = [2: "b", 3: "c-new", 4: "d"]

        let changed = fireCollectionChangedItems(
            current: current,
            incoming: incoming,
            previousTokens: previousTokens,
            currentTokens: currentTokens
        )

        XCTAssertEqual(changed, [3])
    }

    func testScrollRequestDefaultsRequestIdentityToItemID() {
        let request = FireCollectionScrollRequest(itemID: 42)

        XCTAssertEqual(request.requestID, AnyHashable(42))
    }

    func testScrollRequestChangeHelperUsesLogicalRequestIdentity() {
        let current = FireCollectionScrollRequest(itemID: 42, requestID: "initial")
        let retry = FireCollectionScrollRequest(itemID: 42, requestID: "retry")

        XCTAssertTrue(fireCollectionScrollRequestDidChange(current: current, incoming: retry))
        XCTAssertFalse(fireCollectionScrollRequestDidChange(current: retry, incoming: retry))
    }

    func testNeedsScrollRequestHelperAllowsRetryForSameItemWithNewRequestID() {
        let retry = FireCollectionScrollRequest(itemID: 42, requestID: "retry")

        XCTAssertTrue(
            fireCollectionNeedsScrollRequest(
                handledRequestID: "initial",
                incoming: retry
            )
        )
        XCTAssertFalse(
            fireCollectionNeedsScrollRequest(
                handledRequestID: "retry",
                incoming: retry
            )
        )
    }

    func testDefaultScrollAnchorRestorePolicySkipsAnimatedDiffs() {
        XCTAssertFalse(
            FireCollectionScrollAnchorRestorePolicy.whenNotAnimatingDifferences.shouldRestore(
                animatingDifferences: true
            )
        )
        XCTAssertTrue(
            FireCollectionScrollAnchorRestorePolicy.whenNotAnimatingDifferences.shouldRestore(
                animatingDifferences: false
            )
        )
    }

    func testScrollAnchorRestorePolicySupportsExplicitAlwaysAndNeverModes() {
        XCTAssertTrue(
            FireCollectionScrollAnchorRestorePolicy.always.shouldRestore(
                animatingDifferences: true
            )
        )
        XCTAssertFalse(
            FireCollectionScrollAnchorRestorePolicy.never.shouldRestore(
                animatingDifferences: false
            )
        )
    }
}
