import Foundation
import WebKit

enum FireBootstrapHTMLHeuristics {
    static func preferredHTML(
        browserFetchedHomeHTML: String?,
        currentPageHTML: String?
    ) -> String? {
        let homeScore = score(browserFetchedHomeHTML)
        let currentScore = score(currentPageHTML)

        if homeScore > currentScore, let browserFetchedHomeHTML = nonEmpty(browserFetchedHomeHTML) {
            return browserFetchedHomeHTML
        }

        if let currentPageHTML = nonEmpty(currentPageHTML) {
            return currentPageHTML
        }

        return nonEmpty(browserFetchedHomeHTML)
    }

    static func score(_ html: String?) -> Int {
        guard let html else {
            return 0
        }

        let normalized = html.lowercased()
        var score = 0

        if normalized.contains("id=\"data-discourse-setup\"")
            || normalized.contains("id='data-discourse-setup'")
            || normalized.contains("data-preloaded")
        {
            score += 8
        }
        if normalized.contains("meta name=\"shared_session_key\"")
            || normalized.contains("meta name='shared_session_key'")
        {
            score += 4
        }
        if normalized.contains("\"long_polling_base_url\"") {
            score += 6
        }
        if normalized.contains("\"topictrackingstatemeta\"") {
            score += 5
        }
        if normalized.contains("\"notification_channel_position\"") {
            score += 4
        }
        if normalized.contains("\"categories\":") {
            score += 3
        }
        if normalized.contains("\"top_tags\":") {
            score += 3
        }
        if normalized.contains("\"can_tag_topics\"") {
            score += 2
        }
        if normalized.contains("\"sitesettings\":") {
            score += 2
        }
        if normalized.contains("meta name=\"current-username\"")
            || normalized.contains("meta name='current-username'")
        {
            score += 2
        }
        if normalized.contains("meta name=\"csrf-token\"")
            || normalized.contains("meta name='csrf-token'")
        {
            score += 1
        }

        return score
    }

    static func isReusableLoginBootstrap(_ html: String?) -> Bool {
        score(html) >= 8
    }

    private static func nonEmpty(_ html: String?) -> String? {
        guard let html, !html.isEmpty else {
            return nil
        }
        return html
    }
}

public struct FireLoginSyncReadiness: Sendable, Equatable {
    public let isReady: Bool
    public let username: String?
    public let hasAuthCookies: Bool
    public let hasBootstrapHTML: Bool
    public let preferredBootstrapScore: Int

    public init(
        isReady: Bool,
        username: String?,
        hasAuthCookies: Bool,
        hasBootstrapHTML: Bool,
        preferredBootstrapScore: Int
    ) {
        self.isReady = isReady
        self.username = username
        self.hasAuthCookies = hasAuthCookies
        self.hasBootstrapHTML = hasBootstrapHTML
        self.preferredBootstrapScore = preferredBootstrapScore
    }
}

public enum FireWebViewLoginCoordinatorError: LocalizedError {
    case loginSyncNotReady(FireLoginSyncReadiness)

    public var errorDescription: String? {
        switch self {
        case let .loginSyncNotReady(readiness):
            if !readiness.hasAuthCookies {
                return "登录状态尚未写入站点 Cookie，请稍后再试。"
            }
            if !readiness.hasBootstrapHTML {
                return "登录页还未拿到可用的站点引导数据，请稍后再试。"
            }
            return "登录状态尚未准备完成，请稍后再试。"
        }
    }
}

protocol FireLoginSessionStoring: Sendable {
    func restorePersistedSessionIfAvailable() async throws -> SessionState?
    func syncLoginContext(_ captured: FireCapturedLoginState) async throws -> SessionState
    func refreshBootstrapIfNeeded() async throws -> SessionState
    func logout() async throws -> SessionState
    func logoutLocal(preserveCfClearance: Bool) async throws -> SessionState
    func applyPlatformCookies(_ cookies: [PlatformCookieState]) async throws -> SessionState
}

extension FireSessionStore: FireLoginSessionStoring {}

@MainActor
public final class FireWebViewLoginCoordinator {
    private let sessionStore: any FireLoginSessionStoring

    public init(sessionStore: FireSessionStore) {
        self.sessionStore = sessionStore
    }

    init(loginSessionStore: any FireLoginSessionStoring) {
        self.sessionStore = loginSessionStore
    }

    public func restorePersistedSessionIfAvailable() async throws -> SessionState? {
        try await sessionStore.restorePersistedSessionIfAvailable()
    }

    public func completeLogin(from webView: WKWebView) async throws -> SessionState {
        _ = try await refreshPlatformCookies()
        let captured = try await captureLoginState(from: webView)
        let readiness = loginSyncReadiness(for: captured)
        guard readiness.isReady else {
            throw FireWebViewLoginCoordinatorError.loginSyncNotReady(readiness)
        }
        _ = try await completeLogin(captured)
        return try await refreshPlatformCookies()
    }

    func completeLogin(_ captured: FireCapturedLoginState) async throws -> SessionState {
        _ = try await sessionStore.syncLoginContext(captured)

        do {
            return try await sessionStore.refreshBootstrapIfNeeded()
        } catch {
            guard case FireUniFfiError.CloudflareChallenge = error else {
                throw error
            }

            // Don't keep a partially synced native session around when bootstrap
            // refresh is still challenged. The WebView login flow remains open so
            // the user can complete the challenge and retry Sync.
            _ = try? await sessionStore.logoutLocal(preserveCfClearance: true)
            try? await clearPlatformLoginCookies(preserveCfClearance: true)
            throw error
        }
    }

    public func logout() async throws -> SessionState {
        let state = try await sessionStore.logout()
        try await clearPlatformLoginCookies(preserveCfClearance: true)
        return state
    }

    public func captureLoginState(from webView: WKWebView) async throws -> FireCapturedLoginState {
        let currentURL = webView.url?.absoluteString
        async let username = readStringJavaScript(
            script: """
            (function() {
              var meta = document.querySelector('meta[name="current-username"]');
              if (meta && meta.content) return meta.content;
              return null;
            })();
            """,
            in: webView
        )
        async let csrfToken = readStringJavaScript(
            script: """
            (function() {
              var meta = document.querySelector('meta[name="csrf-token"]');
              if (meta && meta.content) return meta.content;
              return null;
            })();
            """,
            in: webView
        )
        async let currentPageHTML = readStringJavaScript(
            script: "document.documentElement.outerHTML",
            in: webView
        )
        async let homeHTML = fetchHomeHTML(in: webView)
        async let browserUserAgent = readStringJavaScript(
            script: "navigator.userAgent",
            in: webView
        )
        async let cookies = relevantCookies(from: webView)

        let capturedUsername = try await username
        let capturedCsrfToken = try await csrfToken
        let capturedCurrentPageHTML = try await currentPageHTML
        let capturedHomeHTML = try await homeHTML
        let capturedBrowserUserAgent = try await browserUserAgent
        let capturedCookies = try await cookies

        return FireCapturedLoginState(
            currentURL: currentURL,
            username: capturedUsername,
            csrfToken: capturedCsrfToken,
            homeHTML: preferredBootstrapHTML(
                browserFetchedHomeHTML: capturedHomeHTML,
                currentPageHTML: capturedCurrentPageHTML
            ),
            browserUserAgent: capturedBrowserUserAgent,
            cookies: capturedCookies
        )
    }

    public func refreshPlatformCookies() async throws -> SessionState {
        let cookies = try await relevantCookies(
            from: WKWebsiteDataStore.default().httpCookieStore
        )
        return try await sessionStore.applyPlatformCookies(cookies)
    }

    public func probeLoginSyncReadiness(from webView: WKWebView) async throws -> FireLoginSyncReadiness {
        let captured = try await captureLoginState(from: webView)
        return loginSyncReadiness(for: captured)
    }

    public func logoutLocalAndClearPlatformCookies(
        preserveCfClearance: Bool = true
    ) async throws -> SessionState {
        let state = try await sessionStore.logoutLocal(preserveCfClearance: preserveCfClearance)
        try await clearPlatformLoginCookies(preserveCfClearance: preserveCfClearance)
        return state
    }

    private func relevantCookies(from webView: WKWebView) async throws -> [PlatformCookieState] {
        try await relevantCookies(from: webView.configuration.websiteDataStore.httpCookieStore)
    }

    private func relevantCookies(from store: WKHTTPCookieStore) async throws -> [PlatformCookieState] {
        let allCookies = try await httpCookies(from: store)
        return allCookies.compactMap { cookie in
            guard cookie.domain.range(of: "linux.do", options: .caseInsensitive) != nil else {
                return nil
            }

            return PlatformCookieState(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
                expiresAtUnixMs: cookie.expiresDate.map { Int64($0.timeIntervalSince1970 * 1000) }
            )
        }
    }

    private func fetchHomeHTML(in webView: WKWebView) async throws -> String? {
        let value = try await webView.callAsyncJavaScript(
            """
            const response = await fetch("/", {
              method: "GET",
              credentials: "include",
              headers: { "Accept": "text/html" },
              cache: "no-store",
              redirect: "follow"
            });
            return await response.text();
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )

        guard let string = value as? String, !string.isEmpty, string != "null" else {
            return nil
        }
        return string
    }

    private func httpCookies(from store: WKHTTPCookieStore) async throws -> [HTTPCookie] {
        try await withCheckedThrowingContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func clearPlatformLoginCookies(preserveCfClearance: Bool) async throws {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = try await httpCookies(from: store)

        for cookie in cookies where shouldDelete(cookie, preserveCfClearance: preserveCfClearance) {
            await deleteCookie(cookie, from: store)
        }
    }

    private func shouldDelete(_ cookie: HTTPCookie, preserveCfClearance: Bool) -> Bool {
        guard cookie.domain.range(of: "linux.do", options: .caseInsensitive) != nil else {
            return false
        }

        if preserveCfClearance && cookie.name == "cf_clearance" {
            return false
        }

        return ["_t", "_forum_session", "cf_clearance"].contains(cookie.name)
    }

    private func deleteCookie(_ cookie: HTTPCookie, from store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.delete(cookie) {
                continuation.resume()
            }
        }
    }

    private func readStringJavaScript(script: String, in webView: WKWebView) async throws -> String? {
        let value: Any? = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }

        guard let string = value as? String, !string.isEmpty, string != "null" else {
            return nil
        }
        return string
    }

    private func preferredBootstrapHTML(
        browserFetchedHomeHTML: String?,
        currentPageHTML: String?
    ) -> String? {
        FireBootstrapHTMLHeuristics.preferredHTML(
            browserFetchedHomeHTML: browserFetchedHomeHTML,
            currentPageHTML: currentPageHTML
        )
    }

    func loginSyncReadiness(for captured: FireCapturedLoginState) -> FireLoginSyncReadiness {
        let username = captured.username?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUsername = !(username?.isEmpty ?? true)
        let activeCookies = captured.cookies.filter { cookie in
            let value = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && !(cookie.expiresAtUnixMs.map { $0 <= currentUnixMs() } ?? false)
        }
        let hasAuthCookies =
            activeCookies.contains(where: { $0.name == "_t" })
            && activeCookies.contains(where: { $0.name == "_forum_session" })
        let preferredHTML = preferredBootstrapHTML(
            browserFetchedHomeHTML: captured.homeHTML,
            currentPageHTML: nil
        )
        let preferredBootstrapScore = FireBootstrapHTMLHeuristics.score(preferredHTML)
        let hasBootstrapHTML = FireBootstrapHTMLHeuristics.isReusableLoginBootstrap(preferredHTML)
        return FireLoginSyncReadiness(
            isReady: hasUsername && hasAuthCookies && hasBootstrapHTML,
            username: username,
            hasAuthCookies: hasAuthCookies,
            hasBootstrapHTML: hasBootstrapHTML,
            preferredBootstrapScore: preferredBootstrapScore
        )
    }

    private func currentUnixMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
