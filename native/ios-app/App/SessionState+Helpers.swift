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
}

extension LoginPhaseState {
    var title: String {
        switch self {
        case .anonymous:
            return "Anonymous"
        case .cookiesCaptured:
            return "Cookies Captured"
        case .bootstrapCaptured:
            return "Bootstrap Captured"
        case .ready:
            return "Ready"
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
