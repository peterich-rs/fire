import UIKit

final class FireSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private var rootCoordinator: FireRootCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        let coordinator = FireRootCoordinator(window: window)
        self.window = window
        self.rootCoordinator = coordinator
        coordinator.start()

        if let url = connectionOptions.urlContexts.first?.url {
            coordinator.handleIncomingURL(url)
        }
        if let userActivity = connectionOptions.userActivities.first(where: {
            $0.activityType == NSUserActivityTypeBrowsingWeb
        }) {
            coordinator.handleUserActivity(userActivity)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            rootCoordinator?.handleIncomingURL(context.url)
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        rootCoordinator?.handleUserActivity(userActivity)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        rootCoordinator?.handleScenePhaseChange(.active)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        rootCoordinator?.handleScenePhaseChange(.inactive)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        rootCoordinator?.handleScenePhaseChange(.background)
    }
}
