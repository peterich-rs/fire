import Combine
import UIKit

extension FireRootCoordinator {
    func bindState() {
        viewModel.$session
            .map { $0.readiness.canReadAuthenticatedApi }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isAuthenticated in
                self?.handleAuthenticationChange(isAuthenticated)
            }
            .store(in: &cancellables)

        navigationState.$pendingRoute
            .receive(on: RunLoop.main)
            .sink { [weak self] route in
                self?.handlePendingRouteIfReady(route)
            }
            .store(in: &cancellables)

        navigationState.$presentedTopicRoute
            .receive(on: RunLoop.main)
            .sink { [weak self] route in
                self?.handleTopicRouteRequest(route)
            }
            .store(in: &cancellables)

        navigationState.$selectedTab
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] selectedTab in
                guard let self else { return }
                self.mainTabBarController?.setSelectedTab(selectedTab)
                self.updateTopLevelAPMRoute()
            }
            .store(in: &cancellables)

        notificationStore.$unreadCount
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] unreadCount in
                self?.mainTabBarController?.setUnreadCount(unreadCount)
            }
            .store(in: &cancellables)

        chatChannelsStore.$totalUnreadBadge
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] unreadCount in
                self?.mainTabBarController?.setChatUnreadCount(unreadCount)
            }
            .store(in: &cancellables)

        // External writers (e.g. residual SwiftUI @AppStorage) still update
        // UserDefaults; mirror into Environment so window + snapshot stay aligned.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                _ = FireAppearanceEnvironment.syncFromStorage(window: self.window)
            }
            .store(in: &cancellables)

        viewModel.$midSessionReauthMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.syncMidSessionReauthOverlay(message: message)
            }
            .store(in: &cancellables)

        viewModel.$isMidSessionReauthInFlight
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] inFlight in
                self?.handleMidSessionReauthFlightChange(inFlight)
            }
            .store(in: &cancellables)
    }

    func handleAuthenticationChange(_ isAuthenticated: Bool) {
        let previous = lastAuthenticatedState
        lastAuthenticatedState = isAuthenticated

        if previous == true, !isAuthenticated {
            if viewModel.isMidSessionReauthInFlight {
                // Passive logout raced with Google headless reauth. Keep the main
                // shell + overlay so a successful reauth can retry the original request.
                isHoldingMainShellForReauth = true
                updateTopLevelAPMRoute()
                return
            }

            tearDownAuthenticatedShellForDeauth()
        }

        if isAuthenticated {
            isHoldingMainShellForReauth = false
        } else if isHoldingMainShellForReauth, viewModel.isMidSessionReauthInFlight {
            updateTopLevelAPMRoute()
            return
        }

        updateRoot(animated: previous != nil)
        updateTopLevelAPMRoute()

        if isAuthenticated {
            Task {
                await FirePushRegistrationCoordinator.shared.ensurePushRegistration()
                await chatChannelsStore.refresh()
            }
            handlePendingRouteIfReady(navigationState.pendingRoute)
        }
    }

    func tearDownAuthenticatedShellForDeauth() {
        isHoldingMainShellForReauth = false
        // Explicit logout → credential form only.
        // Mid-session invalidation → sessionExpired so headless Google can auto-login.
        pendingOnboardingEntry = viewModel.deauthOnboardingEntry()
        homeFeedStore.reset()
        searchStore.reset()
        notificationStore.reset()
        chatChannelsStore.reset()
        topicDetailStore.reset()
        FireMotionCelebrationGate.reset()
        navigationState.dismissPresentedTopicRoute()
        dismissSecondaryStack(animated: false)
        FireBackgroundNotificationAlertScheduler.cancelRefresh()
        dismissMidSessionReauthOverlay()
    }

    func handleMidSessionReauthFlightChange(_ inFlight: Bool) {
        guard !inFlight, isHoldingMainShellForReauth else { return }
        guard !currentAuthenticationState else {
            isHoldingMainShellForReauth = false
            return
        }

        // Reauth finished without restoring auth — fall through to onboarding.
        tearDownAuthenticatedShellForDeauth()
        updateRoot(animated: true)
        updateTopLevelAPMRoute()
    }

    func syncMidSessionReauthOverlay(message: String?) {
        guard let message, !message.isEmpty else {
            dismissMidSessionReauthOverlay()
            return
        }

        if let overlay = midSessionReauthOverlay {
            overlay.updateMessage(message)
            // Keep the overlay below any promoted OAuth surface.
            overlay.view.superview?.bringSubviewToFront(overlay.view)
            return
        }

        guard let host = window?.rootViewController else { return }
        let overlay = FireMidSessionReauthOverlayController()
        overlay.updateMessage(message)
        overlay.onCancel = { [weak self] in
            self?.viewModel.cancelMidSessionReauth(reason: "overlay_cancel")
        }
        midSessionReauthOverlay = overlay

        // Child VC (not modal) so promoted full-screen OAuth can present cleanly above it.
        host.addChild(overlay)
        overlay.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(overlay.view)
        NSLayoutConstraint.activate([
            overlay.view.topAnchor.constraint(equalTo: host.view.topAnchor),
            overlay.view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            overlay.view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            overlay.view.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
        ])
        overlay.didMove(toParent: host)
    }

    func dismissMidSessionReauthOverlay() {
        guard let overlay = midSessionReauthOverlay else { return }
        midSessionReauthOverlay = nil
        overlay.willMove(toParent: nil)
        overlay.view.removeFromSuperview()
        overlay.removeFromParent()
    }
}
