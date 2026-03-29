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
    private let workspacePath: String
    private let sessionFilePath: String

    public init(
        baseURL: String? = nil,
        workspacePath: String? = nil,
        sessionFilePath: String? = nil,
        fileManager: FileManager = .default
    ) throws {
        let resolvedWorkspacePath = try workspacePath
            ?? sessionFilePath.map {
                URL(fileURLWithPath: $0).deletingLastPathComponent().path
            }
            ?? Self.defaultWorkspacePath(fileManager: fileManager)
        let core = try FireCoreHandle(baseUrl: baseURL, workspacePath: resolvedWorkspacePath)
        let resolvedSessionFilePath = try sessionFilePath
            ?? core.resolveWorkspacePath(relativePath: "session.json")
        self.core = core
        self.workspacePath = resolvedWorkspacePath
        self.sessionFilePath = resolvedSessionFilePath
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
    public func syncLoginContext(_ captured: FireCapturedLoginState) throws -> SessionState {
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
        let current = try core.snapshot()
        let state = try core.applyCookies(
            cookies: CookieState(
                tToken: latestCookieValue(named: "_t", from: cookies) ?? current.cookies.tToken,
                forumSession: latestCookieValue(named: "_forum_session", from: cookies) ?? current.cookies.forumSession,
                cfClearance: latestCookieValue(named: "cf_clearance", from: cookies) ?? current.cookies.cfClearance,
                csrfToken: current.cookies.csrfToken
            )
        )
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
        let current = try core.snapshot()
        let readiness = current.readiness
        let needsBootstrapRefresh = !current.bootstrap.hasPreloadedData
            || !readiness.hasCurrentUser
            || !readiness.hasSharedSessionKey

        guard readiness.canReadAuthenticatedApi, needsBootstrapRefresh else {
            return current
        }

        return try await refreshBootstrap()
    }

    @discardableResult
    public func refreshCsrfTokenIfNeeded() async throws -> SessionState {
        let current = try core.snapshot()
        if current.cookies.csrfToken != nil {
            return current
        }

        let refreshed = try await core.refreshCsrfToken()
        try persistCurrentSession()
        return refreshed
    }

    public func persistCurrentSession() throws {
        try core.saveSessionToPath(path: sessionFilePath)
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
        try core.exportSessionJson()
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

    private func latestCookieValue(
        named name: String,
        from cookies: [PlatformCookieState]
    ) -> String? {
        cookies.last(where: { $0.name == name && !$0.value.isEmpty })?.value
    }

    @discardableResult
    public func restoreSessionJSON(_ json: String) throws -> SessionState {
        let state = try core.restoreSessionJson(json: json)
        try persistCurrentSession()
        return state
    }

    @discardableResult
    public func logout() async throws -> SessionState {
        let current = try core.snapshot()
        if current.readiness.canReadAuthenticatedApi && !current.readiness.hasCurrentUser {
            _ = try await refreshBootstrapIfNeeded()
        }
        let state = try await core.logoutRemote(preserveCfClearance: true)
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
}
