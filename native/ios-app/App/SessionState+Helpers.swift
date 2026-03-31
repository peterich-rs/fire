import Foundation

extension SessionState {
    private static let mirroredCookieNames: [String] = ["_t", "_forum_session", "cf_clearance"]

    static func placeholder(baseUrl: String = "https://linux.do") -> SessionState {
        SessionState(
            cookies: CookieState(
                tToken: nil,
                forumSession: nil,
                cfClearance: nil,
                csrfToken: nil
            ),
            bootstrap: BootstrapState(
                baseUrl: baseUrl,
                discourseBaseUri: nil,
                sharedSessionKey: nil,
                currentUsername: nil,
                longPollingBaseUrl: nil,
                turnstileSitekey: nil,
                topicTrackingStateMeta: nil,
                preloadedJson: nil,
                hasPreloadedData: false,
                categories: [],
                enabledReactionIds: ["heart"],
                minPostLength: 1
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

    func mirrorCookiesToNativeStorage() {
        let cookieStorage = HTTPCookieStorage.shared
        let host = baseURL.host ?? "linux.do"

        for existingCookie in cookieStorage.cookies ?? [] {
            guard Self.mirroredCookieNames.contains(existingCookie.name) else {
                continue
            }
            guard existingCookie.domain == host || existingCookie.domain.hasSuffix(".\(host)") else {
                continue
            }
            cookieStorage.deleteCookie(existingCookie)
        }

        for cookie in bridgedCookies(host: host) {
            cookieStorage.setCookie(cookie)
        }
    }

    private func bridgedCookies(host: String) -> [HTTPCookie] {
        [
            ("_t", cookies.tToken),
            ("_forum_session", cookies.forumSession),
            ("cf_clearance", cookies.cfClearance),
        ].compactMap { name, value in
            guard let value, !value.isEmpty else {
                return nil
            }

            return HTTPCookie(properties: [
                .name: name,
                .value: value,
                .domain: host,
                .path: "/",
                .secure: baseURL.scheme?.lowercased() == "https",
            ])
        }
    }
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
            return "Latest"
        case .new:
            return "New"
        case .unread:
            return "Unread"
        case .unseen:
            return "Unseen"
        case .hot:
            return "Hot"
        case .top:
            return "Top"
        }
    }
}
