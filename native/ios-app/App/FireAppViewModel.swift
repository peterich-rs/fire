import Foundation
import WebKit

private enum FireLoginPreparationError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Unable to prepare login network access."
        }
    }
}

private enum FireDiagnosticsAccessError: LocalizedError {
    case unavailable
    case traceNotFound

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Diagnostics are unavailable because the shared session store was not initialized."
        case .traceNotFound:
            "The selected network request trace is no longer available."
        }
    }
}

private enum FireTopicInteractionError: LocalizedError {
    case unavailable
    case requiresAuthenticatedWrite
    case emptyReply
    case requiresCloudflareVerification

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "互动能力暂时不可用。"
        case .requiresAuthenticatedWrite:
            "当前会话还不能执行回复或表情回应。"
        case .emptyReply:
            "回复内容不能为空。"
        case .requiresCloudflareVerification:
            "需要先完成 Cloudflare 验证。请在登录页完成验证后点 Sync，再重试。"
        }
    }
}

private struct FireTopicPostPaginationState {
    var targetLoadedCount: Int
    var exhaustedPostIDs: Set<UInt64> = []
}

enum FireSearchScope: String, CaseIterable, Identifiable {
    case all
    case topic
    case post
    case user

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .topic: "话题"
        case .post: "帖子"
        case .user: "用户"
        }
    }

    var typeFilter: SearchTypeFilterState? {
        switch self {
        case .all: nil
        case .topic: .topic
        case .post: .post
        case .user: .user
        }
    }
}

protocol FireChallengeSessionRecovering: Sendable {
    func logoutLocal(preserveCfClearance: Bool) async throws -> SessionState
}

extension FireSessionStore: FireChallengeSessionRecovering {}

@MainActor
final class FireAppViewModel: ObservableObject {
    private static let messageBusErrorPrefix = "实时同步连接失败："
    private static let loginRequiredMessage = "登录状态已失效，请重新登录。"
    private static let topicPostPageSize = 30
    private static let topicPostPrefetchThreshold = 6
    private static let topicDetailLogTarget = "ios.topic-detail"
    private static let diagnosticsLifecycleLogTarget = "ios.lifecycle"
    private static let topicListRefreshLoadingPollInterval: Duration = .milliseconds(250)

    // MARK: - Session

    @Published private(set) var session: SessionState = .placeholder()

    // MARK: - Topic list

    @Published private(set) var selectedTopicKind: TopicListKindState = .latest
    @Published private(set) var selectedHomeCategoryId: UInt64?
    @Published private(set) var selectedHomeTags: [String] = []
    @Published private(set) var topicRows: [FireTopicRowPresentation] = []
    @Published private(set) var moreTopicsUrl: String?
    @Published private(set) var nextTopicsPage: UInt32?
    @Published private(set) var topicCategories: [UInt64: FireTopicCategoryPresentation] = [:]
    @Published private(set) var topicDetails: [UInt64: TopicDetailState] = [:]
    @Published private(set) var topicPresenceUsersByTopic: [UInt64: [TopicPresenceUserState]] = [:]
    @Published private(set) var loadingMoreTopicPostIDs: Set<UInt64> = []
    @Published private(set) var isLoadingTopics = false
    @Published private(set) var isAppendingTopics = false
    @Published private(set) var loadingTopicIDs: Set<UInt64> = []

    // MARK: - Write interactions

    @Published private(set) var submittingReplyTopicIDs: Set<UInt64> = []
    @Published private(set) var mutatingPostIDs: Set<UInt64> = []

    // MARK: - Notifications

    @Published private(set) var notificationUnreadCount: Int = 0
    @Published private(set) var recentNotifications: [NotificationItemState] = []
    @Published private(set) var isLoadingNotifications = false
    @Published private(set) var notificationFullList: [NotificationItemState] = []
    @Published private(set) var notificationFullNextOffset: UInt32?
    @Published private(set) var isLoadingNotificationFullPage = false
    @Published private(set) var hasMoreNotificationFull = false

    // MARK: - Search

    @Published var searchQuery = ""
    @Published private(set) var searchScope: FireSearchScope = .all
    @Published private(set) var searchResult: SearchResultState?
    @Published private(set) var searchCurrentPage: UInt32 = 1
    @Published private(set) var isSearching = false
    @Published private(set) var isAppendingSearch = false
    @Published private(set) var searchErrorMessage: String?

    // MARK: - General UI state

    @Published var errorMessage: String?
    @Published private(set) var isBootstrappingSession = false
    @Published private(set) var isStartupLoadingVisible = false
    @Published var isPresentingLogin = false
    @Published var isPreparingLogin = false
    @Published var isSyncingLoginSession = false
    @Published var isLoggingOut = false

    // MARK: - Private

    private var sessionStore: FireSessionStore?
    private var loginCoordinator: FireWebViewLoginCoordinator?
    private var sessionStoreInitializationTask: Task<FireSessionStore, Error>?
    private var initialStateTask: Task<Void, Never>?
    private var initialStateLoadingDelayTask: Task<Void, Never>?
    private var initialStateLoadGeneration: UInt64 = 0
    private let loginURL = URL(string: "https://linux.do")!
    private let challengeRecoveryStore: (any FireChallengeSessionRecovering)?
    private let topicListRefreshClock = ContinuousClock()

    // MessageBus
    private var messageBusCoordinator: FireMessageBusCoordinator?
    private var isMessageBusActive = false
    private var messageBusStartRetryCount = 0
    private var messageBusRetryTask: Task<Void, Never>?
    private var pendingTopicListRefreshTask: Task<Void, Never>?
    private var topicListMessageBusRefreshController = FireTopicListMessageBusRefreshController()
    private var pendingTopicDetailRefreshTasks: [UInt64: Task<Void, Never>] = [:]
    private var pendingNotificationStateRefreshTask: Task<Void, Never>?
    private var topicPresenceHeartbeatTasks: [UInt64: Task<Void, Never>] = [:]
    private var topicPostPreloadTasks: [UInt64: Task<Void, Never>] = [:]
    private var topicPostPaginationStates: [UInt64: FireTopicPostPaginationState] = [:]
    private var topicDetailTargetPostNumbers: [UInt64: UInt32] = [:]
    private var activeTopicDetailOwnerTokens: [UInt64: Set<String>] = [:]
    private var searchTask: Task<Void, Never>?
    private var latestSearchRequestID: UInt64 = 0
    private var filterChangeRefreshTask: Task<Void, Never>?

    init(
        initialSession: SessionState = .placeholder(),
        challengeRecoveryStore: (any FireChallengeSessionRecovering)? = nil
    ) {
        self.session = initialSession
        self.challengeRecoveryStore = challengeRecoveryStore
    }

    // MARK: - Lifecycle

    func loadInitialState() {
        initialStateLoadGeneration &+= 1
        let generation = initialStateLoadGeneration

        initialStateTask?.cancel()
        initialStateLoadingDelayTask?.cancel()
        isBootstrappingSession = true
        isStartupLoadingVisible = false

        initialStateLoadingDelayTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }

            guard let self else { return }
            guard self.initialStateLoadGeneration == generation else { return }
            guard self.isBootstrappingSession else { return }
            self.isStartupLoadingVisible = true
        }

        initialStateTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.finishInitialStateLoading(generation: generation)
            }

            do {
                let sessionStore = try await self.sessionStoreValue()
                guard self.initialStateLoadGeneration == generation else { return }
                self.errorMessage = nil
                let restoredSession = try await sessionStore.restoreColdStartSession()
                guard self.initialStateLoadGeneration == generation else { return }
                await self.applySession(restoredSession)
                guard self.initialStateLoadGeneration == generation else { return }
                await self.refreshTopicsIfPossible(force: true)
                guard self.initialStateLoadGeneration == generation else { return }
                await self.loadRecentNotifications(force: false)
            } catch {
                guard self.initialStateLoadGeneration == generation else { return }
                if await self.handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func refreshSession() {
        Task {
            do {
                let sessionStore = try await sessionStoreValue()
                errorMessage = nil
                await applySession(try await sessionStore.snapshot())
                await applySession(try await sessionStore.refreshBootstrapIfNeeded())
                await refreshTopicsIfPossible(force: false)
            } catch {
                if await handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func openLogin() {
        guard !isPreparingLogin else {
            return
        }

        errorMessage = nil
        isPreparingLogin = true

        Task {
            defer { isPreparingLogin = false }

            do {
                _ = try await loginCoordinatorValue()
                try await prepareLoginNetworkAccess()
                isPresentingLogin = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func completeLogin(from webView: WKWebView) {
        guard !isSyncingLoginSession else {
            return
        }

        isSyncingLoginSession = true
        Task {
            defer { isSyncingLoginSession = false }

            do {
                let loginCoordinator = try await loginCoordinatorValue()
                errorMessage = nil
                await applySession(try await loginCoordinator.completeLogin(from: webView))
                isPresentingLogin = false
                await refreshTopicsIfPossible(force: true)
            } catch {
                if await handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshBootstrap() {
        Task {
            do {
                let sessionStore = try await sessionStoreValue()
                errorMessage = nil
                await applySession(try await sessionStore.refreshBootstrap())
                await refreshTopicsIfPossible(force: false)
            } catch {
                if await handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func logout() {
        guard !isLoggingOut else {
            return
        }

        isLoggingOut = true

        Task {
            defer { isLoggingOut = false }

            do {
                let loginCoordinator = try await loginCoordinatorValue()
                stopMessageBus()
                errorMessage = nil
                await applySession(try await loginCoordinator.logout())
                selectedTopicKind = .latest
                clearTopicState()
                clearNotificationState()
                clearSearchState(resetQuery: true)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Topic list

    func selectTopicKind(_ kind: TopicListKindState) {
        guard selectedTopicKind != kind else {
            return
        }
        selectedTopicKind = kind
        scheduleDebouncedRefresh()
    }

    func selectHomeCategory(_ categoryId: UInt64?) {
        guard selectedHomeCategoryId != categoryId else { return }
        selectedHomeCategoryId = categoryId
        selectedHomeTags = []
        scheduleDebouncedRefresh()
    }

    func addHomeTag(_ tag: String) {
        guard !selectedHomeTags.contains(tag) else { return }
        selectedHomeTags.append(tag)
        scheduleDebouncedRefresh()
    }

    func removeHomeTag(_ tag: String) {
        guard selectedHomeTags.contains(tag) else { return }
        selectedHomeTags.removeAll { $0 == tag }
        scheduleDebouncedRefresh()
    }

    func clearHomeTags() {
        guard !selectedHomeTags.isEmpty else { return }
        selectedHomeTags = []
        scheduleDebouncedRefresh()
    }

    private func scheduleDebouncedRefresh() {
        cancelPendingTopicListRefresh()
        filterChangeRefreshTask?.cancel()
        filterChangeRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await refreshTopicsIfPossible(force: true)
        }
    }

    var selectedHomeCategoryPresentation: FireTopicCategoryPresentation? {
        guard let id = selectedHomeCategoryId else { return nil }
        return categoryPresentation(for: id)
    }

    func refreshTopics() {
        Task {
            await refreshTopicsIfPossible(force: true)
        }
    }

    func refreshTopicsAsync() async {
        await refreshTopicsIfPossible(force: true)
    }

    func loadMoreTopics() {
        guard let nextTopicsPage else {
            return
        }

        Task {
            await loadTopics(page: nextTopicsPage, reset: false, force: true)
        }
    }

    func loadTopicDetail(
        topicId: UInt64,
        targetPostNumber: UInt32? = nil,
        force: Bool = false
    ) async {
        guard let sessionStore else {
            return
        }

        if loadingTopicIDs.contains(topicId) {
            return
        }
        if topicDetails[topicId] != nil && !force {
            return
        }
        if !session.readiness.canReadAuthenticatedApi {
            clearTopicState()
            return
        }

        if let targetPostNumber {
            topicDetailTargetPostNumbers[topicId] = targetPostNumber
        }

        let hadCachedDetail = topicDetails[topicId] != nil
        topicDetailLogger()?.debug(
            "loading topic detail topic_id=\(topicId) force=\(force) had_cache=\(hadCachedDetail) target_post=\(String(describing: targetPostNumber))"
        )
        loadingTopicIDs.insert(topicId)
        defer { loadingTopicIDs.remove(topicId) }

        do {
            errorMessage = nil
            let detail = try await sessionStore.fetchTopicDetailInitial(
                query: TopicDetailQueryState(
                    topicId: topicId,
                    postNumber: targetPostNumber,
                    trackVisit: true,
                    filter: nil,
                    usernameFilters: nil,
                    filterTopLevelReplies: false
                )
            )
            applyTopicDetail(detail, topicId: topicId)
            topicDetailLogger()?.debug(
                "loaded topic detail topic_id=\(topicId) loaded_posts=\(detail.postStream.posts.count) stream_posts=\(detail.postStream.stream.count)"
            )
        } catch {
            topicDetailLogger()?.error(
                "topic detail load failed topic_id=\(topicId) error=\(error.localizedDescription)"
            )
            if await handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func clearTopicDetailAnchor(topicId: UInt64) {
        topicDetailTargetPostNumbers.removeValue(forKey: topicId)
    }

    func topicDetail(for topicId: UInt64) -> TopicDetailState? {
        topicDetails[topicId]
    }

    func topicPresenceUsers(for topicId: UInt64) -> [TopicPresenceUserState] {
        topicPresenceUsersByTopic[topicId] ?? []
    }

    func isLoadingTopic(topicId: UInt64) -> Bool {
        loadingTopicIDs.contains(topicId)
    }

    func isLoadingMoreTopicPosts(topicId: UInt64) -> Bool {
        loadingMoreTopicPostIDs.contains(topicId)
    }

    func hasMoreTopicPosts(topicId: UInt64) -> Bool {
        guard let detail = topicDetails[topicId] else {
            return false
        }
        let loadedWindowCount = FireTopicPresentation.loadedWindowCount(detail: detail)
        let pagination = topicPostPaginationStates[topicId]
        let targetLoadedCount = max(pagination?.targetLoadedCount ?? loadedWindowCount, loadedWindowCount)
        let unresolvedPostIDs = FireTopicPresentation.missingPostIDs(
            in: detail,
            upTo: targetLoadedCount,
            excluding: pagination?.exhaustedPostIDs ?? Set<UInt64>()
        )
        return !unresolvedPostIDs.isEmpty || targetLoadedCount < detail.postStream.stream.count
    }

    func preloadTopicPostsIfNeeded(
        topicId: UInt64,
        visibleReplyIndex: Int,
        totalReplyCount: Int
    ) {
        guard totalReplyCount > 0 else { return }
        let triggerIndex = max(totalReplyCount - Self.topicPostPrefetchThreshold, 0)
        guard visibleReplyIndex >= triggerIndex else { return }
        guard hasMoreTopicPosts(topicId: topicId) else { return }
        guard !loadingMoreTopicPostIDs.contains(topicId) else { return }
        guard topicPostPreloadTasks[topicId] == nil else { return }

        topicPostPreloadTasks[topicId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.topicPostPreloadTasks[topicId] = nil }
            await self.loadMoreTopicPostsIfNeeded(topicId: topicId)
        }
    }

    // MARK: - Topic detail lifecycle

    func beginTopicDetailLifecycle(topicId: UInt64, ownerToken: String) {
        var owners = activeTopicDetailOwnerTokens[topicId] ?? []
        let inserted = owners.insert(ownerToken).inserted
        activeTopicDetailOwnerTokens[topicId] = owners
        guard inserted else { return }

        topicDetailLogger()?.debug(
            "registered topic detail lifecycle topic_id=\(topicId) owner_token=\(ownerToken) owner_count=\(owners.count)"
        )
    }

    func endTopicDetailLifecycle(topicId: UInt64, ownerToken: String) {
        guard var owners = activeTopicDetailOwnerTokens[topicId] else { return }
        guard owners.remove(ownerToken) != nil else { return }

        if owners.isEmpty {
            activeTopicDetailOwnerTokens.removeValue(forKey: topicId)
        } else {
            activeTopicDetailOwnerTokens[topicId] = owners
        }

        topicDetailLogger()?.debug(
            "released topic detail lifecycle topic_id=\(topicId) owner_token=\(ownerToken) owner_count=\(owners.count)"
        )

        guard owners.isEmpty else { return }
        topicDetailTargetPostNumbers.removeValue(forKey: topicId)
        let visibleTopicIDs = Set(topicRows.map(\.topic.id))
        guard !visibleTopicIDs.contains(topicId) else { return }
        evictTopicDetailState(topicId: topicId, reason: "detail view disappeared")
    }

    func retainedTopicDetailIDs(visibleTopicIDs: Set<UInt64>) -> Set<UInt64> {
        let activeTopicIDs = activeTopicDetailOwnerTokens.compactMap { topicId, owners in
            owners.isEmpty ? nil : topicId
        }
        return visibleTopicIDs.union(activeTopicIDs)
    }

    // MARK: - Topic detail MessageBus subscription

    func maintainTopicDetailSubscription(topicId: UInt64, ownerToken: String) async {
        guard session.readiness.canOpenMessageBus else { return }
        // Hidden/private topics can 404 while the detail view is already alive. Waiting
        // for a successful detail load avoids bootstrapping presence on a topic we
        // cannot read, which can cause Linux.do to clear the auth cookie.
        guard topicDetails[topicId] != nil else {
            topicDetailLogger()?.debug(
                "skipping topic detail subscription bootstrap topic_id=\(topicId) reason=detail not loaded"
            )
            return
        }
        guard let store = sessionStore else { return }

        do {
            try await store.subscribeTopicDetailChannel(topicId: topicId, ownerToken: ownerToken)
            try await store.subscribeTopicReactionChannel(topicId: topicId, ownerToken: ownerToken)
        } catch {
            try? await store.unsubscribeTopicReactionChannel(topicId: topicId, ownerToken: ownerToken)
            try? await store.unsubscribeTopicDetailChannel(topicId: topicId, ownerToken: ownerToken)
            return
        }

        do {
            let presence = try await store.bootstrapTopicReplyPresence(
                topicId: topicId,
                ownerToken: ownerToken
            )
            applyTopicPresenceState(presence)
        } catch {
            topicPresenceUsersByTopic[topicId] = []
        }

        defer {
            Task {
                await self.endTopicReplyPresence(topicId: topicId)
                self.topicPresenceUsersByTopic[topicId] = []
                try? await store.unsubscribeTopicReplyPresenceChannel(topicId: topicId, ownerToken: ownerToken)
                try? await store.unsubscribeTopicReactionChannel(topicId: topicId, ownerToken: ownerToken)
                try? await store.unsubscribeTopicDetailChannel(topicId: topicId, ownerToken: ownerToken)
            }
        }

        if !isMessageBusActive {
            await startMessageBus()
        }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(3600))
            } catch {
                break
            }
        }
    }

    // MARK: - Write interactions

    func isSubmittingReply(topicId: UInt64) -> Bool {
        submittingReplyTopicIDs.contains(topicId)
    }

    func isMutatingPost(postId: UInt64) -> Bool {
        mutatingPostIDs.contains(postId)
    }

    func categoryPresentation(for categoryID: UInt64?) -> FireTopicCategoryPresentation? {
        guard let categoryID else {
            return nil
        }
        return topicCategories[categoryID]
    }

    func allCategories() -> [FireTopicCategoryPresentation] {
        session.bootstrap.categories
    }

    func topTags() -> [String] {
        session.bootstrap.topTags
    }

    var canTagTopics: Bool {
        session.bootstrap.canTagTopics
    }

    func fetchFilteredTopicList(query: TopicListQueryState) async throws -> TopicListState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchTopicList(query: query)
    }

    func enabledReactionOptions() -> [FireReactionOption] {
        FireTopicPresentation.enabledReactionOptions(from: session.bootstrap.enabledReactionIds)
    }

    func submitReply(
        topicId: UInt64,
        raw: String,
        replyToPostNumber: UInt32?
    ) async throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }

        let sessionStore = try await sessionStoreValue()
        guard session.readiness.canWriteAuthenticatedApi else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !submittingReplyTopicIDs.contains(topicId) else {
            return
        }

        submittingReplyTopicIDs.insert(topicId)
        defer { submittingReplyTopicIDs.remove(topicId) }

        do {
            errorMessage = nil
            let createdReply = try await performWriteWithCloudflareRetry {
                try await sessionStore.createReply(
                    topicID: topicId,
                    raw: trimmed,
                    replyToPostNumber: replyToPostNumber
                )
            }
            if let snapshot = try? await sessionStore.snapshot() {
                await applySession(snapshot)
            }
            applyCreatedReply(createdReply, topicId: topicId)
            try? await refreshTopicDetailAfterMutation(topicId: topicId, sessionStore: sessionStore)
        } catch {
            _ = await handleInteractionError(error)
            throw error
        }
    }

    func createTopic(
        title: String,
        raw: String,
        categoryID: UInt64,
        tags: [String]
    ) async throws -> UInt64 {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }
        guard !trimmedRaw.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }

        let sessionStore = try await sessionStoreValue()
        guard session.readiness.canWriteAuthenticatedApi else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }

        do {
            errorMessage = nil
            let topicID = try await performWriteWithCloudflareRetry {
                try await sessionStore.createTopic(
                    title: trimmedTitle,
                    raw: trimmedRaw,
                    categoryID: categoryID,
                    tags: tags
                )
            }
            if let snapshot = try? await sessionStore.snapshot() {
                await applySession(snapshot)
            }
            await refreshTopicsIfPossible(force: true)
            return topicID
        } catch {
            _ = await handleInteractionError(error)
            throw error
        }
    }

    func updateTopic(
        topicID: UInt64,
        title: String,
        categoryID: UInt64,
        tags: [String]
    ) async throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }

        let sessionStore = try await sessionStoreValue()
        guard session.readiness.canWriteAuthenticatedApi else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }

        do {
            errorMessage = nil
            try await performWriteWithCloudflareRetry {
                try await sessionStore.updateTopic(
                    topicID: topicID,
                    title: trimmedTitle,
                    categoryID: categoryID,
                    tags: tags
                )
            }
            if let snapshot = try? await sessionStore.snapshot() {
                await applySession(snapshot)
            }
            await refreshTopicsIfPossible(force: true)
            try? await refreshTopicDetailAfterMutation(topicId: topicID, sessionStore: sessionStore)
        } catch {
            _ = await handleInteractionError(error)
            throw error
        }
    }

    func fetchPost(postID: UInt64) async throws -> TopicPostState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchPost(postID: postID)
    }

    func updatePost(
        topicID: UInt64,
        postID: UInt64,
        raw: String,
        editReason: String? = nil
    ) async throws -> TopicPostState {
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }

        let sessionStore = try await sessionStoreValue()
        guard session.readiness.canWriteAuthenticatedApi else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postID) else {
            return try await sessionStore.fetchPost(postID: postID)
        }

        mutatingPostIDs.insert(postID)
        defer { mutatingPostIDs.remove(postID) }

        do {
            errorMessage = nil
            let updatedPost = try await performWriteWithCloudflareRetry {
                try await sessionStore.updatePost(
                    postID: postID,
                    raw: trimmedRaw,
                    editReason: editReason
                )
            }
            if let snapshot = try? await sessionStore.snapshot() {
                await applySession(snapshot)
            }
            try? await refreshTopicDetailAfterMutation(topicId: topicID, sessionStore: sessionStore)
            await refreshTopicsIfPossible(force: false)
            return updatedPost
        } catch {
            _ = await handleInteractionError(error)
            throw error
        }
    }

    func fetchDrafts(
        offset: UInt32? = nil,
        limit: UInt32? = nil
    ) async throws -> DraftListResponseState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchDrafts(offset: offset, limit: limit)
    }

    func fetchReadHistory(page: UInt32? = nil) async throws -> TopicListState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchReadHistory(page: page)
    }

    func fetchDraft(draftKey: String) async throws -> DraftState? {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchDraft(draftKey: draftKey)
    }

    func saveDraft(
        draftKey: String,
        data: DraftDataState,
        sequence: UInt32
    ) async throws -> UInt32 {
        let sessionStore = try await sessionStoreValue()
        return try await performWriteWithCloudflareRetry {
            try await sessionStore.saveDraft(
                draftKey: draftKey,
                data: data,
                sequence: sequence
            )
        }
    }

    func deleteDraft(
        draftKey: String,
        sequence: UInt32? = nil
    ) async throws {
        let sessionStore = try await sessionStoreValue()
        try await performWriteWithCloudflareRetry {
            try await sessionStore.deleteDraft(draftKey: draftKey, sequence: sequence)
        }
    }

    func uploadImage(
        fileName: String,
        mimeType: String?,
        bytes: Data
    ) async throws -> UploadResultState {
        let sessionStore = try await sessionStoreValue()
        return try await performWriteWithCloudflareRetry {
            try await sessionStore.uploadImage(
                fileName: fileName,
                mimeType: mimeType,
                bytes: bytes
            )
        }
    }

    func lookupUploadUrls(shortUrls: [String]) async throws -> [ResolvedUploadUrlState] {
        let sessionStore = try await sessionStoreValue()
        return try await performWriteWithCloudflareRetry {
            try await sessionStore.lookupUploadUrls(shortUrls: shortUrls)
        }
    }

    func setPostLiked(
        topicId: UInt64,
        postId: UInt64,
        liked: Bool
    ) async throws {
        let sessionStore = try await sessionStoreValue()
        guard session.readiness.canWriteAuthenticatedApi else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postId) else {
            return
        }

        mutatingPostIDs.insert(postId)
        defer { mutatingPostIDs.remove(postId) }

        do {
            errorMessage = nil
            let update = try await performWriteWithCloudflareRetry {
                if liked {
                    try await sessionStore.likePost(postID: postId)
                } else {
                    try await sessionStore.unlikePost(postID: postId)
                }
            }
            if let snapshot = try? await sessionStore.snapshot() {
                await applySession(snapshot)
            }
            if let update {
                applyPostReactionUpdate(topicId: topicId, postId: postId, update: update)
            } else {
                try? await refreshTopicDetailAfterMutation(topicId: topicId, sessionStore: sessionStore)
            }
        } catch {
            _ = await handleInteractionError(error)
            throw error
        }
    }

    func togglePostReaction(
        topicId: UInt64,
        postId: UInt64,
        reactionId: String
    ) async throws {
        let trimmedReactionID = reactionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReactionID.isEmpty else {
            return
        }

        let sessionStore = try await sessionStoreValue()
        guard session.readiness.canWriteAuthenticatedApi else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postId) else {
            return
        }

        mutatingPostIDs.insert(postId)
        defer { mutatingPostIDs.remove(postId) }

        do {
            errorMessage = nil
            let update = try await performWriteWithCloudflareRetry {
                try await sessionStore.togglePostReaction(
                    postID: postId,
                    reactionID: trimmedReactionID
                )
            }
            applyPostReactionUpdate(topicId: topicId, postId: postId, update: update)
        } catch {
            _ = await handleInteractionError(error)
            throw error
        }
    }

    func votePoll(
        topicID: UInt64,
        postID: UInt64,
        pollName: String,
        options: [String]
    ) async throws -> PollState {
        let sessionStore = try await sessionStoreValue()
        guard session.readiness.canWriteAuthenticatedApi else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postID) else {
            throw FireTopicInteractionError.unavailable
        }

        mutatingPostIDs.insert(postID)
        defer { mutatingPostIDs.remove(postID) }

        do {
            errorMessage = nil
            let poll = try await performWriteWithCloudflareRetry {
                try await sessionStore.votePoll(
                    postID: postID,
                    pollName: pollName,
                    options: options
                )
            }
            try? await refreshTopicDetailAfterMutation(topicId: topicID, sessionStore: sessionStore)
            return poll
        } catch {
            _ = await handleInteractionError(error)
            throw error
        }
    }

    func unvotePoll(
        topicID: UInt64,
        postID: UInt64,
        pollName: String
    ) async throws -> PollState {
        let sessionStore = try await sessionStoreValue()
        guard session.readiness.canWriteAuthenticatedApi else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postID) else {
            throw FireTopicInteractionError.unavailable
        }

        mutatingPostIDs.insert(postID)
        defer { mutatingPostIDs.remove(postID) }

        do {
            errorMessage = nil
            let poll = try await performWriteWithCloudflareRetry {
                try await sessionStore.unvotePoll(postID: postID, pollName: pollName)
            }
            try? await refreshTopicDetailAfterMutation(topicId: topicID, sessionStore: sessionStore)
            return poll
        } catch {
            _ = await handleInteractionError(error)
            throw error
        }
    }

    func voteTopic(topicID: UInt64, voted: Bool) async throws -> VoteResponseState {
        let sessionStore = try await sessionStoreValue()
        guard session.readiness.canWriteAuthenticatedApi else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }

        do {
            errorMessage = nil
            let response = try await performWriteWithCloudflareRetry {
                if voted {
                    try await sessionStore.voteTopic(topicID: topicID)
                } else {
                    try await sessionStore.unvoteTopic(topicID: topicID)
                }
            }
            try? await refreshTopicDetailAfterMutation(topicId: topicID, sessionStore: sessionStore)
            return response
        } catch {
            _ = await handleInteractionError(error)
            throw error
        }
    }

    func fetchTopicVoters(topicID: UInt64) async throws -> [VotedUserState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchTopicVoters(topicID: topicID)
    }

    func reportTopicTimings(
        topicId: UInt64,
        topicTimeMs: UInt32,
        timings: [UInt32: UInt32]
    ) async -> Bool {
        guard let sessionStore else { return false }
        guard session.readiness.canWriteAuthenticatedApi else { return false }
        guard topicTimeMs > 0 else { return true }

        let timingEntries = timings
            .filter { $0.key > 0 && $0.value > 0 }
            .sorted { $0.key < $1.key }
            .map { postNumber, milliseconds in
                TopicTimingEntryState(
                    postNumber: postNumber,
                    milliseconds: milliseconds
                )
            }
        guard !timingEntries.isEmpty else { return true }

        do {
            let accepted = try await sessionStore.reportTopicTimings(
                input: TopicTimingsRequestState(
                    topicId: topicId,
                    topicTimeMs: topicTimeMs,
                    timings: timingEntries
                )
            )
            return accepted
        } catch {
            _ = await handleLoginRequiredIfNeeded(error)
            return false
        }
    }

    // MARK: - Notifications

    func loadRecentNotifications(force: Bool = true) async {
        guard let sessionStore else { return }
        guard session.readiness.canReadAuthenticatedApi else { return }
        guard !isLoadingNotifications || force else { return }

        isLoadingNotifications = true
        defer { isLoadingNotifications = false }
        do {
            let list = try await sessionStore.fetchRecentNotifications()
            recentNotifications = list.notifications
            if let state = try? await sessionStore.notificationState() {
                notificationUnreadCount = Int(state.counters.allUnread)
            }
        } catch {
            _ = await handleRecoverableSessionErrorIfNeeded(error)
            // Silent: notification failures shouldn't interrupt UX
        }
    }

    func markNotificationRead(id: UInt64) {
        guard let sessionStore else { return }
        Task {
            do {
                let state = try await sessionStore.markNotificationRead(id: id)
                notificationUnreadCount = Int(state.counters.allUnread)
                if let idx = recentNotifications.firstIndex(where: { $0.id == id }) {
                    recentNotifications[idx].read = true
                }
                if state.hasLoadedFull {
                    notificationFullList = state.full
                }
            } catch {
                _ = await self.handleRecoverableSessionErrorIfNeeded(error)
            }
        }
    }

    func markAllNotificationsRead() {
        guard let sessionStore else { return }
        Task {
            do {
                let state = try await sessionStore.markAllNotificationsRead()
                notificationUnreadCount = Int(state.counters.allUnread)
                recentNotifications = recentNotifications.map {
                    var n = $0; n.read = true; return n
                }
                if state.hasLoadedFull {
                    notificationFullList = state.full
                }
            } catch {
                _ = await self.handleRecoverableSessionErrorIfNeeded(error)
            }
        }
    }

    func loadNotificationFullPage(offset: UInt32?) async {
        guard let sessionStore else { return }
        guard session.readiness.canReadAuthenticatedApi else { return }
        guard !isLoadingNotificationFullPage else { return }

        isLoadingNotificationFullPage = true
        defer { isLoadingNotificationFullPage = false }
        do {
            _ = try await sessionStore.fetchNotifications(limit: nil, offset: offset)
            let state = try await sessionStore.notificationState()
            notificationFullList = state.full
            notificationFullNextOffset = state.fullNextOffset
            hasMoreNotificationFull = state.fullNextOffset != nil
            notificationUnreadCount = Int(state.counters.allUnread)
        } catch {
            _ = await handleRecoverableSessionErrorIfNeeded(error)
        }
    }

    // MARK: - Search

    var canLoadMoreSearchResults: Bool {
        guard let searchResult else { return false }
        switch searchScope {
        case .all:
            return searchResult.groupedResult.moreFullPageResults
                || searchResult.groupedResult.morePosts
                || searchResult.groupedResult.moreUsers
        case .topic, .post:
            return searchResult.groupedResult.moreFullPageResults
                || searchResult.groupedResult.morePosts
        case .user:
            return searchResult.groupedResult.moreUsers
        }
    }

    func resetSearch() {
        clearSearchState(resetQuery: true)
    }

    func setSearchScope(_ scope: FireSearchScope) {
        guard searchScope != scope else {
            return
        }
        searchScope = scope
        guard searchResult != nil else {
            return
        }
        submitSearch(reset: true)
    }

    func submitSearch(reset: Bool) {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clearSearchState(resetQuery: false)
            return
        }
        if !reset && (isSearching || isAppendingSearch) {
            return
        }

        searchTask?.cancel()
        let nextPage = reset ? UInt32(1) : searchCurrentPage + 1
        let requestID = latestSearchRequestID &+ 1
        latestSearchRequestID = requestID
        let scope = searchScope

        if reset {
            isSearching = true
            isAppendingSearch = false
        } else {
            isAppendingSearch = true
        }

        searchTask = Task { [weak self] in
            guard let self else { return }

            do {
                let response = try await self.search(
                    query: trimmedQuery,
                    typeFilter: scope.typeFilter,
                    page: nextPage
                )
                guard !Task.isCancelled, requestID == self.latestSearchRequestID else {
                    return
                }

                self.searchErrorMessage = nil
                self.searchCurrentPage = nextPage
                self.searchResult = reset
                    ? response
                    : self.mergeSearchResult(existing: self.searchResult, incoming: response)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, requestID == self.latestSearchRequestID else {
                    return
                }
                if await self.handleRecoverableSessionErrorIfNeeded(error) {
                    self.searchErrorMessage = nil
                } else {
                    self.searchErrorMessage = error.localizedDescription
                }
            }

            guard requestID == self.latestSearchRequestID else {
                return
            }
            self.isSearching = false
            self.isAppendingSearch = false
            self.searchTask = nil
        }
    }

    func search(
        query: String,
        typeFilter: SearchTypeFilterState?,
        page: UInt32? = nil
    ) async throws -> SearchResultState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.search(
            query: SearchQueryState(
                q: query,
                page: page,
                typeFilter: typeFilter
            )
        )
    }

    // Reserved for upcoming composer tag autocomplete surfaces.
    func searchTags(
        query: String?,
        filterForInput: Bool = false,
        limit: UInt32? = nil,
        categoryID: UInt64? = nil,
        selectedTags: [String] = []
    ) async throws -> TagSearchResultState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.searchTags(
            query: TagSearchQueryState(
                q: query,
                filterForInput: filterForInput,
                limit: limit,
                categoryId: categoryID,
                selectedTags: selectedTags
            )
        )
    }

    // Reserved for upcoming composer @mention autocomplete surfaces.
    func searchUsers(
        term: String,
        includeGroups: Bool = true,
        limit: UInt32 = 6,
        topicID: UInt64? = nil,
        categoryID: UInt64? = nil
    ) async throws -> UserMentionResultState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.searchUsers(
            query: UserMentionQueryState(
                term: term,
                includeGroups: includeGroups,
                limit: limit,
                topicId: topicID,
                categoryId: categoryID
            )
        )
    }

    // MARK: - Diagnostics

    func listLogFiles() async throws -> [LogFileSummaryState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.listLogFiles()
    }

    func readLogFile(relativePath: String) async throws -> LogFileDetailState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.readLogFile(relativePath: relativePath)
    }

    func readLogFilePage(
        relativePath: String,
        cursor: UInt64? = nil,
        maxBytes: UInt64? = nil,
        direction: DiagnosticsPageDirectionState
    ) async throws -> LogFilePageState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.readLogFilePage(
            relativePath: relativePath,
            cursor: cursor,
            maxBytes: maxBytes,
            direction: direction
        )
    }

    func listNetworkTraces(limit: UInt64 = 200) async throws -> [NetworkTraceSummaryState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.listNetworkTraces(limit: limit)
    }

    func networkTraceDetail(traceID: UInt64) async throws -> NetworkTraceDetailState {
        let sessionStore = try await sessionStoreValue()
        guard let detail = try await sessionStore.networkTraceDetail(traceID: traceID) else {
            throw FireDiagnosticsAccessError.traceNotFound
        }
        return detail
    }

    func networkTraceBodyPage(
        traceID: UInt64,
        cursor: UInt64? = nil,
        maxBytes: UInt64? = nil,
        direction: DiagnosticsPageDirectionState
    ) async throws -> NetworkTraceBodyPageState? {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.networkTraceBodyPage(
            traceID: traceID,
            cursor: cursor,
            maxBytes: maxBytes,
            direction: direction
        )
    }

    func diagnosticSessionID() async throws -> String {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.diagnosticSessionID()
    }

    func exportSupportBundle(scenePhase: String?) async throws -> SupportBundleExportState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.exportSupportBundle(
            platform: "ios",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildNumber: Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String,
            scenePhase: scenePhase
        )
    }

    func flushDiagnosticsLogs(sync: Bool = true) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.flushLogs(sync: sync)
    }

    func handleDiagnosticsScenePhaseChange(_ phase: String, isAuthenticated: Bool) {
        Task {
            guard let sessionStore else { return }
            let logger = sessionStore.makeLogger(target: Self.diagnosticsLifecycleLogTarget)
            logger.info("scene phase changed to \(phase), authenticated=\(isAuthenticated)")
            if phase == "background" || phase == "inactive" {
                try? await sessionStore.flushLogs(sync: phase == "background")
            }
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - MessageBus lifecycle

    private func startMessageBus() async {
        guard let sessionStore else { return }
        guard session.readiness.canOpenMessageBus else { return }
        guard !isMessageBusActive else { return }

        messageBusRetryTask?.cancel()
        messageBusRetryTask = nil

        let coordinator = FireMessageBusCoordinator { [weak self] event in
            self?.handleMessageBusEvent(event)
        }
        messageBusCoordinator = coordinator

        do {
            _ = try await sessionStore.startMessageBus(handler: coordinator)
            isMessageBusActive = true
            messageBusStartRetryCount = 0
            clearMessageBusError()
        } catch {
            messageBusCoordinator = nil
            if await handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            errorMessage = Self.messageBusErrorPrefix + error.localizedDescription
            scheduleMessageBusRetry()
        }
    }

    private func stopMessageBus() {
        messageBusRetryTask?.cancel()
        messageBusRetryTask = nil
        messageBusStartRetryCount = 0
        pendingNotificationStateRefreshTask?.cancel()
        pendingNotificationStateRefreshTask = nil
        clearMessageBusError()
        guard isMessageBusActive else { return }
        pendingTopicListRefreshTask?.cancel()
        pendingTopicListRefreshTask = nil
        topicListMessageBusRefreshController.reset()
        pendingTopicDetailRefreshTasks.values.forEach { $0.cancel() }
        pendingTopicDetailRefreshTasks = [:]
        topicPresenceHeartbeatTasks.values.forEach { $0.cancel() }
        topicPresenceHeartbeatTasks = [:]
        topicPresenceUsersByTopic = [:]
        messageBusCoordinator = nil
        isMessageBusActive = false
        guard let sessionStore else { return }
        Task { try? await sessionStore.stopMessageBus(clearSubscriptions: true) }
    }

    private func handleMessageBusEvent(_ event: MessageBusEventState) {
        switch event.kind {
        case .topicList:
            scheduleTopicListRefresh(for: event)

        case .topicDetail:
            guard let topicId = event.topicId else { return }
            guard topicDetails[topicId] != nil else { return }
            scheduleTopicDetailRefresh(topicId: topicId)

        case .topicReaction:
            guard let topicId = event.topicId else { return }
            guard topicDetails[topicId] != nil else { return }
            scheduleTopicDetailRefresh(topicId: topicId)

        case .presence:
            guard let topicId = event.topicId else { return }
            refreshTopicPresenceState(topicId: topicId)

        case .notification:
            scheduleNotificationStateRefresh()

        case .notificationAlert:
            break

        case .unknown:
            break
        }
    }

    private var currentTopicListRefreshScope: FireTopicListRefreshScope {
        FireTopicListRefreshScope(
            kind: selectedTopicKind,
            categoryId: selectedHomeCategoryId,
            tags: selectedHomeTags
        )
    }

    private func scheduleTopicListRefresh(for event: MessageBusEventState) {
        guard let busKind = event.topicListKind else { return }
        let scope = currentTopicListRefreshScope
        guard busKind == scope.kind else { return }

        let allowIncremental = scope.supportsIncrementalMessageBusRefresh && !topicRows.isEmpty
        guard let delay = topicListMessageBusRefreshController.register(
            event: event,
            for: scope,
            now: topicListRefreshClock.now,
            allowIncremental: allowIncremental
        ) else {
            return
        }

        pendingTopicListRefreshTask?.cancel()
        pendingTopicListRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            guard let self else { return }

            while self.isLoadingTopics {
                do {
                    try await Task.sleep(for: Self.topicListRefreshLoadingPollInterval)
                } catch {
                    return
                }
            }

            let scope = self.currentTopicListRefreshScope
            let refreshMode = self.topicListMessageBusRefreshController.takePendingRefresh(for: scope)
            self.pendingTopicListRefreshTask = nil

            guard let refreshMode else { return }
            await self.refreshTopicsFromMessageBus(refreshMode)
        }
    }

    private func scheduleTopicDetailRefresh(topicId: UInt64) {
        pendingTopicDetailRefreshTasks[topicId]?.cancel()
        pendingTopicDetailRefreshTasks[topicId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            guard let self, let store = self.sessionStore else { return }
            guard self.topicDetails[topicId] != nil else { return }
            let anchorPostNumber = self.topicDetailTargetPostNumbers[topicId]
            do {
                let detail = try await store.fetchTopicDetailInitial(
                    query: TopicDetailQueryState(
                        topicId: topicId,
                        postNumber: anchorPostNumber,
                        trackVisit: false,
                        filter: nil,
                        usernameFilters: nil,
                        filterTopLevelReplies: false
                    )
                )
                self.applyTopicDetail(detail, topicId: topicId)
            } catch {
                if await self.handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
            }
        }
    }

    private func scheduleNotificationStateRefresh() {
        pendingNotificationStateRefreshTask?.cancel()
        pendingNotificationStateRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            guard let self, let store = self.sessionStore else { return }
            guard let state = try? await store.notificationState() else { return }
            self.notificationUnreadCount = Int(state.counters.allUnread)
            self.recentNotifications = state.recent
            self.pendingNotificationStateRefreshTask = nil
        }
    }

    private func refreshTopicPresenceState(topicId: UInt64) {
        guard let store = sessionStore else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let presence = try? await store.topicReplyPresenceState(topicId: topicId) else {
                return
            }
            self.applyTopicPresenceState(presence)
        }
    }

    func beginTopicReplyPresence(topicId: UInt64) {
        guard isMessageBusActive else { return }
        guard session.readiness.canWriteAuthenticatedApi else { return }
        guard topicPresenceHeartbeatTasks[topicId] == nil else { return }
        guard let store = sessionStore else { return }

        topicPresenceHeartbeatTasks[topicId] = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await store.updateTopicReplyPresence(topicId: topicId, active: true)
                } catch {
                    return
                }

                guard let self else { return }
                guard self.topicPresenceHeartbeatTasks[topicId] != nil else { return }

                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
            }
        }
    }

    func endTopicReplyPresence(topicId: UInt64) async {
        let task = topicPresenceHeartbeatTasks.removeValue(forKey: topicId)
        task?.cancel()
        guard let store = sessionStore else { return }
        try? await store.updateTopicReplyPresence(topicId: topicId, active: false)
    }

    // MARK: - Private helpers

    private func prepareLoginNetworkAccess() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true

        let session = URLSession(configuration: configuration)
        var request = URLRequest(url: loginURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (_, response) = try await session.data(for: request)
        guard response is HTTPURLResponse else {
            throw FireLoginPreparationError.invalidResponse
        }
    }

    private func refreshTopicsIfPossible(force: Bool) async {
        cancelPendingTopicListRefresh()
        await loadTopics(page: nil, reset: true, force: force, refreshMode: .full)
    }

    private func refreshTopicsFromMessageBus(_ refreshMode: FireTopicListMessageBusRefreshMode) async {
        await loadTopics(page: nil, reset: true, force: true, refreshMode: refreshMode)
    }

    @discardableResult
    private func loadTopics(
        page: UInt32?,
        reset: Bool,
        force: Bool,
        refreshMode: FireTopicListMessageBusRefreshMode = .full
    ) async -> Bool {
        if !session.readiness.canReadAuthenticatedApi {
            clearTopicState()
            return false
        }
        if isLoadingTopics {
            return false
        }
        if reset && !force && !topicRows.isEmpty {
            return false
        }

        isLoadingTopics = true
        isAppendingTopics = !reset
        defer {
            isLoadingTopics = false
            isAppendingTopics = false
        }

        do {
            let sessionStore = try await sessionStoreValue()
            errorMessage = nil
            let requestedKind = selectedTopicKind
            let categoryId = selectedHomeCategoryId
            let requestedTags = selectedHomeTags
            let requestedScope = FireTopicListRefreshScope(
                kind: requestedKind,
                categoryId: categoryId,
                tags: requestedTags
            )
            let categorySlug = categoryId.flatMap { categoryPresentation(for: $0)?.slug }
            let parentSlug: String? = categoryId.flatMap { id in
                guard let cat = categoryPresentation(for: id),
                      let parentId = cat.parentCategoryId else { return nil }
                return categoryPresentation(for: parentId)?.slug
            }
            let primaryTag = requestedTags.first
            let additionalTags = requestedTags.count > 1
                ? Array(requestedTags.dropFirst())
                : []
            let incrementalTopicIDs: [UInt64]
            switch refreshMode {
            case .full:
                incrementalTopicIDs = []
            case .incremental(let topicIDs):
                incrementalTopicIDs = topicIDs
            }
            let usesIncrementalRefresh = page == nil
                && reset
                && !incrementalTopicIDs.isEmpty
                && requestedScope.supportsIncrementalMessageBusRefresh
                && !topicRows.isEmpty
            let response = try await sessionStore.fetchTopicList(
                query: TopicListQueryState(
                    kind: requestedKind,
                    page: page,
                    topicIds: usesIncrementalRefresh ? incrementalTopicIDs : [],
                    order: nil,
                    ascending: nil,
                    categorySlug: categorySlug,
                    categoryId: categoryId,
                    parentCategorySlug: parentSlug,
                    tag: primaryTag,
                    additionalTags: additionalTags,
                    matchAllTags: !additionalTags.isEmpty
                )
            )
            guard requestedScope == currentTopicListRefreshScope else {
                return false
            }
            let mergedTopicRows = if reset {
                if usesIncrementalRefresh {
                    FireTopicListMessageBusRefreshMerger.merge(
                        existing: topicRows,
                        incoming: response.rows
                    )
                } else {
                    response.rows
                }
            } else {
                mergeItemsByID(topicRows, response.rows, keyPath: \.topic.id)
            }
            let visibleTopicIDs = Set(mergedTopicRows.map(\.topic.id))
            topicRows = mergedTopicRows
            if !usesIncrementalRefresh {
                moreTopicsUrl = response.moreTopicsUrl
                nextTopicsPage = response.nextPage
            }
            let retainedTopicIDs = retainedTopicDetailIDs(visibleTopicIDs: visibleTopicIDs)
            pruneInactiveTopicDetailState(retaining: retainedTopicIDs)
            if reset && page == nil {
                topicListMessageBusRefreshController.markRefreshCompleted(
                    for: requestedScope,
                    at: topicListRefreshClock.now
                )
            }
            return true
        } catch {
            if await handleRecoverableSessionErrorIfNeeded(error) {
                return false
            }
            if reset, case .full = refreshMode {
                topicRows = []
                moreTopicsUrl = nil
                nextTopicsPage = nil
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func clearTopicState() {
        cancelPendingTopicListRefresh()
        pendingTopicDetailRefreshTasks.values.forEach { $0.cancel() }
        pendingTopicDetailRefreshTasks = [:]
        topicPresenceHeartbeatTasks.values.forEach { $0.cancel() }
        topicPresenceHeartbeatTasks = [:]
        for task in topicPostPreloadTasks.values {
            task.cancel()
        }
        activeTopicDetailOwnerTokens = [:]
        topicPostPreloadTasks = [:]
        topicRows = []
        moreTopicsUrl = nil
        nextTopicsPage = nil
        topicDetails = [:]
        topicPostPaginationStates = [:]
        topicPresenceUsersByTopic = [:]
        isLoadingTopics = false
        isAppendingTopics = false
        loadingTopicIDs = []
        loadingMoreTopicPostIDs = []
        submittingReplyTopicIDs = []
        mutatingPostIDs = []
        selectedHomeCategoryId = nil
        selectedHomeTags = []
    }

    private func cancelPendingTopicListRefresh() {
        pendingTopicListRefreshTask?.cancel()
        pendingTopicListRefreshTask = nil

        let scope = currentTopicListRefreshScope
        topicListMessageBusRefreshController.clearPending(for: scope)
    }

    private func clearNotificationState() {
        notificationUnreadCount = 0
        recentNotifications = []
    }

    private func clearSearchState(resetQuery: Bool) {
        searchTask?.cancel()
        searchTask = nil
        latestSearchRequestID = latestSearchRequestID &+ 1
        if resetQuery {
            searchQuery = ""
        }
        searchResult = nil
        searchCurrentPage = 1
        isSearching = false
        isAppendingSearch = false
        searchErrorMessage = nil
        searchScope = .all
    }

    private func finishInitialStateLoading(generation: UInt64) {
        guard initialStateLoadGeneration == generation else {
            return
        }

        initialStateLoadingDelayTask?.cancel()
        initialStateLoadingDelayTask = nil
        isBootstrappingSession = false
        isStartupLoadingVisible = false
        initialStateTask = nil
    }

    private func applyTopicPresenceState(_ state: TopicPresenceState) {
        let currentUserID = session.bootstrap.currentUserId
        let filteredUsers = state.users.filter { user in
            guard let currentUserID else { return true }
            return user.id != currentUserID
        }

        if filteredUsers.isEmpty {
            topicPresenceUsersByTopic.removeValue(forKey: state.topicId)
        } else {
            topicPresenceUsersByTopic[state.topicId] = filteredUsers
        }
    }

    private func applySession(_ session: SessionState) async {
        self.session = session
        session.mirrorCookiesToNativeStorage()
        topicCategories = Dictionary(uniqueKeysWithValues: session.bootstrap.categories.map { ($0.id, $0) })

        // Sync notification badge from in-memory state when available
        if session.readiness.canReadAuthenticatedApi, let store = sessionStore {
            if let state = try? await store.notificationState() {
                notificationUnreadCount = Int(state.counters.allUnread)
            }
        }

        // Reconcile MessageBus lifecycle
        if session.readiness.canOpenMessageBus && !isMessageBusActive {
            await startMessageBus()
        } else if !session.readiness.canOpenMessageBus && isMessageBusActive {
            stopMessageBus()
        } else if !session.readiness.canOpenMessageBus {
            stopMessageBus()
        }
    }

    private func scheduleMessageBusRetry() {
        guard session.readiness.canOpenMessageBus else { return }
        guard !isMessageBusActive else { return }
        guard messageBusStartRetryCount < 3 else { return }

        messageBusStartRetryCount += 1
        let retryDelay = Duration.seconds(Double(messageBusStartRetryCount * 2))
        messageBusRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: retryDelay)
            } catch {
                return
            }
            guard let self else { return }
            self.messageBusRetryTask = nil
            await self.startMessageBus()
        }
    }

    private func clearMessageBusError() {
        if errorMessage?.hasPrefix(Self.messageBusErrorPrefix) == true {
            errorMessage = nil
        }
    }

    private func refreshTopicDetailAfterMutation(
        topicId: UInt64,
        sessionStore: FireSessionStore
    ) async throws {
        let detail = try await sessionStore.fetchTopicDetailInitial(
            query: TopicDetailQueryState(
                topicId: topicId,
                postNumber: nil,
                trackVisit: false,
                filter: nil,
                usernameFilters: nil,
                filterTopLevelReplies: false
            )
        )
        applyTopicDetail(detail, topicId: topicId)
    }

    private func performWriteWithCloudflareRetry<T>(
        operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            guard case FireUniFfiError.CloudflareChallenge = error else {
                throw error
            }

            try? await syncPlatformCookiesFromWebViewStore()

            do {
                return try await operation()
            } catch {
                guard case FireUniFfiError.CloudflareChallenge = error else {
                    throw error
                }
                isPresentingLogin = true
                throw FireTopicInteractionError.requiresCloudflareVerification
            }
        }
    }

    @discardableResult
    private func handleRecoverableSessionErrorIfNeeded(_ error: Error) async -> Bool {
        if await handleLoginRequiredIfNeeded(error) {
            return true
        }
        return await handleCloudflareChallengeIfNeeded(error)
    }

    @discardableResult
    func handleLoginRequiredIfNeeded(_ error: Error) async -> Bool {
        guard case let FireUniFfiError.LoginRequired(message) = error else {
            return false
        }

        await resetSessionAndPresentLogin(
            message: message.isEmpty ? Self.loginRequiredMessage : message
        )
        return true
    }

    @discardableResult
    private func handleInteractionError(_ error: Error) async -> Bool {
        if await handleRecoverableSessionErrorIfNeeded(error) {
            return true
        }
        errorMessage = error.localizedDescription
        return false
    }

    @discardableResult
    func handleCloudflareChallengeIfNeeded(
        _ error: Error,
        message: String? = FireTopicInteractionError.requiresCloudflareVerification.errorDescription
    ) async -> Bool {
        guard case FireUniFfiError.CloudflareChallenge = error else {
            return false
        }

        await resetSessionAndPresentLogin(
            message: message ?? error.localizedDescription
        )
        return true
    }

    private func resetSessionAndPresentLogin(message: String) async {
        stopMessageBus()

        do {
            let recoveryStore = try await challengeRecoveryStoreValue()
            let cleared = try await recoveryStore.logoutLocal(preserveCfClearance: true)
            await applySession(cleared)
        } catch {
            await applySession(.placeholder(baseUrl: session.bootstrap.baseUrl))
        }

        selectedTopicKind = .latest
        clearTopicState()
        clearNotificationState()
        clearSearchState(resetQuery: true)
        errorMessage = message
        isPresentingLogin = true
    }

    private func evictTopicDetailState(topicId: UInt64, reason: String) {
        let removedDetail = topicDetails.removeValue(forKey: topicId) != nil
        let removedPagination = topicPostPaginationStates.removeValue(forKey: topicId) != nil
        let removedPresence = topicPresenceUsersByTopic.removeValue(forKey: topicId) != nil
        let removedLoadingTopic = loadingTopicIDs.remove(topicId) != nil
        let removedLoadingMore = loadingMoreTopicPostIDs.remove(topicId) != nil
        let refreshTask = pendingTopicDetailRefreshTasks.removeValue(forKey: topicId)
        let presenceTask = topicPresenceHeartbeatTasks.removeValue(forKey: topicId)
        let preloadTask = topicPostPreloadTasks.removeValue(forKey: topicId)
        refreshTask?.cancel()
        presenceTask?.cancel()
        preloadTask?.cancel()

        guard removedDetail
            || removedPagination
            || removedPresence
            || removedLoadingTopic
            || removedLoadingMore
            || refreshTask != nil
            || presenceTask != nil
            || preloadTask != nil
        else {
            return
        }

        topicDetailLogger()?.notice(
            "evicted topic detail state topic_id=\(topicId) reason=\(reason)"
        )
    }

    private func pruneInactiveTopicDetailState(retaining retainedTopicIDs: Set<UInt64>) {
        let trackedTopicIDs = Set(topicDetails.keys)
            .union(topicPostPaginationStates.keys)
            .union(topicPresenceUsersByTopic.keys)
            .union(loadingTopicIDs)
            .union(loadingMoreTopicPostIDs)
            .union(topicPostPreloadTasks.keys)
            .union(pendingTopicDetailRefreshTasks.keys)
            .union(topicPresenceHeartbeatTasks.keys)
        let inactiveTopicIDs = trackedTopicIDs.subtracting(retainedTopicIDs)
        guard !inactiveTopicIDs.isEmpty else {
            return
        }

        let activeTopicIDs = retainedTopicIDs.subtracting(Set(topicRows.map(\.topic.id)))
        topicDetailLogger()?.notice(
            "pruning inactive topic detail state retained_active_topic_ids=\(Self.formattedTopicIDs(activeTopicIDs)) pruned_topic_ids=\(Self.formattedTopicIDs(inactiveTopicIDs))"
        )

        for topicId in inactiveTopicIDs.sorted() {
            evictTopicDetailState(topicId: topicId, reason: "topic list refresh pruned inactive detail")
        }
    }

    private static func formattedTopicIDs(_ topicIDs: Set<UInt64>) -> String {
        topicIDs.sorted().map(String.init).joined(separator: ",")
    }

    private func syncPlatformCookiesFromWebViewStore() async throws {
        let loginCoordinator = try await loginCoordinatorValue()
        let session = try await loginCoordinator.refreshPlatformCookies()
        await applySession(session)
    }

    private func topicDetailLogger() -> FireHostLogger? {
        sessionStore?.makeLogger(target: Self.topicDetailLogTarget)
    }

    private func applyTopicDetail(_ incomingDetail: TopicDetailState, topicId: UInt64) {
        let previousDetail = topicDetails[topicId]
        let previousTargetLoadedCount = topicPostPaginationStates[topicId]?.targetLoadedCount
            ?? previousDetail.map { FireTopicPresentation.loadedWindowCount(detail: $0) }
            ?? 0
        let previousWasFullyLoaded = previousDetail.map {
            previousTargetLoadedCount >= $0.postStream.stream.count
        } ?? false

        var detail = incomingDetail
        if let previousDetail {
            detail.postStream.posts = FireTopicPresentation.mergeTopicPosts(
                existing: previousDetail.postStream.posts,
                incoming: detail.postStream.posts,
                orderedPostIDs: detail.postStream.stream
            )
        }
        detail = FireTopicPresentation.recomposedDetail(detail)

        let loadedWindowCount = FireTopicPresentation.loadedWindowCount(detail: detail)
        let targetLoadedCount = min(
            max(previousWasFullyLoaded ? detail.postStream.stream.count : previousTargetLoadedCount, loadedWindowCount),
            detail.postStream.stream.count
        )
        topicDetails[topicId] = detail
        topicPostPaginationStates[topicId] = FireTopicPostPaginationState(
            targetLoadedCount: targetLoadedCount
        )

        let missingPostIDs = FireTopicPresentation.missingPostIDs(
            in: detail,
            upTo: targetLoadedCount
        )
        if !missingPostIDs.isEmpty {
            Task {
                await hydrateTopicPostsToTargetIfNeeded(topicId: topicId)
            }
        }
    }

    private func applyCreatedReply(_ reply: TopicPostState, topicId: UInt64) {
        guard var detail = topicDetails[topicId] else {
            return
        }

        let isNewPost = !detail.postStream.stream.contains(reply.id)
        if isNewPost {
            detail.postStream.stream.append(reply.id)
        }

        if let postIndex = detail.postStream.posts.firstIndex(where: { $0.id == reply.id }) {
            detail.postStream.posts[postIndex] = reply
        } else {
            detail.postStream.posts.append(reply)
        }

        if isNewPost {
            detail.postsCount = max(
                detail.postsCount + 1,
                UInt32(detail.postStream.stream.count)
            )
        }

        detail = FireTopicPresentation.recomposedDetail(detail)
        topicDetails[topicId] = detail

        var pagination = topicPostPaginationStates[topicId]
            ?? FireTopicPostPaginationState(
                targetLoadedCount: FireTopicPresentation.loadedWindowCount(detail: detail)
            )
        pagination.targetLoadedCount = max(pagination.targetLoadedCount, detail.postStream.stream.count)
        pagination.exhaustedPostIDs.remove(reply.id)
        topicPostPaginationStates[topicId] = pagination
    }

    private func loadMoreTopicPostsIfNeeded(topicId: UInt64) async {
        guard var pagination = topicPostPaginationStates[topicId],
              let detail = topicDetails[topicId] else {
            return
        }
        guard !Task.isCancelled else {
            return
        }
        guard !loadingMoreTopicPostIDs.contains(topicId) else {
            return
        }

        let loadedWindowCount = FireTopicPresentation.loadedWindowCount(detail: detail)
        let currentTargetLoadedCount = min(
            max(pagination.targetLoadedCount, loadedWindowCount),
            detail.postStream.stream.count
        )
        let missingPostIDs = FireTopicPresentation.missingPostIDs(
            in: detail,
            upTo: currentTargetLoadedCount,
            excluding: pagination.exhaustedPostIDs
        )
        guard !missingPostIDs.isEmpty || currentTargetLoadedCount < detail.postStream.stream.count else {
            return
        }

        if currentTargetLoadedCount < detail.postStream.stream.count {
            pagination.targetLoadedCount = min(
                currentTargetLoadedCount + Self.topicPostPageSize,
                detail.postStream.stream.count
            )
            topicPostPaginationStates[topicId] = pagination
        }
        await hydrateTopicPostsToTargetIfNeeded(topicId: topicId)
    }

    private func hydrateTopicPostsToTargetIfNeeded(topicId: UInt64) async {
        guard let sessionStore else {
            return
        }
        guard !Task.isCancelled else {
            return
        }
        guard !loadingMoreTopicPostIDs.contains(topicId) else {
            return
        }

        loadingMoreTopicPostIDs.insert(topicId)
        defer { loadingMoreTopicPostIDs.remove(topicId) }

        var hydratedPosts: [TopicPostState] = []
        var hydratedPostIDs: Set<UInt64> = []
        var exhaustedPostIDs: Set<UInt64> = []

        while !Task.isCancelled {
            guard let detail = topicDetails[topicId],
                  let pagination = topicPostPaginationStates[topicId] else {
                return
            }

            let missingPostIDs = FireTopicPresentation.missingPostIDs(
                orderedPostIDs: detail.postStream.stream,
                loadedPostIDs: Set(detail.postStream.posts.map(\.id)).union(hydratedPostIDs),
                upTo: pagination.targetLoadedCount,
                excluding: pagination.exhaustedPostIDs.union(exhaustedPostIDs)
            )
            guard !missingPostIDs.isEmpty else {
                applyHydratedTopicPostsIfNeeded(
                    topicId: topicId,
                    posts: hydratedPosts,
                    exhaustedPostIDs: exhaustedPostIDs
                )
                return
            }

            let batchPostIDs = Array(missingPostIDs.prefix(Self.topicPostPageSize))

            do {
                let fetchedPosts = try await sessionStore.fetchTopicPosts(
                    topicID: topicId,
                    postIDs: batchPostIDs
                )
                let returnedPostIDs = Set(fetchedPosts.map(\.id))
                exhaustedPostIDs.formUnion(
                    batchPostIDs.filter { !returnedPostIDs.contains($0) }
                )
                hydratedPosts.append(contentsOf: fetchedPosts)
                hydratedPostIDs.formUnion(returnedPostIDs)
            } catch {
                applyHydratedTopicPostsIfNeeded(
                    topicId: topicId,
                    posts: hydratedPosts,
                    exhaustedPostIDs: exhaustedPostIDs
                )
                if await handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
                return
            }
        }

        applyHydratedTopicPostsIfNeeded(
            topicId: topicId,
            posts: hydratedPosts,
            exhaustedPostIDs: exhaustedPostIDs
        )
    }

    private func applyHydratedTopicPostsIfNeeded(
        topicId: UInt64,
        posts: [TopicPostState],
        exhaustedPostIDs: Set<UInt64>
    ) {
        guard !posts.isEmpty || !exhaustedPostIDs.isEmpty else {
            return
        }
        guard var currentDetail = topicDetails[topicId],
              var currentPagination = topicPostPaginationStates[topicId] else {
            return
        }

        currentPagination.exhaustedPostIDs.formUnion(exhaustedPostIDs)
        topicPostPaginationStates[topicId] = currentPagination

        guard !posts.isEmpty else {
            return
        }

        currentDetail.postStream.posts = FireTopicPresentation.mergeTopicPosts(
            existing: currentDetail.postStream.posts,
            incoming: posts,
            orderedPostIDs: currentDetail.postStream.stream
        )
        topicDetails[topicId] = FireTopicPresentation.recomposedDetail(currentDetail)
    }

    private func applyPostReactionUpdate(
        topicId: UInt64,
        postId: UInt64,
        update: PostReactionUpdateState
    ) {
        guard var detail = topicDetails[topicId] else {
            return
        }
        guard let postIndex = detail.postStream.posts.firstIndex(where: { $0.id == postId }) else {
            return
        }

        var post = detail.postStream.posts[postIndex]
        let previousHeartCount = post.reactions.first(where: { $0.id == "heart" })?.count
        let updatedHeartCount = update.reactions.first(where: { $0.id == "heart" })?.count

        post.reactions = update.reactions
        post.currentUserReaction = update.currentUserReaction

        if let updatedHeartCount {
            post.likeCount = updatedHeartCount
        } else if previousHeartCount != nil || post.currentUserReaction?.id == "heart" {
            post.likeCount = 0
        }

        detail.postStream.posts[postIndex] = post
        topicDetails[topicId] = FireTopicPresentation.recomposedDetail(detail)
    }

    private func mergeSearchResult(
        existing: SearchResultState?,
        incoming: SearchResultState
    ) -> SearchResultState {
        guard let existing else {
            return incoming
        }

        return SearchResultState(
            posts: mergeItemsByID(existing.posts, incoming.posts, keyPath: \.id),
            topics: mergeItemsByID(existing.topics, incoming.topics, keyPath: \.id),
            users: mergeItemsByID(existing.users, incoming.users, keyPath: \.id),
            groupedResult: incoming.groupedResult
        )
    }

    private func mergeItemsByID<Item>(
        _ existing: [Item],
        _ incoming: [Item],
        keyPath: KeyPath<Item, UInt64>
    ) -> [Item] {
        var merged = Dictionary(uniqueKeysWithValues: existing.map { ($0[keyPath: keyPath], $0) })
        var orderedIDs = existing.map { $0[keyPath: keyPath] }

        for item in incoming {
            let id = item[keyPath: keyPath]
            if merged[id] == nil {
                orderedIDs.append(id)
            }
            merged[id] = item
        }

        return orderedIDs.compactMap { merged[$0] }
    }

    private func sessionStoreValue() async throws -> FireSessionStore {
        if let sessionStore {
            return sessionStore
        }

        if let sessionStoreInitializationTask {
            let sessionStore = try await sessionStoreInitializationTask.value
            self.sessionStore = sessionStore
            return sessionStore
        }

        let initializationTask = Task.detached(priority: .userInitiated) {
            try FireSessionStore()
        }
        sessionStoreInitializationTask = initializationTask

        do {
            let sessionStore = try await initializationTask.value
            sessionStoreInitializationTask = nil
            self.sessionStore = sessionStore
            return sessionStore
        } catch {
            sessionStoreInitializationTask = nil
            throw error
        }
    }

    private func challengeRecoveryStoreValue() async throws -> any FireChallengeSessionRecovering {
        if let challengeRecoveryStore {
            return challengeRecoveryStore
        }

        return try await sessionStoreValue()
    }

    private func loginCoordinatorValue() async throws -> FireWebViewLoginCoordinator {
        if let loginCoordinator {
            return loginCoordinator
        }

        let sessionStore = try await sessionStoreValue()
        let loginCoordinator = FireWebViewLoginCoordinator(sessionStore: sessionStore)
        self.loginCoordinator = loginCoordinator
        return loginCoordinator
    }

    // MARK: - Profile API

    func fetchUserProfile(username: String) async throws -> UserProfileState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchUserProfile(username: username)
    }

    func fetchUserSummary(username: String) async throws -> UserSummaryState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchUserSummary(username: username)
    }

    func fetchUserActions(
        username: String,
        offset: UInt32?,
        filter: String?
    ) async throws -> [UserActionState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchUserActions(
            username: username,
            offset: offset,
            filter: filter
        )
    }

    func fetchBookmarks(
        username: String,
        page: UInt32? = nil
    ) async throws -> TopicListState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchBookmarks(username: username, page: page)
    }

    func fetchFollowing(username: String) async throws -> [FollowUserState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchFollowing(username: username)
    }

    func fetchFollowers(username: String) async throws -> [FollowUserState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchFollowers(username: username)
    }

    func followUser(username: String) async throws {
        let sessionStore = try await sessionStoreValue()
        try await performWriteWithCloudflareRetry {
            try await sessionStore.followUser(username: username)
        }
    }

    func unfollowUser(username: String) async throws {
        let sessionStore = try await sessionStoreValue()
        try await performWriteWithCloudflareRetry {
            try await sessionStore.unfollowUser(username: username)
        }
    }

    func fetchPendingInvites(username: String) async throws -> [InviteLinkState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchPendingInvites(username: username)
    }

    func createInviteLink(
        maxRedemptionsAllowed: UInt32,
        expiresAt: String? = nil,
        description: String? = nil,
        email: String? = nil
    ) async throws -> InviteLinkState {
        let sessionStore = try await sessionStoreValue()
        return try await performWriteWithCloudflareRetry {
            try await sessionStore.createInviteLink(
                maxRedemptionsAllowed: maxRedemptionsAllowed,
                expiresAt: expiresAt,
                description: description,
                email: email
            )
        }
    }

    func fetchBadgeDetail(badgeID: UInt64) async throws -> BadgeState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchBadgeDetail(badgeID: badgeID)
    }

    func createBookmark(
        bookmarkableID: UInt64,
        bookmarkableType: String,
        name: String? = nil,
        reminderAt: String? = nil,
        autoDeletePreference: Int32? = nil
    ) async throws -> UInt64 {
        let sessionStore = try await sessionStoreValue()
        return try await performWriteWithCloudflareRetry {
            try await sessionStore.createBookmark(
                bookmarkableID: bookmarkableID,
                bookmarkableType: bookmarkableType,
                name: name,
                reminderAt: reminderAt,
                autoDeletePreference: autoDeletePreference
            )
        }
    }

    func updateBookmark(
        bookmarkID: UInt64,
        name: String? = nil,
        reminderAt: String? = nil,
        autoDeletePreference: Int32? = nil
    ) async throws {
        let sessionStore = try await sessionStoreValue()
        try await performWriteWithCloudflareRetry {
            try await sessionStore.updateBookmark(
                bookmarkID: bookmarkID,
                name: name,
                reminderAt: reminderAt,
                autoDeletePreference: autoDeletePreference
            )
        }
    }

    func deleteBookmark(bookmarkID: UInt64) async throws {
        let sessionStore = try await sessionStoreValue()
        try await performWriteWithCloudflareRetry {
            try await sessionStore.deleteBookmark(bookmarkID: bookmarkID)
        }
    }

    func setTopicNotificationLevel(
        topicID: UInt64,
        notificationLevel: Int32
    ) async throws {
        let sessionStore = try await sessionStoreValue()
        try await performWriteWithCloudflareRetry {
            try await sessionStore.setTopicNotificationLevel(
                topicID: topicID,
                notificationLevel: notificationLevel
            )
        }
    }
}
