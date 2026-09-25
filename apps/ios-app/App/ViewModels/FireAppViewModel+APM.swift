import Foundation
import UIKit
import WebKit

extension FireAppViewModel {
    func dismissError() {
        errorMessage = nil
    }

    func updateTopLevelAPMRoute(selectedTab: Int, isAuthenticated: Bool) {
        let route: String
        if !isAuthenticated {
            route = "session.onboarding"
        } else {
            switch selectedTab {
            case 0:
                route = "tab.home"
            case 1:
                route = "tab.notifications"
            case 2:
                route = "tab.chat"
            case 3:
                route = "tab.profile"
            default:
                route = "tab.unknown"
            }
        }
        topLevelAPMRoute = route
        FireAPMManager.shared.setCurrentRoute(route)
    }

    func restoreTopLevelAPMRoute() {
        FireAPMManager.shared.setCurrentRoute(topLevelAPMRoute)
    }

    func setAPMRoute(_ route: String) {
        FireAPMManager.shared.setCurrentRoute(route)
    }

    // MARK: - MessageBus lifecycle
}
