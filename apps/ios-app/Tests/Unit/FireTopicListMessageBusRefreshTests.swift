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

    func testLatestEventsRespectExpandedMinimumRefreshIntervalAndCoalesceTopicIDs() {
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

        XCTAssertEqual(firstDelay, .seconds(3))
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

        XCTAssertEqual(secondDelay, .seconds(40))
        XCTAssertEqual(thirdDelay, .seconds(17))
        XCTAssertEqual(
            controller.takePendingRefresh(for: scope),
            .incremental(topicIDs: [202, 303])
        )
    }

    func testUnsupportedEventDoesNotRequestFullRefresh() {
        let clock = ContinuousClock()
        let scope = FireTopicListRefreshScope(kind: .latest, categoryId: nil, tags: [])
        var controller = FireTopicListMessageBusRefreshController()

        let delay = controller.register(
            event: makeLatestEvent(topicID: nil, messageType: "created"),
            for: scope,
            now: clock.now,
            allowIncremental: true
        )

        XCTAssertNil(delay)
        XCTAssertNil(controller.takePendingRefresh(for: scope))
    }

    func testFilteredScopeIgnoresTopicListEventsInsteadOfFullRefreshing() {
        let clock = ContinuousClock()
        let scope = FireTopicListRefreshScope(kind: .latest, categoryId: 42, tags: [])
        var controller = FireTopicListMessageBusRefreshController()

        let delay = controller.register(
            event: makeLatestEvent(topicID: 101),
            for: scope,
            now: clock.now,
            allowIncremental: false
        )

        XCTAssertNil(delay)
        XCTAssertNil(controller.takePendingRefresh(for: scope))
    }

    func testIncrementalRefreshRequiresVisibleRenderedLatestList() {
        let scope = FireTopicListRefreshScope(kind: .latest, categoryId: nil, tags: [])

        XCTAssertFalse(
            FireHomeFeedStore.canScheduleIncrementalMessageBusRefresh(
                scope: scope,
                renderedScope: scope,
                isTopicListVisible: false,
                isSceneActive: true,
                hasRows: true
            )
        )
        XCTAssertFalse(
            FireHomeFeedStore.canScheduleIncrementalMessageBusRefresh(
                scope: scope,
                renderedScope: nil,
                isTopicListVisible: true,
                isSceneActive: true,
                hasRows: true
            )
        )
        XCTAssertFalse(
            FireHomeFeedStore.canScheduleIncrementalMessageBusRefresh(
                scope: scope,
                renderedScope: scope,
                isTopicListVisible: true,
                isSceneActive: false,
                hasRows: true
            )
        )
        XCTAssertFalse(
            FireHomeFeedStore.canScheduleIncrementalMessageBusRefresh(
                scope: scope,
                renderedScope: scope,
                isTopicListVisible: true,
                isSceneActive: true,
                hasRows: false
            )
        )
        XCTAssertTrue(
            FireHomeFeedStore.canScheduleIncrementalMessageBusRefresh(
                scope: scope,
                renderedScope: scope,
                isTopicListVisible: true,
                isSceneActive: true,
                hasRows: true
            )
        )
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

    @MainActor
    func testHomeTopicCountPatchOnlyUpdatesMatchingExistingRow() {
        let row = makeTopicRow(id: 42, activityTimestampUnixMs: 100)
        let patch = TopicHomeRowCountPatchState(
            topicId: 42,
            postsCount: 9,
            replyCount: 8,
            views: 321,
            lastReadPostNumber: 8,
            highestPostNumber: 9,
            unread: .stillUnread
        )

        let patched = FireHomeFeedStore.applyHomeRowCountPatch(row, patch: patch)

        XCTAssertEqual(patched?.topic.id, 42)
        XCTAssertEqual(patched?.topic.postsCount, 9)
        XCTAssertEqual(patched?.topic.replyCount, 8)
        XCTAssertEqual(patched?.topic.views, 321)
        XCTAssertEqual(patched?.topic.highestPostNumber, 9)
        XCTAssertEqual(patched?.topic.lastReadPostNumber, 8)
        XCTAssertNil(FireHomeFeedStore.applyHomeRowCountPatch(
            makeTopicRow(id: 7, activityTimestampUnixMs: 200),
            patch: patch
        ))
    }

    @MainActor
    func testHomeTopicCountPatchClearsUnreadStateWhenReadPositionReachesHighestPost() {
        var row = makeTopicRow(id: 42, activityTimestampUnixMs: 100)
        row.topic.unreadPosts = 2
        row.topic.newPosts = 1
        row.topic.lastReadPostNumber = 7
        row.topic.highestPostNumber = 9
        row.hasUnreadPosts = true
        let patch = TopicHomeRowCountPatchState(
            topicId: 42,
            postsCount: 9,
            replyCount: 9,
            views: 321,
            lastReadPostNumber: 9,
            highestPostNumber: 9,
            unread: .caughtUp
        )

        let patched = FireHomeFeedStore.applyHomeRowCountPatch(row, patch: patch)

        XCTAssertEqual(patched?.topic.lastReadPostNumber, 9)
        XCTAssertEqual(patched?.topic.highestPostNumber, 9)
        XCTAssertEqual(patched?.topic.unreadPosts, 0)
        XCTAssertEqual(patched?.topic.newPosts, 0)
        XCTAssertEqual(patched?.hasUnreadPosts, false)
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

    private func makeTopicDetail(
        id: UInt64,
        postsCount: UInt32,
        replyCount: UInt32,
        views: UInt32 = 0
    ) -> TopicDetailState {
        TopicDetailState(
            id: id,
            messageBusLastId: nil,
            title: "Topic \(id)",
            slug: "topic-\(id)",
            postsCount: postsCount,
            replyCount: replyCount,
            categoryId: nil,
            tags: [],
            views: views,
            likeCount: 0,
            createdAt: nil,
            highestPostNumber: postsCount,
            lastReadPostNumber: replyCount,
            bookmarks: [],
            bookmarked: false,
            bookmarkId: nil,
            bookmarkName: nil,
            bookmarkReminderAt: nil,
            acceptedAnswer: false,
            hasAcceptedAnswer: false,
            canVote: false,
            voteCount: 0,
            userVoted: false,
            summarizable: false,
            hasCachedSummary: false,
            hasSummary: false,
            archetype: "regular",
            postStream: TopicPostStreamState(posts: [], stream: []),
            details: TopicDetailMetaState(
                notificationLevel: nil,
                canEdit: false,
                createdBy: nil,
                participants: []
            )
        )
    }
}
