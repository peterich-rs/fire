import SwiftUI

struct FireTabRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = FireAppViewModel()

    private var isAuthenticated: Bool {
        viewModel.session.readiness.canReadAuthenticatedApi
    }

    var body: some View {
        Group {
            if isAuthenticated {
                TabView {
                    FireHomeView(viewModel: viewModel)
                        .tabItem {
                            Label("首页", systemImage: "house")
                        }

                    FireNotificationsView(viewModel: viewModel)
                        .tabItem {
                            Label("通知", systemImage: "bell")
                        }
                        .badge(viewModel.notificationUnreadCount)

                    FireProfileView(viewModel: viewModel)
                        .tabItem {
                            Label("我的", systemImage: "person")
                        }
                }
                .tint(FireTheme.accent)
            } else {
                FireOnboardingView(viewModel: viewModel)
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
    }
}
