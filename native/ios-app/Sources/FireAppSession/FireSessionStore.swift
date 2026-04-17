import Foundation

public enum FireSessionStoreError: Error {
    case missingApplicationSupportDirectory
}

public struct FireCapturedLoginState: Sendable {
    public let currentURL: String?
    public let username: String?
    public let csrfToken: String?
    public let homeHTML: String?
    public let browserUserAgent: String?
    public let cookies: [PlatformCookieState]

    public init(
        currentURL: String?,
        username: String?,
        csrfToken: String?,
        homeHTML: String?,
        browserUserAgent: String?,
        cookies: [PlatformCookieState]
    ) {
        self.currentURL = currentURL
        self.username = username
        self.csrfToken = csrfToken
        self.homeHTML = homeHTML
        self.browserUserAgent = browserUserAgent
        self.cookies = cookies
    }
}

public struct FireHostLogger: Sendable {
    private let target: String
    private let writeEntry: @Sendable (HostLogLevelState, String, String) -> Void

    fileprivate init(
        target: String,
        writeEntry: @escaping @Sendable (HostLogLevelState, String, String) -> Void
    ) {
        self.target = target
        self.writeEntry = writeEntry
    }

    public func debug(_ message: @autoclosure () -> String) {
        writeEntry(.debug, target, message())
    }

    public func info(_ message: @autoclosure () -> String) {
        writeEntry(.info, target, message())
    }

    public func notice(_ message: @autoclosure () -> String) {
        writeEntry(.info, target, message())
    }

    public func warning(_ message: @autoclosure () -> String) {
        writeEntry(.warn, target, message())
    }

    public func error(_ message: @autoclosure () -> String) {
        writeEntry(.error, target, message())
    }
}

private struct FirePersistedSessionArtifacts: Equatable {
    let sessionJSON: String
    let secureSecrets: FireAuthCookieSecrets
}

public actor FireSessionStore {
    nonisolated private let core: FireAppCore
    private let baseURL: URL
    private let workspacePath: String
    private let sessionFilePath: String
    private let authCookieStore: any FireAuthCookieSecureStore
    // Keep blocking diagnostics IO off elevated Swift concurrency executors.
    private let diagnosticsQueue = DispatchQueue(
        label: "com.fire.session-store.diagnostics",
        qos: .utility
    )

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
        let core = try FireAppCore(baseUrl: baseURL, workspacePath: resolvedWorkspacePath)
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
        try await restoreColdStartSession(
            refreshBootstrapIfNeeded: {
                try await self.refreshBootstrapIfNeeded()
            },
            refreshCsrfTokenIfNeeded: {
                try await self.refreshCsrfTokenIfNeeded()
            }
        )
    }

    @discardableResult
    func restoreColdStartSession(
        refreshBootstrapIfNeeded: () async throws -> SessionState,
        refreshCsrfTokenIfNeeded: () async throws -> SessionState
    ) async throws -> SessionState {
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

        let restored = try await refreshBootstrapIfNeeded()
        if shouldRefreshCsrfAfterColdStartRestore(restored) {
            return try await refreshCsrfTokenIfNeeded()
        }

        return restored
    }

    @discardableResult
    public func syncLoginContext(_ captured: FireCapturedLoginState) throws -> SessionState {
        let state = try core.syncLoginContext(
            context: LoginSyncState(
                currentUrl: captured.currentURL,
                username: captured.username,
                csrfToken: captured.csrfToken,
                homeHtml: captured.homeHTML,
                browserUserAgent: captured.browserUserAgent,
                cookies: captured.cookies
            )
        )
        try persistCurrentSession()
        return state
    }

    @discardableResult
    public func applyPlatformCookies(_ cookies: [PlatformCookieState]) throws -> SessionState {
        let state = try core.applyPlatformCookies(cookies: cookies)
        try persistCurrentSession()
        return state
    }

    @discardableResult
    public func logoutLocal(preserveCfClearance: Bool = true) throws -> SessionState {
        let state = try core.logoutLocal(preserveCfClearance: preserveCfClearance)
        try authCookieStore.clear(preserveCfClearance: preserveCfClearance)
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
        let before = try persistedSessionArtifacts()
        let refreshed = try await core.refreshBootstrapIfNeeded()
        if try persistedSessionArtifacts() != before {
            try persistCurrentSession()
        }
        return refreshed
    }

    @discardableResult
    public func refreshCsrfTokenIfNeeded() async throws -> SessionState {
        let before = try persistedSessionArtifacts()
        let refreshed = try await core.refreshCsrfTokenIfNeeded()
        if try persistedSessionArtifacts() != before {
            try persistCurrentSession()
        }
        return refreshed
    }

    public func persistCurrentSession() throws {
        try persistCurrentAuthCookies()
        try persistSessionFile()
    }

    public func workspacePathValue() -> String {
        workspacePath
    }

    public nonisolated func logHost(level: HostLogLevelState, target: String, message: String) {
        try? core.diagnostics().logHost(level: level, target: target, message: message)
    }

    public nonisolated func makeLogger(target: String) -> FireHostLogger {
        let core = self.core
        return FireHostLogger(target: target) { level, target, message in
            try? core.diagnostics().logHost(level: level, target: target, message: message)
        }
    }

    public func listLogFiles() async throws -> [LogFileSummaryState] {
        let core = self.core
        let diagnosticsQueue = self.diagnosticsQueue
        return try await withCheckedThrowingContinuation { continuation in
            diagnosticsQueue.async {
                continuation.resume(with: Result { try core.diagnostics().listLogFiles() })
            }
        }
    }

    public func readLogFile(relativePath: String) async throws -> LogFileDetailState {
        let core = self.core
        let diagnosticsQueue = self.diagnosticsQueue
        return try await withCheckedThrowingContinuation { continuation in
            diagnosticsQueue.async {
                continuation.resume(with: Result { try core.diagnostics().readLogFile(relativePath: relativePath) })
            }
        }
    }

    public func readLogFilePage(
        relativePath: String,
        cursor: UInt64? = nil,
        maxBytes: UInt64? = nil,
        direction: DiagnosticsPageDirectionState
    ) async throws -> LogFilePageState {
        let core = self.core
        let diagnosticsQueue = self.diagnosticsQueue
        return try await withCheckedThrowingContinuation { continuation in
            diagnosticsQueue.async {
                continuation.resume(
                    with: Result {
                        try core.diagnostics().readLogFilePage(
                            relativePath: relativePath,
                            cursor: cursor,
                            maxBytes: maxBytes,
                            direction: direction
                        )
                    }
                )
            }
        }
    }

    public func listNetworkTraces(limit: UInt64 = 200) throws -> [NetworkTraceSummaryState] {
        try core.diagnostics().listNetworkTraces(limit: limit)
    }

    public func networkTraceDetail(traceID: UInt64) throws -> NetworkTraceDetailState? {
        try core.diagnostics().networkTraceDetail(traceId: traceID)
    }

    public func networkTraceBodyPage(
        traceID: UInt64,
        cursor: UInt64? = nil,
        maxBytes: UInt64? = nil,
        direction: DiagnosticsPageDirectionState
    ) async throws -> NetworkTraceBodyPageState? {
        let core = self.core
        let diagnosticsQueue = self.diagnosticsQueue
        return try await withCheckedThrowingContinuation { continuation in
            diagnosticsQueue.async {
                continuation.resume(
                    with: Result {
                        try core.diagnostics().networkTraceBodyPage(
                            traceId: traceID,
                            cursor: cursor,
                            maxBytes: maxBytes,
                            direction: direction
                        )
                    }
                )
            }
        }
    }

    public func diagnosticSessionID() throws -> String {
        try core.diagnostics().diagnosticSessionId()
    }

    public func exportSupportBundle(
        platform: String,
        appVersion: String?,
        buildNumber: String?,
        scenePhase: String?
    ) async throws -> SupportBundleExportState {
        let core = self.core
        let diagnosticsQueue = self.diagnosticsQueue
        return try await withCheckedThrowingContinuation { continuation in
            diagnosticsQueue.async {
                continuation.resume(
                    with: Result {
                        try core.diagnostics().exportSupportBundle(
                            hostContext: SupportBundleHostContextState(
                                platform: platform,
                                appVersion: appVersion,
                                buildNumber: buildNumber,
                                scenePhase: scenePhase
                            )
                        )
                    }
                )
            }
        }
    }

    public func flushLogs(sync: Bool = true) async throws {
        let core = self.core
        let diagnosticsQueue = self.diagnosticsQueue
        try await withCheckedThrowingContinuation { continuation in
            diagnosticsQueue.async {
                continuation.resume(with: Result { try core.diagnostics().flushLogs(sync: sync) })
            }
        }
    }

    public func exportSessionJSON() throws -> String {
        try core.exportSessionJson()
    }

    public func notificationState() throws -> NotificationCenterState {
        try core.notifications().notificationState()
    }

    public func fetchRecentNotifications(limit: UInt32? = nil) async throws -> NotificationListState {
        try await runPersistingSessionChanges {
            try await core.notifications().fetchRecentNotifications(limit: limit)
        }
    }

    public func fetchNotifications(
        limit: UInt32? = nil,
        offset: UInt32? = nil
    ) async throws -> NotificationListState {
        try await runPersistingSessionChanges {
            try await core.notifications().fetchNotifications(limit: limit, offset: offset)
        }
    }

    public func markNotificationRead(id: UInt64) async throws -> NotificationCenterState {
        try await runPersistingSessionChanges {
            try await core.notifications().markNotificationRead(notificationId: id)
        }
    }

    public func markAllNotificationsRead() async throws -> NotificationCenterState {
        try await runPersistingSessionChanges {
            try await core.notifications().markAllNotificationsRead()
        }
    }

    public func fetchBookmarks(
        username: String,
        page: UInt32? = nil
    ) async throws -> TopicListState {
        try await runPersistingSessionChanges {
            try await core.notifications().fetchBookmarks(username: username, page: page)
        }
    }

    public func fetchReadHistory(page: UInt32? = nil) async throws -> TopicListState {
        try await runPersistingSessionChanges {
            try await core.notifications().fetchReadHistory(page: page)
        }
    }

    public func fetchDrafts(
        offset: UInt32? = nil,
        limit: UInt32? = nil
    ) async throws -> DraftListResponseState {
        try await runPersistingSessionChanges {
            try await core.notifications().fetchDrafts(offset: offset, limit: limit)
        }
    }

    public func fetchDraft(draftKey: String) async throws -> DraftState? {
        try await runPersistingSessionChanges {
            try await core.notifications().fetchDraft(draftKey: draftKey)
        }
    }

    public func saveDraft(
        draftKey: String,
        data: DraftDataState,
        sequence: UInt32
    ) async throws -> UInt32 {
        try await runPersistingSessionChanges {
            try await core.notifications().saveDraft(draftKey: draftKey, data: data, sequence: sequence)
        }
    }

    public func deleteDraft(
        draftKey: String,
        sequence: UInt32? = nil
    ) async throws {
        try await runPersistingSessionChanges {
            try await core.notifications().deleteDraft(draftKey: draftKey, sequence: sequence)
        }
    }

    public func pollNotificationAlertOnce(
        lastMessageId: Int64
    ) async throws -> NotificationAlertPollResultState {
        try await runPersistingSessionChanges {
            try await core.messagebus().pollNotificationAlertOnce(lastMessageId: lastMessageId)
        }
    }

    public func search(query: SearchQueryState) async throws -> SearchResultState {
        try await runPersistingSessionChanges {
            try await core.search().search(query: query)
        }
    }

    public func searchTags(query: TagSearchQueryState) async throws -> TagSearchResultState {
        try await runPersistingSessionChanges {
            try await core.search().searchTags(query: query)
        }
    }

    public func searchUsers(query: UserMentionQueryState) async throws -> UserMentionResultState {
        try await runPersistingSessionChanges {
            try await core.search().searchUsers(query: query)
        }
    }

    public func fetchTopicList(query: TopicListQueryState) async throws -> TopicListState {
        try await runPersistingSessionChanges {
            try await core.topics().fetchTopicList(query: query)
        }
    }

    public func fetchTopicList(kind: TopicListKindState) async throws -> TopicListState {
        try await fetchTopicList(
            query: TopicListQueryState(
                kind: kind,
                page: nil,
                topicIds: [],
                order: nil,
                ascending: nil,
                categorySlug: nil,
                categoryId: nil,
                parentCategorySlug: nil,
                tag: nil,
                additionalTags: [],
                matchAllTags: false
            )
        )
    }

    public func fetchTopicDetail(query: TopicDetailQueryState) async throws -> TopicDetailState {
        try await runPersistingSessionChanges {
            try await core.topics().fetchTopicDetail(query: query)
        }
    }

    public func fetchTopicDetailInitial(query: TopicDetailQueryState) async throws -> TopicDetailState {
        try await runPersistingSessionChanges {
            try await core.topics().fetchTopicDetailInitial(query: query)
        }
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

    public func fetchTopicPosts(topicID: UInt64, postIDs: [UInt64]) async throws -> [TopicPostState] {
        try await runPersistingSessionChanges {
            try await core.topics().fetchTopicPosts(topicId: topicID, postIds: postIDs)
        }
    }

    public func fetchPost(postID: UInt64) async throws -> TopicPostState {
        try await runPersistingSessionChanges {
            try await core.topics().fetchPost(postId: postID)
        }
    }

    public func createReply(
        topicID: UInt64,
        raw: String,
        replyToPostNumber: UInt32?
    ) async throws -> TopicPostState {
        try await runPersistingSessionChanges {
            try await core.topics().createReply(
                input: TopicReplyRequestState(
                    topicId: topicID,
                    raw: raw,
                    replyToPostNumber: replyToPostNumber
                )
            )
        }
    }

    public func updatePost(
        postID: UInt64,
        raw: String,
        editReason: String? = nil
    ) async throws -> TopicPostState {
        try await runPersistingSessionChanges {
            try await core.topics().updatePost(
                input: PostUpdateRequestState(
                    postId: postID,
                    raw: raw,
                    editReason: editReason
                )
            )
        }
    }

    public func createTopic(
        title: String,
        raw: String,
        categoryID: UInt64,
        tags: [String]
    ) async throws -> UInt64 {
        try await runPersistingSessionChanges {
            try await core.topics().createTopic(
                input: TopicCreateRequestState(
                    title: title,
                    raw: raw,
                    categoryId: categoryID,
                    tags: tags
                )
            )
        }
    }

    public func createPrivateMessage(
        title: String,
        raw: String,
        targetRecipients: [String]
    ) async throws -> UInt64 {
        try await runPersistingSessionChanges {
            try await core.topics().createPrivateMessage(
                input: PrivateMessageCreateRequestState(
                    title: title,
                    raw: raw,
                    targetRecipients: targetRecipients
                )
            )
        }
    }

    public func updateTopic(
        topicID: UInt64,
        title: String,
        categoryID: UInt64,
        tags: [String]
    ) async throws {
        try await runPersistingSessionChanges {
            try await core.topics().updateTopic(
                input: TopicUpdateRequestState(
                    topicId: topicID,
                    title: title,
                    categoryId: categoryID,
                    tags: tags
                )
            )
        }
    }

    public func uploadImage(
        fileName: String,
        mimeType: String?,
        bytes: Data
    ) async throws -> UploadResultState {
        try await runPersistingSessionChanges {
            try await core.topics().uploadImage(
                input: UploadImageRequestState(
                    fileName: fileName,
                    mimeType: mimeType,
                    bytes: bytes
                )
            )
        }
    }

    public func lookupUploadUrls(shortUrls: [String]) async throws -> [ResolvedUploadUrlState] {
        try await runPersistingSessionChanges {
            try await core.topics().lookupUploadUrls(shortUrls: shortUrls)
        }
    }

    public func reportTopicTimings(
        input: TopicTimingsRequestState
    ) async throws -> Bool {
        try await runPersistingSessionChanges {
            try await core.topics().reportTopicTimings(input: input)
        }
    }

    public func likePost(postID: UInt64) async throws -> PostReactionUpdateState? {
        try await runPersistingSessionChanges {
            try await core.topics().likePost(postId: postID)
        }
    }

    public func unlikePost(postID: UInt64) async throws -> PostReactionUpdateState? {
        try await runPersistingSessionChanges {
            try await core.topics().unlikePost(postId: postID)
        }
    }

    public func togglePostReaction(
        postID: UInt64,
        reactionID: String
    ) async throws -> PostReactionUpdateState {
        try await runPersistingSessionChanges {
            try await core.topics().togglePostReaction(postId: postID, reactionId: reactionID)
        }
    }

    public func votePoll(
        postID: UInt64,
        pollName: String,
        options: [String]
    ) async throws -> PollState {
        try await runPersistingSessionChanges {
            try await core.topics().votePoll(postId: postID, pollName: pollName, options: options)
        }
    }

    public func unvotePoll(
        postID: UInt64,
        pollName: String
    ) async throws -> PollState {
        try await runPersistingSessionChanges {
            try await core.topics().unvotePoll(postId: postID, pollName: pollName)
        }
    }

    public func voteTopic(topicID: UInt64) async throws -> VoteResponseState {
        try await runPersistingSessionChanges {
            try await core.topics().voteTopic(topicId: topicID)
        }
    }

    public func unvoteTopic(topicID: UInt64) async throws -> VoteResponseState {
        try await runPersistingSessionChanges {
            try await core.topics().unvoteTopic(topicId: topicID)
        }
    }

    public func fetchTopicVoters(topicID: UInt64) async throws -> [VotedUserState] {
        try await runPersistingSessionChanges {
            try await core.topics().fetchTopicVoters(topicId: topicID)
        }
    }

    public func createBookmark(
        bookmarkableID: UInt64,
        bookmarkableType: String,
        name: String? = nil,
        reminderAt: String? = nil,
        autoDeletePreference: Int32? = nil
    ) async throws -> UInt64 {
        try await runPersistingSessionChanges {
            try await core.notifications().createBookmark(
                bookmarkableId: bookmarkableID,
                bookmarkableType: bookmarkableType,
                name: name,
                reminderAt: reminderAt,
                autoDeletePreference: autoDeletePreference
            )
        }
    }

    public func updateBookmark(
        bookmarkID: UInt64,
        name: String? = nil,
        reminderAt: String? = nil,
        autoDeletePreference: Int32? = nil
    ) async throws {
        try await runPersistingSessionChanges {
            try await core.notifications().updateBookmark(
                bookmarkId: bookmarkID,
                name: name,
                reminderAt: reminderAt,
                autoDeletePreference: autoDeletePreference
            )
        }
    }

    public func deleteBookmark(bookmarkID: UInt64) async throws {
        try await runPersistingSessionChanges {
            try await core.notifications().deleteBookmark(bookmarkId: bookmarkID)
        }
    }

    public func setTopicNotificationLevel(
        topicID: UInt64,
        notificationLevel: Int32
    ) async throws {
        try await runPersistingSessionChanges {
            try await core.notifications().setTopicNotificationLevel(
                topicId: topicID,
                notificationLevel: notificationLevel
            )
        }
    }

    public func fetchUserProfile(username: String) async throws -> UserProfileState {
        try await runPersistingSessionChanges {
            try await core.fetchUserProfile(username: username)
        }
    }

    public func fetchUserSummary(username: String) async throws -> UserSummaryState {
        try await runPersistingSessionChanges {
            try await core.fetchUserSummary(username: username)
        }
    }

    public func fetchUserActions(
        username: String,
        offset: UInt32?,
        filter: String?
    ) async throws -> [UserActionState] {
        try await runPersistingSessionChanges {
            try await core.fetchUserActions(username: username, offset: offset, filter: filter)
        }
    }

    public func fetchFollowing(username: String) async throws -> [FollowUserState] {
        try await runPersistingSessionChanges {
            try await core.fetchFollowing(username: username)
        }
    }

    public func fetchFollowers(username: String) async throws -> [FollowUserState] {
        try await runPersistingSessionChanges {
            try await core.fetchFollowers(username: username)
        }
    }

    public func followUser(username: String) async throws {
        try await runPersistingSessionChanges {
            try await core.followUser(username: username)
        }
    }

    public func unfollowUser(username: String) async throws {
        try await runPersistingSessionChanges {
            try await core.unfollowUser(username: username)
        }
    }

    public func fetchPendingInvites(username: String) async throws -> [InviteLinkState] {
        try await runPersistingSessionChanges {
            try await core.fetchPendingInvites(username: username)
        }
    }

    public func createInviteLink(
        maxRedemptionsAllowed: UInt32,
        expiresAt: String? = nil,
        description: String? = nil,
        email: String? = nil
    ) async throws -> InviteLinkState {
        try await runPersistingSessionChanges {
            try await core.createInviteLink(
                input: InviteCreateRequestState(
                    maxRedemptionsAllowed: maxRedemptionsAllowed,
                    expiresAt: expiresAt,
                    description: description,
                    email: email
                )
            )
        }
    }

    public func fetchBadgeDetail(badgeID: UInt64) async throws -> BadgeState {
        try await runPersistingSessionChanges {
            try await core.fetchBadgeDetail(badgeId: badgeID)
        }
    }

    @discardableResult
    public func restoreSessionJSON(_ json: String) throws -> SessionState {
        let state = try core.restoreSessionJson(json: json)
        try persistCurrentSession()
        return state
    }

    // MARK: - MessageBus

    @discardableResult
    public func startMessageBus(handler: any MessageBusEventHandler) async throws -> String {
        try await runPersistingSessionChanges {
            try await core.messagebus().startMessageBus(mode: .foreground, handler: handler)
        }
    }

    public func stopMessageBus(clearSubscriptions: Bool = false) throws {
        try core.messagebus().stopMessageBus(clearSubscriptions: clearSubscriptions)
    }

    public func subscribeTopicDetailChannel(topicId: UInt64, ownerToken: String) throws {
        try core.messagebus().subscribeChannel(
            subscription: MessageBusSubscriptionState(
                ownerToken: ownerToken,
                channel: "/topic/\(topicId)",
                lastMessageId: nil,
                scope: .transient
            )
        )
    }

    public func unsubscribeTopicDetailChannel(topicId: UInt64, ownerToken: String) throws {
        try core.messagebus().unsubscribeChannel(ownerToken: ownerToken, channel: "/topic/\(topicId)")
    }

    public func subscribeTopicReactionChannel(topicId: UInt64, ownerToken: String) throws {
        try core.messagebus().subscribeChannel(
            subscription: MessageBusSubscriptionState(
                ownerToken: ownerToken,
                channel: "/topic/\(topicId)/reactions",
                lastMessageId: nil,
                scope: .transient
            )
        )
    }

    public func unsubscribeTopicReactionChannel(topicId: UInt64, ownerToken: String) throws {
        try core.messagebus().unsubscribeChannel(ownerToken: ownerToken, channel: "/topic/\(topicId)/reactions")
    }

    public func topicReplyPresenceState(topicId: UInt64) throws -> TopicPresenceState {
        try core.messagebus().topicReplyPresenceState(topicId: topicId)
    }

    public func bootstrapTopicReplyPresence(
        topicId: UInt64,
        ownerToken: String
    ) async throws -> TopicPresenceState {
        try await runPersistingSessionChanges {
            try await core.messagebus().bootstrapTopicReplyPresence(topicId: topicId, ownerToken: ownerToken)
        }
    }

    public func unsubscribeTopicReplyPresenceChannel(topicId: UInt64, ownerToken: String) throws {
        try core.messagebus().unsubscribeChannel(
            ownerToken: ownerToken,
            channel: "/presence/discourse-presence/reply/\(topicId)"
        )
    }

    public func updateTopicReplyPresence(topicId: UInt64, active: Bool) async throws {
        try await runPersistingSessionChanges {
            try await core.messagebus().updateTopicReplyPresence(topicId: topicId, active: active)
        }
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

    private func shouldRefreshCsrfAfterColdStartRestore(_ session: SessionState) -> Bool {
        // A cold-start restore can still come back without a usable CSRF token even
        // when cookie/bootstrap state is otherwise ready.
        session.readiness.canReadAuthenticatedApi
            && session.readiness.hasCurrentUser
            && session.bootstrap.hasPreloadedData
            && session.bootstrap.hasSiteMetadata
            && session.bootstrap.hasSiteSettings
            && !session.readiness.hasCsrfToken
    }

    private func persistedSessionArtifacts() throws -> FirePersistedSessionArtifacts {
        FirePersistedSessionArtifacts(
            sessionJSON: try core.exportSessionJson(),
            secureSecrets: FireAuthCookieSecrets(cookieState: try core.snapshot().cookies)
        )
    }

    private func persistCurrentAuthCookies() throws {
        try authCookieStore.save(FireAuthCookieSecrets(cookieState: try core.snapshot().cookies))
    }

    private func persistSessionFile() throws {
        try core.saveSessionToPath(path: sessionFilePath)
    }

    private func runPersistingSessionChanges<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        let before = try persistedSessionArtifacts()
        let result = try await operation()
        if try persistedSessionArtifacts() != before {
            try persistCurrentSession()
        }
        return result
    }
}
