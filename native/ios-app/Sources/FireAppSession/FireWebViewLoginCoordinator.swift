import Foundation
import WebKit

enum FireBootstrapHTMLHeuristics {
    static let reusableLoginBootstrapScoreThreshold = 8

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
        score(html) >= reusableLoginBootstrapScoreThreshold
    }

    private static func nonEmpty(_ html: String?) -> String? {
        guard let html, !html.isEmpty else {
            return nil
        }
        return html
    }
}

enum FireBootstrapHTMLMetadataParser {
    static func currentUsername(from html: String?) -> String? {
        metaContent(named: "current-username", in: html)
    }

    static func csrfToken(from html: String?) -> String? {
        metaContent(named: "csrf-token", in: html)
    }

    private static func metaContent(named name: String, in html: String?) -> String? {
        guard let html, !html.isEmpty else {
            return nil
        }

        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            #"<meta\b[^>]*\bname\s*=\s*["']\#(escapedName)["'][^>]*\bcontent\s*=\s*["']([^"']+)["'][^>]*>"#,
            #"<meta\b[^>]*\bcontent\s*=\s*["']([^"']+)["'][^>]*\bname\s*=\s*["']\#(escapedName)["'][^>]*>"#,
        ]

        for pattern in patterns {
            guard
                let regex = try? NSRegularExpression(
                    pattern: pattern,
                    options: [.caseInsensitive]
                )
            else {
                continue
            }

            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard
                let match = regex.firstMatch(in: html, options: [], range: range),
                match.numberOfRanges > 1,
                let contentRange = Range(match.range(at: 1), in: html)
            else {
                continue
            }

            let content = html[contentRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                return content
            }
        }

        return nil
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
    private let challengeRecoveryCookieCleaner: (@Sendable () async throws -> Void)?
    private var probeHomeFallbackCache: FireLoginProbeHomeFallbackCache?

    public init(sessionStore: FireSessionStore) {
        self.sessionStore = sessionStore
        self.challengeRecoveryCookieCleaner = nil
    }

    init(
        loginSessionStore: any FireLoginSessionStoring,
        challengeRecoveryCookieCleaner: (@Sendable () async throws -> Void)? = nil
    ) {
        self.sessionStore = loginSessionStore
        self.challengeRecoveryCookieCleaner = challengeRecoveryCookieCleaner
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
            if let challengeRecoveryCookieCleaner {
                try? await challengeRecoveryCookieCleaner()
            } else {
                try? await clearChallengeRecoveryCookies()
            }
            throw error
        }
    }

    public func logout() async throws -> SessionState {
        let state = try await sessionStore.logout()
        try await clearSameSitePlatformCookies(preserving: ["cf_clearance"])
        return state
    }

    public func captureLoginState(from webView: WKWebView) async throws -> FireCapturedLoginState {
        let currentURL = webView.url?.absoluteString
        async let username = readCurrentUsername(in: webView)
        async let csrfToken = readCsrfToken(in: webView)
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
        let preferredHomeHTML = preferredBootstrapHTML(
            browserFetchedHomeHTML: capturedHomeHTML,
            currentPageHTML: capturedCurrentPageHTML
        )
        let resolvedUsername =
            capturedUsername ?? FireBootstrapHTMLMetadataParser.currentUsername(from: preferredHomeHTML)
        let resolvedCsrfToken =
            capturedCsrfToken ?? FireBootstrapHTMLMetadataParser.csrfToken(from: preferredHomeHTML)

        return FireCapturedLoginState(
            currentURL: currentURL,
            username: resolvedUsername,
            csrfToken: resolvedCsrfToken,
            homeHTML: preferredHomeHTML,
            browserUserAgent: capturedBrowserUserAgent,
            cookies: capturedCookies
        )
    }

    public func platformCookiesForSessionResync() async throws -> [PlatformCookieState] {
        try await relevantCookies(
            from: WKWebsiteDataStore.default().httpCookieStore
        )
    }

    public func refreshPlatformCookies() async throws -> SessionState {
        let cookies = try await platformCookiesForSessionResync()
        return try await sessionStore.applyPlatformCookies(cookies)
    }

    public func probeLoginSyncReadiness(from webView: WKWebView) async throws -> FireLoginSyncReadiness {
        let currentURL = webView.url?.absoluteString
        async let username = readCurrentUsername(in: webView)
        async let currentPageBootstrapScore = readCurrentPageBootstrapScore(in: webView)
        async let cookies = relevantCookies(from: webView)

        let capturedUsername = try await username
        let capturedCurrentPageBootstrapScore = try await currentPageBootstrapScore
        let capturedCookies = try await cookies

        var resolvedUsername = normalizeUsername(capturedUsername)
        var preferredBootstrapScore = capturedCurrentPageBootstrapScore
        let hasAuthCookies = containsAuthCookies(in: capturedCookies)

        if !hasAuthCookies {
            probeHomeFallbackCache = nil
        } else if shouldProbeHomeFallback(
            in: webView,
            currentPageBootstrapScore: capturedCurrentPageBootstrapScore,
            username: resolvedUsername
        ) {
            if let cachedFallback = probeHomeFallbackCache, cachedFallback.currentURL == currentURL {
                if resolvedUsername == nil {
                    resolvedUsername = cachedFallback.username
                }
                preferredBootstrapScore = max(
                    preferredBootstrapScore,
                    cachedFallback.bootstrapScore
                )
            } else {
                let homeHTML = try await fetchHomeHTML(in: webView)
                let homeBootstrapScore = FireBootstrapHTMLHeuristics.score(homeHTML)
                let homeUsername = FireBootstrapHTMLMetadataParser.currentUsername(from: homeHTML)
                probeHomeFallbackCache = FireLoginProbeHomeFallbackCache(
                    currentURL: currentURL,
                    username: homeUsername,
                    bootstrapScore: homeBootstrapScore
                )
                if resolvedUsername == nil {
                    resolvedUsername = normalizeUsername(homeUsername)
                }
                preferredBootstrapScore = max(preferredBootstrapScore, homeBootstrapScore)
            }
        }

        return loginSyncReadiness(
            username: resolvedUsername,
            cookies: capturedCookies,
            preferredBootstrapScore: preferredBootstrapScore
        )
    }

    public func logoutLocalAndClearPlatformCookies(
        preserveCfClearance: Bool = true
    ) async throws -> SessionState {
        let state = try await sessionStore.logoutLocal(preserveCfClearance: preserveCfClearance)
        try await clearSameSitePlatformCookies(
            preserving: preserveCfClearance ? ["cf_clearance"] : []
        )
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
        guard !webView.isLoading, isLinuxDoHost(webView.url) else {
            return nil
        }

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

    private func clearSameSitePlatformCookies(
        preserving preservedCookieNames: Set<String> = []
    ) async throws {
        try await clearPlatformCookies { cookie in
            isSameSiteCookie(cookie) && !preservedCookieNames.contains(cookie.name)
        }
    }

    private func clearChallengeRecoveryCookies() async throws {
        let targetedNames: Set<String> = ["_t", "_forum_session"]
        try await clearPlatformCookies { cookie in
            isSameSiteCookie(cookie) && targetedNames.contains(cookie.name)
        }
    }

    private func clearPlatformCookies(
        matching shouldDelete: (HTTPCookie) -> Bool
    ) async throws {
        let webKitStore = WKWebsiteDataStore.default().httpCookieStore
        let webKitCookies = try await httpCookies(from: webKitStore)
        for cookie in webKitCookies where shouldDelete(cookie) {
            await deleteCookie(cookie, from: webKitStore)
        }

        for cookie in HTTPCookieStorage.shared.cookies ?? [] where shouldDelete(cookie) {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private func isSameSiteCookie(_ cookie: HTTPCookie) -> Bool {
        cookie.domain.range(of: "linux.do", options: .caseInsensitive) != nil
    }

    private func deleteCookie(_ cookie: HTTPCookie, from store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.delete(cookie) {
                continuation.resume()
            }
        }
    }

    private func readCurrentUsername(in webView: WKWebView) async throws -> String? {
        try await readStringJavaScript(
            script: """
            (function() {
              try {
                var meta = document.querySelector('meta[name="current-username"]');
                if (meta && meta.content) return meta.content;
                if (
                  typeof Discourse !== 'undefined'
                  && Discourse.User
                  && typeof Discourse.User.current === 'function'
                ) {
                  var currentUser = Discourse.User.current();
                  if (currentUser && currentUser.username) return currentUser.username;
                }
              } catch (error) {}
              return null;
            })();
            """,
            in: webView
        )
    }

    private func readCsrfToken(in webView: WKWebView) async throws -> String? {
        try await readStringJavaScript(
            script: """
            (function() {
              var meta = document.querySelector('meta[name="csrf-token"]');
              if (meta && meta.content) return meta.content;
              return null;
            })();
            """,
            in: webView
        )
    }

    private func readCurrentPageBootstrapScore(in webView: WKWebView) async throws -> Int {
        try await readIntJavaScript(
            script: """
            (function() {
              try {
                var score = 0;
                if (document.querySelector('#data-discourse-setup,[data-preloaded]')) score += 8;
                if (document.querySelector('meta[name="shared_session_key"]')) score += 4;
                if (document.querySelector('meta[name="current-username"]')) score += 2;
                if (document.querySelector('meta[name="csrf-token"]')) score += 1;
                return score;
              } catch (error) {
                return 0;
              }
            })();
            """,
            in: webView
        ) ?? 0
    }

    private func readStringJavaScript(script: String, in webView: WKWebView) async throws -> String? {
        let value = try await evaluateJavaScript(script: script, in: webView)

        guard let string = value as? String, !string.isEmpty, string != "null" else {
            return nil
        }
        return string
    }

    private func readIntJavaScript(script: String, in webView: WKWebView) async throws -> Int? {
        let value = try await evaluateJavaScript(script: script, in: webView)

        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private func evaluateJavaScript(script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
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
        let preferredHTML = preferredBootstrapHTML(
            browserFetchedHomeHTML: captured.homeHTML,
            currentPageHTML: nil
        )
        return loginSyncReadiness(
            username: captured.username,
            cookies: captured.cookies,
            preferredBootstrapScore: FireBootstrapHTMLHeuristics.score(preferredHTML)
        )
    }

    func loginSyncReadiness(
        username: String?,
        cookies: [PlatformCookieState],
        preferredBootstrapScore: Int
    ) -> FireLoginSyncReadiness {
        let normalizedUsername = normalizeUsername(username)
        let hasUsername = !(normalizedUsername?.isEmpty ?? true)
        let hasAuthCookies = containsAuthCookies(in: cookies)
        let hasBootstrapHTML =
            preferredBootstrapScore >= FireBootstrapHTMLHeuristics.reusableLoginBootstrapScoreThreshold

        return FireLoginSyncReadiness(
            isReady: hasUsername && hasAuthCookies && hasBootstrapHTML,
            username: normalizedUsername,
            hasAuthCookies: hasAuthCookies,
            hasBootstrapHTML: hasBootstrapHTML,
            preferredBootstrapScore: preferredBootstrapScore
        )
    }

    private func shouldProbeHomeFallback(
        in webView: WKWebView,
        currentPageBootstrapScore: Int,
        username: String?
    ) -> Bool {
        guard !webView.isLoading, isLinuxDoHost(webView.url) else {
            return false
        }

        return username == nil
            || currentPageBootstrapScore < FireBootstrapHTMLHeuristics.reusableLoginBootstrapScoreThreshold
    }

    private func normalizeUsername(_ username: String?) -> String? {
        let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }

    private func containsAuthCookies(in cookies: [PlatformCookieState]) -> Bool {
        let activeCookies = cookies.filter { cookie in
            let value = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && !(cookie.expiresAtUnixMs.map { $0 <= currentUnixMs() } ?? false)
        }

        return activeCookies.contains(where: { $0.name == "_t" })
            && activeCookies.contains(where: { $0.name == "_forum_session" })
    }

    private func isLinuxDoHost(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else {
            return false
        }

        return host == "linux.do" || host.hasSuffix(".linux.do")
    }

    private func currentUnixMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

private struct FireLoginProbeHomeFallbackCache {
    let currentURL: String?
    let username: String?
    let bootstrapScore: Int
}
