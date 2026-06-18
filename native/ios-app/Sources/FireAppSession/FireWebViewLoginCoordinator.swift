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

enum FireWebViewCookieActionSupport {
    static func webViewCookieInfo(_ cookie: HTTPCookie) -> WebViewCookieInfoState {
        WebViewCookieInfoState(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path,
            hostOnly: !cookie.domain.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("."),
            secure: cookie.isSecure,
            httpOnly: cookie.isHTTPOnly,
            sameSite: sameSitePolicy(from: cookie) ?? inferredSameSitePolicy(forName: cookie.name),
            expiresAtUnixMs: cookie.expiresDate.map { Int64($0.timeIntervalSince1970 * 1000) }
        )
    }

    static func cookies(fromSetCookieHeader setCookie: String, urlString: String) throws -> [HTTPCookie] {
        guard let url = URL(string: urlString) else {
            throw FireWebViewCookieActionSupportError.invalidCookieURL(urlString)
        }
        return HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": setCookie], for: url)
    }

    static func matchesExactDelete(
        _ cookie: HTTPCookie,
        url: URL?,
        name: String,
        domain: String?,
        path: String
    ) -> Bool {
        guard cookie.name == name else {
            return false
        }
        let normalizedPath = path.isEmpty ? "/" : path
        guard cookie.path == normalizedPath else {
            return false
        }
        if let domain, !domain.isEmpty {
            return normalizedDomain(cookie.domain) == normalizedDomain(domain)
        }
        return url.map { applies(cookie, to: $0) } ?? true
    }

    static func matchesDeleteByName(
        _ cookie: HTTPCookie,
        url: URL?,
        name: String
    ) -> Bool {
        cookie.name == name && (url.map { applies(cookie, to: $0) } ?? true)
    }

    static func applies(_ cookie: HTTPCookie, to url: URL) -> Bool {
        guard let host = url.host?.lowercased(), domainMatches(cookie.domain, host: host) else {
            return false
        }
        let urlPath = url.path.isEmpty ? "/" : url.path
        let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
        return urlPath == cookiePath || urlPath.hasPrefix(cookiePath.hasSuffix("/") ? cookiePath : "\(cookiePath)/")
    }

    private static func sameSitePolicy(from cookie: HTTPCookie) -> CookieSameSiteState? {
        guard
            let raw = cookie.properties?[HTTPCookiePropertyKey("SameSite")] as? String
                ?? cookie.properties?[HTTPCookiePropertyKey("sameSite")] as? String
        else {
            return nil
        }

        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "lax":
            return .lax
        case "strict":
            return .strict
        case "none":
            return CookieSameSiteState.none
        default:
            return .unspecified
        }
    }

    private static func inferredSameSitePolicy(forName name: String) -> CookieSameSiteState? {
        name == "cf_clearance" ? CookieSameSiteState.none : nil
    }

    private static func domainMatches(_ cookieDomain: String, host: String) -> Bool {
        let normalized = normalizedDomain(cookieDomain)
        return host == normalized || host.hasSuffix(".\(normalized)")
    }

    private static func normalizedDomain(_ domain: String) -> String {
        let normalized = domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized.hasPrefix(".") else {
            return normalized
        }
        return String(normalized.dropFirst())
    }
}

enum FireWebViewCookieActionSupportError: LocalizedError {
    case invalidCookieURL(String)

    var errorDescription: String? {
        switch self {
        case let .invalidCookieURL(url):
            return "Invalid cookie action URL: \(url)"
        }
    }
}

protocol FireLoginSessionStoring: Sendable {
    func currentSessionSnapshot() async throws -> SessionState
    func restorePersistedSessionIfAvailable() async throws -> SessionState?
    func finalizeLoginFromWebView(
        _ captured: FireCapturedLoginState,
        allowLowConfidenceSessionCookies: Bool
    ) async throws -> LoginFinalizationResultState
    func syncLoginContext(_ captured: FireCapturedLoginState) async throws -> SessionState
    func refreshBootstrapIfNeeded() async throws -> SessionState
    func refreshCsrfTokenIfNeeded() async throws -> SessionState
    func logout() async throws -> SessionState
    func logoutLocal(preserveCfClearance: Bool) async throws -> SessionState
    func applyPlatformCookies(_ cookies: [PlatformCookieState]) async throws -> SessionState
    func completeCloudflareChallenge(
        cookies: [PlatformCookieState],
        freshCfClearance: String,
        browserUserAgent: String?
    ) async throws -> SessionState
    func webViewPrimingPayload(targetURL: String?) async throws -> [WebViewCookieActionState]
    func cookieSweepPlan(
        targetURL: String?,
        name: String,
        webViewCookies: [WebViewCookieInfoState]
    ) async throws -> CookieSweepPlanState
    func cookieNuclearResetPlan(
        targetURL: String?,
        webViewCookies: [WebViewCookieInfoState]
    ) async throws -> NuclearResetPlanState
    func commitCookieSweepResult(
        targetURL: String?,
        name: String,
        intent: CookieSweepIntentState,
        webViewCookies: [WebViewCookieInfoState]
    ) async throws -> SessionState
}

extension FireSessionStore: FireLoginSessionStoring {
    func currentSessionSnapshot() async throws -> SessionState {
        try snapshot()
    }
}

@MainActor
public final class FireWebViewLoginCoordinator {
    private static let defaultLoginURL = URL(string: "https://linux.do/")!
    private static let sessionCookieNames = ["_t", "_forum_session", "cf_clearance", "_cfuvid"]

    private let sessionStore: any FireLoginSessionStoring

    public init(sessionStore: FireSessionStore) {
        self.sessionStore = sessionStore
    }

    init(
        loginSessionStore: any FireLoginSessionStoring
    ) {
        self.sessionStore = loginSessionStore
    }

    public func restorePersistedSessionIfAvailable() async throws -> SessionState? {
        try await sessionStore.restorePersistedSessionIfAvailable()
    }

    public func completeLogin(
        from webView: WKWebView
    ) async throws -> SessionState {
        let captured = try await captureLoginState(from: webView)
        let readiness = loginSyncReadiness(for: captured)
        guard readiness.isReady else {
            throw FireWebViewLoginCoordinatorError.loginSyncNotReady(readiness)
        }
        return try await completeLogin(captured)
    }

    func completeLogin(
        _ captured: FireCapturedLoginState
    ) async throws -> SessionState {
        let finalized = try await sessionStore.finalizeLoginFromWebView(
            captured,
            allowLowConfidenceSessionCookies: false
        )
        if finalized.session.loginPhase == .ready {
            return finalized.session
        }

        return try await sessionStore.refreshBootstrapIfNeeded()
    }

    public func completeJsLogin(
        from webView: WKWebView,
        identifier: String
    ) async throws -> SessionState {
        let captured = FireCapturedLoginState(
            currentURL: webView.url?.absoluteString,
            username: identifier,
            csrfToken: nil,
            homeHTML: nil,
            browserUserAgent: try await readStringJavaScript(
                script: "navigator.userAgent",
                in: webView
            ),
            cookies: try await relevantCookies(from: webView)
        )
        return try await completeLogin(captured)
    }

    public func logout() async throws -> SessionState {
        let state: SessionState
        do {
            state = try await sessionStore.logout()
        } catch {
            state = try await sessionStore.logoutLocal(preserveCfClearance: true)
        }
        try await clearSameSitePlatformCookies(preserving: ["cf_clearance"])
        return state
    }

    public func captureLoginState(from webView: WKWebView) async throws -> FireCapturedLoginState {
        let currentURL = webView.url?.absoluteString
        async let username = readCurrentUsername(in: webView)
        async let csrfToken = readCsrfToken(in: webView)
        async let preloadedHTML = readStringJavaScript(
            script: FireLoginScripts.readPreloadedData,
            in: webView
        )
        async let browserUserAgent = readStringJavaScript(
            script: "navigator.userAgent",
            in: webView
        )
        async let cookies = relevantCookies(from: webView)

        let capturedUsername = try await username
        let capturedCsrfToken = try await csrfToken
        let capturedPreloadedHTML = try await preloadedHTML
        let capturedBrowserUserAgent = try await browserUserAgent
        let capturedCookies = try await cookies
        let resolvedUsername =
            capturedUsername
            ?? FireBootstrapHTMLMetadataParser.currentUsername(from: capturedPreloadedHTML)
        let resolvedCsrfToken =
            capturedCsrfToken
            ?? FireBootstrapHTMLMetadataParser.csrfToken(from: capturedPreloadedHTML)

        return FireCapturedLoginState(
            currentURL: currentURL,
            username: resolvedUsername,
            csrfToken: resolvedCsrfToken,
            homeHTML: capturedPreloadedHTML,
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
        return try await applyPlatformCookiesIfAuthoritative(cookies)
    }

    public func completeCloudflareChallenge(
        cookies: [PlatformCookieState],
        freshCfClearance: String,
        browserUserAgent: String? = nil
    ) async throws -> SessionState {
        try await sessionStore.completeCloudflareChallenge(
            cookies: cookies,
            freshCfClearance: freshCfClearance,
            browserUserAgent: browserUserAgent
        )
    }

    public func primeCookies(
        into webView: WKWebView,
        targetURL: URL? = nil
    ) async throws {
        let resolvedURL = targetURL ?? webView.url ?? Self.defaultLoginURL
        let actions = try await sessionStore.webViewPrimingPayload(
            targetURL: resolvedURL.absoluteString
        )
        try await executeCookieActions(
            actions,
            in: webView.configuration.websiteDataStore.httpCookieStore
        )
    }

    @discardableResult
    public func sweepCookies(
        in webView: WKWebView,
        names: [String]? = nil,
        targetURL: URL? = nil
    ) async throws -> [CookieSweepPlanState] {
        let resolvedURL = targetURL ?? webView.url ?? Self.defaultLoginURL
        return try await sweepCookies(
            in: webView.configuration.websiteDataStore.httpCookieStore,
            names: names,
            targetURL: resolvedURL
        )
    }

    @discardableResult
    public func sweepCookies(
        names: [String]? = nil,
        targetURL: URL? = nil
    ) async throws -> [CookieSweepPlanState] {
        try await sweepCookies(
            in: WKWebsiteDataStore.default().httpCookieStore,
            names: names,
            targetURL: targetURL ?? Self.defaultLoginURL
        )
    }

    private func sweepCookies(
        in store: WKHTTPCookieStore,
        names: [String]? = nil,
        targetURL resolvedURL: URL
    ) async throws -> [CookieSweepPlanState] {
        let cookieInfos = try await webViewCookieInfos(
            from: store
        )
        let targetNames = names ?? Self.sessionCookieNames
        var plans: [CookieSweepPlanState] = []
        for name in targetNames {
            let plan = try await sessionStore.cookieSweepPlan(
                targetURL: resolvedURL.absoluteString,
                name: name,
                webViewCookies: cookieInfos
            )
            try await executeCookieActions(
                plan.actions,
                in: store
            )
            _ = try await sessionStore.commitCookieSweepResult(
                targetURL: resolvedURL.absoluteString,
                name: name,
                intent: plan.intent,
                webViewCookies: try await webViewCookieInfos(
                    from: store
                )
            )
            plans.append(plan)
        }
        return plans
    }

    public func nuclearResetCookies(
        in webView: WKWebView,
        targetURL: URL? = nil
    ) async throws {
        let resolvedURL = targetURL ?? webView.url ?? Self.defaultLoginURL
        try await nuclearResetCookies(
            in: webView.configuration.websiteDataStore.httpCookieStore,
            targetURL: resolvedURL
        )
    }

    public func nuclearResetCookies(
        targetURL: URL? = nil
    ) async throws {
        try await nuclearResetCookies(
            in: WKWebsiteDataStore.default().httpCookieStore,
            targetURL: targetURL ?? Self.defaultLoginURL
        )
    }

    private func nuclearResetCookies(
        in store: WKHTTPCookieStore,
        targetURL resolvedURL: URL
    ) async throws {
        let plan = try await sessionStore.cookieNuclearResetPlan(
            targetURL: resolvedURL.absoluteString,
            webViewCookies: try await webViewCookieInfos(
                from: store
            )
        )
        try await executeCookieActions(
            plan.actions,
            in: store
        )
        let committedCookies = try await webViewCookieInfos(
            from: store
        )
        for name in Self.sessionCookieNames {
            _ = try await sessionStore.commitCookieSweepResult(
                targetURL: resolvedURL.absoluteString,
                name: name,
                intent: CookieSweepIntentState.ensureUnique,
                webViewCookies: committedCookies
            )
        }
    }

    public func webViewCookieInfos(from webView: WKWebView) async throws -> [WebViewCookieInfoState] {
        try await webViewCookieInfos(from: webView.configuration.websiteDataStore.httpCookieStore)
    }

    func executeCookieActions(
        _ actions: [WebViewCookieActionState],
        in store: WKHTTPCookieStore
    ) async throws {
        guard !actions.isEmpty else {
            return
        }

        for action in actions {
            switch action {
            case let .setRaw(url: urlString, setCookie: setCookie):
                try await setRawCookie(setCookie, urlString: urlString, in: store)
            case let .deleteExact(url: urlString, name: name, domain: domain, path: path):
                try await deleteExactCookie(
                    urlString: urlString,
                    name: name,
                    domain: domain,
                    path: path,
                    from: store
                )
            case let .deleteByName(url: urlString, name: name):
                try await deleteCookiesByName(
                    urlString: urlString,
                    name: name,
                    from: store
                )
            }
        }
    }

    func applyPlatformCookiesIfAuthoritative(
        _ cookies: [PlatformCookieState]
    ) async throws -> SessionState {
        guard Self.containsActiveAuthCookies(in: cookies) else {
            return try await sessionStore.currentSessionSnapshot()
        }
        return try await sessionStore.applyPlatformCookies(cookies)
    }

    public func probeLoginSyncReadiness(from webView: WKWebView) async throws -> FireLoginSyncReadiness {
        async let username = readCurrentUsername(in: webView)
        async let preloadedHTML = readStringJavaScript(
            script: FireLoginScripts.readPreloadedData,
            in: webView
        )
        async let cookies = relevantCookies(from: webView)

        let capturedUsername = try await username
        let capturedPreloadedHTML = try await preloadedHTML
        let capturedCookies = try await cookies
        return loginSyncReadiness(
            username: capturedUsername
                ?? FireBootstrapHTMLMetadataParser.currentUsername(from: capturedPreloadedHTML),
            cookies: capturedCookies,
            preferredBootstrapScore: FireBootstrapHTMLHeuristics.score(capturedPreloadedHTML)
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

    private func webViewCookieInfos(
        from store: WKHTTPCookieStore
    ) async throws -> [WebViewCookieInfoState] {
        try await httpCookies(from: store)
            .filter { cookie in
                isSameSiteCookie(cookie) && isActiveCookie(cookie)
            }
            .map(FireWebViewCookieActionSupport.webViewCookieInfo)
    }

    private func relevantCookies(from store: WKHTTPCookieStore) async throws -> [PlatformCookieState] {
        let allCookies = try await httpCookies(from: store)
        var relevant: [PlatformCookieState] = []
        for cookie in allCookies {
            guard cookie.domain.range(of: "linux.do", options: .caseInsensitive) != nil else {
                continue
            }
            guard isActiveCookie(cookie) else {
                continue
            }

            relevant.append(
                PlatformCookieState(
                    name: cookie.name,
                    value: cookie.value,
                    domain: cookie.domain,
                    path: cookie.path,
                    expiresAtUnixMs: cookie.expiresDate.map { Int64($0.timeIntervalSince1970 * 1000) },
                    sameSite: nil
                )
            )
        }
        return relevant
    }

    private func isActiveCookie(_ cookie: HTTPCookie) -> Bool {
        let normalizedValue = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else {
            return false
        }
        guard let expiresDate = cookie.expiresDate else {
            return true
        }
        return expiresDate > Date()
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

    private func setRawCookie(
        _ rawSetCookie: String,
        urlString: String,
        in store: WKHTTPCookieStore
    ) async throws {
        let cookies = try FireWebViewCookieActionSupport.cookies(
            fromSetCookieHeader: rawSetCookie,
            urlString: urlString
        )
        for cookie in cookies {
            await setCookie(cookie, in: store)
        }
    }

    private func setCookie(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    private func deleteExactCookie(
        urlString: String,
        name: String,
        domain: String?,
        path: String,
        from store: WKHTTPCookieStore
    ) async throws {
        let url = URL(string: urlString)
        let cookies = try await httpCookies(from: store)
        for cookie in cookies where FireWebViewCookieActionSupport.matchesExactDelete(
            cookie,
            url: url,
            name: name,
            domain: domain,
            path: path
        ) {
            await deleteCookie(cookie, from: store)
        }
    }

    private func deleteCookiesByName(
        urlString: String,
        name: String,
        from store: WKHTTPCookieStore
    ) async throws {
        let url = URL(string: urlString)
        let cookies = try await httpCookies(from: store)
        for cookie in cookies where FireWebViewCookieActionSupport.matchesDeleteByName(
            cookie,
            url: url,
            name: name
        ) {
            await deleteCookie(cookie, from: store)
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

    func loginSyncReadiness(for captured: FireCapturedLoginState) -> FireLoginSyncReadiness {
        return loginSyncReadiness(
            username: captured.username,
            cookies: captured.cookies,
            preferredBootstrapScore: FireBootstrapHTMLHeuristics.score(captured.homeHTML)
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

    private func normalizeUsername(_ username: String?) -> String? {
        let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }

    nonisolated static func containsActiveAuthCookies(
        in cookies: [PlatformCookieState]
    ) -> Bool {
        let activeCookies = cookies.filter { cookie in
            let value = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && !(cookie.expiresAtUnixMs.map { $0 <= currentUnixMs() } ?? false)
        }

        return activeCookies.contains(where: { $0.name == "_t" })
            && activeCookies.contains(where: { $0.name == "_forum_session" })
    }

    private func containsAuthCookies(in cookies: [PlatformCookieState]) -> Bool {
        Self.containsActiveAuthCookies(in: cookies)
    }

    private func isLinuxDoHost(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else {
            return false
        }

        return host == "linux.do" || host.hasSuffix(".linux.do")
    }

    private nonisolated static func currentUnixMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
