import Foundation

public enum FireSessionStoreError: Error {
    case missingApplicationSupportDirectory
}

public struct FireCapturedLoginState: Sendable {
    public let currentURL: String?
    public let username: String?
    public let csrfToken: String?
    public let homeHTML: String?
    public let cookies: [PlatformCookieState]

    public init(
        currentURL: String?,
        username: String?,
        csrfToken: String?,
        homeHTML: String?,
        cookies: [PlatformCookieState]
    ) {
        self.currentURL = currentURL
        self.username = username
        self.csrfToken = csrfToken
        self.homeHTML = homeHTML
        self.cookies = cookies
    }
}

public actor FireSessionStore {
    private let core: FireCoreHandle
    private let baseURL: URL
    private let workspacePath: String
    private let sessionFilePath: String
    private let authCookieStore: any FireAuthCookieSecureStore

    public init(
        baseURL: String? = nil,
        workspacePath: String? = nil,
        sessionFilePath: String? = nil,
        fileManager: FileManager = .default,
        authCookieStore: (any FireAuthCookieSecureStore)? = nil
    ) throws {
        let resolvedWorkspacePath = try workspacePath
            ?? sessionFilePath.map {
                URL(fileURLWithPath: $0).deletingLastPathComponent().path
            }
            ?? Self.defaultWorkspacePath(fileManager: fileManager)
        let core = try FireCoreHandle(baseUrl: baseURL, workspacePath: resolvedWorkspacePath)
        let resolvedBaseURL = URL(string: try core.snapshot().bootstrap.baseUrl)
            ?? URL(string: "https://linux.do")!
        let resolvedSessionFilePath = try sessionFilePath
            ?? core.resolveWorkspacePath(relativePath: "session.json")
        self.core = core
        self.baseURL = resolvedBaseURL
        self.workspacePath = resolvedWorkspacePath
        self.sessionFilePath = resolvedSessionFilePath
        self.authCookieStore = authCookieStore ?? FireKeychainAuthCookieStore(baseURL: resolvedBaseURL)
    }

    public func snapshot() throws -> SessionState {
        try core.snapshot()
    }

    public func restorePersistedSessionIfAvailable() throws -> SessionState? {
        guard FileManager.default.fileExists(atPath: sessionFilePath) else {
            return nil
        }
        return try core.loadSessionFromPath(path: sessionFilePath)
    }

    @discardableResult
    public func restoreColdStartSession() async throws -> SessionState {
        _ = try restorePersistedSessionIfAvailable()
        let secureSecrets = try authCookieStore.load()

        if !secureSecrets.isEmpty {
            _ = try applyPlatformCookies(secureSecrets.platformCookies(baseURL: baseURL))
        }

        let current = try core.snapshot()
        if !current.readiness.canReadAuthenticatedApi && shouldDiscardRestoredBootstrap(current) {
            let cleared = try core.logoutLocal(preserveCfClearance: true)
            try persistCurrentSession()
            return cleared
        }

        return try await refreshBootstrapIfNeeded()
    }

    @discardableResult
    public func syncLoginContext(_ captured: FireCapturedLoginState) throws -> SessionState {
        try authCookieStore.save(FireAuthCookieSecrets(platformCookies: captured.cookies))
        let state = try core.syncLoginContext(
            context: LoginSyncState(
                currentUrl: captured.currentURL,
                username: captured.username,
                csrfToken: captured.csrfToken,
                homeHtml: captured.homeHTML,
                cookies: captured.cookies
            )
        )
        try persistCurrentSession()
        return state
    }

    @discardableResult
    public func applyPlatformCookies(_ cookies: [PlatformCookieState]) throws -> SessionState {
        try authCookieStore.save(FireAuthCookieSecrets(platformCookies: cookies))
        let state = try core.applyPlatformCookies(cookies: cookies)
        try persistCurrentSession()
        return state
    }

    @discardableResult
    public func refreshBootstrap() async throws -> SessionState {
        let refreshed = try await core.refreshBootstrap()
        try persistCurrentSession()
        return refreshed
    }

    @discardableResult
    public func refreshBootstrapIfNeeded() async throws -> SessionState {
        let before = try persistedSessionJSON()
        let refreshed = try await core.refreshBootstrapIfNeeded()
        if try persistedSessionJSON() != before {
            try persistCurrentSession()
        }
        return refreshed
    }

    @discardableResult
    public func refreshCsrfTokenIfNeeded() async throws -> SessionState {
        let before = try persistedSessionJSON()
        let refreshed = try await core.refreshCsrfTokenIfNeeded()
        if try persistedSessionJSON() != before {
            try persistCurrentSession()
        }
        return refreshed
    }

    public func persistCurrentSession() throws {
        try core.saveRedactedSessionToPath(path: sessionFilePath)
    }

    public func workspacePathValue() -> String {
        workspacePath
    }

    public func listLogFiles() throws -> [LogFileSummaryState] {
        try core.listLogFiles()
    }

    public func readLogFile(relativePath: String) throws -> LogFileDetailState {
        try core.readLogFile(relativePath: relativePath)
    }

    public func listNetworkTraces(limit: UInt64 = 200) throws -> [NetworkTraceSummaryState] {
        try core.listNetworkTraces(limit: limit)
    }

    public func networkTraceDetail(traceID: UInt64) throws -> NetworkTraceDetailState? {
        try core.networkTraceDetail(traceId: traceID)
    }

    public func exportSessionJSON() throws -> String {
        try persistedSessionJSON()
    }

    public func notificationState() throws -> NotificationCenterState {
        try core.notificationState()
    }

    public func fetchRecentNotifications(limit: UInt32? = nil) async throws -> NotificationListState {
        try await core.fetchRecentNotifications(limit: limit)
    }

    public func fetchNotifications(
        limit: UInt32? = nil,
        offset: UInt32? = nil
    ) async throws -> NotificationListState {
        try await core.fetchNotifications(limit: limit, offset: offset)
    }

    public func markNotificationRead(id: UInt64) async throws -> NotificationCenterState {
        try await core.markNotificationRead(notificationId: id)
    }

    public func markAllNotificationsRead() async throws -> NotificationCenterState {
        try await core.markAllNotificationsRead()
    }

    public func pollNotificationAlertOnce(
        lastMessageId: Int64
    ) async throws -> NotificationAlertPollResultState {
        try await core.pollNotificationAlertOnce(lastMessageId: lastMessageId)
    }

    public func fetchTopicList(query: TopicListQueryState) async throws -> TopicListState {
        try await core.fetchTopicList(query: query)
    }

    public func fetchTopicList(kind: TopicListKindState) async throws -> TopicListState {
        try await fetchTopicList(
            query: TopicListQueryState(
                kind: kind,
                page: nil,
                topicIds: [],
                order: nil,
                ascending: nil
            )
        )
    }

    public func fetchTopicDetail(query: TopicDetailQueryState) async throws -> TopicDetailState {
        try await core.fetchTopicDetail(query: query)
    }

    public func fetchTopicDetail(topicID: UInt64, trackVisit: Bool = true) async throws -> TopicDetailState {
        try await fetchTopicDetail(
            query: TopicDetailQueryState(
                topicId: topicID,
                postNumber: nil,
                trackVisit: trackVisit,
                filter: nil,
                usernameFilters: nil,
                filterTopLevelReplies: false
            )
        )
    }

    public func createReply(
        topicID: UInt64,
        raw: String,
        replyToPostNumber: UInt32?
    ) async throws -> TopicPostState {
        try await core.createReply(
            input: TopicReplyRequestState(
                topicId: topicID,
                raw: raw,
                replyToPostNumber: replyToPostNumber
            )
        )
    }

    public func reportTopicTimings(
        input: TopicTimingsRequestState
    ) async throws {
        try await core.reportTopicTimings(input: input)
    }

    public func likePost(postID: UInt64) async throws {
        try await core.likePost(postId: postID)
    }

    public func unlikePost(postID: UInt64) async throws {
        try await core.unlikePost(postId: postID)
    }

    public func togglePostReaction(
        postID: UInt64,
        reactionID: String
    ) async throws -> PostReactionUpdateState {
        try await core.togglePostReaction(postId: postID, reactionId: reactionID)
    }

    @discardableResult
    public func restoreSessionJSON(_ json: String) throws -> SessionState {
        let state = try core.restoreSessionJson(json: json)
        let restoredSecrets = FireAuthCookieSecrets(cookieState: state.cookies)
        if !restoredSecrets.isEmpty {
            try authCookieStore.save(restoredSecrets)
        }
        try persistCurrentSession()
        return state
    }

    // MARK: - MessageBus

    @discardableResult
    public func startMessageBus(handler: any MessageBusEventHandler) async throws -> String {
        try await core.startMessageBus(mode: .foreground, handler: handler)
    }

    public func stopMessageBus(clearSubscriptions: Bool = false) throws {
        try core.stopMessageBus(clearSubscriptions: clearSubscriptions)
    }

    public func subscribeTopicDetailChannel(topicId: UInt64) throws {
        try core.subscribeChannel(
            subscription: MessageBusSubscriptionState(
                channel: "/topic/\(topicId)",
                lastMessageId: nil,
                scope: .transient
            )
        )
    }

    public func unsubscribeTopicDetailChannel(topicId: UInt64) throws {
        try core.unsubscribeChannel(channel: "/topic/\(topicId)")
    }

    public func subscribeTopicReactionChannel(topicId: UInt64) throws {
        try core.subscribeChannel(
            subscription: MessageBusSubscriptionState(
                channel: "/topic/\(topicId)/reactions",
                lastMessageId: nil,
                scope: .transient
            )
        )
    }

    public func unsubscribeTopicReactionChannel(topicId: UInt64) throws {
        try core.unsubscribeChannel(channel: "/topic/\(topicId)/reactions")
    }

    public func topicReplyPresenceState(topicId: UInt64) throws -> TopicPresenceState {
        try core.topicReplyPresenceState(topicId: topicId)
    }

    public func bootstrapTopicReplyPresence(topicId: UInt64) async throws -> TopicPresenceState {
        try await core.bootstrapTopicReplyPresence(topicId: topicId)
    }

    public func unsubscribeTopicReplyPresenceChannel(topicId: UInt64) throws {
        try core.unsubscribeChannel(channel: "/presence/discourse-presence/reply/\(topicId)")
    }

    public func updateTopicReplyPresence(topicId: UInt64, active: Bool) async throws {
        try await core.updateTopicReplyPresence(topicId: topicId, active: active)
    }

    // MARK: - Logout

    @discardableResult
    public func logout() async throws -> SessionState {
        let current = try core.snapshot()
        if current.readiness.canReadAuthenticatedApi && !current.readiness.hasCurrentUser {
            _ = try await refreshBootstrapIfNeeded()
        }
        let state = try await core.logoutRemote(preserveCfClearance: true)
        try authCookieStore.save(FireAuthCookieSecrets(cookieState: state.cookies))
        try clearPersistedSession()
        return state
    }

    public func clearPersistedSession() throws {
        try core.clearSessionPath(path: sessionFilePath)
    }

    public static func defaultWorkspacePath(fileManager: FileManager = .default) throws -> String {
        guard let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) as URL? else {
            throw FireSessionStoreError.missingApplicationSupportDirectory
        }

        let fireDirectory = directory.appendingPathComponent("Fire", isDirectory: true)
        try fileManager.createDirectory(
            at: fireDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return fireDirectory.path
    }

    public static func defaultSessionFilePath(fileManager: FileManager = .default) throws -> String {
        let workspacePath = try defaultWorkspacePath(fileManager: fileManager)
        return URL(fileURLWithPath: workspacePath)
            .appendingPathComponent("session.json", isDirectory: false)
            .path
    }

    private func shouldDiscardRestoredBootstrap(_ session: SessionState) -> Bool {
        session.readiness.hasCurrentUser
            || session.readiness.hasPreloadedData
            || session.readiness.hasSharedSessionKey
    }

    private func persistedSessionJSON() throws -> String {
        try core.exportRedactedSessionJson()
    }
}
