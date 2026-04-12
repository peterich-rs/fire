import Foundation

@MainActor
final class FireNavigationState: ObservableObject {
    static let shared = FireNavigationState()

    @Published var selectedTab: Int = 0
    @Published var pendingRoute: FireAppRoute?

    func handleIncomingURL(_ url: URL) {
        guard let route = FireRouteParser.parse(url: url) else {
            return
        }
        pendingRoute = route
    }
}
