import SwiftUI
import UIKit

@MainActor
enum FireAppRouteControllerFactory {
    static func makeViewController(
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore,
        route: FireAppRoute,
        topicRoutePresenter: FireTopicRoutePresenter = .local
    ) -> UIViewController {
        viewModel.topicRouteLogger()?.debug("route factory make view controller \(route.diagnosticsSummary)")
        switch route {
        case .topic(let payload):
            viewModel.topicDetailLogger()?.info(
                "route factory make topic detail controller topic_id=\(payload.topicId) post_number=\(payload.postNumber.map(String.init) ?? "nil") has_preview=\(payload.preview != nil)"
            )
            return FireTopicDetailViewController(
                viewModel: viewModel,
                topicDetailStore: topicDetailStore,
                row: payload.row,
                scrollToPostNumber: payload.postNumber
            )
        case .profile(let username):
            return FirePublicProfileViewController(
                viewModel: viewModel,
                username: username,
                topicDetailStore: topicDetailStore,
                topicRoutePresenter: topicRoutePresenter
            )
        case .profileTab, .notifications, .search:
            // Non-secondary tab routes should never be materialised as pages.
            assertionFailure("attempted to build secondary host for non-secondary route \(route.diagnosticsSummary)")
            return FireHosting.controller(rootView: EmptyView())
        case .badge(let badgeID, _):
            return FireHosting.controller(
                rootView: FireBadgeDetailView(
                    viewModel: viewModel,
                    badgeID: badgeID
                )
                .fireTopicRoutePresenter(topicRoutePresenter)
            )
        }
    }

    static func makeTopicRoutePresenter(
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore,
        navigationControllerProvider: @escaping @MainActor () -> UINavigationController?
    ) -> FireTopicRoutePresenter {
        FireTopicRoutePresenter { route in
            guard route.isTopicRoute,
                  let navigationController = navigationControllerProvider() else {
                viewModel.topicRouteLogger()?.debug(
                    "nested topic route presenter ignored route navigation_controller_available=\(navigationControllerProvider() != nil) \(route.diagnosticsSummary)"
                )
                return false
            }
            viewModel.topicRouteLogger()?.info(
                "nested topic route presenter pushing route \(route.diagnosticsSummary) current_stack_count=\(navigationController.viewControllers.count)"
            )
            let controller = makeViewController(
                viewModel: viewModel,
                topicDetailStore: topicDetailStore,
                route: route,
                topicRoutePresenter: makeTopicRoutePresenter(
                    viewModel: viewModel,
                    topicDetailStore: topicDetailStore,
                    navigationControllerProvider: navigationControllerProvider
                )
            )
            navigationController.pushViewController(controller, animated: true)
            viewModel.topicRouteLogger()?.debug(
                "nested topic route presenter push requested \(route.diagnosticsSummary) new_stack_count=\(navigationController.viewControllers.count)"
            )
            return true
        }
    }

    /// Nested presenter that always targets the app-root secondary stack when present,
    /// otherwise falls through so callers can use `FireRootCoordinator.presentSecondaryRoute`.
    static func makeSecondaryStackTopicRoutePresenter(
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore
    ) -> FireTopicRoutePresenter {
        makeTopicRoutePresenter(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            navigationControllerProvider: { FireRootCoordinator.activeSecondaryNavigationController }
        )
    }

    /// Open any secondary-capable route above the tab shell.
    static func presentSecondaryRoute(
        _ route: FireAppRoute,
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore
    ) {
        if route.isTopicRoute {
            // Keep the single-flight topic path for topics.
            FireNavigationState.shared.presentTopicRoute(route)
            return
        }
        if route.presentsAsSecondaryPage {
            FireRootCoordinator.presentSecondaryRoute(route)
            return
        }
        viewModel.topicRouteLogger()?.debug(
            "route factory presentSecondaryRoute ignored non-secondary \(route.diagnosticsSummary)"
        )
    }
}
