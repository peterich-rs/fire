import SwiftUI

struct FireTabRoot: View {
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
    }
}
