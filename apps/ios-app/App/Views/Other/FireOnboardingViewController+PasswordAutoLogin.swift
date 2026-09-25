import UIKit

extension FireOnboardingViewController {
    func startPasswordAutoLogin(credential: FireSavedCredential) async {
        guard !viewModel.session.readiness.canReadAuthenticatedApi else { return }
        guard !isAutoLoginInFlight else { return }

        isAutoLoginInFlight = true
        activeAutoLoginKind = .password(credential)
        pendingIdentifier = credential.username
        pendingPassword = credential.password
        pendingRememberCredential = true
        cfRetryUsed = false
        hasShownSecondFactor = false
        hideErrorBanner()
        updateLoggingInMessage(FireAutoLoginPlanner.loadingMessage(for: .password(credential)))
        applyPhase(.loggingIn)
        logAuth("password auto-login begin user_len=\(credential.username.count)")
        await performLogin()
    }
}
