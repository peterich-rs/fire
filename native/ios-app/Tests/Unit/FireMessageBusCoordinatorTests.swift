import XCTest
@testable import Fire

final class FireMessageBusCoordinatorTests: XCTestCase {
    func testBufferedQueueCoalescesTopicScopedEventsKeepingNewestMessage() {
        var queue = FireMessageBusBufferedEventQueue()

        queue.enqueue(makeEvent(kind: .topicDetail, channel: "/topic/42", messageId: 10))
        queue.enqueue(makeEvent(kind: .topicDetail, channel: "/topic/42", messageId: 12))

        let batch = queue.dequeueBatch(limit: 10)

        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch.first?.messageId, 12)
    }

    func testBufferedQueueDropsOldestUniqueEventsWhenCapacityIsExceeded() {
        var queue = FireMessageBusBufferedEventQueue()

        for index in 0..<70 {
            queue.enqueue(
                makeEvent(
                    kind: .unknown,
                    channel: "/unknown/\(index)",
                    messageId: Int64(index)
                )
            )
        }

        let batch = queue.dequeueBatch(limit: 100)

        XCTAssertEqual(batch.count, 64)
        XCTAssertEqual(batch.first?.messageId, 6)
        XCTAssertEqual(batch.last?.messageId, 69)
    }

    private func makeEvent(
        kind: MessageBusEventKindState,
        channel: String,
        messageId: Int64
    ) -> MessageBusEventState {
        MessageBusEventState(
            channel: channel,
            messageId: messageId,
            kind: kind,
            topicListKind: nil,
            topicId: nil,
            notificationUserId: nil,
            messageType: nil,
            detailEventType: nil,
            reloadTopic: false,
            refreshStream: false,
            allUnreadNotificationsCount: nil,
            unreadNotifications: nil,
            unreadHighPriorityNotifications: nil,
            payloadJson: nil
        )
    }
}
