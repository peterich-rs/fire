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
        }
        .task(id: isAuthenticated) {
            if isAuthenticated {
                await FireBackgroundNotificationAlertScheduler.requestAuthorizationIfNeeded()
            } else {
                FireBackgroundNotificationAlertScheduler.cancelRefresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if isAuthenticated {
                    Task {
                        await FireBackgroundNotificationAlertScheduler.requestAuthorizationIfNeeded()
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
        .onChange(of: navigationState.pendingDeepLink) { _, deepLink in
            consumeDeepLinkIfReady(deepLink)
        }
        .onChange(of: isAuthenticated) { _, authenticated in
            if authenticated, let deepLink = navigationState.pendingDeepLink {
                consumeDeepLinkIfReady(deepLink)
            }
        }
    }

    private func consumeDeepLinkIfReady(_ deepLink: FireDeepLink?) {
        guard let deepLink, isAuthenticated else { return }
        navigationState.selectedTab = 1
        navigationState.pendingDeepLink = nil

        NotificationCenter.default.post(
            name: .fireNotificationDeepLink,
            object: nil,
            userInfo: [
                "topicId": deepLink.topicId,
                "postNumber": deepLink.postNumber as Any
            ]
        )
    }
}

extension Notification.Name {
    static let fireNotificationDeepLink = Notification.Name("fireNotificationDeepLink")
}
