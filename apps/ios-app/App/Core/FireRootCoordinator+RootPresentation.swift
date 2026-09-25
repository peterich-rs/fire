import UIKit

extension FireRootCoordinator {
    func updateRoot(animated: Bool) {
        let nextKind: RootKind = currentAuthenticationState ? .main : .launch
        guard rootKind != nextKind else { return }

        rootKind = nextKind
        let controller: UIViewController
        switch nextKind {
        case .launch:
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

    func makeOnboardingController() -> UIViewController {
        dismissSecondaryStack(animated: false)
        mainTabBarController = nil
        let entry = pendingOnboardingEntry
        // Cold start is the default for a fresh process; consume signedOut after one presentation.
        pendingOnboardingEntry = .coldStart
        let controller = FireOnboardingViewController(viewModel: viewModel, entry: entry)
        // Hosting nav is only for optional drill-down (developer tools). Login itself hides the bar
        // so the page is one continuous canvas, not a chrome strip + content stack.
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.setNavigationBarHidden(true, animated: false)
        return navigationController
    }

    func makeMainTabBarController() -> UIViewController {
        let controller = FireMainTabBarController(
            viewModel: viewModel,
            navigationState: navigationState,
            homeFeedStore: homeFeedStore,
            searchStore: searchStore,
            notificationStore: notificationStore,
            chatChannelsStore: chatChannelsStore,
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
        controller.setChatUnreadCount(chatChannelsStore.totalUnreadBadge)
        mainTabBarController = controller
        return controller
    }

    func openSecondaryPage(
        _ controller: UIViewController,
        animated: Bool,
        diagnostics: String? = nil
    ) {
        guard let tabBarController = mainTabBarController else {
            viewModel.topicRouteLogger()?.warning(
                "root coordinator could not resolve tab shell for secondary page \(diagnostics ?? controller.title ?? String(describing: type(of: controller)))"
            )
            return
        }

        // Prefer push onto the existing secondary stack when already covering the tab shell.
        if let secondaryNavigationController,
           secondaryNavigationController.presentingViewController != nil {
            viewModel.topicRouteLogger()?.info(
                "root coordinator pushing secondary page \(diagnostics ?? String(describing: type(of: controller))) stack_count=\(secondaryNavigationController.viewControllers.count)"
            )
            secondaryNavigationController.pushViewController(controller, animated: animated)
            return
        }

        let secondary = FireMainNavigationController(rootViewController: controller)
        secondary.modalPresentationStyle = .fullScreen
        secondary.allowsInteractiveDismissWhenAtRoot = true
        secondary.onDidDismissCompletely = { [weak self] in
            self?.secondaryNavigationController = nil
        }
        secondaryNavigationController = secondary

        viewModel.topicRouteLogger()?.info(
            "root coordinator presenting secondary stack \(diagnostics ?? String(describing: type(of: controller)))"
        )
        tabBarController.present(secondary, animated: animated)
    }

    func dismissSecondaryStack(animated: Bool) {
        guard let secondaryNavigationController else { return }
        secondaryNavigationController.onDidDismissCompletely = nil
        if secondaryNavigationController.presentingViewController != nil {
            secondaryNavigationController.dismiss(animated: animated)
        }
        self.secondaryNavigationController = nil
    }
}
