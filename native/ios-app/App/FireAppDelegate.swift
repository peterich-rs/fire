import Foundation
import UIKit
import UserNotifications

final class FireAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FireAPMManager.shared.start()
        UNUserNotificationCenter.current().delegate = self
        FireBackgroundNotificationAlertScheduler.registerBackgroundTask()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let topicId = extractUInt64(from: userInfo, key: "topicId") else {
            return
        }
        let postNumber = extractUInt32(from: userInfo, key: "postNumber")

        await MainActor.run {
            FireNavigationState.shared.pendingDeepLink = FireDeepLink(
                topicId: topicId,
                postNumber: postNumber
            )
        }
    }

    private func extractUInt64(from userInfo: [AnyHashable: Any], key: String) -> UInt64? {
        if let value = userInfo[key] as? UInt64 { return value }
        if let value = userInfo[key] as? Int64 { return UInt64(value) }
        if let value = userInfo[key] as? Int { return UInt64(value) }
        if let value = userInfo[key] as? NSNumber { return value.uint64Value }
        return nil
    }

    private func extractUInt32(from userInfo: [AnyHashable: Any], key: String) -> UInt32? {
        if let value = userInfo[key] as? UInt32 { return value }
        if let value = userInfo[key] as? Int { return UInt32(value) }
        if let value = userInfo[key] as? NSNumber { return value.uint32Value }
        return nil
    }
}
