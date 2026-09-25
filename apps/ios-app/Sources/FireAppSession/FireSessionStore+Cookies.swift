import Foundation

extension FireSessionStore {
    public func cookieReplayQueue() throws -> [CookieReplayEntryState] {
        try core.session().cookieReplayQueue()
    }

    public func clearCookieReplayQueue() throws {
        try core.session().clearCookieReplayQueue()
    }

    @discardableResult
    public func mergePlatformCookies(_ cookies: [PlatformCookieState]) throws -> SessionState {
        let state = try core.session().mergePlatformCookies(cookies: cookies)
        try persistCurrentSessionIfNeeded()
        return state
    }

    public func webViewPrimingPayload(
        targetURL: String? = nil
    ) throws -> [WebViewCookieActionState] {
        try core.session().webviewPrimingPayload(targetUrl: targetURL)
    }

    public func cookieSweepPlan(
        targetURL: String? = nil,
        name: String,
        webViewCookies: [WebViewCookieInfoState]
    ) throws -> CookieSweepPlanState {
        try core.session().cookieSweepPlan(
            targetUrl: targetURL,
            name: name,
            webviewCookies: webViewCookies
        )
    }

    public func cookieNuclearResetPlan(
        targetURL: String? = nil,
        webViewCookies: [WebViewCookieInfoState]
    ) throws -> NuclearResetPlanState {
        try core.session().cookieNuclearResetPlan(
            targetUrl: targetURL,
            webviewCookies: webViewCookies
        )
    }

    @discardableResult
    public func commitCookieSweepResult(
        targetURL: String? = nil,
        name: String,
        intent: CookieSweepIntentState,
        webViewCookies: [WebViewCookieInfoState]
    ) throws -> SessionState {
        let state = try core.session().commitCookieSweepResult(
            targetUrl: targetURL,
            name: name,
            intent: intent,
            webviewCookies: webViewCookies
        )
        try persistCurrentSessionIfNeeded()
        return state
    }

    @discardableResult
    public func syncLoginContext(_ captured: FireCapturedLoginState) throws -> SessionState {
        let state = try core.session().syncLoginContext(
            context: LoginSyncState(
                currentUrl: captured.currentURL,
                username: captured.username,
                csrfToken: captured.csrfToken,
                homeHtml: captured.homeHTML,
                browserUserAgent: captured.browserUserAgent,
                cookies: captured.cookies
            )
        )
        try persistCurrentSessionIfNeeded()
        return state
    }

    @discardableResult
    public func applyPlatformCookies(_ cookies: [PlatformCookieState]) throws -> SessionState {
        let state = try core.session().applyPlatformCookies(cookies: cookies)
        try persistCurrentSessionIfNeeded()
        return state
    }
}
