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

enum FireTopicInteractionError: LocalizedError {
    case unavailable
    case requiresAuthenticatedWrite
    case emptyReply
    case requiresCloudflareVerification

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "互动能力暂时不可用。"
        case .requiresAuthenticatedWrite:
            "当前登录会话还不能执行需要登录的写入操作。"
        case .emptyReply:
            "回复内容不能为空。"
        case .requiresCloudflareVerification:
            "需要先完成 Cloudflare 验证。请在验证页完成后重试。"
        }
    }
}

struct FireCloudflareChallengeContext: Equatable {
    let id: UUID
    let operation: String
    let preferredURL: URL
    let message: String
}

enum FireAuthPresentationState: Identifiable, Equatable {
    case login
    case cloudflareRecovery(FireCloudflareChallengeContext)

    var id: String {
        switch self {
        case .login:
            return "login"
        case let .cloudflareRecovery(context):
            return "cloudflare-\(context.id.uuidString)"
        }
    }
}

private enum FireCloudflareRecoveryError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Cloudflare 验证已取消。"
        }
    }
}

private final class PendingCloudflareRecoveryWaiters: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    func add(_ waiter: CheckedContinuation<Void, Error>, for id: UUID) {
        lock.lock()
        waiters[id] = waiter
        lock.unlock()
    }

    func remove(_ id: UUID) -> CheckedContinuation<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return waiters.removeValue(forKey: id)
    }

    func removeAll() -> [CheckedContinuation<Void, Error>] {
        lock.lock()
        defer {
            waiters.removeAll()
            lock.unlock()
        }
        return Array(waiters.values)
    }
}

private struct PendingCloudflareRecovery {
    let context: FireCloudflareChallengeContext
    let waiters = PendingCloudflareRecoveryWaiters()
}

struct FireTopicDetailWindowState {
    static let maxWindowSize = 200

    var anchorPostNumber: UInt32?
    var requestedRange: Range<Int>
    var loadedIndices: IndexSet
    var loadedPostNumbers: Set<UInt32> = []
    var exhaustedPostIDs: Set<UInt64> = []
    var pendingScrollTarget: UInt32?

    var activeAnchorPostNumber: UInt32? {
        pendingScrollTarget ?? anchorPostNumber
    }

    func clearingTransientAnchor() -> FireTopicDetailWindowState {
        var window = self
        window.anchorPostNumber = nil
        window.pendingScrollTarget = nil
        return window
    }
}

struct FireTopicDetailRequest: Equatable {
    enum Reason: Equatable {
        case initialOpen
        case routeAnchor
        case visibleRangeExpansion
        case userRefresh
        case messageBusRefresh
    }

    var anchorPostNumber: UInt32?
    var reason: Reason
    var forceNetwork: Bool = false
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

protocol FireChallengeSessionRecovering {
    func logoutLocalAndClearPlatformCookies(
        preserveCfClearance: Bool
    ) async throws -> SessionState
}

extension FireWebViewLoginCoordinator: FireChallengeSessionRecovering {}

@MainActor
final class FireAppViewModel: ObservableObject {
    typealias LoginCoordinatorPreloader = @Sendable () async throws -> Void
    typealias LoginNetworkWarmup = @Sendable () async -> Void
    typealias CloudflareRecoveryCookieSync = @Sendable () async throws -> SessionState

    private static let messageBusErrorPrefix = "实时同步连接失败："
    private static let loginRequiredMessage = "登录状态已失效，请重新登录。"
    private static let authDiagnosticsLogTarget = "ios.auth"
    private static let topicDetailLogTarget = "ios.topic-detail"
    private static let diagnosticsLifecycleLogTarget = "ios.lifecycle"

    // MARK: - Session

    @Published private(set) var session: SessionState = .placeholder()

    // MARK: - General UI state

    @Published var errorMessage: String?
    @Published private(set) var isBootstrappingSession = false
    @Published private(set) var isStartupLoadingVisible = false
    @Published var authPresentationState: FireAuthPresentationState?
    @Published var isPreparingLogin = false
    @Published var isSyncingLoginSession = false
    @Published var isCompletingCloudflareChallenge = false
    @Published private(set) var canSyncLoginSession = false
    @Published var isLoggingOut = false

    // MARK: - Private

    private var sessionStore: FireSessionStore?
    private var loginCoordinator: FireWebViewLoginCoordinator?
    private var sessionStoreInitializationTask: Task<FireSessionStore, Error>?
    private var initialStateTask: Task<Void, Never>?
    private var initialStateLoadingDelayTask: Task<Void, Never>?
    private var initialStateLoadGeneration: UInt64 = 0
    private var loginSyncReadinessTask: Task<Void, Never>?
    private var pendingCloudflareRecovery: PendingCloudflareRecovery?
    private var isResettingSession = false
    private let loginURL = URL(string: "https://linux.do")!
    private let challengeRecoveryStore: (any FireChallengeSessionRecovering)?
    private let loginCoordinatorPreloader: LoginCoordinatorPreloader?
    private let loginNetworkWarmup: LoginNetworkWarmup?
    private let cloudflareRecoveryCookieSync: CloudflareRecoveryCookieSync?
    // MessageBus
    private var messageBusCoordinator: FireMessageBusCoordinator?
    private var isMessageBusActive = false
    private var messageBusStartRetryCount = 0
    private var messageBusRetryTask: Task<Void, Never>?
    private var topLevelAPMRoute = "session.onboarding"
    private weak var homeFeedStore: FireHomeFeedStore?
    private weak var notificationStore: FireNotificationStore?
    private weak var topicDetailStore: FireTopicDetailStore?

    init(
        initialSession: SessionState = .placeholder(),
        challengeRecoveryStore: (any FireChallengeSessionRecovering)? = nil,
        loginCoordinatorPreloader: LoginCoordinatorPreloader? = nil,
        loginNetworkWarmup: LoginNetworkWarmup? = nil,
        cloudflareRecoveryCookieSync: CloudflareRecoveryCookieSync? = nil
    ) {
        self.session = initialSession
        self.challengeRecoveryStore = challengeRecoveryStore
        self.loginCoordinatorPreloader = loginCoordinatorPreloader
        self.loginNetworkWarmup = loginNetworkWarmup
        self.cloudflareRecoveryCookieSync = cloudflareRecoveryCookieSync
    }

    var isPresentingLogin: Bool {
        authPresentationState != nil
    }

    func bindHomeFeedStore(_ store: FireHomeFeedStore) {
        homeFeedStore = store
    }

    func bindNotificationStore(_ store: FireNotificationStore) {
        notificationStore = store
    }

    func bindTopicDetailStore(_ store: FireTopicDetailStore) {
        topicDetailStore = store
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
                try await FireAPMManager.shared.withSpan(.appLaunchRestoreSession) {
                    let sessionStore = try await self.sessionStoreValue()
                    guard self.initialStateLoadGeneration == generation else { return }
                    self.errorMessage = nil
                    let restoredSession = try await sessionStore.restoreColdStartSession()
                    guard self.initialStateLoadGeneration == generation else { return }
                    await self.applySession(restoredSession)
                    guard self.initialStateLoadGeneration == generation else { return }
                    await self.refreshHomeFeedIfPossible(force: true)
                    guard self.initialStateLoadGeneration == generation else { return }
                    await self.notificationStore?.loadRecent(force: false)
                }
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
                await refreshHomeFeedIfPossible(force: false)
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
            if authPresentationState == nil {
                presentLoginAuthFlow()
            }
            return
        }

        errorMessage = nil
        canSyncLoginSession = false
        presentLoginAuthFlow()
        isPreparingLogin = true

        Task {
            defer { isPreparingLogin = false }

            do {
                try await preloadLoginCoordinator()
                await warmLoginNetworkAccess()
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
                try await FireAPMManager.shared.withSpan(.authLoginSync) {
                    let loginCoordinator = try await loginCoordinatorValue()
                    errorMessage = nil
                    await applySession(try await loginCoordinator.completeLogin(from: webView))
                    setAuthPresentationState(nil)
                    await refreshHomeFeedIfPossible(force: true)
                    canSyncLoginSession = false
                }
            } catch {
                if await handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func completeCloudflareRecovery() {
        guard pendingCloudflareRecovery != nil else {
            return
        }
        guard !isCompletingCloudflareChallenge else {
            return
        }

        isCompletingCloudflareChallenge = true
        Task {
            defer { isCompletingCloudflareChallenge = false }

            do {
                errorMessage = nil
                let refreshedSession = try await syncCookiesForCloudflareRecovery()
                await applySession(refreshedSession)
                setAuthPresentationState(nil)
                resolvePendingCloudflareRecovery(with: .success(()))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func dismissAuthPresentation() {
        if pendingCloudflareRecovery != nil {
            resolvePendingCloudflareRecovery(
                with: .failure(FireCloudflareRecoveryError.cancelled)
            )
        }
        canSyncLoginSession = false
        setAuthPresentationState(nil)
    }

    func refreshBootstrap() {
        Task {
            do {
                try await FireAPMManager.shared.withSpan(.bootstrapRefresh) {
                    let sessionStore = try await sessionStoreValue()
                    errorMessage = nil
                    await applySession(try await sessionStore.refreshBootstrap())
                    await refreshHomeFeedIfPossible(force: false)
                }
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
                canSyncLoginSession = false
                clearTopicState()
                notificationStore?.reset()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Topic list

    func selectTopicKind(_ kind: TopicListKindState) {
        homeFeedStore?.selectTopicKind(kind)
    }

    func selectHomeCategory(_ categoryId: UInt64?) {
        homeFeedStore?.selectHomeCategory(categoryId)
    }

    func addHomeTag(_ tag: String) {
        homeFeedStore?.addHomeTag(tag)
    }

    func removeHomeTag(_ tag: String) {
        homeFeedStore?.removeHomeTag(tag)
    }

    func clearHomeTags() {
        homeFeedStore?.clearHomeTags()
    }

    var selectedHomeCategoryPresentation: FireTopicCategoryPresentation? {
        homeFeedStore?.selectedHomeCategoryPresentation
    }

    func refreshTopics() {
        homeFeedStore?.refreshTopics()
    }

    func refreshTopicsAsync() async {
        await homeFeedStore?.refreshTopicsAsync()
    }

    func loadMoreTopics() {
        homeFeedStore?.loadMoreTopics()
    }

    func loadTopicDetail(
        topicId: UInt64,
        targetPostNumber: UInt32? = nil,
        force: Bool = false
    ) async {
        await topicDetailStore?.loadTopicDetail(
            topicId: topicId,
            targetPostNumber: targetPostNumber,
            force: force
        )
    }

    func clearTopicDetailAnchor(topicId: UInt64) {
        topicDetailStore?.clearTopicDetailAnchor(topicId: topicId)
    }

    func topicDetail(for topicId: UInt64) -> TopicDetailState? {
        topicDetailStore?.topicDetail(for: topicId)
    }

    func topicPresenceUsers(for topicId: UInt64) -> [TopicPresenceUserState] {
        topicDetailStore?.topicPresenceUsers(for: topicId) ?? []
    }

    func isLoadingTopic(topicId: UInt64) -> Bool {
        topicDetailStore?.isLoadingTopic(topicId: topicId) ?? false
    }

    func isLoadingMoreTopicPosts(topicId: UInt64) -> Bool {
        topicDetailStore?.isLoadingMoreTopicPosts(topicId: topicId) ?? false
    }

    func hasMoreTopicPosts(topicId: UInt64) -> Bool {
        topicDetailStore?.hasMoreTopicPosts(topicId: topicId) ?? false
    }

    func preloadTopicPostsIfNeeded(
        topicId: UInt64,
        visiblePostNumbers: Set<UInt32>
    ) {
        topicDetailStore?.preloadTopicPostsIfNeeded(
            topicId: topicId,
            visiblePostNumbers: visiblePostNumbers
        )
    }

    // MARK: - Topic detail lifecycle

    func beginTopicDetailLifecycle(topicId: UInt64, ownerToken: String) {
        topicDetailStore?.beginTopicDetailLifecycle(topicId: topicId, ownerToken: ownerToken)
    }

    func endTopicDetailLifecycle(topicId: UInt64, ownerToken: String) {
        topicDetailStore?.endTopicDetailLifecycle(
            topicId: topicId,
            ownerToken: ownerToken,
            visibleTopicIDs: currentVisibleTopicIDs()
        )
    }

    func retainedTopicDetailIDs(visibleTopicIDs: Set<UInt64>) -> Set<UInt64> {
        topicDetailStore?.retainedTopicDetailIDs(visibleTopicIDs: visibleTopicIDs)
            ?? visibleTopicIDs
    }

    // MARK: - Topic detail MessageBus subscription

    func maintainTopicDetailSubscription(topicId: UInt64, ownerToken: String) async {
        await topicDetailStore?.maintainTopicDetailSubscription(
            topicId: topicId,
            ownerToken: ownerToken
        )
    }

    // MARK: - Write interactions

    func isSubmittingReply(topicId: UInt64) -> Bool {
        topicDetailStore?.isSubmittingReply(topicId: topicId) ?? false
    }

    func isMutatingPost(postId: UInt64) -> Bool {
        topicDetailStore?.isMutatingPost(postId: postId) ?? false
    }

    func categoryPresentation(for categoryID: UInt64?) -> FireTopicCategoryPresentation? {
        if let category = homeFeedStore?.categoryPresentation(for: categoryID) {
            return category
        }
        guard let categoryID else { return nil }
        return session.bootstrap.categories.first(where: { $0.id == categoryID })
    }

    func allCategories() -> [FireTopicCategoryPresentation] {
        homeFeedStore?.allCategories ?? session.bootstrap.categories
    }

    func topTags() -> [String] {
        homeFeedStore?.topTags ?? session.bootstrap.topTags
    }

    var canTagTopics: Bool {
        homeFeedStore?.canTagTopics ?? session.bootstrap.canTagTopics
    }

    var canStartAuthenticatedMutation: Bool {
        session.readiness.canReadAuthenticatedApi
    }

    func fetchFilteredTopicList(query: TopicListQueryState) async throws -> TopicListState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchTopicList(query: query)
    }

    func fetchPrivateMessages(
        kind: TopicListKindState,
        page: UInt32? = nil
    ) async throws -> TopicListState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchTopicList(
            query: TopicListQueryState(
                kind: kind,
                page: page,
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

    func enabledReactionOptions() -> [FireReactionOption] {
        FireTopicPresentation.enabledReactionOptions(from: session.bootstrap.enabledReactionIds)
    }

    func submitReply(
        topicId: UInt64,
        raw: String,
        replyToPostNumber: UInt32?
    ) async throws {
        guard let topicDetailStore else {
            throw FireTopicInteractionError.unavailable
        }
        try await topicDetailStore.submitReply(
            topicId: topicId,
            raw: raw,
            replyToPostNumber: replyToPostNumber
        )
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
        guard canStartAuthenticatedMutation else {
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
            await syncSessionSnapshotIfAvailable(from: sessionStore)
            await refreshHomeFeedIfPossible(force: true)
            return topicID
        } catch {
            _ = await handleInteractionError(error)
            throw error
        }
    }

    func createPrivateMessage(
        title: String,
        raw: String,
        targetRecipients: [String]
    ) async throws -> UInt64 {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipients = targetRecipients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedTitle.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }
        guard !trimmedRaw.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }
        guard !recipients.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }

        let sessionStore = try await sessionStoreValue()
        guard canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }

        do {
            errorMessage = nil
            let topicID = try await performWriteWithCloudflareRetry {
                try await sessionStore.createPrivateMessage(
                    title: trimmedTitle,
                    raw: trimmedRaw,
                    targetRecipients: recipients
                )
            }
            await syncSessionSnapshotIfAvailable(from: sessionStore)
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
        guard canStartAuthenticatedMutation else {
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
            await syncSessionSnapshotIfAvailable(from: sessionStore)
            await refreshHomeFeedIfPossible(force: true)
            await topicDetailStore?.refreshTopicDetailAfterMutation(topicId: topicID)
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
        guard let topicDetailStore else {
            throw FireTopicInteractionError.unavailable
        }
        return try await topicDetailStore.updatePost(
            topicID: topicID,
            postID: postID,
            raw: raw,
            editReason: editReason
        )
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
        guard let topicDetailStore else {
            throw FireTopicInteractionError.unavailable
        }
        try await topicDetailStore.setPostLiked(
            topicId: topicId,
            postId: postId,
            liked: liked
        )
    }

    func togglePostReaction(
        topicId: UInt64,
        postId: UInt64,
        reactionId: String
    ) async throws {
        guard let topicDetailStore else {
            throw FireTopicInteractionError.unavailable
        }
        try await topicDetailStore.togglePostReaction(
            topicId: topicId,
            postId: postId,
            reactionId: reactionId
        )
    }

    func votePoll(
        topicID: UInt64,
        postID: UInt64,
        pollName: String,
        options: [String]
    ) async throws -> PollState {
        let sessionStore = try await sessionStoreValue()
        guard canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard topicDetailStore?.isMutatingPost(postId: postID) != true else {
            throw FireTopicInteractionError.unavailable
        }

        do {
            errorMessage = nil
            let poll = try await performWriteWithCloudflareRetry {
                try await sessionStore.votePoll(
                    postID: postID,
                    pollName: pollName,
                    options: options
                )
            }
            await topicDetailStore?.refreshTopicDetailAfterMutation(topicId: topicID)
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
        guard canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard topicDetailStore?.isMutatingPost(postId: postID) != true else {
            throw FireTopicInteractionError.unavailable
        }

        do {
            errorMessage = nil
            let poll = try await performWriteWithCloudflareRetry {
                try await sessionStore.unvotePoll(postID: postID, pollName: pollName)
            }
            await topicDetailStore?.refreshTopicDetailAfterMutation(topicId: topicID)
            return poll
        } catch {
            _ = await handleInteractionError(error)
            throw error
        }
    }

    func voteTopic(topicID: UInt64, voted: Bool) async throws -> VoteResponseState {
        let sessionStore = try await sessionStoreValue()
        guard canStartAuthenticatedMutation else {
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
            await topicDetailStore?.refreshTopicDetailAfterMutation(topicId: topicID)
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
        guard canStartAuthenticatedMutation else { return false }
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
            _ = await handleRecoverableSessionErrorIfNeeded(error)
            return false
        }
    }

    // MARK: - Notification helpers

    func notificationCenterState() async throws -> NotificationCenterState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.notificationState()
    }

    func fetchRecentNotificationsData(limit: UInt32? = nil) async throws -> NotificationListState {
        let sessionStore = try await sessionStoreValue()
        return try await performWithCloudflareRecovery(operation: "刷新通知列表") {
            try await sessionStore.fetchRecentNotifications(limit: limit)
        }
    }

    func fetchNotificationsData(
        limit: UInt32? = nil,
        offset: UInt32? = nil
    ) async throws -> NotificationListState {
        let sessionStore = try await sessionStoreValue()
        return try await performWithCloudflareRecovery(operation: "加载更多通知") {
            try await sessionStore.fetchNotifications(limit: limit, offset: offset)
        }
    }

    func markNotificationReadState(id: UInt64) async throws -> NotificationCenterState {
        let sessionStore = try await sessionStoreValue()
        return try await performWriteWithCloudflareRetry(
            operationDescription: "标记通知已读"
        ) {
            try await sessionStore.markNotificationRead(id: id)
        }
    }

    func markAllNotificationsReadState() async throws -> NotificationCenterState {
        let sessionStore = try await sessionStoreValue()
        return try await performWriteWithCloudflareRetry(
            operationDescription: "全部通知标记已读"
        ) {
            try await sessionStore.markAllNotificationsRead()
        }
    }

    // MARK: - Search helpers

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

    func apmDiagnosticsSummary() async throws -> FireAPMDiagnosticsSummary {
        try await FireAPMManager.shared.diagnosticsSummary()
    }

    func exportFullAPMSupportBundle(scenePhase: String?) async throws -> FireAPMSupportBundleExport {
        let rustBundleURL: URL?
        if let sessionStore = try? await sessionStoreValue() {
            let rustBundle = try? await sessionStore.exportSupportBundle(
                platform: "ios",
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                buildNumber: Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String,
                scenePhase: scenePhase
            )
            rustBundleURL = rustBundle.map { URL(fileURLWithPath: $0.absolutePath) }
        } else {
            rustBundleURL = nil
        }
        defer {
            if let rustBundleURL {
                try? FileManager.default.removeItem(at: rustBundleURL)
            }
        }
        return try await FireAPMManager.shared.exportSupportBundle(
            rustSupportBundleURL: rustBundleURL,
            scenePhase: scenePhase
        )
    }

    func flushDiagnosticsLogs(sync: Bool = true) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.flushLogs(sync: sync)
    }

    func handleDiagnosticsScenePhaseChange(_ phase: String, isAuthenticated: Bool) {
        FireCfClearanceRefreshService.shared.setSceneActive(phase == "active")
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

    func updateTopLevelAPMRoute(selectedTab: Int, isAuthenticated: Bool) {
        let route: String
        if !isAuthenticated {
            route = "session.onboarding"
        } else {
            switch selectedTab {
            case 0:
                route = "tab.home"
            case 1:
                route = "tab.notifications"
            case 2:
                route = "tab.profile"
            default:
                route = "tab.unknown"
            }
        }
        topLevelAPMRoute = route
        FireAPMManager.shared.setCurrentRoute(route)
    }

    func restoreTopLevelAPMRoute() {
        FireAPMManager.shared.setCurrentRoute(topLevelAPMRoute)
    }

    func setAPMRoute(_ route: String) {
        FireAPMManager.shared.setCurrentRoute(route)
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
            _ = try await FireAPMManager.shared.withSpan(.messageBusStart) {
                try await sessionStore.startMessageBus(handler: coordinator)
            }
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
        notificationStore?.cancelScheduledRefresh()
        homeFeedStore?.handleMessageBusStopped()
        topicDetailStore?.handleMessageBusStopped()
        clearMessageBusError()
        guard isMessageBusActive else { return }
        messageBusCoordinator = nil
        isMessageBusActive = false
        guard let sessionStore else { return }
        Task { try? await sessionStore.stopMessageBus(clearSubscriptions: true) }
    }

    private func handleMessageBusEvent(_ event: MessageBusEventState) {
        switch event.kind {
        case .topicList:
            homeFeedStore?.handleTopicListMessageBusEvent(event)

        case .topicDetail, .topicReaction, .presence:
            topicDetailStore?.handleMessageBusEvent(event)

        case .notification:
            notificationStore?.scheduleStateRefresh()

        case .notificationAlert:
            break

        case .unknown:
            break
        }
    }

    func beginTopicReplyPresence(topicId: UInt64) {
        topicDetailStore?.beginTopicReplyPresence(topicId: topicId)
    }

    func endTopicReplyPresence(topicId: UInt64) async {
        await topicDetailStore?.endTopicReplyPresence(topicId: topicId)
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

    private func preloadLoginCoordinator() async throws {
        if let loginCoordinatorPreloader {
            try await loginCoordinatorPreloader()
            return
        }

        _ = try await loginCoordinatorValue()
    }

    private func warmLoginNetworkAccess() async {
        if let loginNetworkWarmup {
            await loginNetworkWarmup()
            return
        }

        do {
            try await prepareLoginNetworkAccess()
        } catch {
            FireAPMManager.shared.recordBreadcrumb(
                level: "warn",
                target: "auth.login",
                message: "login network warmup failed: \(error.localizedDescription)"
            )
        }
    }

    private func refreshTopicsIfPossible(force: Bool) async {
        await refreshHomeFeedIfPossible(force: force)
    }

    private func clearTopicState() {
        homeFeedStore?.reset(resetTopicKind: true)
        topicDetailStore?.reset()
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

    private func applySession(_ session: SessionState) async {
        let shouldMirrorCookies = session.cookies != self.session.cookies
            || session.bootstrap.baseUrl != self.session.bootstrap.baseUrl
        self.session = session
        if shouldMirrorCookies {
            await session.mirrorCookiesToNativeStorage()
        }
        homeFeedStore?.applySession(session)
        topicDetailStore?.applySession(session)

        if session.readiness.canReadAuthenticatedApi {
            await notificationStore?.syncStateFromRuntimeIfAvailable()
        } else {
            notificationStore?.reset()
        }

        // Reconcile MessageBus lifecycle
        if session.readiness.canOpenMessageBus && !isMessageBusActive {
            await startMessageBus()
        } else if !session.readiness.canOpenMessageBus && isMessageBusActive {
            stopMessageBus()
        } else if !session.readiness.canOpenMessageBus {
            stopMessageBus()
        }

        if let coordinator = try? await loginCoordinatorValue() {
            FireCfClearanceRefreshService.shared.updateSession(
                session,
                loginCoordinator: coordinator,
                onSessionRefreshed: { [weak self] updatedSession in
                    guard let self else { return }
                    await self.cfClearanceDidRefresh(updatedSession)
                }
            )
        }
    }

    func cfClearanceDidRefresh(_ updatedSession: SessionState) async {
        await applySession(updatedSession)
    }

    func refreshLoginSyncReadiness(from webView: WKWebView) {
        loginSyncReadinessTask?.cancel()
        loginSyncReadinessTask = Task { [weak self] in
            guard let self else { return }
            do {
                let coordinator = try await loginCoordinatorValue()
                let readiness = try await coordinator.probeLoginSyncReadiness(from: webView)
                guard !Task.isCancelled else { return }
                let previous = canSyncLoginSession
                canSyncLoginSession = readiness.isReady
                if previous != readiness.isReady {
                    FireAPMManager.shared.recordBreadcrumb(
                        target: "auth.login",
                        message: readiness.isReady
                            ? "login sync readiness satisfied"
                            : "login sync readiness cleared"
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                canSyncLoginSession = false
            }
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

    func performWriteWithCloudflareRetry<T>(
        operationDescription: String = "执行当前操作",
        operation: @escaping () async throws -> T
    ) async throws -> T {
        do {
            return try await performWithCloudflareRecovery(
                operation: operationDescription,
                work: operation
            )
        } catch is FireCloudflareRecoveryError {
            throw FireTopicInteractionError.requiresCloudflareVerification
        }
    }

    func performWithCloudflareRecovery<T>(
        operation: String,
        work: @escaping () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch {
            guard case FireUniFfiError.CloudflareChallenge = error else {
                throw error
            }
        }

        try? await syncPlatformCookiesFromWebViewStore()

        do {
            return try await work()
        } catch {
            guard case FireUniFfiError.CloudflareChallenge = error else {
                throw error
            }
        }

        try await beginCloudflareRecoveryAndWait(operation: operation)
        try Task.checkCancellation()
        return try await work()
    }

    private func beginCloudflareRecoveryAndWait(operation: String) async throws {
        if pendingCloudflareRecovery == nil {
            let context = FireCloudflareChallengeContext(
                id: UUID(),
                operation: operation,
                preferredURL: challengeRecoveryURL(),
                message: "\(operation) 需要先完成 Cloudflare 验证。完成后会自动重试。"
            )
            pendingCloudflareRecovery = PendingCloudflareRecovery(context: context)
            errorMessage = nil
            canSyncLoginSession = false
            setAuthPresentationState(.cloudflareRecovery(context))
        }

        guard let pendingCloudflareRecovery else {
            throw FireCloudflareRecoveryError.cancelled
        }

        let waiters = pendingCloudflareRecovery.waiters
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                waiters.add(continuation, for: waiterID)
                if Task.isCancelled, let waiter = waiters.remove(waiterID) {
                    waiter.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            if let waiter = waiters.remove(waiterID) {
                waiter.resume(throwing: CancellationError())
            }
        }
    }

    @discardableResult
    func handleRecoverableSessionErrorIfNeeded(_ error: Error) async -> Bool {
        if await handleLoginRequiredIfNeeded(error) {
            return true
        }
        if await handleStaleSessionResponseIfNeeded(error) {
            return true
        }
        return await handleCloudflareChallengeIfNeeded(error)
    }

    @discardableResult
    func handleLoginRequiredIfNeeded(_ error: Error) async -> Bool {
        guard case let FireUniFfiError.LoginRequired(message) = error else {
            return false
        }

        await logLoginInvalidationDiagnostics(
            message: message.isEmpty ? Self.loginRequiredMessage : message
        )
        await resetSessionAndPresentLogin(
            message: message.isEmpty ? Self.loginRequiredMessage : message
        )
        return true
    }

    @discardableResult
    func handleStaleSessionResponseIfNeeded(_ error: Error) async -> Bool {
        guard case let FireUniFfiError.StaleSessionResponse(operation) = error else {
            return false
        }

        FireAPMManager.shared.recordBreadcrumb(
            target: Self.authDiagnosticsLogTarget,
            message: "discarded stale session response operation=\(operation)"
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

        let operation = message ?? "当前请求"
        if pendingCloudflareRecovery == nil {
            let context = FireCloudflareChallengeContext(
                id: UUID(),
                operation: operation,
                preferredURL: challengeRecoveryURL(),
                message: message ?? error.localizedDescription
            )
            pendingCloudflareRecovery = PendingCloudflareRecovery(context: context)
            errorMessage = nil
            canSyncLoginSession = false
            setAuthPresentationState(.cloudflareRecovery(context))
        } else if case let .cloudflareRecovery(context)? = authPresentationState {
            setAuthPresentationState(.cloudflareRecovery(context))
        }
        return true
    }

    private func challengeRecoveryURL() -> URL {
        session.baseURL.appendingPathComponent("challenge", isDirectory: false)
    }

    private func resetSessionAndPresentLogin(message: String) async {
        guard !isResettingSession else {
            return
        }

        isResettingSession = true
        defer { isResettingSession = false }

        resolvePendingCloudflareRecovery(
            with: .failure(FireCloudflareRecoveryError.cancelled)
        )
        stopMessageBus()

        do {
            let recoveryStore = try await challengeRecoveryStoreValue()
            let cleared = try await recoveryStore.logoutLocalAndClearPlatformCookies(
                preserveCfClearance: true
            )
            await applySession(cleared)
        } catch {
            await applySession(.placeholder(baseUrl: session.bootstrap.baseUrl))
        }

        clearTopicState()
        notificationStore?.reset()
        canSyncLoginSession = false
        errorMessage = message
        presentLoginAuthFlow()
    }

    private func logLoginInvalidationDiagnostics(message: String) async {
        let logger = await authDiagnosticsLogger()
        guard let logger else { return }

        let rustSummary = summarizeSessionAuthCookies(session)
        let sharedSummary = summarizeHTTPCookies(
            HTTPCookieStorage.shared.cookies ?? [],
            source: "http-cookie-storage"
        )
        let webKitSummary = summarizeHTTPCookies(
            await currentWebKitCookies(),
            source: "wk-cookie-store"
        )

        logger.warning(
            "login invalidation diagnostics message=\(message) rust=\(rustSummary) shared=\(sharedSummary) webkit=\(webKitSummary)"
        )
    }

    private func authDiagnosticsLogger() async -> FireHostLogger? {
        if let sessionStore {
            return sessionStore.makeLogger(target: Self.authDiagnosticsLogTarget)
        }
        guard let sessionStore = try? await sessionStoreValue() else {
            return nil
        }
        return sessionStore.makeLogger(target: Self.authDiagnosticsLogTarget)
    }

    private func currentWebKitCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func summarizeSessionAuthCookies(_ session: SessionState) -> String {
        let platformCookieSummary = session.cookies.platformCookies
            .filter { Self.isCriticalCookieName($0.name) }
            .map { cookie in
                sessionCookieDescriptor(
                    name: cookie.name,
                    domain: cookie.domain,
                    path: cookie.path,
                    expiresAtUnixMs: cookie.expiresAtUnixMs,
                    value: cookie.value
                )
            }
            .joined(separator: ",")

        let scalarSummary = [
            sessionScalarCookieDescriptor(name: "_t", value: session.cookies.tToken),
            sessionScalarCookieDescriptor(name: "_forum_session", value: session.cookies.forumSession),
            sessionScalarCookieDescriptor(name: "cf_clearance", value: session.cookies.cfClearance),
            sessionScalarCookieDescriptor(name: "csrf", value: session.cookies.csrfToken)
        ].joined(separator: ",")

        return "scalar[\(scalarSummary)] platform_count=\(session.cookies.platformCookies.count) critical_platform[\(platformCookieSummary)] readiness[login=\(session.readiness.hasLoginCookie),forum=\(session.readiness.hasForumSession),csrf=\(session.readiness.hasCsrfToken),user=\(session.readiness.hasCurrentUser)]"
    }

    private func summarizeHTTPCookies(_ cookies: [HTTPCookie], source: String) -> String {
        let relevant = cookies
            .filter { Self.isCriticalCookieName($0.name) }
            .sorted {
                if $0.name != $1.name {
                    return $0.name < $1.name
                }
                if $0.domain != $1.domain {
                    return $0.domain < $1.domain
                }
                return $0.path < $1.path
            }

        if relevant.isEmpty {
            return "\(source)[none]"
        }

        let descriptors = relevant.map { cookie in
            sessionCookieDescriptor(
                name: cookie.name,
                domain: cookie.domain,
                path: cookie.path,
                expiresAtUnixMs: cookie.expiresDate.map { Int64($0.timeIntervalSince1970 * 1000) },
                value: cookie.value
            )
        }
        return "\(source)[\(descriptors.joined(separator: ","))]"
    }

    private func sessionScalarCookieDescriptor(name: String, value: String?) -> String {
        let length = value?.count ?? 0
        return "\(name):len=\(length)"
    }

    private func sessionCookieDescriptor(
        name: String,
        domain: String?,
        path: String?,
        expiresAtUnixMs: Int64?,
        value: String
    ) -> String {
        let normalizedDomain = domain?.isEmpty == false ? domain! : "?"
        let normalizedPath = path?.isEmpty == false ? path! : "/"
        let scope = normalizedDomain.hasPrefix(".") ? "domain" : "host"
        let expiry = expiresAtUnixMs.map(String.init) ?? "session"
        return "\(name)@\(normalizedDomain)\(normalizedPath){\(scope),len=\(value.count),exp=\(expiry)}"
    }

    private static func isCriticalCookieName(_ name: String) -> Bool {
        ["_t", "_forum_session", "cf_clearance"].contains(name)
    }

    private func syncPlatformCookiesFromWebViewStore() async throws {
        let loginCoordinator = try await loginCoordinatorValue()
        let session = try await loginCoordinator.refreshPlatformCookies()
        await applySession(session)
    }

    private func syncCookiesForCloudflareRecovery() async throws -> SessionState {
        if let cloudflareRecoveryCookieSync {
            return try await cloudflareRecoveryCookieSync()
        }

        let loginCoordinator = try await loginCoordinatorValue()
        return try await loginCoordinator.refreshPlatformCookies()
    }

    private func presentLoginAuthFlow() {
        resolvePendingCloudflareRecovery(
            with: .failure(FireCloudflareRecoveryError.cancelled)
        )
        canSyncLoginSession = false
        setAuthPresentationState(.login)
    }

    private func setAuthPresentationState(_ state: FireAuthPresentationState?) {
        authPresentationState = state
        let isInteractiveRecoveryActive: Bool
        switch state {
        case .cloudflareRecovery:
            isInteractiveRecoveryActive = true
        case .login, .none:
            isInteractiveRecoveryActive = false
        }
        FireCfClearanceRefreshService.shared.setInteractiveRecoveryActive(
            isInteractiveRecoveryActive
        )
    }

    private func resolvePendingCloudflareRecovery(with result: Result<Void, Error>) {
        guard let pendingCloudflareRecovery else {
            return
        }

        let waiters = pendingCloudflareRecovery.waiters.removeAll()
        self.pendingCloudflareRecovery = nil
        waiters.forEach { $0.resume(with: result) }
    }

    func topicDetailLogger() -> FireHostLogger? {
        sessionStore?.makeLogger(target: Self.topicDetailLogTarget)
    }

    func currentSessionStore() -> FireSessionStore? {
        sessionStore
    }

    func ensureMessageBusActiveIfPossible() async {
        guard !isMessageBusActive else { return }
        await startMessageBus()
    }

    func refreshHomeFeedIfPossible(force: Bool) async {
        await homeFeedStore?.refreshTopicsIfPossible(force: force)
    }

    func pruneTopicDetailState(retainingVisibleTopicIDs visibleTopicIDs: Set<UInt64>) {
        topicDetailStore?.pruneInactiveTopicDetailState(
            retainingVisibleTopicIDs: visibleTopicIDs
        )
    }

    func currentVisibleTopicIDs() -> Set<UInt64> {
        homeFeedStore?.visibleTopicIDs ?? []
    }

    func syncSessionSnapshotIfAvailable(from sessionStore: FireSessionStore) async {
        if let snapshot = try? await sessionStore.snapshot() {
            await applySession(snapshot)
        }
    }

    func sessionStoreValue() async throws -> FireSessionStore {
        if let sessionStore {
            await configureAuthenticatedWriteHostResyncProvider(with: sessionStore)
            return sessionStore
        }

        if let sessionStoreInitializationTask {
            let sessionStore = try await sessionStoreInitializationTask.value
            self.sessionStore = sessionStore
            await FireAPMManager.shared.attachSessionStore(sessionStore)
            await configureAuthenticatedWriteHostResyncProvider(with: sessionStore)
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
            await FireAPMManager.shared.attachSessionStore(sessionStore)
            await configureAuthenticatedWriteHostResyncProvider(with: sessionStore)
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

        return try await loginCoordinatorValue()
    }

    private func loginCoordinatorValue() async throws -> FireWebViewLoginCoordinator {
        if let loginCoordinator {
            return loginCoordinator
        }

        let sessionStore = try await sessionStoreValue()
        await configureAuthenticatedWriteHostResyncProvider(with: sessionStore)
        guard let loginCoordinator else {
            throw CancellationError()
        }
        return loginCoordinator
    }

    private func configureAuthenticatedWriteHostResyncProvider(
        with sessionStore: FireSessionStore
    ) async {
        let loginCoordinator: FireWebViewLoginCoordinator
        if let existingLoginCoordinator = self.loginCoordinator {
            loginCoordinator = existingLoginCoordinator
        } else {
            let newLoginCoordinator = FireWebViewLoginCoordinator(sessionStore: sessionStore)
            self.loginCoordinator = newLoginCoordinator
            loginCoordinator = newLoginCoordinator
        }

        await sessionStore.setAuthenticatedWriteHostResyncProvider { [weak loginCoordinator] in
            guard let loginCoordinator else {
                return nil
            }
            return try await loginCoordinator.platformCookiesForSessionResync()
        }
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
