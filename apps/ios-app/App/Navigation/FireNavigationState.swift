import Foundation

@MainActor
final class FireNavigationState: ObservableObject {
    static let shared = FireNavigationState()

    @Published var selectedTab: Int = 0
    @Published var pendingRoute: FireAppRoute?
    @Published var presentedTopicRoute: FireAppRoute?
    @Published var pendingSearchQuery: String?

    func handleIncomingURL(_ url: URL) {
        guard let route = FireRouteParser.parse(url: url) else {
            return
        }
        pendingRoute = route
    }

    func presentTopicRoute(_ route: FireAppRoute) {
        guard route.isTopicRoute else {
            return
        }
        guard presentedTopicRoute == nil else {
            return
        }
        presentedTopicRoute = route
    }

    func dismissPresentedTopicRoute() {
        presentedTopicRoute = nil
    }
}
