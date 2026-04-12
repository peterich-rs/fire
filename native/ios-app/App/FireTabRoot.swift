import SwiftUI

struct FireTabRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var navigationState: FireNavigationState
    @StateObject private var viewModel = FireAppViewModel()
    @StateObject private var profileViewModel: FireProfileViewModel

    init() {
        let vm = FireAppViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _profileViewModel = StateObject(wrappedValue: FireProfileViewModel(appViewModel: vm))
    }

    private var isAuthenticated: Bool {
        viewModel.session.readiness.canReadAuthenticatedApi
    }

    var body: some View {
        Group {
            if isAuthenticated {
                TabView(selection: $navigationState.selectedTab) {
                    FireHomeView(viewModel: viewModel)
                        .tabItem {
                            Label("首页", systemImage: "house")
                        }
                        .tag(0)

                    FireNotificationsView(viewModel: viewModel)
                        .tabItem {
                            Label("通知", systemImage: "bell")
                        }
                        .badge(viewModel.notificationUnreadCount)
                        .tag(1)

                    FireProfileView(viewModel: viewModel, profileViewModel: profileViewModel)
                        .tabItem {
                            Label("我的", systemImage: "person")
                        }
                        .tag(2)
                }
                .tint(FireTheme.accent)
            } else {
                FireOnboardingView(
                    viewModel: viewModel,
                    isBootstrappingSession: viewModel.isBootstrappingSession,
                    isStartupLoadingVisible: viewModel.isStartupLoadingVisible
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isAuthenticated)
        .fullScreenCover(isPresented: $viewModel.isPresentingLogin) {
            FireLoginScreen(viewModel: viewModel)
        }
        .task {
            viewModel.loadInitialState()
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
                FireBackgroundNotificationAlertScheduler.cancelRefresh()
            }
            viewModel.updateTopLevelAPMRoute(
                selectedTab: navigationState.selectedTab,
                isAuthenticated: isAuthenticated
            )
        }
        .onChange(of: scenePhase) { _, phase in
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
            viewModel.updateTopLevelAPMRoute(
                selectedTab: navigationState.selectedTab,
                isAuthenticated: authenticated
            )
            if authenticated, let route = navigationState.pendingRoute {
                selectTabForPendingRouteIfReady(route)
            }
        }
    }

    private func selectTabForPendingRouteIfReady(_ route: FireAppRoute?) {
        guard route != nil, isAuthenticated else { return }
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
