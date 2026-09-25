import Combine
import UIKit

@MainActor
final class FireRootCoordinator {
    enum ScenePhaseLabel: String {
        case active
        case inactive
        case background
        case unknown
    }

    enum RootKind: Equatable {
        case launch
        case main
    }

    /// How the next onboarding host should behave. Logout forces credential-only entry.
    var pendingOnboardingEntry: FireOnboardingEntry = .coldStart
    /// Keep the authenticated shell mounted while mid-session Google reauth runs,
    /// even if Rust has already cleared the local session snapshot.
    var isHoldingMainShellForReauth = false
    weak var midSessionReauthOverlay: FireMidSessionReauthOverlayController?

    static weak var activeCoordinator: FireRootCoordinator?

    static func dispatch(_ route: FireAppRoute) {
        if let activeCoordinator {
            activeCoordinator.enqueue(route)
        } else {
            FireNavigationState.shared.pendingRoute = route
        }
    }

    /// Present or push a secondary page above the tab shell (covers tab bar; does not hide it).
    static func presentSecondary(_ viewController: UIViewController, animated: Bool = true) {
        guard let activeCoordinator else {
            assertionFailure("FireRootCoordinator.presentSecondary called before start()")
            return
        }
        activeCoordinator.openSecondaryPage(viewController, animated: animated)
    }

    /// Whether the main tab shell is available for full-screen secondary pages.
    static var canPresentSecondary: Bool {
        activeCoordinator?.hasMainTabShell == true
    }

    var hasMainTabShell: Bool {
        mainTabBarController != nil
    }

    /// Present or push a typed secondary route (topic / profile / badge) above the tab shell.
    static func presentSecondaryRoute(_ route: FireAppRoute, animated: Bool = true) {
        guard let activeCoordinator else {
            assertionFailure("FireRootCoordinator.presentSecondaryRoute called before start()")
            return
        }
        activeCoordinator.openSecondaryRoute(route, animated: animated)
    }

    /// Secondary stack host when one is covering the tab shell; used by nested route presenters.
    static var activeSecondaryNavigationController: UINavigationController? {
        activeCoordinator?.secondaryNavigationController
    }

    /// Present feedback from any scene (settings, shake). Does not require login.
    static func presentFeedback(source: String = "system") {
        activeCoordinator?.presentFeedback(source: source)
    }

    weak var window: UIWindow?
    let navigationState = FireNavigationState.shared
    let viewModel: FireAppViewModel
    let homeFeedStore: FireHomeFeedStore
    let searchStore: FireSearchStore
    let notificationStore: FireNotificationStore
    let chatChannelsStore: FireChatChannelsStore
    let topicDetailStore: FireTopicDetailStore
    let profileViewModel: FireProfileViewModel

    var cancellables = Set<AnyCancellable>()
    var rootKind: RootKind?
    var mainTabBarController: FireMainTabBarController?
    /// App-root secondary page stack (topics, nested drill-down). Covers the tab shell;
    /// does not mutate or hide the tab bar.
    weak var secondaryNavigationController: FireMainNavigationController?
    var lastAuthenticatedState: Bool?
    let selectionFeedback = UISelectionFeedbackGenerator()

    init(window: UIWindow) {
        let vm = FireAppViewModel()
        let homeFeed = FireHomeFeedStore(appViewModel: vm)
        let notifications = FireNotificationStore(appViewModel: vm)
        let topicDetails = FireTopicDetailStore(appViewModel: vm)
        vm.bindHomeFeedStore(homeFeed)
        vm.bindNotificationStore(notifications)
        vm.bindTopicDetailStore(topicDetails)

        self.window = window
        self.viewModel = vm
        self.homeFeedStore = homeFeed
        self.searchStore = FireSearchStore(appViewModel: vm)
        self.notificationStore = notifications
        let chatChannels = FireChatChannelsStore(viewModel: vm)
        vm.bindChatChannelsStore(chatChannels)
        self.chatChannelsStore = chatChannels
        self.topicDetailStore = topicDetails
        self.profileViewModel = FireProfileViewModel(appViewModel: vm)
    }

    func start() {
        guard let window else { return }
        Self.activeCoordinator = self
        FireTheme.applyGlobalAppearances()
        FireUIKitSkeleton.applyThemeDefaults()
        bindState()
        // Environment owns window override + snapshot publish for the whole app.
        _ = FireAppearanceEnvironment.syncFromStorage(window: window, forcePublish: true)
        updateRoot(animated: false)
        window.makeKeyAndVisible()

        homeFeedStore.setSceneActive(false)
        FireAPMManager.shared.setScenePhase(ScenePhaseLabel.inactive.rawValue)
        updateTopLevelAPMRoute()
    }

    func handleIncomingURL(_ url: URL) {
        guard let route = FireRouteParser.parse(url: url) else {
            return
        }
        enqueue(route)
    }

    func handleUserActivity(_ userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return
        }
        handleIncomingURL(url)
    }

    func handleShakeForFeedback() {
        FireFeedbackPresenter.presentFromShake(appViewModel: viewModel)
    }

    func presentFeedback(source: String) {
        FireFeedbackPresenter.present(
            from: nil,
            appViewModel: viewModel,
            source: source
        )
    }

    var currentAuthenticationState: Bool {
        viewModel.session.readiness.canReadAuthenticatedApi
    }

}
