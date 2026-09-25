import Foundation
import UIKit
import WebKit

extension FireAppViewModel {
    func performWriteWithCloudflareRetry<T>(
        operationDescription: String = "执行当前操作",
        originURL: URL? = nil,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        _ = operationDescription
        _ = originURL
        return try await operation()
    }

    /// Read-path join/retry helper for Cloudflare errors. **Does not present** UI.
    ///
    /// - `in_progress`: wait for the host presentation gate (Rust handler already
    ///   owns the WebView), settle jar merge, then retry `work` once.
    /// - other CF reasons: rethrow for banners / explicit manual verify.
    ///
    /// `originURL` is retained for call-site compatibility and diagnostics only.
    func performWithCloudflareRecovery<T>(
        operation: String,
        originURL: URL? = nil,
        work: @escaping () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch {
            guard Self.isCloudflareChallengeError(error) else {
                throw error
            }
            let reason = Self.cloudflareChallengeReason(from: error)
            switch Self.cloudflareRecoveryAction(forReason: reason) {
            case .waitThenRetry:
                FireAPMManager.shared.recordBreadcrumb(
                    level: "info",
                    target: "auth.cf",
                    message: "recovery wait-then-retry operation=\(operation) reason=\(reason) origin=\(originURL?.absoluteString ?? "nil")"
                )
                await Self.awaitCloudflareChallengeQuietPeriod()
                return try await work()
            case .rethrow:
                throw error
            }
        }
    }

    /// Host recovery policy for a normalized CF reason token (read path).
    /// Automatic paths never present UI (`waitThenRetry` / `rethrow` only).
    enum CloudflareRecoveryAction: Equatable {
        case waitThenRetry
        case rethrow
    }

    nonisolated static func cloudflareRecoveryAction(
        forReason reason: String
    ) -> CloudflareRecoveryAction {
        switch reason {
        case "in_progress":
            return .waitThenRetry
        default:
            // required / failed / cancelled / cooldown / background_suppressed:
            // surface to UI. Present only via Rust handler or explicit manual APIs.
            return .rethrow
        }
    }

    /// Wait for an in-flight host challenge presentation, then briefly settle.
    /// Used on read paths when Rust blocks concurrent traffic with `in_progress`.
    static func awaitCloudflareChallengeQuietPeriod(
        appearTimeout: Duration = .seconds(2),
        presentationTimeout: Duration = .seconds(120),
        settle: Duration = .milliseconds(500)
    ) async {
        await FireCloudflareChallengePresentationGate.awaitPresentationAppearance(
            timeout: appearTimeout
        )
        if FireCloudflareChallengePresentationGate.isPresentationInFlight {
            await FireCloudflareChallengePresentationGate.awaitActivePresentationIfAny(
                timeout: presentationTimeout
            )
        }
        try? await Task.sleep(for: settle)
    }

    nonisolated static func isCloudflareChallengeError(_ error: Error) -> Bool {
        if let fireError = error as? FireUniFfiError {
            if case .CloudflareChallenge = fireError {
                return true
            }
        }
        let message = String(describing: error).lowercased()
        return message.contains("cloudflare challenge")
    }

    nonisolated static func cloudflareChallengeReason(from error: Error) -> String {
        if let fireError = error as? FireUniFfiError,
           case let .CloudflareChallenge(reason) = fireError {
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        let message = String(describing: error)
        for token in ["in_progress", "cooldown", "cancelled", "failed", "background_suppressed", "required"] {
            if message.contains("(\(token))") || message.contains(token) {
                return token
            }
        }
        return "required"
    }

    /// Onboarding entry used when the authenticated shell loses auth.
    /// Explicit logout always returns `.signedOut` (no auto-login).
    /// Passive / mid-session invalidation returns `.sessionExpired` so headless
    /// Google can auto-login on the onboarding host as a fallback path.
    func cancelMidSessionReauth(reason: String = "user_cancel") {
        guard isMidSessionReauthInFlight || midSessionReauthEngine != nil else { return }
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: Self.authDiagnosticsLogTarget,
            message: "mid-session reauth cancelled reason=\(reason)"
        )
        if let engine = midSessionReauthEngine {
            engine.cancel()
            return
        }
        finishMidSessionReauth(success: false)
    }

    /// Read-side recovery for transient `LoginRequired` errors observed during
    /// passive reads (home feed, topic detail) and other in-app requests.
    ///
    /// Recovery order:
    /// 1. Single-flight host cookie resync per session epoch (WebKit may be ahead
    ///    of the shared Rust jar after `_t` / `_forum_session` rotation).
    /// 2. If the last login method is headless-capable (currently Google), run
    ///    mid-session headless reauth under a loading overlay and keep the main
    ///    shell mounted so the caller can retry the original request in place.
    ///
    /// - Returns: `true` when recovery succeeded and the caller should retry once.
    @discardableResult
    func attemptReadPathLoginRecovery(
        operation: String,
        error: Error
    ) async -> Bool {
        guard case FireUniFfiError.LoginRequired = error else {
            return false
        }

        if await attemptHostCookieResyncRecovery(operation: operation) {
            return true
        }

        return await attemptMidSessionHeadlessReauth(operation: operation)
    }

    func attemptHostCookieResyncRecovery(operation: String) async -> Bool {
        let logger = await authDiagnosticsLogger()

        let beforeEpoch: UInt64
        do {
            beforeEpoch = try await currentSessionEpoch()
        } catch {
            logger?.warning(
                "read-path resync skipped operation=\(operation) reason=epoch_unavailable error=\(error.localizedDescription)"
            )
            return false
        }

        if readPathLoginRecoveryAttemptedEpochs.contains(beforeEpoch) {
            logger?.notice(
                "read-path resync skipped operation=\(operation) reason=already_attempted epoch=\(beforeEpoch)"
            )
            return false
        }

        if let existingTask = readPathLoginRecoveryTask,
            readPathLoginRecoveryEpoch == beforeEpoch {
            return await existingTask.value
        }

        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.runReadPathLoginRecovery(
                operation: operation,
                beforeEpoch: beforeEpoch
            )
        }
        readPathLoginRecoveryTask = task
        readPathLoginRecoveryEpoch = beforeEpoch
        defer {
            if readPathLoginRecoveryEpoch == beforeEpoch {
                readPathLoginRecoveryTask = nil
                readPathLoginRecoveryEpoch = nil
            }
        }
        return await task.value
    }

    private func runReadPathLoginRecovery(
        operation: String,
        beforeEpoch: UInt64
    ) async -> Bool {
        readPathLoginRecoveryAttemptedEpochs.insert(beforeEpoch)
        let logger = await authDiagnosticsLogger()

        let coordinator: FireWebViewLoginCoordinator
        do {
            coordinator = try await loginCoordinatorValue()
        } catch {
            logger?.warning(
                "read-path resync skipped operation=\(operation) epoch=\(beforeEpoch) reason=no_coordinator error=\(error.localizedDescription)"
            )
            return false
        }

        let cookies: [PlatformCookieState]
        do {
            cookies = try await coordinator.platformCookiesForSessionResync()
        } catch {
            logger?.warning(
                "read-path resync failed operation=\(operation) epoch=\(beforeEpoch) reason=cookie_fetch_failed error=\(error.localizedDescription)"
            )
            return false
        }

        guard FireWebViewLoginCoordinator.containsActiveAuthCookies(in: cookies) else {
            logger?.notice(
                "read-path resync skipped operation=\(operation) epoch=\(beforeEpoch) reason=no_authoritative_webview_auth_cookies cookie_count=\(cookies.count)"
            )
            return false
        }

        let sessionStore: FireSessionStore
        do {
            sessionStore = try await sessionStoreValue()
        } catch {
            logger?.warning(
                "read-path resync skipped operation=\(operation) epoch=\(beforeEpoch) reason=no_session_store error=\(error.localizedDescription)"
            )
            return false
        }

        do {
            _ = try await sessionStore.applyPlatformCookies(cookies)
        } catch {
            logger?.warning(
                "read-path resync failed operation=\(operation) epoch=\(beforeEpoch) reason=apply_failed error=\(error.localizedDescription)"
            )
            return false
        }

        let afterEpoch: UInt64
        do {
            afterEpoch = try await sessionStore.currentSessionEpoch()
        } catch {
            logger?.warning(
                "read-path resync inconclusive operation=\(operation) epoch=\(beforeEpoch) reason=post_epoch_unavailable error=\(error.localizedDescription)"
            )
            return false
        }

        let didRotate = afterEpoch != beforeEpoch
        if didRotate {
            // Once the resync actually rotated us into a new auth epoch, the
            // older `attempted` markers no longer protect us from anything;
            // keep the set small so a long-lived session doesn't accumulate
            // stale markers.
            readPathLoginRecoveryAttemptedEpochs = readPathLoginRecoveryAttemptedEpochs
                .filter { $0 == afterEpoch }
            FireAPMManager.shared.recordBreadcrumb(
                target: Self.authDiagnosticsLogTarget,
                message: "read-path resync rotated auth operation=\(operation) before_epoch=\(beforeEpoch) after_epoch=\(afterEpoch) cookie_count=\(cookies.count)"
            )
            logger?.notice(
                "read-path resync rotated auth operation=\(operation) before_epoch=\(beforeEpoch) after_epoch=\(afterEpoch) cookie_count=\(cookies.count)"
            )
        } else {
            logger?.notice(
                "read-path resync no_change operation=\(operation) epoch=\(beforeEpoch) cookie_count=\(cookies.count)"
            )
        }
        return didRotate
    }

    /// Called from `applySession` when auth drops without an explicit logout.
    /// Starts Google headless recovery early enough for RootCoordinator to hold the shell.
    func scheduleMidSessionReauthAfterPassiveDeauth() {
        if midSessionReauthTask != nil || isMidSessionReauthInFlight {
            return
        }

        let knownMethod = FireAutoLoginPlanner.midSessionHeadlessKind(
            lastLoginMethod: lastLoginMethod
        )
        // lastLoginMethod may not be loaded yet on a long-lived session; optimistically
        // hold and resolve eligibility inside the single-flight reauth task.
        guard knownMethod != nil || lastLoginMethod == nil else {
            return
        }

        isMidSessionReauthInFlight = true
        if midSessionReauthMessage == nil {
            if let knownMethod {
                midSessionReauthMessage = FireAutoLoginPlanner.loadingMessage(
                    for: .external(knownMethod)
                )
            } else {
                midSessionReauthMessage = "正在恢复登录…"
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.attemptMidSessionHeadlessReauth(operation: "session_deauth")
        }
    }

    /// Mid-session headless reauth for LoginRequired when cookie resync cannot help.
    /// Currently limited to providers in `FireAutoLoginPlanner.headlessExternalPool`
    /// (Google). Single-flight across the app so concurrent failing requests share
    /// one overlay + one OAuth attempt, then all retry.
    func attemptMidSessionHeadlessReauth(operation: String) async -> Bool {
        if let existing = midSessionReauthTask {
            return await existing.value
        }

        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.runMidSessionHeadlessReauth(operation: operation)
        }
        midSessionReauthTask = task
        let result = await task.value
        if midSessionReauthTask != nil {
            midSessionReauthTask = nil
        }
        return result
    }

    private func runMidSessionHeadlessReauth(operation: String) async -> Bool {
        // Explicit logout wins over any in-flight recovery.
        guard !didRequestExplicitLogout, !isLoggingOut else {
            finishMidSessionReauth(success: false)
            return false
        }

        if lastLoginMethod == nil {
            await prepareLoginForm()
        }

        guard let method = FireAutoLoginPlanner.midSessionHeadlessKind(
            lastLoginMethod: lastLoginMethod
        ) else {
            let logger = await authDiagnosticsLogger()
            logger?.notice(
                "mid-session reauth skipped operation=\(operation) reason=method_ineligible last=\(String(describing: lastLoginMethod))"
            )
            finishMidSessionReauth(success: false)
            return false
        }

        guard let hostViewController = Self.topPresenterForMidSessionReauth() else {
            let logger = await authDiagnosticsLogger()
            logger?.warning(
                "mid-session reauth skipped operation=\(operation) reason=no_presenter"
            )
            finishMidSessionReauth(success: false)
            return false
        }

        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: Self.authDiagnosticsLogTarget,
            message: "mid-session reauth begin operation=\(operation) method=\(method.rawValue)"
        )

        isMidSessionReauthInFlight = true
        midSessionReauthMessage = FireAutoLoginPlanner.loadingMessage(for: .external(method))

        let succeeded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            // A proactive deauth hold may already have flipped inFlight without a waiter.
            if let previous = self.midSessionReauthContinuation {
                self.midSessionReauthContinuation = nil
                previous.resume(returning: false)
            }
            self.midSessionReauthContinuation = continuation

            let engine = FireHeadlessExternalLoginEngine(method: method, viewModel: self)
            self.midSessionReauthEngine = engine
            engine.onOutcome = { [weak self] outcome in
                guard let self else { return }
                self.handleMidSessionReauthOutcome(
                    outcome,
                    method: method,
                    presenter: hostViewController
                )
            }
            engine.start(in: hostViewController.view)
        }

        if succeeded {
            FireAPMManager.shared.recordBreadcrumb(
                level: "info",
                target: Self.authDiagnosticsLogTarget,
                message: "mid-session reauth succeeded operation=\(operation) method=\(method.rawValue)"
            )
        } else {
            FireAPMManager.shared.recordBreadcrumb(
                level: "warn",
                target: Self.authDiagnosticsLogTarget,
                message: "mid-session reauth failed operation=\(operation) method=\(method.rawValue)"
            )
        }
        return succeeded
    }

    private func handleMidSessionReauthOutcome(
        _ outcome: FireHeadlessExternalLoginEngine.Outcome,
        method: FireExternalLoginMethod,
        presenter: UIViewController
    ) {
        switch outcome {
        case .authenticated:
            guard let webView = midSessionReauthEngine?.currentWebView else {
                finishMidSessionReauth(success: false)
                return
            }
            midSessionReauthMessage = "正在同步登录态…"
            Task { @MainActor in
                let ok = await self.completeLoginAwaitingResult(
                    from: webView,
                    method: method.lastLoginMethod
                )
                self.finishMidSessionReauth(success: ok && self.session.readiness.canReadAuthenticatedApi)
            }

        case .needsUserInteraction:
            midSessionReauthMessage = FireAutoLoginPlanner.loadingMessage(for: .external(method))
                .replacingOccurrences(of: "正在通过", with: "请完成")
                .replacingOccurrences(of: "…", with: "")
            midSessionReauthEngine?.promote(from: presenter)

        case .failed:
            finishMidSessionReauth(success: false)

        case .cancelled:
            finishMidSessionReauth(success: false)
        }
    }

    private func finishMidSessionReauth(success: Bool) {
        midSessionReauthEngine?.teardown()
        midSessionReauthEngine = nil
        midSessionReauthMessage = nil
        isMidSessionReauthInFlight = false

        if let continuation = midSessionReauthContinuation {
            midSessionReauthContinuation = nil
            continuation.resume(returning: success)
        }
    }

    private static func topPresenterForMidSessionReauth() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    @discardableResult
    func handleRecoverableSessionErrorIfNeeded(_ error: Error) async -> Bool {
        await handleStaleSessionResponseIfNeeded(error)
    }

    @discardableResult
    func handleStaleSessionResponseIfNeeded(_ error: Error) async -> Bool {
        guard case let FireUniFfiError.StaleSessionResponse(operation) = error else {
            return false
        }

        FireAPMManager.shared.recordBreadcrumb(
            target: Self.authDiagnosticsLogTarget,
            message: "discarded stale session response operation=\(operation)"
        )
        return true
    }

    @discardableResult
    func handleInteractionError(_ error: Error) async -> Bool {
        if await handleRecoverableSessionErrorIfNeeded(error) {
            return true
        }
        errorMessage = error.localizedDescription
        return false
    }

    func configureAuthenticatedWriteHostResyncProvider(
        with sessionStore: FireSessionStore
    ) async {
        let loginCoordinator: FireWebViewLoginCoordinator
        if let existingLoginCoordinator = self.loginCoordinator {
            loginCoordinator = existingLoginCoordinator
        } else {
            let newLoginCoordinator = FireWebViewLoginCoordinator(sessionStore: sessionStore)
            self.loginCoordinator = newLoginCoordinator
            loginCoordinator = newLoginCoordinator
        }

        await sessionStore.setAuthenticatedWriteHostResyncProvider { [weak loginCoordinator] in
            guard let loginCoordinator else {
                return nil
            }
            return try await loginCoordinator.platformCookiesForSessionResync()
        }

        if cloudflareChallengeHandler == nil {
            cloudflareChallengeHandler = FireCloudflareChallengeRuntimeHandler(
                sessionStore: sessionStore
            )
        }
        if let cloudflareChallengeHandler {
            try? await sessionStore.registerCloudflareChallengeHandler(
                cloudflareChallengeHandler
            )
        }
        if clearanceResolvedHandler == nil {
            clearanceResolvedHandler = FireClearanceResolvedRuntimeHandler { [weak self] event in
                await self?.handleClearanceResolved(event)
            }
        }
        if let clearanceResolvedHandler {
            try? await sessionStore.registerCloudflareClearanceResolvedHandler(
                clearanceResolvedHandler
            )
        }
        if cookieSelfHealingHandler == nil {
            cookieSelfHealingHandler = FireCookieSelfHealingRuntimeHandler(
                loginCoordinator: loginCoordinator
            )
        }
        if let cookieSelfHealingHandler {
            try? await sessionStore.registerCookieSelfHealingHandler(
                cookieSelfHealingHandler
            )
        }
    }
}
