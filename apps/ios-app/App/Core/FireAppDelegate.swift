import Foundation
import UIKit
import UserNotifications

@main
final class FireAppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
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

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = FireSceneDelegate.self
        return configuration
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
            FireRootCoordinator.dispatch(route)
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
