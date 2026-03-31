import BackgroundTasks
import Foundation
import UserNotifications

enum FireBackgroundNotificationAlertScheduler {
    static let taskIdentifier = "com.fire.app.ios.notification-alert-refresh"

    private static let refreshInterval: TimeInterval = 15 * 60

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task: task)
        }
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancelRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    private static func handle(task: BGAppRefreshTask) {
        scheduleRefresh()

        let worker = Task {
            await FireBackgroundNotificationAlertWorker.shared.performRefresh()
        }
        task.expirationHandler = {
            worker.cancel()
        }

        Task {
            let success = await worker.value
            task.setTaskCompleted(success: success)
        }
    }
}

actor FireBackgroundNotificationAlertWorker {
    static let shared = FireBackgroundNotificationAlertWorker()

    private let defaults = UserDefaults.standard

    func performRefresh() async -> Bool {
        do {
            let sessionStore = try FireSessionStore()
            let initialSession = if let restored = try await sessionStore.restorePersistedSessionIfAvailable() {
                restored
            } else {
                try await sessionStore.snapshot()
            }
            let session: SessionState
            if initialSession.readiness.canReadAuthenticatedApi && !initialSession.readiness.hasCurrentUser {
                session = try await sessionStore.refreshBootstrapIfNeeded()
            } else {
                session = initialSession
            }

            guard session.readiness.canOpenMessageBus,
                  let userId = session.bootstrap.currentUserId else {
                return true
            }

            let previousLastMessageId = lastMessageId(for: userId)
            let pollResult = try await sessionStore.pollNotificationAlertOnce(
                lastMessageId: previousLastMessageId
            )
            if pollResult.lastMessageId > previousLastMessageId {
                setLastMessageId(pollResult.lastMessageId, for: userId)
            }

            guard !Task.isCancelled else { return false }
            guard await FireSystemNotificationPresenter.canPresentNotifications() else {
                return true
            }

            for alert in pollResult.alerts {
                guard !Task.isCancelled else { return false }
                try await FireSystemNotificationPresenter.present(alert: alert)
            }
            return true
        } catch {
            return false
        }
    }

    private func lastMessageId(for userId: UInt64) -> Int64 {
        let value = defaults.object(forKey: lastMessageIdKey(for: userId)) as? NSNumber
        return value?.int64Value ?? -1
    }

    private func setLastMessageId(_ lastMessageId: Int64, for userId: UInt64) {
        defaults.set(NSNumber(value: lastMessageId), forKey: lastMessageIdKey(for: userId))
    }

    private func lastMessageIdKey(for userId: UInt64) -> String {
        "fire.background.notification-alert.last-message-id.\(userId)"
    }
}

enum FireSystemNotificationPresenter {
    static func canPresentNotifications() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    static func present(alert: NotificationAlertState) async throws {
        let content = UNMutableNotificationContent()
        content.title = title(for: alert)
        content.body = body(for: alert)
        content.sound = .default
        content.threadIdentifier = "linux.do.notification-alert"

        if let topicId = alert.topicId {
            content.userInfo["topicId"] = topicId
        }
        if let postNumber = alert.postNumber {
            content.userInfo["postNumber"] = postNumber
        }
        content.userInfo["messageId"] = alert.messageId

        let request = UNNotificationRequest(
            identifier: "fire.notification-alert.\(alert.messageId)",
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    private static func title(for alert: NotificationAlertState) -> String {
        let trimmedTopicTitle = alert.topicTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTopicTitle.isEmpty {
            return trimmedTopicTitle
        }

        switch alert.notificationType {
        case 1: return "有人提到了你"
        case 2: return "有人回复了你"
        case 3: return "有人引用了你"
        case 5: return "有人赞了你"
        case 6: return "你收到了一条私信"
        case 15: return "有人提到了你的群组"
        case 25: return "有人对你用了表情"
        default: return "新通知"
        }
    }

    private static func body(for alert: NotificationAlertState) -> String {
        let trimmedExcerpt = alert.excerpt?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedExcerpt.isEmpty {
            return trimmedExcerpt
        }

        let trimmedUsername = alert.username?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedUsername.isEmpty {
            return trimmedUsername
        }

        return "Linux.do 有新的动态。"
    }
}
