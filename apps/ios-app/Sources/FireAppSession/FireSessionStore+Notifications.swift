import Foundation

extension FireSessionStore {
    public func notificationState() throws -> NotificationCenterState {
        try core.notifications().notificationState()
    }

    public func fetchRecentNotifications(limit: UInt32? = nil) async throws -> NotificationListState {
        try await runPersistingSessionChanges {
            try await core.notifications().fetchRecentNotifications(limit: limit)
        }
    }

    public func fetchNotifications(
        limit: UInt32? = nil,
        offset: UInt32? = nil
    ) async throws -> NotificationListState {
        try await runPersistingSessionChanges {
            try await core.notifications().fetchNotifications(limit: limit, offset: offset)
        }
    }

    public func markNotificationRead(id: UInt64) async throws -> NotificationCenterState {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.notifications().markNotificationRead(notificationId: id)
        }
    }

    public func markAllNotificationsRead() async throws -> NotificationCenterState {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.notifications().markAllNotificationsRead()
        }
    }

    public func pollNotificationAlertOnce(
        lastMessageId: Int64
    ) async throws -> NotificationAlertPollResultState {
        try await runPersistingSessionChanges {
            try await core.messagebus().pollNotificationAlertOnce(lastMessageId: lastMessageId)
        }
    }

    // MARK: - Chat
}
