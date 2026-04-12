import Foundation

@MainActor
final class FireNavigationState: ObservableObject {
    static let shared = FireNavigationState()

    @Published var selectedTab: Int = 0
    @Published var pendingRoute: FireAppRoute?
}
