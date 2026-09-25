import Foundation
import UIKit
import WebKit

extension FireAppViewModel {
    var isPresentingLogin: Bool {
        authPresentationState != nil
    }

    func openLogin() {
        guard authPresentationState == nil else { return }
        errorMessage = nil
        canSyncLoginSession = false
        cachedLoginSyncReadiness = nil
        setAuthPresentationState(.login)

        Task { await prepareLoginForm() }
    }

    func completeLogin(
        from webView: WKWebView,
        method: FireLastLoginMethod? = nil
    ) {
        Task {
            _ = await completeLoginAwaitingResult(from: webView, method: method)
        }
    }

    /// Finalize WebView/OAuth login and return whether session is ready for home.
    @discardableResult
    func completeLoginAwaitingResult(
        from webView: WKWebView,
        method: FireLastLoginMethod? = nil
    ) async -> Bool {
        guard !isSyncingLoginSession else {
            FireAPMManager.shared.recordBreadcrumb(
                level: "warn",
                target: "auth.login",
                message: "completeLogin ignored; already syncing"
            )
            return session.readiness.canReadAuthenticatedApi
        }

        isSyncingLoginSession = true
        defer { isSyncingLoginSession = false }

        do {
            return try await FireAPMManager.shared.withSpan(.authLoginSync) {
                let loginCoordinator = try await loginCoordinatorValue()
                let sessionStore = try await sessionStoreValue()
                errorMessage = nil
                let readiness = try await loginCoordinator.probeLoginSyncReadiness(from: webView)
                FireAPMManager.shared.recordBreadcrumb(
                    level: "info",
                    target: "auth.login",
                    message: "completeLogin probe ready=\(readiness.isReady) username=\(readiness.username ?? "nil") authCookies=\(readiness.hasAuthCookies) bootstrap=\(readiness.hasBootstrapHTML) score=\(readiness.preferredBootstrapScore)"
                )
                let session = try await loginCoordinator.completeLogin(from: webView)
                // Prefer starting MessageBus when bootstrap already made it possible.
                await applySession(session, activateMessageBus: true)
                if let method {
                    try await persistLastLoginMethod(method, sessionStore: sessionStore)
                }
                FireCfClearanceRefreshService.shared.setLoginStateConfirmed(true)
                FireCfClearanceRefreshService.shared.updateSession(
                    session,
                    loginCoordinator: loginCoordinator
                )
                // fluxdo finally: cookies trusted → enter home immediately.
                // App-state refresh must not block login-ready UI forever.
                setAuthPresentationState(nil)
                canSyncLoginSession = false
                cachedLoginSyncReadiness = nil
                Task { [weak self] in
                    guard let self else { return }
                    try? await sessionStore.triggerAppStateRefresh(
                        .loginCompleted,
                        handler: self.appStateRefreshCoordinator
                    )
                    await self.ensureMessageBusActiveIfPossible()
                }
                FireAPMManager.shared.recordBreadcrumb(
                    level: "info",
                    target: "auth.login",
                    message: "completeLogin finished canReadAuth=\(session.readiness.canReadAuthenticatedApi)"
                )
                return session.readiness.canReadAuthenticatedApi
            }
        } catch {
            FireAPMManager.shared.recordBreadcrumb(
                level: "error",
                target: "auth.login",
                message: "completeLogin failed: \(error.localizedDescription)"
            )
            if await handleRecoverableSessionErrorIfNeeded(error) {
                return session.readiness.canReadAuthenticatedApi
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func completeMinimalLogin(
        from webView: WKWebView,
        identifier: String,
        password: String,
        rememberCredential: Bool
    ) {
        guard !isSyncingLoginSession else {
            FireAPMManager.shared.recordBreadcrumb(
                level: "warn",
                target: "auth.login",
                message: "completeMinimalLogin ignored; already syncing"
            )
            return
        }

        isSyncingLoginSession = true
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: "auth.login",
            message: "completeMinimalLogin capture-from-webView start remember=\(rememberCredential)"
        )
        Task {
            do {
                let loginCoordinator = try await loginCoordinatorValue()
                let captured = try await loginCoordinator.captureJsLoginState(
                    from: webView,
                    identifier: identifier
                )
                await completeMinimalLogin(
                    captured: captured,
                    password: password,
                    rememberCredential: rememberCredential,
                    alreadyMarkedSyncing: true
                )
            } catch {
                isSyncingLoginSession = false
                FireAPMManager.shared.recordBreadcrumb(
                    level: "error",
                    target: "auth.login",
                    message: "completeMinimalLogin capture failed: \(error.localizedDescription)"
                )
                if await handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Finalize password login from an already-captured WebView cookie snapshot.
    /// Callers should dismiss captcha UI first and show host-owned sync loading.
    func completeMinimalLogin(
        captured: FireCapturedLoginState,
        password: String,
        rememberCredential: Bool,
        alreadyMarkedSyncing: Bool = false
    ) async {
        if !alreadyMarkedSyncing {
            guard !isSyncingLoginSession else {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "warn",
                    target: "auth.login",
                    message: "completeMinimalLogin(captured) ignored; already syncing"
                )
                return
            }
            isSyncingLoginSession = true
        }

        let identifier = (captured.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: "auth.login",
            message: "completeMinimalLogin start remember=\(rememberCredential) identifier_present=\(!identifier.isEmpty)"
        )

        defer { isSyncingLoginSession = false }

        do {
            try await FireAPMManager.shared.withSpan(.authLoginSync) {
                let loginCoordinator = try await loginCoordinatorValue()
                let sessionStore = try await sessionStoreValue()
                errorMessage = nil
                let session = try await loginCoordinator.completeJsLogin(captured)
                FireAPMManager.shared.recordBreadcrumb(
                    level: "info",
                    target: "auth.login",
                    message: "completeJsLogin ok canReadAuth=\(session.readiness.canReadAuthenticatedApi) loginPhase=\(String(describing: session.loginPhase))"
                )
                await applySession(session, activateMessageBus: true)
                try await persistLastLoginMethod(.password, sessionStore: sessionStore)
                if rememberCredential, !identifier.isEmpty {
                    try await sessionStore.saveLoginCredential(
                        username: identifier,
                        password: password
                    )
                    savedLoginCredential = try await sessionStore.loadSavedCredential()
                } else if !rememberCredential {
                    try await sessionStore.clearSavedCredential()
                    savedLoginCredential = nil
                }
                FireCfClearanceRefreshService.shared.setLoginStateConfirmed(true)
                // fluxdo finally: trusted cookies are enough to leave the login UI.
                setAuthPresentationState(nil)
                canSyncLoginSession = false
                cachedLoginSyncReadiness = nil
                Task { [weak self] in
                    guard let self else { return }
                    try? await sessionStore.triggerAppStateRefresh(
                        .loginCompleted,
                        handler: self.appStateRefreshCoordinator
                    )
                    await self.ensureMessageBusActiveIfPossible()
                }
                FireAPMManager.shared.recordBreadcrumb(
                    level: "info",
                    target: "auth.login",
                    message: "completeMinimalLogin finished successfully"
                )
            }
        } catch {
            FireAPMManager.shared.recordBreadcrumb(
                level: "error",
                target: "auth.login",
                message: "completeMinimalLogin failed: \(error.localizedDescription)"
            )
            if await handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func classifyWebViewLoginResult(
        _ result: WebViewLoginJsResultState
    ) async throws -> WebViewLoginDecisionState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.classifyWebViewLoginResult(result)
    }

    func classifyLoginResult(
        phase: WebViewLoginPhaseState,
        status: UInt16,
        body: String
    ) async throws -> WebViewLoginDecisionState {
        let result = WebViewLoginJsResultState(
            phase: phase,
            status: status,
            body: body
        )
        return try await classifyWebViewLoginResult(result)
    }

    func dismissAuthPresentation() {
        canSyncLoginSession = false
        cachedLoginSyncReadiness = nil
        setAuthPresentationState(nil)
    }

    func prepareAuthWebView(_ webView: WKWebView) {
        guard webView.url == nil else {
            return
        }

        let targetURL = authPresentationURL
        Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                let sessionStore = try await sessionStoreValue()
                let replayEntries = try await sessionStore.cookieReplayQueue()
                if !replayEntries.isEmpty {
                    let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
                    for entry in replayEntries {
                        guard let cookieURL = URL(string: entry.url) else {
                            continue
                        }
                        let cookies = HTTPCookie.cookies(
                            withResponseHeaderFields: ["Set-Cookie": entry.rawSetCookie],
                            for: cookieURL
                        )
                        for cookie in cookies {
                            await setWebKitCookie(cookie, in: cookieStore)
                        }
                    }
                    try await sessionStore.clearCookieReplayQueue()
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            guard webView.url == nil else {
                return
            }
            webView.load(URLRequest(url: targetURL))
        }
    }

    func saveLoginCredential(username: String, password: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let sessionStore = try await sessionStoreValue()
                try await sessionStore.saveLoginCredential(username: username, password: password)
                savedLoginCredential = try await sessionStore.loadSavedCredential()
            } catch {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "warn",
                    target: Self.authDiagnosticsLogTarget,
                    message: "failed to persist login credential: \(error.localizedDescription)"
                )
            }
        }
    }

    private func persistLastLoginMethod(
        _ method: FireLastLoginMethod,
        sessionStore: FireSessionStore
    ) async throws {
        try await sessionStore.saveLastLoginMethod(method)
        lastLoginMethod = method
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: Self.authDiagnosticsLogTarget,
            message: "recorded last login method=\(method.rawValue)"
        )
    }

    func recordLoginFingerprintDone() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let sessionStore = try await sessionStoreValue()
                await sessionStore.recordFingerprintDone()
            } catch {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "warn",
                    target: Self.authDiagnosticsLogTarget,
                    message: "failed to record fingerprint completion: \(error.localizedDescription)"
                )
            }
        }
    }

    func logout() {
        guard !isLoggingOut else {
            return
        }

        isLoggingOut = true
        // Explicit logout must never trigger mid-session / session-expired auto-login.
        didRequestExplicitLogout = true
        cancelMidSessionReauth(reason: "explicit_logout")

        Task {
            defer { isLoggingOut = false }

            do {
                let loginCoordinator = try await loginCoordinatorValue()
                stopMessageBus()
                errorMessage = nil
                FireCfClearanceRefreshService.shared.setLoginStateConfirmed(false)
                await applySession(try await loginCoordinator.logout())
                let sessionStore = try await sessionStoreValue()
                try await sessionStore.triggerAppStateRefresh(.logoutCompleted)
                canSyncLoginSession = false
                cachedLoginSyncReadiness = nil
                clearTopicState()
                notificationStore?.reset()
                updateWidgetData()
            } catch {
                do {
                    let loginCoordinator = try await loginCoordinatorValue()
                    FireCfClearanceRefreshService.shared.setLoginStateConfirmed(false)
                    await applySession(
                        try await loginCoordinator.logoutLocalAndClearPlatformCookies(
                            preserveCfClearance: true
                        )
                    )
                    canSyncLoginSession = false
                    cachedLoginSyncReadiness = nil
                    clearTopicState()
                    notificationStore?.reset()
                    updateWidgetData()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Topic list

    var authPresentationURL: URL {
        loginURL
    }

    func deauthOnboardingEntry() -> FireOnboardingEntry {
        if didRequestExplicitLogout {
            didRequestExplicitLogout = false
            return .signedOut
        }
        return .sessionExpired
    }

    /// Cancel an in-flight mid-session reauth (overlay cancel / explicit logout).
    private func setAuthPresentationState(_ state: FireAuthPresentationState?) {
        authPresentationState = state
    }
}
