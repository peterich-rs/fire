import XCTest
@testable import Fire

final class FireTopicListMessageBusRefreshTests: XCTestCase {
    func testHomeTopicListDisplayStateShowsBlockingErrorWhenCurrentScopeHasNoSnapshot() {
        XCTAssertEqual(
            FireHomeTopicListDisplayState.resolve(
                hasResolvedCurrentScope: false,
                hasRows: false,
                errorMessage: "offline"
            ),
            .blockingError(message: "offline")
        )
    }

    func testHomeTopicListDisplayStateKeepsContentVisibleOnRefreshFailure() {
        XCTAssertEqual(
            FireHomeTopicListDisplayState.resolve(
                hasResolvedCurrentScope: true,
                hasRows: true,
                errorMessage: "offline"
            ),
            .content(nonBlockingErrorMessage: "offline")
        )
    }

    func testLatestEventsRespectMinimumRefreshIntervalAndCoalesceTopicIDs() {
        let clock = ContinuousClock()
        let scope = FireTopicListRefreshScope(kind: .latest, categoryId: nil, tags: [])
        let base = clock.now
        var controller = FireTopicListMessageBusRefreshController()

        let firstDelay = controller.register(
            event: makeLatestEvent(topicID: 101),
            for: scope,
            now: base,
            allowIncremental: true
        )

        XCTAssertEqual(firstDelay, .seconds(1.5))
        XCTAssertEqual(
            controller.takePendingRefresh(for: scope),
            .incremental(topicIDs: [101])
        )

        controller.markRefreshCompleted(for: scope, at: base)

        let secondDelay = controller.register(
            event: makeLatestEvent(topicID: 202),
            for: scope,
            now: base.advanced(by: .seconds(5)),
            allowIncremental: true
        )
        let thirdDelay = controller.register(
            event: makeLatestEvent(topicID: 303),
            for: scope,
            now: base.advanced(by: .seconds(28)),
            allowIncremental: true
        )

        XCTAssertEqual(secondDelay, .seconds(25))
        XCTAssertEqual(thirdDelay, .seconds(2))
        XCTAssertEqual(
            controller.takePendingRefresh(for: scope),
            .incremental(topicIDs: [202, 303])
        )
    }

    func testUnsupportedEventFallsBackToFullRefresh() {
        let clock = ContinuousClock()
        let scope = FireTopicListRefreshScope(kind: .latest, categoryId: nil, tags: [])
        var controller = FireTopicListMessageBusRefreshController()

        let delay = controller.register(
            event: makeLatestEvent(topicID: nil, messageType: "created"),
            for: scope,
            now: clock.now,
            allowIncremental: true
        )

        XCTAssertEqual(delay, .seconds(1.5))
        XCTAssertEqual(controller.takePendingRefresh(for: scope), .full)
    }

    func testIncrementalMergeMovesUpdatedTopicsToFront() {
        let existing = [
            makeTopicRow(id: 1, activityTimestampUnixMs: 10),
            makeTopicRow(id: 2, activityTimestampUnixMs: 20),
            makeTopicRow(id: 3, activityTimestampUnixMs: 30),
        ]
        let incoming = [
            makeTopicRow(id: 3, activityTimestampUnixMs: 300),
            makeTopicRow(id: 4, activityTimestampUnixMs: 400),
        ]

        let merged = FireTopicListMessageBusRefreshMerger.merge(
            existing: existing,
            incoming: incoming
        )

        XCTAssertEqual(merged.map(\.topic.id), [3, 4, 1, 2])
        XCTAssertEqual(merged.first?.activityTimestampUnixMs, 300)
    }

    private func makeLatestEvent(
        topicID: UInt64?,
        messageType: String? = "latest"
    ) -> MessageBusEventState {
        MessageBusEventState(
            channel: "/latest",
            messageId: 1,
            kind: .topicList,
            topicListKind: .latest,
            topicId: topicID,
            notificationUserId: nil,
            messageType: messageType,
            detailEventType: nil,
            reloadTopic: false,
            refreshStream: false,
            allUnreadNotificationsCount: nil,
            unreadNotifications: nil,
            unreadHighPriorityNotifications: nil,
            payloadJson: nil
        )
    }

    private func makeTopicRow(
        id: UInt64,
        activityTimestampUnixMs: UInt64
    ) -> TopicRowState {
        TopicRowState(
            topic: TopicSummaryState(
                id: id,
                title: "Topic \(id)",
                slug: "topic-\(id)",
                postsCount: 1,
                replyCount: 0,
                views: 0,
                likeCount: 0,
                excerpt: nil,
                createdAt: nil,
                lastPostedAt: nil,
                lastPosterUsername: nil,
                categoryId: nil,
                pinned: false,
                visible: true,
                closed: false,
                archived: false,
                tags: [],
                posters: [],
                participants: [],
                unseen: false,
                unreadPosts: 0,
                newPosts: 0,
                lastReadPostNumber: nil,
                highestPostNumber: 1,
                bookmarkedPostNumber: nil,
                bookmarkId: nil,
                bookmarkName: nil,
                bookmarkReminderAt: nil,
                bookmarkableType: nil,
                hasAcceptedAnswer: false,
                canHaveAnswer: false
            ),
            excerptText: nil,
            originalPosterUsername: nil,
            originalPosterAvatarTemplate: nil,
            tagNames: [],
            statusLabels: [],
            isPinned: false,
            isClosed: false,
            isArchived: false,
            hasAcceptedAnswer: false,
            hasUnreadPosts: false,
            createdTimestampUnixMs: nil,
            activityTimestampUnixMs: activityTimestampUnixMs,
            lastPosterUsername: nil
        )
    }
}
