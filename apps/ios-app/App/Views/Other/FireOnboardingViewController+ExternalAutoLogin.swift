import UIKit

extension FireOnboardingViewController {
    func startExternalAutoLogin(method: FireExternalLoginMethod) {
        guard !viewModel.session.readiness.canReadAuthenticatedApi else { return }
        guard !isAutoLoginInFlight else { return }

        isAutoLoginInFlight = true
        activeAutoLoginKind = .external(method)
        hideErrorBanner()
        updateLoggingInMessage(FireAutoLoginPlanner.loadingMessage(for: .external(method)))
        applyPhase(.loggingIn)
        logAuth("external auto-login begin method=\(method.rawValue)")

        let engine = FireHeadlessExternalLoginEngine(method: method, viewModel: viewModel)
        headlessExternalEngine = engine
        engine.onOutcome = { [weak self] outcome in
            self?.handleHeadlessExternalOutcome(outcome)
        }
        engine.start(in: view)
    }
    func handleHeadlessExternalOutcome(
        _ outcome: FireHeadlessExternalLoginEngine.Outcome
    ) {
        switch outcome {
        case .authenticated:
            guard let webView = headlessExternalEngine?.currentWebView,
                  case let .external(method) = activeAutoLoginKind else {
                abortLoginAttempt(
                    message: "自动登录状态丢失，请手动登录",
                    source: "headless.authenticated.missing_webview"
                )
                return
            }
            logAuth("headless external authenticated method=\(method.rawValue); syncing")
            updateLoggingInMessage("正在同步登录态…")
            applyPhase(.loggingIn)
            Task { @MainActor in
                let ok = await self.viewModel.completeLoginAwaitingResult(
                    from: webView,
                    method: method.lastLoginMethod
                )
                if ok {
                    self.logAuth("headless external login finalized")
                    self.isAutoLoginInFlight = false
                    self.activeAutoLoginKind = nil
                    self.teardownHeadlessExternalEngine()
                    // Root coordinator swaps to home when canReadAuthenticatedApi flips.
                } else {
                    self.abortLoginAttempt(
                        message: self.viewModel.errorMessage ?? "登录态同步失败，请重试",
                        source: "headless.authenticated.sync_failed"
                    )
                }
            }

        case .needsUserInteraction:
            logAuth("headless external needs user interaction")
            updateLoggingInMessage("请完成登录")
            headlessExternalEngine?.promote(from: self)

        case let .failed(message):
            abortLoginAttempt(message: message, source: "headless.failed")

        case .cancelled:
            abortLoginAttempt(message: "已取消自动登录", source: "headless.cancelled")
        }
    }
    func teardownHeadlessExternalEngine() {
        headlessExternalEngine?.teardown()
        headlessExternalEngine = nil
    }
    func cancelAutoLogin(source: String) {
        guard isAutoLoginInFlight else { return }
        logAuth("auto-login cancelled source=\(source)")
        if headlessExternalEngine != nil {
            headlessExternalEngine?.cancel()
            return
        }
        abortLoginAttempt(message: "已取消自动登录", source: source)
    }
}
