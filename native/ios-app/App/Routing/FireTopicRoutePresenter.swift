import SwiftUI

struct FireTopicRoutePresenter {
    let present: @MainActor (FireAppRoute) -> Bool

    static let local = FireTopicRoutePresenter { _ in
        false
    }

    static func appRoot(navigationState: FireNavigationState) -> FireTopicRoutePresenter {
        FireTopicRoutePresenter { route in
            guard route.isTopicRoute else {
                return false
            }
            navigationState.presentTopicRoute(route)
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
