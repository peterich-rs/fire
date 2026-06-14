import SwiftUI
import UIKit

final class FireMainTabBarController: UITabBarController, UITabBarControllerDelegate {
    var onSelectedTabChanged: ((Int) -> Void)?

    private let navigationState: FireNavigationState
    private let viewModel: FireAppViewModel
    private let homeFeedStore: FireHomeFeedStore
    private let searchStore: FireSearchStore
    private let notificationStore: FireNotificationStore
    private let topicDetailStore: FireTopicDetailStore
    private let profileViewModel: FireProfileViewModel

    init(
        viewModel: FireAppViewModel,
        navigationState: FireNavigationState,
        homeFeedStore: FireHomeFeedStore,
        searchStore: FireSearchStore,
        notificationStore: FireNotificationStore,
        topicDetailStore: FireTopicDetailStore,
        profileViewModel: FireProfileViewModel
    ) {
        self.viewModel = viewModel
        self.navigationState = navigationState
        self.homeFeedStore = homeFeedStore
        self.searchStore = searchStore
        self.notificationStore = notificationStore
        self.topicDetailStore = topicDetailStore
        self.profileViewModel = profileViewModel
        super.init(nibName: nil, bundle: nil)
        delegate = self
        configureAppearance()
        configureTabs()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setSelectedTab(_ index: Int) {
        guard let controllers = viewControllers,
              controllers.indices.contains(index),
              selectedIndex != index else {
            return
        }
        selectedIndex = index
    }

    func setUnreadCount(_ count: Int) {
        guard let notificationsItem = viewControllers?[safe: 1]?.tabBarItem else {
            return
        }
        notificationsItem.badgeValue = count > 0 ? String(count) : nil
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard let index = viewControllers?.firstIndex(of: viewController) else {
            return
        }
        onSelectedTabChanged?(index)
    }

    private func configureTabs() {
        let home = makeNavigationController(
            title: "首页",
            systemImage: "house",
            selectedSystemImage: "house.fill",
            rootView: AnyView(
                FireHomeTabRootHost(
                    viewModel: viewModel,
                    navigationState: navigationState,
                    homeFeedStore: homeFeedStore,
                    searchStore: searchStore,
                    topicDetailStore: topicDetailStore
                )
            )
        )
        let notifications = makeNavigationController(
            title: "通知",
            systemImage: "bell",
            selectedSystemImage: "bell.fill",
            rootView: AnyView(
                FireNotificationsTabRootHost(
                    viewModel: viewModel,
                    navigationState: navigationState,
                    notificationStore: notificationStore,
                    topicDetailStore: topicDetailStore
                )
            )
        )
        let profile = makeNavigationController(
            title: "我的",
            systemImage: "person",
            selectedSystemImage: "person.fill",
            rootView: AnyView(
                FireProfileTabRootHost(
                    viewModel: viewModel,
                    navigationState: navigationState,
                    profileViewModel: profileViewModel,
                    topicDetailStore: topicDetailStore
                )
            )
        )
        viewControllers = [home, notifications, profile]
    }

    private func makeNavigationController(
        title: String,
        systemImage: String,
        selectedSystemImage: String,
        rootView: AnyView
    ) -> UINavigationController {
        let host = UIHostingController(rootView: rootView)
        host.view.backgroundColor = .systemBackground
        let navigationController = UINavigationController(rootViewController: host)
        navigationController.setNavigationBarHidden(true, animated: false)
        navigationController.tabBarItem = UITabBarItem(
            title: title,
            image: UIImage(systemName: systemImage),
            selectedImage: UIImage(systemName: selectedSystemImage)
        )
        return navigationController
    }

    private func configureAppearance() {
        tabBar.tintColor = UIColor(red: 0.91, green: 0.39, blue: 0.18, alpha: 1)
        tabBar.unselectedItemTintColor = .secondaryLabel

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 0.94)
                : UIColor(red: 0.97, green: 0.96, blue: 0.95, alpha: 0.94)
        }
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }
}

private struct FireHomeTabRootHost: View {
    let viewModel: FireAppViewModel
    @ObservedObject var navigationState: FireNavigationState
    @ObservedObject var homeFeedStore: FireHomeFeedStore
    let searchStore: FireSearchStore
    @ObservedObject var topicDetailStore: FireTopicDetailStore

    var body: some View {
        FireHomeView(viewModel: viewModel, searchStore: searchStore)
            .environmentObject(navigationState)
            .environmentObject(homeFeedStore)
            .environmentObject(topicDetailStore)
            .fireTopicRoutePresenter(topicRoutePresenter)
    }

    private var topicRoutePresenter: FireTopicRoutePresenter {
        FireTopicRoutePresenter { route in
            guard route.isTopicRoute else {
                viewModel.topicRouteLogger()?.debug(
                    "tab host topic presenter ignored non-topic route \(route.diagnosticsSummary)"
                )
                return false
            }
            viewModel.topicRouteLogger()?.info("tab host presenting topic route \(route.diagnosticsSummary)")
            navigationState.presentTopicRoute(route)
            return true
        }
    }
}

private struct FireNotificationsTabRootHost: View {
    let viewModel: FireAppViewModel
    @ObservedObject var navigationState: FireNavigationState
    @ObservedObject var notificationStore: FireNotificationStore
    @ObservedObject var topicDetailStore: FireTopicDetailStore

    var body: some View {
        FireNotificationsView(
            appViewModel: viewModel,
            notificationStore: notificationStore,
            isActive: navigationState.selectedTab == 1
        )
        .environmentObject(navigationState)
        .environmentObject(topicDetailStore)
        .fireTopicRoutePresenter(topicRoutePresenter)
    }

    private var topicRoutePresenter: FireTopicRoutePresenter {
        FireTopicRoutePresenter { route in
            guard route.isTopicRoute else {
                viewModel.topicRouteLogger()?.debug(
                    "notifications tab topic presenter ignored non-topic route \(route.diagnosticsSummary)"
                )
                return false
            }
            viewModel.topicRouteLogger()?.info("notifications tab presenting topic route \(route.diagnosticsSummary)")
            navigationState.presentTopicRoute(route)
            return true
        }
    }
}

private struct FireProfileTabRootHost: View {
    let viewModel: FireAppViewModel
    @ObservedObject var navigationState: FireNavigationState
    @ObservedObject var profileViewModel: FireProfileViewModel
    @ObservedObject var topicDetailStore: FireTopicDetailStore

    var body: some View {
        FireProfileView(
            viewModel: viewModel,
            profileViewModel: profileViewModel,
            isActive: navigationState.selectedTab == 2
        )
        .environmentObject(navigationState)
        .environmentObject(topicDetailStore)
        .fireTopicRoutePresenter(topicRoutePresenter)
    }

    private var topicRoutePresenter: FireTopicRoutePresenter {
        FireTopicRoutePresenter { route in
            guard route.isTopicRoute else {
                viewModel.topicRouteLogger()?.debug(
                    "profile tab topic presenter ignored non-topic route \(route.diagnosticsSummary)"
                )
                return false
            }
            viewModel.topicRouteLogger()?.info("profile tab presenting topic route \(route.diagnosticsSummary)")
            navigationState.presentTopicRoute(route)
            return true
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
