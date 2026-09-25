import UIKit

extension FireOnboardingViewController {
    func presentCaptchaDialog(loginCoordinator: FireWebViewLoginCoordinator) {
        let dialog = FireCaptchaLoginDialogController(
            identifier: pendingIdentifier,
            password: pendingPassword,
            loginCoordinator: loginCoordinator,
            onResult: { [weak self] result in
                self?.handleDialogResult(result)
            },
            onCancel: { [weak self] in
                self?.abortLoginAttempt(
                    message: self?.isAutoLoginInFlight == true ? "已取消自动登录" : nil,
                    source: "captchaDialog.cancel"
                )
            }
        )

        dialog.classifyResult = { [weak self, weak dialog] phase, status, body in
            guard let self, let dialog else { return }
            self.logAuth(
                "login_result bridge phase=\(String(describing: phase)) status=\(status) body_len=\(body.count)"
            )
            Task {
                do {
                    let decision = try await self.viewModel.classifyLoginResult(
                        phase: phase,
                        status: status,
                        body: body
                    )
                    self.logAuth("classifyLoginResult decision=\(String(describing: decision))")
                    dialog.dispatchResult(self.dialogResult(from: decision))
                } catch {
                    self.logAuth("classifyLoginResult failed: \(error.localizedDescription)")
                    dialog.dispatchResult(
                        .failure(
                            LoginFailureState(
                                kind: .unknown,
                                message: error.localizedDescription,
                                sentToEmail: nil,
                                currentEmail: nil
                            )
                        )
                    )
                }
            }
        }

        if isAutoLoginInFlight {
            // Keep host loading under the sheet so auto-login feels continuous.
            if let kind = activeAutoLoginKind {
                updateLoggingInMessage(FireAutoLoginPlanner.captchaUnderlyingMessage(for: kind))
            }
            applyPhase(.loggingIn)
        } else if phase == .loggingIn {
            // Manual login: captcha sheet is the wait UI over the credential form.
            applyPhase(.credential)
        }

        captchaDialog = dialog
        refreshLoggingInChrome()
        present(dialog, animated: true)
    }
    func dialogResult(from decision: WebViewLoginDecisionState) -> FireCaptchaDialogResult {
        switch decision {
        case .success:
            return .success
        case let .needSecondFactor(requirement):
            return .needSecondFactor(requirement)
        case .retryCloudflare:
            return .retryCloudflare
        case let .failure(failure):
            return .failure(failure)
        }
    }
    func handleDialogResult(_ result: FireCaptchaDialogResult) {
        logAuth("captcha dialog result=\(String(describing: result))")
        switch result {
        case .success:
            completeLoginFromDialog()
        case let .needSecondFactor(requirement):
            showSecondFactorPrompt(requirement: requirement)
        case .retryCloudflare:
            recoverCloudflare()
        case let .failure(failure):
            // Keep the typed account/password so the user can fix a typo and retry.
            abortLoginAttempt(
                message: failure.message ?? "登录失败",
                source: "captchaDialog.failure kind=\(String(describing: failure.kind))"
            )
        }
    }
    func completeLoginFromDialog() {
        guard let dialog = captchaDialog else {
            abortLoginAttempt(message: "登录状态丢失，请重试", source: "completeLoginFromDialog missing dialog")
            return
        }
        let webView = dialog.webView!
        logAuth("login API succeeded; capturing cookies then dismissing captcha for sync loading")

        // Switch to host loading immediately so the sheet is not the wait UI.
        // Auto-login remains in-flight until sync finishes or aborts.
        updateLoggingInMessage("正在同步登录态…")
        applyPhase(.loggingIn)

        Task { @MainActor in
            do {
                let loginCoordinator = try await viewModel.loginCoordinatorForDialog()
                let captured = try await loginCoordinator.captureJsLoginState(
                    from: webView,
                    identifier: pendingIdentifier
                )
                self.dismissCaptchaDialog()
                self.logAuth("captcha dismissed; completeMinimalLogin begin")
                await self.viewModel.completeMinimalLogin(
                    captured: captured,
                    password: self.pendingPassword,
                    rememberCredential: self.pendingRememberCredential
                )
            } catch {
                self.abortLoginAttempt(
                    message: error.localizedDescription,
                    source: "completeLoginFromDialog capture/sync: \(error.localizedDescription)"
                )
            }
        }
    }
    func dismissCaptchaDialog() {
        captchaDialog?.dismiss(animated: true) { [weak self] in
            self?.captchaDialog = nil
        }
    }
}
