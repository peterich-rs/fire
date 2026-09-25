import UIKit

extension FireOnboardingViewController {
    func scheduleRouteAfterStartupValidationIfNeeded() {
        guard startupRouteState == .pending else { return }
        startupRouteState = .routing
        Task { @MainActor in
            await self.routeAfterStartupValidation()
        }
    }
    /// Session-expired onboarding: try headless Google auto-login once, else credential form.
    func routeAfterSessionExpired() async {
        guard entry == .sessionExpired else { return }
        guard startupRouteState == .pending else { return }
        startupRouteState = .routing
        defer {
            if startupRouteState == .routing {
                startupRouteState = .finished
            }
        }

        guard !viewModel.session.readiness.canReadAuthenticatedApi else {
            logAuth("routeAfterSessionExpired skipped; already authenticated")
            return
        }

        await viewModel.prepareLoginForm()
        credentialFormView.applySavedCredential(viewModel.savedLoginCredential)
        credentialFormView.applyLastLoginMethod(viewModel.lastLoginMethod)

        let kind = FireAutoLoginPlanner.autoLoginKind(
            entry: .sessionExpired,
            lastLoginMethod: viewModel.lastLoginMethod,
            savedCredential: viewModel.savedLoginCredential
        )

        guard let kind else {
            logAuth(
                "session-expired auto-login ineligible method=\(String(describing: viewModel.lastLoginMethod))"
            )
            startupRouteState = .finished
            applyPhase(.credential)
            return
        }

        switch kind {
        case .password:
            // Mid-session recovery only auto-runs headless external methods.
            startupRouteState = .finished
            applyPhase(.credential)
        case let .external(method):
            startupRouteState = .finished
            startExternalAutoLogin(method: method)
        }
    }
    /// After cold-start auth probe fails, optionally attempt password auto-login once
    /// before falling through to the manual credential form.
    func routeAfterStartupValidation() async {
        defer {
            if startupRouteState == .routing {
                startupRouteState = .finished
            }
        }

        guard !viewModel.session.readiness.canReadAuthenticatedApi else {
            logAuth("routeAfterStartupValidation skipped; already authenticated")
            return
        }

        await viewModel.prepareLoginForm()
        credentialFormView.applySavedCredential(viewModel.savedLoginCredential)
        credentialFormView.applyLastLoginMethod(viewModel.lastLoginMethod)

        let kind = FireAutoLoginPlanner.coldStartKind(
            entry: entry,
            lastLoginMethod: viewModel.lastLoginMethod,
            savedCredential: viewModel.savedLoginCredential
        )

        guard let kind else {
            logAuth(
                "auto-login ineligible method=\(String(describing: viewModel.lastLoginMethod)) has_credential=\(viewModel.savedLoginCredential != nil)"
            )
            applyPhase(.credential)
            return
        }

        switch kind {
        case let .password(credential):
            // Mark finished before awaiting login so bindState can keep loggingIn via isAutoLoginInFlight.
            startupRouteState = .finished
            await startPasswordAutoLogin(credential: credential)
        case let .external(method):
            startupRouteState = .finished
            startExternalAutoLogin(method: method)
        }
    }
}
