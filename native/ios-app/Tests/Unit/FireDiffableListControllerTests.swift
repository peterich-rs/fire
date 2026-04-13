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
