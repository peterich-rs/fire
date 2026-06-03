import SwiftUI
import UIKit

@MainActor
enum FireAppRouteControllerFactory {
    static func makeNavigationController(
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore,
        route: FireAppRoute
    ) -> UINavigationController {
        let navigationControllerBox = FireWeakNavigationControllerBox()
        let topicRoutePresenter = makeTopicRoutePresenter(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            navigationControllerProvider: { navigationControllerBox.navigationController }
        )
        let rootViewController = makeViewController(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            route: route,
            topicRoutePresenter: topicRoutePresenter
        )
        let navigationController = UINavigationController(rootViewController: rootViewController)
        navigationControllerBox.navigationController = navigationController
        return navigationController
    }

    static func makeViewController(
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore,
        route: FireAppRoute,
        topicRoutePresenter: FireTopicRoutePresenter = .local
    ) -> UIViewController {
        switch route {
        case .topic(let payload):
            return FireTopicDetailViewController(
                viewModel: viewModel,
                topicDetailStore: topicDetailStore,
                row: payload.row,
                scrollToPostNumber: payload.postNumber
            )
        case .profile(let username):
            return UIHostingController(
                rootView: FirePublicProfileView(
                    viewModel: viewModel,
                    username: username
                )
                .fireTopicRoutePresenter(topicRoutePresenter)
            )
        case .badge(let badgeID, _):
            return UIHostingController(
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
                return false
            }
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
            return true
        }
    }
}

private final class FireWeakNavigationControllerBox {
    weak var navigationController: UINavigationController?
}
