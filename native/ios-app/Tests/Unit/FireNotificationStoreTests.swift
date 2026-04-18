import XCTest
@testable import Fire

final class FireNotificationStoreTests: XCTestCase {
    @MainActor
    func testRecentLoadFailureIsBlockingBeforeFirstSuccessfulLoad() {
        let store = FireNotificationStore(appViewModel: FireAppViewModel())

        store.recordRecentLoadFailure("offline")

        XCTAssertEqual(store.blockingRecentErrorMessage, "offline")
        XCTAssertNil(store.recentNonBlockingErrorMessage)
    }

    @MainActor
    func testRecentLoadFailureIsNonBlockingAfterSuccessfulLoad() {
        let store = FireNotificationStore(appViewModel: FireAppViewModel())

        store.apply(
            centerState: NotificationCenterState(
                counters: NotificationCountersState(allUnread: 1, unread: 1, highPriority: 0),
                recent: [makeNotification(id: 1, read: false)],
                hasLoadedRecent: true,
                recentSeenNotificationId: 1,
                full: [],
                hasLoadedFull: false,
                totalRowsNotifications: 1,
                fullSeenNotificationId: 0,
                fullLoadMoreNotifications: nil,
                fullNextOffset: nil
            ),
            updateRecent: true,
            updateFull: false
        )

        store.recordRecentLoadFailure("offline")

        XCTAssertNil(store.blockingRecentErrorMessage)
        XCTAssertEqual(store.recentNonBlockingErrorMessage, "offline")
        XCTAssertEqual(store.recentNotifications.map(\.id), [1])
    }

    @MainActor
    func testApplyCenterStateUpdatesUnreadRecentAndFullLists() {
        let store = FireNotificationStore(appViewModel: FireAppViewModel())
        let recent = makeNotification(id: 1, read: false)
        let full = makeNotification(id: 2, read: true)

        store.apply(
            centerState: NotificationCenterState(
                counters: NotificationCountersState(allUnread: 7, unread: 4, highPriority: 1),
                recent: [recent],
                hasLoadedRecent: true,
                recentSeenNotificationId: 1,
                full: [full],
                hasLoadedFull: true,
                totalRowsNotifications: 10,
                fullSeenNotificationId: 2,
                fullLoadMoreNotifications: "/notifications?offset=60",
                fullNextOffset: 60
            ),
            updateRecent: true,
            updateFull: true
        )

        XCTAssertEqual(store.unreadCount, 7)
        XCTAssertEqual(store.recentNotifications.map(\.id), [1])
        XCTAssertEqual(store.fullNotifications.map(\.id), [2])
        XCTAssertEqual(store.fullNextOffset, 60)
        XCTAssertTrue(store.hasMoreFull)
    }

    @MainActor
    func testResetClearsNotificationState() {
        let store = FireNotificationStore(appViewModel: FireAppViewModel())
        store.apply(
            centerState: NotificationCenterState(
                counters: NotificationCountersState(allUnread: 2, unread: 2, highPriority: 0),
                recent: [makeNotification(id: 1, read: false)],
                hasLoadedRecent: true,
                recentSeenNotificationId: 1,
                full: [makeNotification(id: 2, read: true)],
                hasLoadedFull: true,
                totalRowsNotifications: 2,
                fullSeenNotificationId: 2,
                fullLoadMoreNotifications: nil,
                fullNextOffset: 20
            ),
            updateRecent: true,
            updateFull: true
        )

        store.reset()

        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertTrue(store.recentNotifications.isEmpty)
        XCTAssertTrue(store.fullNotifications.isEmpty)
        XCTAssertNil(store.fullNextOffset)
        XCTAssertFalse(store.hasMoreFull)
        XCTAssertFalse(store.isLoadingRecent)
        XCTAssertFalse(store.isLoadingFullPage)
    }

    private func makeNotification(id: UInt64, read: Bool) -> NotificationItemState {
        NotificationItemState(
            id: id,
            userId: 1,
            notificationType: 2,
            read: read,
            highPriority: false,
            createdAt: nil,
            createdTimestampUnixMs: nil,
            postNumber: 1,
            topicId: 100 + id,
            slug: "topic-\(id)",
            fancyTitle: "Topic \(id)",
            actingUserAvatarTemplate: nil,
            data: NotificationDataState(
                displayUsername: "alice",
                originalPostId: nil,
                originalPostType: nil,
                originalUsername: nil,
                revisionNumber: nil,
                topicTitle: "Topic \(id)",
                badgeName: nil,
                badgeId: nil,
                badgeSlug: nil,
                groupName: nil,
                inboxCount: nil,
                count: nil,
                username: "alice",
                username2: nil,
                avatarTemplate: nil,
                excerpt: nil,
                payloadJson: nil
            )
        )
    }
}
