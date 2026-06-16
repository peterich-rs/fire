import Foundation

extension SessionState {
    private static let mirroredCookieNames: Set<String> = ["_t", "_forum_session", "cf_clearance"]

    static func placeholder(baseUrl: String = "https://linux.do") -> SessionState {
        SessionState(
            cookies: CookieState(
                tToken: nil,
                forumSession: nil,
                cfClearance: nil,
                csrfToken: nil,
                platformCookies: [],
                canonicalCookies: []
            ),
            bootstrap: BootstrapState(
                baseUrl: baseUrl,
                discourseBaseUri: nil,
                sharedSessionKey: nil,
                currentUsername: nil,
                currentUserId: nil,
                notificationChannelPosition: nil,
                longPollingBaseUrl: nil,
                turnstileSitekey: nil,
                topicTrackingStateMeta: nil,
                preloadedJson: nil,
                hasPreloadedData: false,
                hasSiteMetadata: false,
                topTags: [],
                canTagTopics: false,
                categories: [],
                hasSiteSettings: false,
                enabledReactionIds: ["heart"],
                minPostLength: 1,
                minTopicTitleLength: 15,
                minFirstPostLength: 20,
                minPersonalMessageTitleLength: 2,
                minPersonalMessagePostLength: 10,
                defaultComposerCategory: nil
            ),
            readiness: SessionReadinessState(
                hasLoginCookie: false,
                hasForumSession: false,
                hasCloudflareClearance: false,
                hasCsrfToken: false,
                hasCurrentUser: false,
                hasPreloadedData: false,
                hasSharedSessionKey: false,
                canReadAuthenticatedApi: false,
                canWriteAuthenticatedApi: false,
                canOpenMessageBus: false
            ),
            loginPhase: .anonymous,
            hasLoginSession: false,
            browserUserAgent: nil,
            profileDisplayName: "未登录",
            loginPhaseLabel: "未登录"
        )
    }

    var profileStatusTitle: String {
        loginPhaseLabel
    }

    var baseURL: URL {
        URL(string: bootstrap.baseUrl) ?? URL(string: "https://linux.do")!
    }

    @MainActor
    func syncCookiesToNativeStorage() {
        let host = baseURL.host ?? "linux.do"
        let batch = bridgedCookieBatch(host: host)

        // Keep URLSession/media requests aligned with the current Rust session
        // without writing cookies back into the WebKit browser store.
        syncCookiesToSharedStorage(
            batch.cookies,
            host: host,
            fullSameSiteScope: batch.usesFullSameSiteScope
        )
    }

    @MainActor
    private func syncCookiesToSharedStorage(
        _ cookies: [HTTPCookie],
        host: String,
        fullSameSiteScope: Bool
    ) {
        let cookieStorage = HTTPCookieStorage.shared

        for existingCookie in cookieStorage.cookies ?? [] {
            guard Self.shouldMirror(existingCookie, host: host, fullSameSiteScope: fullSameSiteScope) else {
                continue
            }
            cookieStorage.deleteCookie(existingCookie)
        }

        for cookie in cookies {
            cookieStorage.setCookie(cookie)
        }
    }

    private func bridgedCookieBatch(host: String) -> NativeCookieBatch {
        let secure = baseURL.scheme?.lowercased() == "https"
        let platformCookies = cookies.platformCookies
            .filter { Self.shouldBridgePlatformCookie($0, host: host) }
            .compactMap { cookie in
                Self.makeCookie(
                    name: cookie.name,
                    value: cookie.value,
                    domain: cookie.domain ?? host,
                    path: cookie.path ?? "/",
                    expiresAtUnixMs: cookie.expiresAtUnixMs,
                    secure: secure,
                    originURL: baseURL
                )
            }
        let usesFullSameSiteScope = !platformCookies.isEmpty

        let sortedCookies = platformCookies.sorted {
            let lhs = Self.cookieDescriptor($0)
            let rhs = Self.cookieDescriptor($1)
            return lhs < rhs
        }

        return NativeCookieBatch(
            cookies: sortedCookies,
            usesFullSameSiteScope: usesFullSameSiteScope
        )
    }

    private static func shouldBridgePlatformCookie(
        _ cookie: PlatformCookieState,
        host: String
    ) -> Bool {
        let normalizedValue = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else {
            return false
        }
        if let expiresAtUnixMs = cookie.expiresAtUnixMs, expiresAtUnixMs <= currentUnixMs() {
            return false
        }

        return sameSiteDomainMatches(cookie.domain ?? host, host: host)
    }

    private static func shouldMirror(
        _ cookie: HTTPCookie,
        host: String,
        fullSameSiteScope: Bool
    ) -> Bool {
        if !fullSameSiteScope && !mirroredCookieNames.contains(cookie.name) {
            return false
        }

        return sameSiteDomainMatches(cookie.domain, host: host)
    }

    private static func sameSiteDomainMatches(_ domain: String, host: String) -> Bool {
        let normalizedHost = normalizeDomain(host)
        let normalizedDomain = normalizeDomain(domain)
        return normalizedDomain == normalizedHost
            || normalizedDomain.hasSuffix(".\(normalizedHost)")
    }

    private static func currentUnixMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func normalizeDomain(_ domain: String) -> String {
        let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix(".") {
            return String(normalized.dropFirst())
        }
        return normalized
    }

    private static func makeCookie(
        name: String,
        value: String,
        domain: String,
        path: String,
        expiresAtUnixMs: Int64?,
        secure: Bool,
        originURL: URL
    ) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .originURL: originURL,
        ]
        if secure {
            properties[.secure] = true
        }
        if let expiresAtUnixMs {
            properties[.expires] = Date(timeIntervalSince1970: TimeInterval(expiresAtUnixMs) / 1000)
        }
        return HTTPCookie(properties: properties)
    }

    private static func cookieDescriptors(_ cookies: [HTTPCookie]) -> [String] {
        cookies.map(cookieDescriptor).sorted()
    }

    private static func cookieDescriptor(_ cookie: HTTPCookie) -> String {
        let expiry = cookie.expiresDate.map { Int64($0.timeIntervalSince1970 * 1000) }
            .map(String.init) ?? "session"
        return "\(cookie.name)|\(normalizeDomain(cookie.domain))|\(cookie.path)|\(cookie.value)|\(expiry)"
    }

}

private struct NativeCookieBatch {
    let cookies: [HTTPCookie]
    let usesFullSameSiteScope: Bool
}

extension TopicListKindState {
    static let orderedCases: [TopicListKindState] = [
        .latest,
        .new,
        .unread,
        .unseen,
        .hot,
        .top,
    ]

    var title: String {
        switch self {
        case .latest:
            return "最新"
        case .new:
            return "最新发布"
        case .unread:
            return "未读"
        case .unseen:
            return "未看"
        case .hot:
            return "热门"
        case .top:
            return "精华"
        case .privateMessagesInbox:
            return "收件箱"
        case .privateMessagesSent:
            return "已发送"
        }
    }
}
