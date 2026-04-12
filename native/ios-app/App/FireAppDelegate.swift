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
        Task { @MainActor in
            await FirePushRegistrationCoordinator.shared.refreshAuthorizationStatus()
        }
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
        guard let route = FireRouteParser.route(fromNotificationUserInfo: userInfo) else {
            return
        }

        await MainActor.run {
            FireNavigationState.shared.pendingRoute = route
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            FirePushRegistrationCoordinator.shared.handleRegisteredDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            FirePushRegistrationCoordinator.shared.handleRegistrationFailure(error)
        }
    }
}
