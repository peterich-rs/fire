import UIKit

extension FireRootCoordinator {
    func handleScenePhaseChange(_ phase: ScenePhaseLabel) {
        if phase == .active {
            Self.activeCoordinator = self
        }

        let isAuthenticated = currentAuthenticationState
        homeFeedStore.setSceneActive(phase == .active)
        FireAPMManager.shared.setScenePhase(phase.rawValue)
        viewModel.handleDiagnosticsScenePhaseChange(
            phase.rawValue,
            isAuthenticated: isAuthenticated
        )

        switch phase {
        case .active:
            if isAuthenticated {
                Task {
                    await FirePushRegistrationCoordinator.shared.refreshAuthorizationStatus()
                    await FirePushRegistrationCoordinator.shared.ensurePushRegistration()
                }
            }
            handlePendingRouteIfReady(navigationState.pendingRoute)
        case .background:
            if isAuthenticated {
                FireBackgroundNotificationAlertScheduler.scheduleRefresh()
            } else {
                FireBackgroundNotificationAlertScheduler.cancelRefresh()
            }
        case .inactive, .unknown:
            break
        }
    }

    func updateTopLevelAPMRoute() {
        viewModel.updateTopLevelAPMRoute(
            selectedTab: navigationState.selectedTab,
            isAuthenticated: currentAuthenticationState
        )
    }
}
