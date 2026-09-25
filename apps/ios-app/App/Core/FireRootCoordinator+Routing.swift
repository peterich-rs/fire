import UIKit

extension FireRootCoordinator {
    func enqueue(_ route: FireAppRoute) {
        viewModel.topicRouteLogger()?.info("root coordinator enqueued route \(route.diagnosticsSummary)")
        navigationState.pendingRoute = route
        handlePendingRouteIfReady(route)
    }

    func handleTopicRouteRequest(_ route: FireAppRoute?) {
        guard let route else { return }
        openSecondaryRoute(route, animated: true)
        navigationState.dismissPresentedTopicRoute()
    }

    func openSecondaryRoute(_ route: FireAppRoute, animated: Bool) {
        guard route.presentsAsSecondaryPage else {
            viewModel.topicRouteLogger()?.debug(
                "root coordinator ignored non-secondary route \(route.diagnosticsSummary)"
            )
            return
        }

        let topicRoutePresenter = FireAppRouteControllerFactory.makeTopicRoutePresenter(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            navigationControllerProvider: { [weak self] in self?.secondaryNavigationController }
        )
        let controller = FireAppRouteControllerFactory.makeViewController(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            route: route,
            topicRoutePresenter: topicRoutePresenter
        )
        openSecondaryPage(controller, animated: animated, diagnostics: route.diagnosticsSummary)
    }

    func handlePendingRouteIfReady(_ route: FireAppRoute?) {
        guard let route, currentAuthenticationState else { return }
        switch route {
        case .topic:
            navigationState.presentTopicRoute(route)
            navigationState.pendingRoute = nil
        case .notifications:
            navigationState.selectedTab = 1
            navigationState.pendingRoute = nil
        case .profileTab:
            // Tabs: 0 home, 1 notifications, 2 chat, 3 profile
            navigationState.selectedTab = 3
            navigationState.pendingRoute = nil
        case .search(let query):
            navigationState.pendingSearchQuery = query ?? ""
            navigationState.selectedTab = 0
            navigationState.pendingRoute = nil
        case .profile, .badge:
            openSecondaryRoute(route, animated: true)
            navigationState.pendingRoute = nil
        }
    }
}
