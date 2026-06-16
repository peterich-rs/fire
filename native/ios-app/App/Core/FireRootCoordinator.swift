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

    private enum RootKind: Equatable {
        case preheat
        case onboarding
        case main
    }

    private static weak var activeCoordinator: FireRootCoordinator?

    static func dispatch(_ route: FireAppRoute) {
        if let activeCoordinator {
            activeCoordinator.enqueue(route)
        } else {
            FireNavigationState.shared.pendingRoute = route
        }
    }

    private weak var window: UIWindow?
    private let navigationState = FireNavigationState.shared
    private let viewModel: FireAppViewModel
    private let homeFeedStore: FireHomeFeedStore
    private let searchStore: FireSearchStore
    private let notificationStore: FireNotificationStore
    private let topicDetailStore: FireTopicDetailStore
    private let profileViewModel: FireProfileViewModel

    private var cancellables = Set<AnyCancellable>()
    private var rootKind: RootKind?
    private var preheatComplete = false
    private weak var preheatController: FirePreheatGateWaitingViewController?
    private var preheatSessionStoreTask: Task<Void, Never>?
    private var mainTabBarController: FireMainTabBarController?
    private weak var authController: UIViewController?
    private weak var topicNavigationController: UINavigationController?
    private var lastAuthenticatedState: Bool?
    private let selectionFeedback = UISelectionFeedbackGenerator()

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
        self.topicDetailStore = topicDetails
        self.profileViewModel = FireProfileViewModel(appViewModel: vm)
    }

    deinit {
        preheatSessionStoreTask?.cancel()
    }

    func start() {
        guard let window else { return }
        Self.activeCoordinator = self
        bindState()
        updatePreferredAppearance()
        updateRoot(animated: false)
        window.makeKeyAndVisible()

        viewModel.loadInitialState()
        homeFeedStore.setSceneActive(false)
        FireAPMManager.shared.setScenePhase(ScenePhaseLabel.inactive.rawValue)
        updateTopLevelAPMRoute()
        preparePreheatSessionStoreIfNeeded()
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

    func handleScenePhaseChange(_ phase: ScenePhaseLabel) {
        if phase == .active {
            Self.activeCoordinator = self
        }

        let isAuthenticated = currentAuthenticationState
        homeFeedStore.setSceneActive(phase == .active)
        FireAPMManager.shared.setScenePhase(phase.rawValue)
        viewModel.handleDiagnosticsScenePhaseChange(
            phase.rawValue,
            isAuthenticated: isAuthenticated
        )

        switch phase {
        case .active:
            if isAuthenticated {
                Task {
                    await FirePushRegistrationCoordinator.shared.refreshAuthorizationStatus()
                    await FirePushRegistrationCoordinator.shared.ensurePushRegistration()
                }
            }
            handlePendingRouteIfReady(navigationState.pendingRoute)
        case .background:
            if isAuthenticated {
                FireBackgroundNotificationAlertScheduler.scheduleRefresh()
            } else {
                FireBackgroundNotificationAlertScheduler.cancelRefresh()
            }
        case .inactive, .unknown:
            break
        }
    }

    private var currentAuthenticationState: Bool {
        viewModel.session.readiness.canReadAuthenticatedApi
    }

    private func bindState() {
        viewModel.$session
            .map { $0.readiness.canReadAuthenticatedApi }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isAuthenticated in
                self?.handleAuthenticationChange(isAuthenticated)
            }
            .store(in: &cancellables)

        viewModel.$authPresentationState
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.syncAuthPresentation(state)
            }
            .store(in: &cancellables)

        navigationState.$pendingRoute
            .receive(on: RunLoop.main)
            .sink { [weak self] route in
                self?.handlePendingRouteIfReady(route)
            }
            .store(in: &cancellables)

        navigationState.$presentedTopicRoute
            .receive(on: RunLoop.main)
            .sink { [weak self] route in
                self?.syncTopicPresentation(route)
            }
            .store(in: &cancellables)

        navigationState.$selectedTab
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] selectedTab in
                guard let self else { return }
                self.mainTabBarController?.setSelectedTab(selectedTab)
                self.updateTopLevelAPMRoute()
            }
            .store(in: &cancellables)

        notificationStore.$unreadCount
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] unreadCount in
                self?.mainTabBarController?.setUnreadCount(unreadCount)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updatePreferredAppearance()
            }
            .store(in: &cancellables)
    }

    private func enqueue(_ route: FireAppRoute) {
        viewModel.topicRouteLogger()?.info("root coordinator enqueued route \(route.diagnosticsSummary)")
        navigationState.pendingRoute = route
        handlePendingRouteIfReady(route)
    }

    private func handleAuthenticationChange(_ isAuthenticated: Bool) {
        let previous = lastAuthenticatedState
        lastAuthenticatedState = isAuthenticated

        if previous == true, !isAuthenticated {
            homeFeedStore.reset()
            searchStore.reset()
            notificationStore.reset()
            topicDetailStore.reset()
            FireMotionCelebrationGate.reset()
            navigationState.dismissPresentedTopicRoute()
            FireBackgroundNotificationAlertScheduler.cancelRefresh()
        }

        updateRoot(animated: previous != nil)
        updateTopLevelAPMRoute()

        if isAuthenticated {
            Task {
                await FirePushRegistrationCoordinator.shared.ensurePushRegistration()
            }
            handlePendingRouteIfReady(navigationState.pendingRoute)
        }
    }

    private func updateRoot(animated: Bool) {
        let nextKind: RootKind = {
            if !preheatComplete {
                return .preheat
            }
            return currentAuthenticationState ? .main : .onboarding
        }()

        guard rootKind != nextKind else {
            if nextKind == .preheat {
                preparePreheatSessionStoreIfNeeded()
            }
            return
        }

        rootKind = nextKind
        let controller: UIViewController
        switch nextKind {
        case .preheat:
            controller = makePreheatController()
        case .onboarding:
            controller = makeOnboardingController()
        case .main:
            controller = makeMainTabBarController()
        }

        guard let window else { return }
        guard animated, window.rootViewController != nil else {
            window.rootViewController = controller
            return
        }

        UIView.transition(
            with: window,
            duration: 0.22,
            options: [.transitionCrossDissolve, .allowAnimatedContent],
            animations: {
                window.rootViewController = controller
            }
        )
    }

    private func makePreheatController() -> UIViewController {
        let controller = FirePreheatGateWaitingViewController(
            sessionStore: viewModel.currentSessionStore(),
            onComplete: { [weak self] in
                self?.completePreheat()
            },
            onRequestLogin: { [weak self] message in
                self?.requestLoginAfterPreheatFailure(message: message)
            }
        )
        preheatController = controller
        preparePreheatSessionStoreIfNeeded()
        return controller
    }

    private func makeOnboardingController() -> UIViewController {
        mainTabBarController = nil
        let controller = FireOnboardingViewController(viewModel: viewModel)
        return UINavigationController(rootViewController: controller)
    }

    private func makeMainTabBarController() -> UIViewController {
        let controller = FireMainTabBarController(
            viewModel: viewModel,
            navigationState: navigationState,
            homeFeedStore: homeFeedStore,
            searchStore: searchStore,
            notificationStore: notificationStore,
            topicDetailStore: topicDetailStore,
            profileViewModel: profileViewModel
        )
        controller.onSelectedTabChanged = { [weak self] selectedTab in
            guard let self else { return }
            self.selectionFeedback.selectionChanged()
            if self.navigationState.selectedTab != selectedTab {
                self.navigationState.selectedTab = selectedTab
            }
            self.updateTopLevelAPMRoute()
            self.handlePendingRouteIfReady(self.navigationState.pendingRoute)
        }
        controller.setSelectedTab(navigationState.selectedTab)
        controller.setUnreadCount(notificationStore.unreadCount)
        mainTabBarController = controller
        return controller
    }

    private func preparePreheatSessionStoreIfNeeded() {
        guard !preheatComplete else { return }
        guard let preheatController else { return }
        if let sessionStore = viewModel.currentSessionStore() {
            preheatController.configure(with: sessionStore)
            return
        }
        guard preheatSessionStoreTask == nil else { return }

        preheatSessionStoreTask = Task { [weak self] in
            guard let self else { return }
            do {
                let sessionStore = try await self.viewModel.sessionStoreValue()
                guard !Task.isCancelled else { return }
                self.preheatController?.configure(with: sessionStore)
            } catch {
                guard !Task.isCancelled else { return }
                self.viewModel.completeStartupAfterPreheatFailure(message: error.localizedDescription)
                self.preheatComplete = true
                self.updateRoot(animated: true)
            }
            self.preheatSessionStoreTask = nil
        }
    }

    private func completePreheat() {
        Task { [weak self] in
            guard let self else { return }
            await self.viewModel.completeStartupAfterPreheat()
            self.preheatComplete = true
            self.updateRoot(animated: true)
            self.handlePendingRouteIfReady(self.navigationState.pendingRoute)
        }
    }

    private func requestLoginAfterPreheatFailure(message: String?) {
        viewModel.completeStartupAfterPreheatFailure(message: message)
        preheatComplete = true
        updateRoot(animated: true)
        viewModel.openLogin()
    }

    private func syncAuthPresentation(_ state: FireAuthPresentationState?) {
        if state != nil {
            guard authController == nil else { return }
            let controller = FireLoginViewController(viewModel: viewModel)
            let navigationController = UINavigationController(rootViewController: controller)
            navigationController.modalPresentationStyle = .fullScreen
            presentationAnchor()?.present(navigationController, animated: true)
            authController = navigationController
            return
        }

        guard let authController else {
            syncTopicPresentation(navigationState.presentedTopicRoute)
            return
        }
        authController.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.authController = nil
            self.syncTopicPresentation(self.navigationState.presentedTopicRoute)
            self.handlePendingRouteIfReady(self.navigationState.pendingRoute)
        }
    }

    private func syncTopicPresentation(_ route: FireAppRoute?) {
        guard authController == nil else { return }

        if let route {
            guard topicNavigationController == nil else { return }
            viewModel.topicRouteLogger()?.info("root coordinator presenting topic route \(route.diagnosticsSummary)")
            let navigationController = FireAppRouteControllerFactory.makeNavigationController(
                viewModel: viewModel,
                topicDetailStore: topicDetailStore,
                route: route,
                onDismiss: { [weak self] in
                    self?.topicPresentationDidDismiss()
                }
            )
            navigationController.modalPresentationStyle = .fullScreen
            presentationAnchor()?.present(navigationController, animated: true)
            topicNavigationController = navigationController
            return
        }

        guard let topicNavigationController else { return }
        topicNavigationController.dismiss(animated: true)
        self.topicNavigationController = nil
    }

    private func topicPresentationDidDismiss() {
        viewModel.topicRouteLogger()?.info(
            "root coordinator topic route dismissed current_presented_route_id=\(navigationState.presentedTopicRoute?.id ?? "nil")"
        )
        topicNavigationController = nil
        if navigationState.presentedTopicRoute != nil {
            navigationState.dismissPresentedTopicRoute()
        }
        updateTopLevelAPMRoute()
    }

    private func handlePendingRouteIfReady(_ route: FireAppRoute?) {
        guard let route, currentAuthenticationState else { return }
        switch route {
        case .topic:
            navigationState.presentTopicRoute(route)
            navigationState.pendingRoute = nil
        case .notifications:
            navigationState.selectedTab = 1
            navigationState.pendingRoute = nil
        case .profileTab:
            navigationState.selectedTab = 2
            navigationState.pendingRoute = nil
        case .search(let query):
            navigationState.pendingSearchQuery = query ?? ""
            navigationState.selectedTab = 0
            navigationState.pendingRoute = nil
        case .profile, .badge:
            navigationState.selectedTab = 0
        }
    }

    private func updateTopLevelAPMRoute() {
        viewModel.updateTopLevelAPMRoute(
            selectedTab: navigationState.selectedTab,
            isAuthenticated: currentAuthenticationState
        )
    }

    private func updatePreferredAppearance() {
        let rawValue = UserDefaults.standard.string(forKey: FireTheme.appearancePreferenceStorageKey) ?? ""
        let preference = FireAppearancePreference(rawValue: rawValue) ?? .system
        switch preference {
        case .system:
            window?.overrideUserInterfaceStyle = .unspecified
        case .light:
            window?.overrideUserInterfaceStyle = .light
        case .dark, .oled:
            window?.overrideUserInterfaceStyle = .dark
        }
    }

    private func presentationAnchor() -> UIViewController? {
        window?.rootViewController?.fireTopPresentedViewController
    }
}

private extension UIViewController {
    var fireTopPresentedViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.fireTopPresentedViewController
        }
        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return visibleViewController.fireTopPresentedViewController
        }
        if let tabBarController = self as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return selectedViewController.fireTopPresentedViewController
        }
        return self
    }
}
