import Foundation

extension SessionState {
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
                hasPreloadedData: false
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
            hasLoginSession: false
        )
    }

    var profileDisplayName: String {
        if let currentUsername = bootstrap.currentUsername, !currentUsername.isEmpty {
            return currentUsername
        }
        if readiness.canReadAuthenticatedApi || hasLoginSession {
            return "会话已连接"
        }
        return "未登录"
    }

    var profileStatusTitle: String {
        if readiness.canReadAuthenticatedApi && !readiness.hasCurrentUser {
            return "账号信息同步中"
        }
        return loginPhase.title
    }
}

extension LoginPhaseState {
    var title: String {
        switch self {
        case .anonymous:
            return "未登录"
        case .cookiesCaptured:
            return "Cookie 已同步"
        case .bootstrapCaptured:
            return "会话初始化中"
        case .ready:
            return "已就绪"
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
