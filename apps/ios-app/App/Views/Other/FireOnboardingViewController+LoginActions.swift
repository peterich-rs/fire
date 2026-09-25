import UIKit

extension FireOnboardingViewController {
    func wireCredentialFormCallbacks() {
        credentialFormView.onLoginTapped = { [weak self] identifier, password, remember in
            guard let self else { return }
            self.pendingIdentifier = identifier
            self.pendingPassword = password
            self.pendingRememberCredential = remember
            self.cfRetryUsed = false
            self.hasShownSecondFactor = false
            self.hideErrorBanner()
            self.logAuth("login tapped identifier_len=\(identifier.count) remember=\(remember)")
            self.loggingInMessage = "正在准备验证…"
            self.applyPhase(.loggingIn)
            Task { await self.performLogin() }
        }
        credentialFormView.onForgotPassword = { [weak self] in
            self?.presentWebViewBrowser(url: URL(string: "https://linux.do/password-reset")!)
        }
        credentialFormView.onExternalLogin = { [weak self] method in
            self?.presentWebViewBrowser(
                url: URL(string: "https://linux.do/login")!,
                autoStartExternalLogin: method
            )
        }
    }
    func performLogin() async {
        logAuth("performLogin begin; ensuring cloudflare clearance")
        let hasCloudflareClearance = await viewModel.ensureCloudflareClearance()
        guard hasCloudflareClearance else {
            let reason = viewModel.errorMessage.map { message in
                // Reuse token scan against the last CF error string.
                for token in ["cooldown", "cancelled", "in_progress", "background_suppressed", "failed", "required"] {
                    if message.localizedCaseInsensitiveContains(token) {
                        return token
                    }
                }
                return "failed"
            }
            abortLoginAttempt(
                message: Self.loginCloudflareFailureMessage(reason: reason),
                source: "ensureCloudflareClearance"
            )
            return
        }

        let loginCoordinator: FireWebViewLoginCoordinator
        do {
            loginCoordinator = try await viewModel.loginCoordinatorForDialog()
        } catch {
            abortLoginAttempt(
                message: "网络准备失败，请重试",
                source: "loginCoordinatorForDialog: \(error.localizedDescription)"
            )
            return
        }

        logAuth("presenting captcha dialog")
        presentCaptchaDialog(loginCoordinator: loginCoordinator)
    }
    /// Tear down captcha + logging-in overlay and return to the credential form.
    func abortLoginAttempt(message: String?, source: String) {
        logAuth("abortLoginAttempt source=\(source) message=\(message ?? "nil") auto=\(isAutoLoginInFlight)")
        let wasAutoLogin = isAutoLoginInFlight
        isAutoLoginInFlight = false
        activeAutoLoginKind = nil
        teardownHeadlessExternalEngine()
        dismissCaptchaDialog()
        if viewModel.session.readiness.canReadAuthenticatedApi {
            setLoginLoading(false)
            return
        }
        // Prefill remembered credentials after a failed/cancelled auto-login.
        if wasAutoLogin {
            credentialFormView.applySavedCredential(viewModel.savedLoginCredential)
            credentialFormView.applyLastLoginMethod(viewModel.lastLoginMethod)
        }
        applyPhase(.credential)
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showErrorBanner(message)
        } else if wasAutoLogin {
            showErrorBanner("自动登录未完成，请手动登录")
        }
    }
    func setLoginLoading(_ loading: Bool) {
        if loading {
            view.endEditing(true)
        }
        credentialFormView.setLoggingIn(loading)
        view.isUserInteractionEnabled = !loading
    }
}
