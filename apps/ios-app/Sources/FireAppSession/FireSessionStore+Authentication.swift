import Foundation

extension FireSessionStore {
    public func determineLoginState() -> LoginStateDeterminationState {
        (try? core.session().determineLoginState()) ?? .notLoggedIn
    }

    public func determineLoginStateWithProbe() async throws -> LoginStateDeterminationState {
        let state = try await core.session().determineLoginStateWithProbe()
        try persistCurrentSessionIfNeeded()
        return state
    }

    public func loadSavedCredential() throws -> FireSavedCredential? {
        try authCookieStore.loadCredential()
    }

    public func saveLoginCredential(username: String, password: String) throws {
        guard let credential = FireSavedCredential(username: username, password: password) else {
            return
        }
        try authCookieStore.saveCredential(credential)
    }

    public func clearSavedCredential() throws {
        try authCookieStore.clearCredential()
    }

    public func loadLastLoginMethod() throws -> FireLastLoginMethod? {
        try authCookieStore.loadLastLoginMethod()
    }

    public func saveLastLoginMethod(_ method: FireLastLoginMethod) throws {
        try authCookieStore.saveLastLoginMethod(method)
    }

    public func clearLastLoginMethod() throws {
        try authCookieStore.clearLastLoginMethod()
    }

    @discardableResult
    public func recordFingerprintDone(_ cookies: [PlatformCookieState] = []) throws -> SessionState {
        let state = try core.session().recordFingerprintDone(cookies: cookies)
        try persistCurrentSessionIfNeeded()
        return state
    }

    public func buildUserApiKeyAuthorizeUrl(
        publicKeyPem: String,
        clientId: String,
        applicationName: String? = nil
    ) throws -> UserApiKeyAuthorizeUrlState {
        try core.session().buildUserApiKeyAuthorizeUrl(
            publicKeyPem: publicKeyPem,
            clientId: clientId,
            applicationName: applicationName
        )
    }

    public func handleUserApiKeyAuthRedirect(_ uri: String) async throws -> UserApiKeyAuthRedirectResultState {
        let result = try await core.session().handleUserApiKeyAuthRedirect(uri: uri)
        try persistCurrentSessionIfNeeded()
        return result
    }

    public func createQrLoginPayload(
        publicKeyPem: String,
        clientId: String,
        username: String? = nil
    ) async throws -> QrLoginPayloadState {
        try await core.session().createQrLoginPayload(
            publicKeyPem: publicKeyPem,
            clientId: clientId,
            username: username
        )
    }

    public func encodeQrLoginPayload(_ payload: QrLoginPayloadState, scheme: String = "fire") throws -> String {
        try core.session().encodeQrLoginPayload(payload: payload, scheme: scheme)
    }

    public func parseQrLoginPayload(_ raw: String) throws -> QrLoginPayloadState? {
        try core.session().parseQrLoginPayload(raw: raw)
    }

    public func loginWithQrPayload(_ raw: String) async throws -> UserApiKeyAuthRedirectResultState {
        let result = try await core.session().loginWithQrPayload(raw: raw)
        try persistCurrentSessionIfNeeded()
        return result
    }

    @discardableResult
    public func finalizeLoginFromWebView(
        _ captured: FireCapturedLoginState,
        allowLowConfidenceSessionCookies: Bool = false
    ) throws -> LoginFinalizationResultState {
        let result = try core.session().finalizeLoginFromWebview(
            username: captured.username ?? "",
            csrfToken: captured.csrfToken,
            rawPreloadedHtml: captured.homeHTML,
            browserUserAgent: captured.browserUserAgent,
            cookies: captured.cookies,
            allowLowConfidenceSessionCookies: allowLowConfidenceSessionCookies
        )
        try persistCurrentSessionIfNeeded()
        return result
    }

    public func cloudflareClearanceIsTrusted() throws -> Bool {
        try core.session().cloudflareClearanceIsTrusted()
    }

    public func noteCloudflareClearanceRejected() throws {
        try core.session().noteCloudflareClearanceRejected()
    }

    public func clearCloudflareCooldown() throws {
        try core.session().clearCloudflareCooldown()
    }

    @discardableResult
    public func beginManualCloudflareChallenge() throws -> Bool {
        try core.session().beginManualCloudflareChallenge()
    }

    public func finalizeLoginReady() async throws -> SessionState {
        let state = try await core.session().finalizeLoginReady()
        try persistCurrentSessionIfNeeded()
        return state
    }

    public func classifyWebViewLoginResult(
        _ result: WebViewLoginJsResultState
    ) throws -> WebViewLoginDecisionState {
        try core.session().classifyWebviewLoginResult(result: result)
    }

    @discardableResult
    public func completeCloudflareChallenge(
        cookies: [PlatformCookieState],
        freshCfClearance: String?,
        browserUserAgent: String?
    ) throws -> SessionState {
        let state = try core.session().completeCloudflareChallenge(
            cookies: cookies,
            freshCfClearance: {
                let trimmed = freshCfClearance?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (trimmed?.isEmpty == false) ? trimmed : nil
            }(),
            browserUserAgent: browserUserAgent
        )
        try persistCurrentSessionIfNeeded()
        return state
    }

    @discardableResult
    public func logoutLocal(preserveCfClearance: Bool = true) throws -> SessionState {
        let state = try core.session().logoutLocal(preserveCfClearance: preserveCfClearance)
        try authCookieStore.clear(preserveCfClearance: preserveCfClearance)
        try persistCurrentSessionIfNeeded()
        return state
    }

    @discardableResult
    public func logout() async throws -> SessionState {
        let current = try core.session().snapshot()
        if current.readiness.canReadAuthenticatedApi && !current.readiness.hasCurrentUser {
            _ = try await refreshBootstrapIfNeeded()
        }
        let state = try await core.session().logoutRemote(preserveCfClearance: true)
        try authCookieStore.save(FireAuthCookieSecrets(cookieState: state.cookies))
        let persistenceState = try currentSessionPersistenceState()
        lastPersistedAuthCookieRevision = persistenceState.authCookieRevision
        try clearPersistedSession()
        return state
    }
}
