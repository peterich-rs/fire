import SwiftUI
import UIKit

@MainActor
enum FireAppRouteControllerFactory {
    static func makeNavigationController(
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore,
        route: FireAppRoute,
        onDismiss: (@MainActor () -> Void)? = nil
    ) -> UINavigationController {
        viewModel.topicRouteLogger()?.info("route factory make navigation controller start \(route.diagnosticsSummary)")
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
        let navigationController = FirePresentedRouteNavigationController(rootViewController: rootViewController)
        navigationController.onDidDismiss = onDismiss
        navigationControllerBox.navigationController = navigationController
        viewModel.topicRouteLogger()?.info(
            "route factory make navigation controller complete \(route.diagnosticsSummary) view_controller_count=\(navigationController.viewControllers.count)"
        )
        return navigationController
    }

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
            return UIHostingController(
                rootView: FirePublicProfileView(
                    viewModel: viewModel,
                    username: username
                )
                .fireTopicRoutePresenter(topicRoutePresenter)
            )
        case .profileTab, .notifications, .search:
            return UIHostingController(rootView: EmptyView())
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
}

private final class FireWeakNavigationControllerBox {
    weak var navigationController: UINavigationController?
}

private final class FirePresentedRouteNavigationController: UINavigationController {
    var onDidDismiss: (@MainActor () -> Void)?

    private var didReportDismissal = false

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed else { return }
        reportDismissalIfNeeded()
    }

    private func reportDismissalIfNeeded() {
        guard !didReportDismissal else { return }
        didReportDismissal = true
        onDidDismiss?()
    }
}
