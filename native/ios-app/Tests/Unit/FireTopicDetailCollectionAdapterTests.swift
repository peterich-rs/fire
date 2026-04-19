import XCTest
@testable import Fire

final class FireTopicDetailCollectionAdapterTests: XCTestCase {
    func testVisiblePostNumbersIncludeOriginalAndReplyItems() {
        let items: [FireTopicDetailCollectionItem] = [
            .header(topicID: 42),
            .originalPost(topicID: 42),
            .reply(FireTopicDetailCollectionReplyKey(postID: 200, postNumber: 2)),
            .replyFooter(topicID: 42),
        ]

        let visiblePostNumbers = FireTopicDetailCollectionAdapter.visiblePostNumbers(
            from: items,
            originalPostNumber: 1
        )

        XCTAssertEqual(visiblePostNumbers, Set<UInt32>([1, 2]))
    }

    func testScrollItemResolvesOriginalPostSlot() {
        let replyRows = [
            FirePreparedTopicTimelineRow(
                entry: FireTopicTimelineEntry(
                    postId: 200,
                    postNumber: 2,
                    parentPostNumber: 1,
                    depth: 1,
                    isOriginalPost: false
                )
            )
        ]

        let item = FireTopicDetailCollectionAdapter.scrollItem(
            for: 1,
            topicID: 42,
            originalPostNumber: 1,
            replyRows: replyRows
        )

        XCTAssertEqual(item, .originalPost(topicID: 42))
    }

    func testScrollItemResolvesReplyByPostNumber() {
        let replyRows = [
            FirePreparedTopicTimelineRow(
                entry: FireTopicTimelineEntry(
                    postId: 200,
                    postNumber: 2,
                    parentPostNumber: 1,
                    depth: 1,
                    isOriginalPost: false
                )
            ),
            FirePreparedTopicTimelineRow(
                entry: FireTopicTimelineEntry(
                    postId: 300,
                    postNumber: 3,
                    parentPostNumber: 2,
                    depth: 2,
                    isOriginalPost: false
                )
            ),
        ]

        let item = FireTopicDetailCollectionAdapter.scrollItem(
            for: 3,
            topicID: 42,
            originalPostNumber: 1,
            replyRows: replyRows
        )

        XCTAssertEqual(
            item,
            .reply(FireTopicDetailCollectionReplyKey(postID: 300, postNumber: 3))
        )
    }
}