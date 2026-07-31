import SwiftUI

struct FireTopicRoutePresenter {
    let present: @MainActor (FireAppRoute) -> Bool
    /// Marks the environment default that always declines presentation.
    /// Nested UIKit surfaces treat this as “no preferred capability” and fall
    /// through the shared route-present cascade.
    let isLocalNoOp: Bool

    init(
        isLocalNoOp: Bool = false,
        present: @escaping @MainActor (FireAppRoute) -> Bool
    ) {
        self.isLocalNoOp = isLocalNoOp
        self.present = present
    }

    static let local = FireTopicRoutePresenter(isLocalNoOp: true) { _ in
        false
    }

    static func appRoot(
        navigationState: FireNavigationState,
        logger: FireHostLogger? = nil
    ) -> FireTopicRoutePresenter {
        FireTopicRoutePresenter { route in
            guard route.isTopicRoute else {
                logger?.debug("topic route presenter ignored non-topic route \(route.diagnosticsSummary)")
                return false
            }
            if let existingRoute = navigationState.presentedTopicRoute {
                logger?.warning(
                    "topic route presenter already has presented route existing={\(existingRoute.diagnosticsSummary)} incoming={\(route.diagnosticsSummary)}"
                )
            } else {
                logger?.info("topic route presenter presenting route \(route.diagnosticsSummary)")
            }
            navigationState.presentTopicRoute(route)
            logger?.debug(
                "topic route presenter present completed incoming_route_id=\(route.id) current_presented_route_id=\(navigationState.presentedTopicRoute?.id ?? "nil")"
            )
            return true
        }
    }
}

private struct FireTopicRoutePresenterKey: EnvironmentKey {
    static let defaultValue = FireTopicRoutePresenter.local
}

extension EnvironmentValues {
    var fireTopicRoutePresenter: FireTopicRoutePresenter {
        get { self[FireTopicRoutePresenterKey.self] }
        set { self[FireTopicRoutePresenterKey.self] = newValue }
    }
}

extension View {
    func fireTopicRoutePresenter(_ presenter: FireTopicRoutePresenter) -> some View {
        environment(\.fireTopicRoutePresenter, presenter)
    }
}
