import Foundation

struct FireDeepLink: Equatable {
    let topicId: UInt64
    let postNumber: UInt32?
}

@MainActor
final class FireNavigationState: ObservableObject {
    static let shared = FireNavigationState()

    @Published var selectedTab: Int = 0
    @Published var pendingDeepLink: FireDeepLink?
}
