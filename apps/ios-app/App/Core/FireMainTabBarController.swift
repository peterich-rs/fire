import UIKit

final class FireMainTabBarController: UITabBarController, UITabBarControllerDelegate {
    var onSelectedTabChanged: ((Int) -> Void)?

    private let navigationState: FireNavigationState
    private let viewModel: FireAppViewModel
    private let homeFeedStore: FireHomeFeedStore
    private let searchStore: FireSearchStore
    private let notificationStore: FireNotificationStore
    private let chatChannelsStore: FireChatChannelsStore
    private let topicDetailStore: FireTopicDetailStore
    private let profileViewModel: FireProfileViewModel

    init(
        viewModel: FireAppViewModel,
        navigationState: FireNavigationState,
        homeFeedStore: FireHomeFeedStore,
        searchStore: FireSearchStore,
        notificationStore: FireNotificationStore,
        chatChannelsStore: FireChatChannelsStore,
        topicDetailStore: FireTopicDetailStore,
        profileViewModel: FireProfileViewModel
    ) {
        self.viewModel = viewModel
        self.navigationState = navigationState
        self.homeFeedStore = homeFeedStore
        self.searchStore = searchStore
        self.notificationStore = notificationStore
        self.chatChannelsStore = chatChannelsStore
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

    func setChatUnreadCount(_ count: Int) {
        guard let chatItem = viewControllers?[safe: 2]?.tabBarItem else {
            return
        }
        chatItem.badgeValue = count > 0 ? String(count) : nil
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
            rootViewController: FireHomeViewController(
                viewModel: viewModel,
                navigationState: navigationState,
                homeFeedStore: homeFeedStore,
                searchStore: searchStore,
                topicDetailStore: topicDetailStore,
                topicRoutePresenter: FireTopicRoutePresenter.appRoot(
                    navigationState: navigationState,
                    logger: viewModel.topicRouteLogger()
                )
            )
        )
        let notifications = makeNavigationController(
            title: "通知",
            systemImage: "bell",
            selectedSystemImage: "bell.fill",
            rootViewController: FireNotificationsViewController(
                viewModel: viewModel,
                navigationState: navigationState,
                notificationStore: notificationStore,
                topicDetailStore: topicDetailStore
            )
        )
        let chat = makeNavigationController(
            title: "聊天",
            systemImage: "bubble.left.and.bubble.right",
            selectedSystemImage: "bubble.left.and.bubble.right.fill",
            rootViewController: FireChatViewController(
                viewModel: viewModel,
                channelsStore: chatChannelsStore
            )
        )
        let profile = makeNavigationController(
            title: "我的",
            systemImage: "person",
            selectedSystemImage: "person.fill",
            rootViewController: FireProfileViewController(
                viewModel: viewModel,
                navigationState: navigationState,
                profileViewModel: profileViewModel,
                topicDetailStore: topicDetailStore
            )
        )
        viewControllers = [home, notifications, chat, profile]
    }

    private func makeNavigationController(
        title: String,
        systemImage: String,
        selectedSystemImage: String,
        rootViewController: UIViewController
    ) -> UINavigationController {
        let navigationController = FireMainNavigationController(rootViewController: rootViewController)
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.tabBarItem = UITabBarItem(
            title: title,
            image: UIImage(systemName: systemImage),
            selectedImage: UIImage(systemName: selectedSystemImage)
        )
        return navigationController
    }

    private func configureAppearance() {
        tabBar.tintColor = FireTheme.uiAccent
        tabBar.unselectedItemTintColor = FireTheme.uiTertiaryInk

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = FireTheme.uiTabBarBackground
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }
}


private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
