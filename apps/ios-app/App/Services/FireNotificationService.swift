import Foundation

@MainActor
final class FireNotificationService {
    private let host: FireAppServiceHost

    init(host: FireAppServiceHost) {
        self.host = host
    }

    func notificationCenterState() async throws -> NotificationCenterState {
        let sessionStore = try await host.sessionStoreValue()
        return try await sessionStore.notificationState()
    }

    func fetchRecentNotifications(limit: UInt32? = nil) async throws -> NotificationListState {
        let sessionStore = try await host.sessionStoreValue()
        return try await host.performWithCloudflareRecovery(operation: "刷新通知列表") {
            try await sessionStore.fetchRecentNotifications(limit: limit)
        }
    }

    func fetchNotifications(
        limit: UInt32? = nil,
        offset: UInt32? = nil
    ) async throws -> NotificationListState {
        let sessionStore = try await host.sessionStoreValue()
        return try await host.performWithCloudflareRecovery(operation: "加载更多通知") {
            try await sessionStore.fetchNotifications(limit: limit, offset: offset)
        }
    }

    func markNotificationRead(id: UInt64) async throws -> NotificationCenterState {
        let sessionStore = try await host.sessionStoreValue()
        return try await host.performWriteWithCloudflareRetry(
            operationDescription: "标记通知已读"
        ) {
            try await sessionStore.markNotificationRead(id: id)
        }
    }

    func markAllNotificationsRead() async throws -> NotificationCenterState {
        let sessionStore = try await host.sessionStoreValue()
        return try await host.performWriteWithCloudflareRetry(
            operationDescription: "全部通知标记已读"
        ) {
            try await sessionStore.markAllNotificationsRead()
        }
    }
}
