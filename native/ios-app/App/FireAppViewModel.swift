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

@MainActor
final class FireAppViewModel: ObservableObject {
    private static let messageBusErrorPrefix = "实时同步连接失败："

    // MARK: - Session

    @Published private(set) var session: SessionState = .placeholder()

    // MARK: - Topic list

    @Published private(set) var selectedTopicKind: TopicListKindState = .latest
    @Published private(set) var topicRows: [FireTopicRowPresentation] = []
    @Published private(set) var moreTopicsUrl: String?
    @Published private(set) var nextTopicsPage: UInt32?
    @Published private(set) var topicCategories: [UInt64: FireTopicCategoryPresentation] = [:]
    @Published private(set) var topicDetails: [UInt64: TopicDetailState] = [:]
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

    // MARK: - General UI state

    @Published var errorMessage: String?
    @Published var isPresentingLogin = false
    @Published var isPreparingLogin = false
    @Published var isLoggingOut = false

    // MARK: - Private

    private var sessionStore: FireSessionStore?
    private var loginCoordinator: FireWebViewLoginCoordinator?
    private var sessionStoreInitializationTask: Task<FireSessionStore, Error>?
    private let loginURL = URL(string: "https://linux.do")!

    // MessageBus
    private var messageBusCoordinator: FireMessageBusCoordinator?
    private var isMessageBusActive = false
    private var messageBusStartRetryCount = 0
    private var messageBusRetryTask: Task<Void, Never>?
    private var pendingTopicListRefreshTask: Task<Void, Never>?
    private var pendingTopicDetailRefreshTasks: [UInt64: Task<Void, Never>] = [:]

    init() {}

    // MARK: - Lifecycle

    func loadInitialState() {
        Task {
            do {
                let loginCoordinator = try await loginCoordinatorValue()
                let sessionStore = try await sessionStoreValue()
                errorMessage = nil
                let initialSession: SessionState
                if let restored = try await loginCoordinator.restorePersistedSessionIfAvailable() {
                    initialSession = restored
                } else {
                    initialSession = try await sessionStore.snapshot()
                }
                await applySession(initialSession)
                await applySession(try await sessionStore.refreshBootstrapIfNeeded())
                await refreshTopicsIfPossible(force: true)
                await loadRecentNotifications(force: false)
            } catch {
                errorMessage = error.localizedDescription
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
        Task {
            do {
                let loginCoordinator = try await loginCoordinatorValue()
                errorMessage = nil
                await applySession(try await loginCoordinator.completeLogin(from: webView))
                isPresentingLogin = false
                await refreshTopicsIfPossible(force: true)
            } catch {
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
        refreshTopics()
    }

    func refreshTopics() {
        Task {
            await refreshTopicsIfPossible(force: true)
        }
    }

    func loadMoreTopics() {
        guard let nextTopicsPage else {
            return
        }

        Task {
            await loadTopics(page: nextTopicsPage, reset: false, force: true)
        }
    }

    func loadTopicDetail(topicId: UInt64, force: Bool = false) async {
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

        loadingTopicIDs.insert(topicId)
        defer { loadingTopicIDs.remove(topicId) }

        do {
            errorMessage = nil
            let detail = try await sessionStore.fetchTopicDetail(
                query: TopicDetailQueryState(
                    topicId: topicId,
                    postNumber: nil,
                    trackVisit: true,
                    filter: nil,
                    usernameFilters: nil,
                    filterTopLevelReplies: false
                )
            )
            topicDetails[topicId] = detail
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func topicDetail(for topicId: UInt64) -> TopicDetailState? {
        topicDetails[topicId]
    }

    func isLoadingTopic(topicId: UInt64) -> Bool {
        loadingTopicIDs.contains(topicId)
    }

    // MARK: - Topic detail MessageBus subscription

    func maintainTopicDetailSubscription(topicId: UInt64) async {
        guard isMessageBusActive else { return }
        guard let store = sessionStore else { return }

        do {
            try await store.subscribeTopicDetailChannel(topicId: topicId)
        } catch {
            return
        }

        defer {
            Task {
                try? await store.unsubscribeTopicDetailChannel(topicId: topicId)
            }
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
            _ = try await performWriteWithCloudflareRetry {
                try await sessionStore.createReply(
                    topicID: topicId,
                    raw: trimmed,
                    replyToPostNumber: replyToPostNumber
                )
            }
            if let snapshot = try? await sessionStore.snapshot() {
                await applySession(snapshot)
            }
            try? await refreshTopicDetailAfterMutation(topicId: topicId, sessionStore: sessionStore)
        } catch {
            errorMessage = error.localizedDescription
            throw error
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
            try await performWriteWithCloudflareRetry {
                if liked {
                    try await sessionStore.likePost(postID: postId)
                } else {
                    try await sessionStore.unlikePost(postID: postId)
                }
            }
            if let snapshot = try? await sessionStore.snapshot() {
                await applySession(snapshot)
            }
            try? await refreshTopicDetailAfterMutation(topicId: topicId, sessionStore: sessionStore)
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
            throw error
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
            } catch {}
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
            } catch {}
        }
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
            errorMessage = Self.messageBusErrorPrefix + error.localizedDescription
            scheduleMessageBusRetry()
        }
    }

    private func stopMessageBus() {
        messageBusRetryTask?.cancel()
        messageBusRetryTask = nil
        messageBusStartRetryCount = 0
        clearMessageBusError()
        guard isMessageBusActive else { return }
        pendingTopicListRefreshTask?.cancel()
        pendingTopicListRefreshTask = nil
        pendingTopicDetailRefreshTasks.values.forEach { $0.cancel() }
        pendingTopicDetailRefreshTasks = [:]
        messageBusCoordinator = nil
        isMessageBusActive = false
        guard let sessionStore else { return }
        Task { try? await sessionStore.stopMessageBus(clearSubscriptions: true) }
    }

    private func handleMessageBusEvent(_ event: MessageBusEventState) {
        switch event.kind {
        case .topicList:
            guard let kind = event.topicListKind else { return }
            scheduleTopicListRefresh(for: kind)

        case .topicDetail:
            guard let topicId = event.topicId else { return }
            guard topicDetails[topicId] != nil else { return }
            scheduleTopicDetailRefresh(topicId: topicId)

        case .notification:
            if let count = event.allUnreadNotificationsCount {
                notificationUnreadCount = Int(count)
            }

        case .unknown:
            break
        }
    }

    private func scheduleTopicListRefresh(for busKind: TopicListKindState) {
        guard busKind == selectedTopicKind else { return }
        pendingTopicListRefreshTask?.cancel()
        pendingTopicListRefreshTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await refreshTopicsIfPossible(force: true)
        }
    }

    private func scheduleTopicDetailRefresh(topicId: UInt64) {
        pendingTopicDetailRefreshTasks[topicId]?.cancel()
        pendingTopicDetailRefreshTasks[topicId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            guard let self, let store = self.sessionStore else { return }
            guard self.topicDetails[topicId] != nil else { return }
            do {
                let detail = try await store.fetchTopicDetail(topicID: topicId, trackVisit: false)
                self.topicDetails[topicId] = detail
            } catch {}
        }
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
        await loadTopics(page: nil, reset: true, force: force)
    }

    private func loadTopics(page: UInt32?, reset: Bool, force: Bool) async {
        if !session.readiness.canReadAuthenticatedApi {
            clearTopicState()
            return
        }
        if isLoadingTopics {
            return
        }
        if reset && !force && !topicRows.isEmpty {
            return
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
            let response = try await sessionStore.fetchTopicList(
                query: TopicListQueryState(
                    kind: requestedKind,
                    page: page,
                    topicIds: [],
                    order: nil,
                    ascending: nil
                )
            )
            let mergedTopicRows = reset
                ? response.rows
                : mergeTopicRows(existing: topicRows, incoming: response.rows)
            let visibleTopicIDs = Set(mergedTopicRows.map(\.topic.id))
            guard requestedKind == selectedTopicKind else {
                return
            }
            topicRows = mergedTopicRows
            moreTopicsUrl = response.moreTopicsUrl
            nextTopicsPage = response.nextPage
            topicDetails = topicDetails.filter { visibleTopicIDs.contains($0.key) }
            loadingTopicIDs = loadingTopicIDs.intersection(visibleTopicIDs)
        } catch {
            if reset {
                topicRows = []
                moreTopicsUrl = nil
                nextTopicsPage = nil
            }
            errorMessage = error.localizedDescription
        }
    }

    private func clearTopicState() {
        topicRows = []
        moreTopicsUrl = nil
        nextTopicsPage = nil
        topicDetails = [:]
        isLoadingTopics = false
        isAppendingTopics = false
        loadingTopicIDs = []
        submittingReplyTopicIDs = []
        mutatingPostIDs = []
    }

    private func clearNotificationState() {
        notificationUnreadCount = 0
        recentNotifications = []
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
        let detail = try await sessionStore.fetchTopicDetail(
            query: TopicDetailQueryState(
                topicId: topicId,
                postNumber: nil,
                trackVisit: false,
                filter: nil,
                usernameFilters: nil,
                filterTopLevelReplies: false
            )
        )
        topicDetails[topicId] = detail
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

    private func syncPlatformCookiesFromWebViewStore() async throws {
        let loginCoordinator = try await loginCoordinatorValue()
        let session = try await loginCoordinator.refreshPlatformCookies()
        await applySession(session)
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
        topicDetails[topicId] = detail
    }

    private func mergeTopicRows(
        existing: [FireTopicRowPresentation],
        incoming: [FireTopicRowPresentation]
    ) -> [FireTopicRowPresentation] {
        var merged = Dictionary(uniqueKeysWithValues: existing.map { ($0.topic.id, $0) })
        var orderedIDs = existing.map { $0.topic.id }

        for row in incoming {
            if merged[row.topic.id] == nil {
                orderedIDs.append(row.topic.id)
            }
            merged[row.topic.id] = row
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

    private func loginCoordinatorValue() async throws -> FireWebViewLoginCoordinator {
        if let loginCoordinator {
            return loginCoordinator
        }

        let sessionStore = try await sessionStoreValue()
        let loginCoordinator = FireWebViewLoginCoordinator(sessionStore: sessionStore)
        self.loginCoordinator = loginCoordinator
        return loginCoordinator
    }
}
