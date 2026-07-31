import SwiftUI
import UIKit

@MainActor
enum FireAppRouteControllerFactory {
    /// Outcome of the shared secondary/topic presentation cascade (for tests + logs).
    enum PresentationOutcome: String, Equatable {
        case preferredPresenter
        case nestedNavigationStack
        case rootSecondaryStack
        case unhandled
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

    /// Stack-aware presenter for drill-down pages already living inside a nav stack
    /// (public profile, follow list). Prefers the local stack, then the app secondary stack.
    static func makeStackAwareTopicRoutePresenter(
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore,
        navigationControllerProvider: @escaping @MainActor () -> UINavigationController?
    ) -> FireTopicRoutePresenter {
        makeTopicRoutePresenter(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            navigationControllerProvider: {
                navigationControllerProvider()
                    ?? FireRootCoordinator.activeSecondaryNavigationController
            }
        )
    }

    /// Single authoritative cascade for secondary/topic routes from nested product surfaces.
    ///
    /// Order:
    /// 1. Preferred presenter (injected app-root / parent stack capability)
    /// 2. Push onto the caller's navigation stack (or active secondary stack)
    /// 3. Root secondary presentation (`FireRootCoordinator` / navigation state)
    @discardableResult
    static func present(
        _ route: FireAppRoute,
        preferredPresenter: FireTopicRoutePresenter,
        navigationControllerProvider: (@MainActor () -> UINavigationController?)? = nil,
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore
    ) -> PresentationOutcome {
        let logger = viewModel.topicRouteLogger()
        logger?.info("route present cascade start \(route.diagnosticsSummary)")

        if preferredPresenter.present(route) {
            logger?.info(
                "route present cascade outcome=\(PresentationOutcome.preferredPresenter.rawValue) \(route.diagnosticsSummary)"
            )
            return .preferredPresenter
        }

        if route.isTopicRoute {
            let nested = makeStackAwareTopicRoutePresenter(
                viewModel: viewModel,
                topicDetailStore: topicDetailStore,
                navigationControllerProvider: {
                    navigationControllerProvider?()
                }
            )
            if nested.present(route) {
                logger?.info(
                    "route present cascade outcome=\(PresentationOutcome.nestedNavigationStack.rawValue) \(route.diagnosticsSummary)"
                )
                return .nestedNavigationStack
            }
        }

        if route.presentsAsSecondaryPage {
            logger?.info(
                "route present cascade outcome=\(PresentationOutcome.rootSecondaryStack.rawValue) \(route.diagnosticsSummary)"
            )
            presentSecondaryRoute(
                route,
                viewModel: viewModel,
                topicDetailStore: topicDetailStore
            )
            return .rootSecondaryStack
        }

        logger?.warning(
            "route present cascade outcome=\(PresentationOutcome.unhandled.rawValue) \(route.diagnosticsSummary)"
        )
        return .unhandled
    }

    /// Build a public profile controller whose topic drill-down uses the shared cascade
    /// against the profile's own navigation controller (evaluated at present time).
    static func makePublicProfileViewController(
        viewModel: FireAppViewModel,
        username: String,
        topicDetailStore: FireTopicDetailStore,
        preferredPresenter: FireTopicRoutePresenter
    ) -> FirePublicProfileViewController {
        // Preferred presenter is retained for app-root / parent-capable injection;
        // the VC always re-resolves via `present(...)` with its live navigationController.
        FirePublicProfileViewController(
            viewModel: viewModel,
            username: username,
            topicDetailStore: topicDetailStore,
            topicRoutePresenter: preferredPresenter
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
