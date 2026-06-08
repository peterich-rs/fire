import XCTest
@testable import Fire

final class FireEntityStateTests: XCTestCase {
    func testOrderedIDListDeduplicatesAndPreservesAppendOrder() {
        var orderedIDs = FireOrderedIDList(ids: [2, 1, 2])
        orderedIDs.append([1, 3, 4, 3])

        XCTAssertEqual(orderedIDs.ids, [2, 1, 3, 4])
    }

    func testEntityIndexUpsertReplacesExistingPayloadAndKeepsOtherEntities() {
        var index = FireEntityIndex<UInt64, TestEntity>()
        index.replaceAll(
            [
                TestEntity(id: 1, title: "one"),
                TestEntity(id: 2, title: "two"),
            ],
            id: \.id
        )

        index.upsert(
            [
                TestEntity(id: 2, title: "two-updated"),
                TestEntity(id: 3, title: "three"),
            ],
            id: \.id
        )

        XCTAssertEqual(index.entity(for: 1)?.title, "one")
        XCTAssertEqual(index.entity(for: 2)?.title, "two-updated")
        XCTAssertEqual(index.entity(for: 3)?.title, "three")
    }

    func testOrderedValuesFollowExplicitIDListOrder() {
        var index = FireEntityIndex<UInt64, TestEntity>()
        index.replaceAll(
            [
                TestEntity(id: 1, title: "one"),
                TestEntity(id: 2, title: "two"),
                TestEntity(id: 3, title: "three"),
            ],
            id: \.id
        )

        let orderedValues = index.orderedValues(
            for: FireOrderedIDList(ids: [3, 1, 2])
        )

        XCTAssertEqual(orderedValues.map(\.title), ["three", "one", "two"])
    }

    func testTopicListKindTitlesUseChineseLabels() {
        XCTAssertEqual(TopicListKindState.latest.title, "最新")
        XCTAssertEqual(TopicListKindState.new.title, "最新发布")
        XCTAssertEqual(TopicListKindState.unread.title, "未读")
        XCTAssertEqual(TopicListKindState.unseen.title, "未看")
        XCTAssertEqual(TopicListKindState.hot.title, "热门")
        XCTAssertEqual(TopicListKindState.top.title, "精华")
        XCTAssertEqual(TopicListKindState.privateMessagesInbox.title, "收件箱")
        XCTAssertEqual(TopicListKindState.privateMessagesSent.title, "已发送")
    }
}

private struct TestEntity: Equatable {
    let id: UInt64
    let title: String
}
