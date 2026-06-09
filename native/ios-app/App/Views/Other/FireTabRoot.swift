import SwiftUI

struct FireTabRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var navigationState: FireNavigationState
    @StateObject private var viewModel = FireAppViewModel()
    @StateObject private var homeFeedStore: FireHomeFeedStore
    @StateObject private var searchStore: FireSearchStore
    @StateObject private var notificationStore: FireNotificationStore
    @StateObject private var topicDetailStore: FireTopicDetailStore
    @StateObject private var profileViewModel: FireProfileViewModel
    @AppStorage(FireTheme.appearancePreferenceStorageKey) private var appearancePreferenceRawValue = FireAppearancePreference.system.rawValue
    @State private var preheatComplete = false
    @State private var tabSelectionFeedbackPulse: Int = 0

    init() {
        let vm = FireAppViewModel()
        let homeFeed = FireHomeFeedStore(appViewModel: vm)
        let notifications = FireNotificationStore(appViewModel: vm)
        let topicDetails = FireTopicDetailStore(appViewModel: vm)
        vm.bindHomeFeedStore(homeFeed)
        vm.bindNotificationStore(notifications)
        vm.bindTopicDetailStore(topicDetails)
        _viewModel = StateObject(wrappedValue: vm)
        _homeFeedStore = StateObject(wrappedValue: homeFeed)
        _searchStore = StateObject(wrappedValue: FireSearchStore(appViewModel: vm))
        _notificationStore = StateObject(wrappedValue: notifications)
        _topicDetailStore = StateObject(wrappedValue: topicDetails)
        _profileViewModel = StateObject(wrappedValue: FireProfileViewModel(appViewModel: vm))
    }

    private var isAuthenticated: Bool {
        viewModel.session.readiness.canReadAuthenticatedApi
    }

    var body: some View {
        Group {
            if !preheatComplete {
                FirePreheatGateRepresentable(sessionStore: viewModel.currentSessionStore())
            } else if isAuthenticated {
                TabView(selection: $navigationState.selectedTab) {
                    FireHomeView(viewModel: viewModel, searchStore: searchStore)
                        .tabItem {
                            Label("首页", systemImage: "house")
                        }
                        .tag(0)

                    FireNotificationsView(
                        appViewModel: viewModel,
                        notificationStore: notificationStore,
                        isActive: navigationState.selectedTab == 1
                    )
                    .tabItem {
                        Label("通知", systemImage: "bell")
                    }
                    .badge(notificationStore.unreadCount)
                    .tag(1)

                    FireProfileView(
                        viewModel: viewModel,
                        profileViewModel: profileViewModel,
                        isActive: navigationState.selectedTab == 2
                    )
                    .tabItem {
                        Label("我的", systemImage: "person")
                    }
                    .tag(2)
                }
                .tint(FireTheme.accent)
                .toolbar(.visible, for: .tabBar)
                .toolbarBackground(FireTheme.tabBarBackground, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .environmentObject(homeFeedStore)
                .environmentObject(topicDetailStore)
                .fireTopicRoutePresenter(.appRoot(navigationState: navigationState))
                .fireSelectionFeedback(trigger: tabSelectionFeedbackPulse)
            } else {
                FireOnboardingView(
                    viewModel: viewModel,
                    isBootstrappingSession: viewModel.isBootstrappingSession,
                    isStartupLoadingVisible: viewModel.isStartupLoadingVisible
                )
            }
        }
        .fireRespectingReduceMotion { content, reduceMotion in
            content.animation(
                FireMotionTokens.animation(for: .standard, reduceMotion: reduceMotion),
                value: isAuthenticated
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .firePreheatGateDidComplete)) { _ in
            Task { @MainActor in
                await viewModel.completeStartupAfterPreheat()
                preheatComplete = true
            }
        }
        .fullScreenCover(item: $viewModel.authPresentationState) { presentationState in
            FireAuthScreen(
                viewModel: viewModel,
                presentationState: presentationState
            )
        }
        .fullScreenCover(item: $navigationState.presentedTopicRoute) { route in
            FirePresentedTopicRouteHost(viewModel: viewModel, route: route)
            .environmentObject(topicDetailStore)
        }
        .task {
            viewModel.loadInitialState()
            homeFeedStore.setSceneActive(scenePhase == .active)
            viewModel.updateTopLevelAPMRoute(
                selectedTab: navigationState.selectedTab,
                isAuthenticated: isAuthenticated
            )
            FireAPMManager.shared.setScenePhase(scenePhaseLabel(scenePhase))
        }
        .task(id: isAuthenticated) {
            if isAuthenticated {
                await FirePushRegistrationCoordinator.shared.ensurePushRegistration()
                selectTabForPendingRouteIfReady(navigationState.pendingRoute)
            } else {
                navigationState.dismissPresentedTopicRoute()
                FireBackgroundNotificationAlertScheduler.cancelRefresh()
            }
            viewModel.updateTopLevelAPMRoute(
                selectedTab: navigationState.selectedTab,
                isAuthenticated: isAuthenticated
            )
        }
        .onChange(of: scenePhase) { _, phase in
            homeFeedStore.setSceneActive(phase == .active)
            FireAPMManager.shared.setScenePhase(scenePhaseLabel(phase))
            viewModel.handleDiagnosticsScenePhaseChange(
                scenePhaseLabel(phase),
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
            case .background:
                if isAuthenticated {
                    FireBackgroundNotificationAlertScheduler.scheduleRefresh()
                } else {
                    FireBackgroundNotificationAlertScheduler.cancelRefresh()
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onChange(of: navigationState.selectedTab) { _, _ in
            tabSelectionFeedbackPulse += 1
        }
        .onChange(of: navigationState.pendingRoute) { _, route in
            selectTabForPendingRouteIfReady(route)
        }
        .onChange(of: navigationState.selectedTab) { _, selectedTab in
            viewModel.updateTopLevelAPMRoute(
                selectedTab: selectedTab,
                isAuthenticated: isAuthenticated
            )
        }
        .onChange(of: isAuthenticated) { _, authenticated in
            if !authenticated {
                homeFeedStore.reset()
                searchStore.reset()
                notificationStore.reset()
                topicDetailStore.reset()
                FireMotionCelebrationGate.reset()
                navigationState.dismissPresentedTopicRoute()
            }
            viewModel.updateTopLevelAPMRoute(
                selectedTab: navigationState.selectedTab,
                isAuthenticated: authenticated
            )
            if authenticated, let route = navigationState.pendingRoute {
                selectTabForPendingRouteIfReady(route)
            }
        }
        .preferredColorScheme(appearancePreference.colorScheme)
    }

    private var appearancePreference: FireAppearancePreference {
        FireAppearancePreference(rawValue: appearancePreferenceRawValue) ?? .system
    }

    private func selectTabForPendingRouteIfReady(_ route: FireAppRoute?) {
        guard let route, isAuthenticated else { return }
        if route.isTopicRoute {
            navigationState.presentTopicRoute(route)
            navigationState.pendingRoute = nil
            return
        }
        navigationState.selectedTab = 0
    }

    private func scenePhaseLabel(_ phase: ScenePhase) -> String {
        switch phase {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .background:
            return "background"
        @unknown default:
            return "unknown"
        }
    }
}

struct FirePreheatGateRepresentable: UIViewControllerRepresentable {
    let sessionStore: FireSessionStore?

    func makeUIViewController(context: Context) -> FirePreheatGateWaitingViewController {
        if let store = sessionStore {
            return FirePreheatGateWaitingViewController(sessionStore: store)
        }
        return FirePreheatGateWaitingViewController(sessionStore: nil)
    }

    func updateUIViewController(_ uiViewController: FirePreheatGateWaitingViewController, context: Context) {
        if let store = sessionStore, uiViewController.sessionStore == nil {
            uiViewController.configure(with: store)
        }
    }
}

final class FirePreheatGateWaitingViewController: UIViewController {
    private(set) var sessionStore: FireSessionStore?
    private var gateViewController: FirePreheatGateViewController?
    private let statusView = FireStartupOnboardingStatusView()

    init(sessionStore: FireSessionStore?) {
        self.sessionStore = sessionStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FireStartupOnboardingPalette.background

        statusView.translatesAutoresizingMaskIntoConstraints = false
        statusView.showLoading("正在准备登录态…")
        view.addSubview(statusView)
        NSLayoutConstraint.activate([
            statusView.topAnchor.constraint(equalTo: view.topAnchor),
            statusView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        if let store = sessionStore {
            installGate(with: store)
        }
    }

    func configure(with store: FireSessionStore) {
        sessionStore = store
        if isViewLoaded {
            installGate(with: store)
        }
    }

    private func installGate(with store: FireSessionStore) {
        guard gateViewController == nil else { return }
        statusView.removeFromSuperview()
        let gate = FirePreheatGateViewController(sessionStore: store)
        gateViewController = gate
        addChild(gate)
        view.addSubview(gate.view)
        gate.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            gate.view.topAnchor.constraint(equalTo: view.topAnchor),
            gate.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gate.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gate.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        gate.didMove(toParent: self)
    }
}
