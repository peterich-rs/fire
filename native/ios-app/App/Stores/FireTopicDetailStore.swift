import Foundation

private enum FireTopicDetailSearchDirection {
    case backward
    case forward
}

@MainActor
final class FireTopicDetailStore: ObservableObject {
    nonisolated private static let topicPostPageSize = 30
    nonisolated private static let topicPostPrefetchThreshold = 10
    nonisolated private static let topicPostForwardExpansionSize = 60
    nonisolated private static let replyContextPostBatchSize = 20

    @Published private(set) var topicDetails: [UInt64: TopicDetailState] = [:]
    @Published private(set) var topicRenderStates: [UInt64: FireTopicDetailRenderState] = [:]
    @Published private(set) var topicPresenceUsersByTopic: [UInt64: [TopicPresenceUserState]] = [:]
    @Published private(set) var loadingMoreTopicPostIDs: Set<UInt64> = []
    @Published private(set) var loadingTopicIDs: Set<UInt64> = []
    @Published private(set) var submittingReplyTopicIDs: Set<UInt64> = []
    @Published private(set) var mutatingPostIDs: Set<UInt64> = []
    @Published private(set) var postActionTypes: [PostActionTypeState] = []
    @Published private(set) var isLoadingPostActionTypes = false
    @Published private(set) var postRepliesByPostID: [UInt64: [TopicPostState]] = [:]
    @Published private(set) var postReplyHistoryByPostID: [UInt64: [TopicPostState]] = [:]
    @Published private(set) var postReplyContextErrorsByPostID: [UInt64: String] = [:]
    @Published private(set) var loadingPostReplyContextIDs: Set<UInt64> = []
    @Published private(set) var topicAiSummaries: [UInt64: TopicAiSummaryState] = [:]
    @Published private(set) var loadingTopicAiSummaryIDs: Set<UInt64> = []
    @Published private(set) var unavailableTopicAiSummaryIDs: Set<UInt64> = []
    @Published private(set) var topicAiSummaryErrorsByTopicID: [UInt64: String] = [:]
    @Published private(set) var topicListRevisions: [UInt64: UInt64] = [:]
    @Published var errorMessage: String?

    private let appViewModel: FireAppViewModel
    private var topicScreens: [UInt64: TopicScreenState] = [:]
    private var topicResponseRowsByTopic: [UInt64: [TopicResponseRowState]] = [:]
    private var topicResponseCursorsByTopic: [UInt64: TopicResponseCursorState] = [:]
    private var topicMaxLoadedPostNumbers: [UInt64: UInt32] = [:]
    private var pendingTopicDetailRefreshTasks: [UInt64: Task<Void, Never>] = [:]
    private var topicPresenceHeartbeatTasks: [UInt64: Task<Void, Never>] = [:]
    private var topicPostPreloadTasks: [UInt64: Task<Void, Never>] = [:]
    private var topicWindowStates: [UInt64: FireTopicDetailWindowState] = [:]
    private var topicRenderCaches: [UInt64: FireTopicDetailRenderCache] = [:]
    private var topicDetailTargetPostNumbers: [UInt64: UInt32] = [:]
    private var activeTopicDetailOwnerTokens: [UInt64: Set<String>] = [:]
    private var topicAiSummaryTasks: [UInt64: Task<Void, Never>] = [:]
    private var hasLoadedPostActionTypes = false

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    private var renderBaseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    private func bumpTopicListRevision(topicId: UInt64) {
        topicListRevisions[topicId, default: 0] &+= 1
    }

    private func setLoadingTopic(_ isLoading: Bool, topicId: UInt64) {
        let changed: Bool
        if isLoading {
            changed = loadingTopicIDs.insert(topicId).inserted
        } else {
            changed = loadingTopicIDs.remove(topicId) != nil
        }
        if changed {
            bumpTopicListRevision(topicId: topicId)
        }
    }

    private func setLoadingMoreTopicPosts(_ isLoading: Bool, topicId: UInt64) {
        let changed: Bool
        if isLoading {
            changed = loadingMoreTopicPostIDs.insert(topicId).inserted
        } else {
            changed = loadingMoreTopicPostIDs.remove(topicId) != nil
        }
        if changed {
            bumpTopicListRevision(topicId: topicId)
        }
    }

    private func setLoadingTopicAiSummary(_ isLoading: Bool, topicId: UInt64) {
        let changed: Bool
        if isLoading {
            changed = loadingTopicAiSummaryIDs.insert(topicId).inserted
        } else {
            changed = loadingTopicAiSummaryIDs.remove(topicId) != nil
        }
        if changed {
            bumpTopicListRevision(topicId: topicId)
        }
    }

    private func setMutatingPost(
        _ isMutating: Bool,
        topicId: UInt64,
        postId: UInt64
    ) {
        let changed: Bool
        if isMutating {
            changed = mutatingPostIDs.insert(postId).inserted
        } else {
            changed = mutatingPostIDs.remove(postId) != nil
        }
        if changed {
            bumpTopicListRevision(topicId: topicId)
        }
    }

    private func updateTopicErrorMessage(_ message: String?, topicId: UInt64) {
        guard errorMessage != message else { return }
        errorMessage = message
        bumpTopicListRevision(topicId: topicId)
    }

    func applySession(_ session: SessionState) {
        let readiness = session.readiness
        if readiness.canReadAuthenticatedApi {
            return
        }
        let isLoggedOut = !readiness.hasLoginCookie && !readiness.hasCurrentUser
        if isLoggedOut {
            appViewModel.topicDetailLogger()?.notice(
                "resetting topic detail store reason=logged-out topic_ids=\(Self.formattedTopicIDs(Set(topicDetails.keys)))"
            )
            reset()
        } else {
            appViewModel.topicDetailLogger()?.debug(
                "pausing topic detail fetches reason=transient-unauth retained_topic_ids=\(Self.formattedTopicIDs(Set(topicDetails.keys)))"
            )
            cancelInFlightFetches()
        }
    }

    private func cancelInFlightFetches() {
        pendingTopicDetailRefreshTasks.values.forEach { $0.cancel() }
        pendingTopicDetailRefreshTasks = [:]
        topicPostPreloadTasks.values.forEach { $0.cancel() }
        topicPostPreloadTasks = [:]
        loadingTopicIDs.removeAll()
        loadingMoreTopicPostIDs.removeAll()
        loadingPostReplyContextIDs.removeAll()
        topicAiSummaryTasks.values.forEach { $0.cancel() }
        topicAiSummaryTasks = [:]
        loadingTopicAiSummaryIDs.removeAll()
    }

    func handleMessageBusStopped() {
        pendingTopicDetailRefreshTasks.values.forEach { $0.cancel() }
        pendingTopicDetailRefreshTasks = [:]
        topicPresenceHeartbeatTasks.values.forEach { $0.cancel() }
        topicPresenceHeartbeatTasks = [:]
        topicPresenceUsersByTopic = [:]
    }

    func reset() {
        appViewModel.topicDetailLogger()?.notice(
            "resetting topic detail store topic_ids=\(Self.formattedTopicIDs(Set(topicDetails.keys))) loading_ids=\(Self.formattedTopicIDs(loadingTopicIDs))"
        )
        pendingTopicDetailRefreshTasks.values.forEach { $0.cancel() }
        pendingTopicDetailRefreshTasks = [:]
        topicPresenceHeartbeatTasks.values.forEach { $0.cancel() }
        topicPresenceHeartbeatTasks = [:]
        topicPostPreloadTasks.values.forEach { $0.cancel() }
        topicPostPreloadTasks = [:]
        topicAiSummaryTasks.values.forEach { $0.cancel() }
        topicAiSummaryTasks = [:]
        activeTopicDetailOwnerTokens = [:]
        topicDetailTargetPostNumbers = [:]
        topicWindowStates = [:]
        topicRenderCaches = [:]
        topicScreens = [:]
        topicResponseRowsByTopic = [:]
        topicResponseCursorsByTopic = [:]
        topicMaxLoadedPostNumbers = [:]
        topicDetails = [:]
        topicRenderStates = [:]
        topicAiSummaries = [:]
        unavailableTopicAiSummaryIDs = []
        topicAiSummaryErrorsByTopicID = [:]
        topicListRevisions = [:]
        topicPresenceUsersByTopic = [:]
        loadingMoreTopicPostIDs = []
        loadingTopicIDs = []
        loadingTopicAiSummaryIDs = []
        submittingReplyTopicIDs = []
        mutatingPostIDs = []
        postActionTypes = []
        isLoadingPostActionTypes = false
        postRepliesByPostID = [:]
        postReplyHistoryByPostID = [:]
        postReplyContextErrorsByPostID = [:]
        loadingPostReplyContextIDs = []
        hasLoadedPostActionTypes = false
        errorMessage = nil
    }

    func loadTopicDetail(
        topicId: UInt64,
        targetPostNumber: UInt32? = nil,
        force: Bool = false
    ) async {
        if loadingTopicIDs.contains(topicId) {
            return
        }
        if !appViewModel.session.readiness.canReadAuthenticatedApi {
            applySession(appViewModel.session)
            return
        }

        if let targetPostNumber {
            topicDetailTargetPostNumbers[topicId] = targetPostNumber
        }

        if !force,
           let cachedScreen = topicScreens[topicId],
           targetPostNumber == nil || detailContainsPostNumber(topicId: topicId, postNumber: targetPostNumber) {
            updateTopicErrorMessage(nil, topicId: topicId)
            topicScreens[topicId] = cachedScreen
            return
        }

        appViewModel.topicDetailLogger()?.debug(
            "loading topic screen topic_id=\(topicId) force=\(force) target_post=\(String(describing: targetPostNumber))"
        )
        setLoadingTopic(true, topicId: topicId)
        defer { setLoadingTopic(false, topicId: topicId) }

        do {
            let sessionStore = try await appViewModel.sessionStoreValue()
            updateTopicErrorMessage(nil, topicId: topicId)
            let screen = try await performWithTimeout(30, operation: "加载话题详情") { [appViewModel] in
                try await FireAPMManager.shared.withSpan(
                    .topicDetailInitialLoad,
                    metadata: ["topic_id": String(topicId)]
                ) {
                    try await appViewModel.performWithCloudflareRecovery(
                        operation: "加载话题详情"
                    ) {
                        try await sessionStore.fetchTopicScreen(
                            query: TopicScreenQueryState(
                                topicId: topicId,
                                targetPostNumber: targetPostNumber,
                                rootPageSize: 10,
                                trackVisit: true,
                            )
                        )
                    }
                }
            }
            applyTopicScreen(screen, topicId: topicId)
            appViewModel.topicDetailLogger()?.debug(
                "loaded topic screen topic_id=\(topicId) loaded_replies=\(screen.response.rows.count) total_replies=\(screen.response.totalResponseCount)"
            )
        } catch {
            appViewModel.topicDetailLogger()?.error(
                "topic detail load failed topic_id=\(topicId) error=\(error.localizedDescription)"
            )
            if await appViewModel.attemptReadPathLoginRecovery(
                operation: "加载话题详情",
                error: error
            ) {
                // Release the in-flight gate before recursing; the inner call
                // returns immediately on `loadingTopicIDs.contains(topicId)`.
                setLoadingTopic(false, topicId: topicId)
                await loadTopicDetail(
                    topicId: topicId,
                    targetPostNumber: targetPostNumber,
                    force: true
                )
                return
            }
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                if topicDetails[topicId] == nil {
                    updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
                }
                return
            }
            updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
        }
    }

    private func detailContainsPostNumber(topicId: UInt64, postNumber: UInt32?) -> Bool {
        guard let postNumber else { return true }
        return topicDetails[topicId]?.postStream.posts.contains(where: { $0.postNumber == postNumber }) == true
    }

    private func synthesizedTopicDetail(
        screen: TopicScreenState,
        responseRows: [TopicResponseRowState]
    ) -> TopicDetailState {
        let posts = [screen.body.post] + responseRows.map(\.post)
        return TopicDetailState(
            id: screen.header.topicId,
            title: screen.header.title,
            slug: screen.header.slug,
            postsCount: screen.header.postsCount,
            categoryId: screen.header.categoryId,
            tags: screen.header.tags,
            views: screen.header.views,
            likeCount: screen.header.likeCount,
            createdAt: screen.header.createdAt,
            lastReadPostNumber: screen.header.lastReadPostNumber,
            bookmarks: screen.header.bookmarks,
            bookmarked: screen.header.bookmarked,
            bookmarkId: screen.header.bookmarkId,
            bookmarkName: screen.header.bookmarkName,
            bookmarkReminderAt: screen.header.bookmarkReminderAt,
            acceptedAnswer: screen.header.acceptedAnswer,
            hasAcceptedAnswer: screen.header.hasAcceptedAnswer,
            canVote: screen.header.canVote,
            voteCount: screen.header.voteCount,
            userVoted: screen.header.userVoted,
            summarizable: screen.header.summarizable,
            hasCachedSummary: screen.header.hasCachedSummary,
            hasSummary: screen.header.hasSummary,
            archetype: screen.header.archetype,
            postStream: TopicPostStreamState(
                posts: posts,
                stream: posts.map(\.id)
            ),
            details: screen.header.details
        )
    }

    nonisolated static func shouldApplyLoadedResponsePage(
        expectedCursor: TopicResponseCursorState,
        currentCursor: TopicResponseCursorState?
    ) -> Bool {
        currentCursor == expectedCursor
    }

    private func applyTopicScreen(_ screen: TopicScreenState, topicId: UInt64) {
        topicScreens[topicId] = screen
        topicResponseRowsByTopic[topicId] = screen.response.rows
        if let cursor = screen.response.nextCursor {
            topicResponseCursorsByTopic[topicId] = cursor
        } else {
            topicResponseCursorsByTopic.removeValue(forKey: topicId)
        }
        let detail = synthesizedTopicDetail(screen: screen, responseRows: screen.response.rows)
        _ = cacheTopicDetail(detail, topicId: topicId)
        loadTopicAiSummaryIfNeeded(topicId: topicId, detail: detail)
    }

    private func loadNextTopicResponsePage(topicId: UInt64) async {
        guard let cursor = topicResponseCursorsByTopic[topicId],
              let sessionStore = try? await appViewModel.sessionStoreValue() else {
            return
        }

        setLoadingMoreTopicPosts(true, topicId: topicId)
        defer { setLoadingMoreTopicPosts(false, topicId: topicId) }

        do {
            let page = try await appViewModel.performWithCloudflareRecovery(
                operation: "加载更多帖子"
            ) {
                try await sessionStore.fetchTopicResponsePage(
                    query: TopicResponsePageQueryState(cursor: cursor)
                )
            }
            guard Self.shouldApplyLoadedResponsePage(
                expectedCursor: cursor,
                currentCursor: topicResponseCursorsByTopic[topicId]
            ), let screen = topicScreens[topicId] else {
                return
            }
            var rows = topicResponseRowsByTopic[topicId] ?? []
            rows.append(contentsOf: page.rows)
            topicResponseRowsByTopic[topicId] = rows
            if let nextCursor = page.nextCursor {
                topicResponseCursorsByTopic[topicId] = nextCursor
            } else {
                topicResponseCursorsByTopic.removeValue(forKey: topicId)
            }
            let detail = synthesizedTopicDetail(screen: screen, responseRows: rows)
            _ = cacheTopicDetail(detail, topicId: topicId)
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
        }
    }

    func clearTopicDetailAnchor(topicId: UInt64) {
        clearTransientAnchor(topicId: topicId)
    }

    func pendingScrollTarget(topicId: UInt64) -> UInt32? {
        topicDetailTargetPostNumbers[topicId]
    }

    func isScrollTargetExhausted(topicId: UInt64, postNumber: UInt32) -> Bool {
        guard let detail = topicDetails[topicId] else { return false }
        if detail.postStream.posts.contains(where: { $0.postNumber == postNumber }) {
            return false
        }
        return topicResponseCursorsByTopic[topicId] == nil
    }

    func markScrollTargetSatisfied(topicId: UInt64, postNumber: UInt32) {
        guard activeAnchorPostNumber(topicId: topicId) == postNumber
            || topicDetailTargetPostNumbers[topicId] == postNumber else {
            return
        }
        clearTransientAnchor(topicId: topicId)
    }

    func topicDetail(for topicId: UInt64) -> TopicDetailState? {
        topicDetails[topicId]
    }

    func topicRenderState(for topicId: UInt64) -> FireTopicDetailRenderState? {
        topicRenderStates[topicId]
    }

    func topicPresenceUsers(for topicId: UInt64) -> [TopicPresenceUserState] {
        topicPresenceUsersByTopic[topicId] ?? []
    }

    func topicAiSummary(for topicId: UInt64) -> TopicAiSummaryState? {
        topicAiSummaries[topicId]
    }

    func isLoadingTopicAiSummary(topicId: UInt64) -> Bool {
        loadingTopicAiSummaryIDs.contains(topicId)
    }

    func topicAiSummaryError(for topicId: UInt64) -> String? {
        topicAiSummaryErrorsByTopicID[topicId]
    }

    func topicListRevision(topicId: UInt64) -> UInt64 {
        topicListRevisions[topicId] ?? 0
    }

    func isLoadingTopic(topicId: UInt64) -> Bool {
        loadingTopicIDs.contains(topicId)
    }

    func isLoadingMoreTopicPosts(topicId: UInt64) -> Bool {
        loadingMoreTopicPostIDs.contains(topicId)
    }

    func postReplies(for postID: UInt64) -> [TopicPostState]? {
        postRepliesByPostID[postID]
    }

    func postReplyHistory(for postID: UInt64) -> [TopicPostState]? {
        postReplyHistoryByPostID[postID]
    }

    func postReplyContextError(for postID: UInt64) -> String? {
        postReplyContextErrorsByPostID[postID]
    }

    func isLoadingPostReplyContext(postID: UInt64) -> Bool {
        loadingPostReplyContextIDs.contains(postID)
    }

    func hasMoreTopicPosts(topicId: UInt64) -> Bool {
        topicResponseCursorsByTopic[topicId] != nil
    }

    func preloadTopicPostsIfNeeded(
        topicId: UInt64,
        visiblePostNumbers: Set<UInt32>
    ) {
        guard hasMoreTopicPosts(topicId: topicId) else { return }
        guard !loadingMoreTopicPostIDs.contains(topicId) else { return }
        guard topicPostPreloadTasks[topicId] == nil else { return }
        guard topicDetails[topicId] != nil,
              let maxLoadedPostNumber = topicMaxLoadedPostNumbers[topicId],
              visiblePostNumbers.contains(maxLoadedPostNumber) else {
            return
        }

        topicPostPreloadTasks[topicId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.topicPostPreloadTasks[topicId] = nil }
            await self.loadNextTopicResponsePage(topicId: topicId)
        }
    }

    func needsAnchoredReload(
        detail: TopicDetailState?,
        anchorPostNumber: UInt32?,
        window: FireTopicDetailWindowState?
    ) -> Bool {
        guard let anchorPostNumber else { return detail == nil }
        guard detail != nil, let window else { return true }
        return !window.loadedPostNumbers.contains(anchorPostNumber)
    }

    func beginTopicDetailLifecycle(topicId: UInt64, ownerToken: String) {
        var owners = activeTopicDetailOwnerTokens[topicId] ?? []
        let inserted = owners.insert(ownerToken).inserted
        activeTopicDetailOwnerTokens[topicId] = owners
        guard inserted else { return }

        appViewModel.topicDetailLogger()?.debug(
            "registered topic detail lifecycle topic_id=\(topicId) owner_token=\(ownerToken) owner_count=\(owners.count)"
        )
    }

    func endTopicDetailLifecycle(
        topicId: UInt64,
        ownerToken: String,
        visibleTopicIDs: Set<UInt64>
    ) {
        guard var owners = activeTopicDetailOwnerTokens[topicId] else { return }
        guard owners.remove(ownerToken) != nil else { return }

        if owners.isEmpty {
            activeTopicDetailOwnerTokens.removeValue(forKey: topicId)
        } else {
            activeTopicDetailOwnerTokens[topicId] = owners
        }

        appViewModel.topicDetailLogger()?.debug(
            "released topic detail lifecycle topic_id=\(topicId) owner_token=\(ownerToken) owner_count=\(owners.count)"
        )

        guard owners.isEmpty else { return }
        topicDetailTargetPostNumbers.removeValue(forKey: topicId)
        guard !visibleTopicIDs.contains(topicId) else { return }
        evictTopicDetailState(topicId: topicId, reason: "detail view disappeared")
    }

    func pruneInactiveTopicDetailState(retainingVisibleTopicIDs visibleTopicIDs: Set<UInt64>) {
        let retainedTopicIDs = retainedTopicDetailIDs(visibleTopicIDs: visibleTopicIDs)
        pruneInactiveTopicDetailState(retaining: retainedTopicIDs, visibleTopicIDs: visibleTopicIDs)
    }

    func maintainTopicDetailSubscription(topicId: UInt64, ownerToken: String) async {
        guard appViewModel.session.readiness.canOpenMessageBus else { return }
        guard topicDetails[topicId] != nil else {
            appViewModel.topicDetailLogger()?.debug(
                "skipping topic detail subscription bootstrap topic_id=\(topicId) reason=detail not loaded"
            )
            return
        }

        guard let store = appViewModel.currentSessionStore() else { return }

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

        await appViewModel.ensureMessageBusActiveIfPossible()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(3600))
            } catch {
                break
            }
        }
    }

    func handleMessageBusEvent(_ event: MessageBusEventState) {
        switch event.kind {
        case .topicDetail, .topicReaction:
            guard let topicId = event.topicId else { return }
            guard topicDetails[topicId] != nil else { return }
            scheduleTopicDetailRefresh(topicId: topicId)
        case .presence:
            guard let topicId = event.topicId else { return }
            refreshTopicPresenceState(topicId: topicId)
        default:
            break
        }
    }

    func beginTopicReplyPresence(topicId: UInt64) {
        guard appViewModel.session.readiness.canOpenMessageBus else { return }
        guard appViewModel.canStartAuthenticatedMutation else { return }
        guard topicPresenceHeartbeatTasks[topicId] == nil else { return }
        guard let store = appViewModel.currentSessionStore() else { return }

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
        guard let store = appViewModel.currentSessionStore() else { return }
        try? await store.updateTopicReplyPresence(topicId: topicId, active: false)
    }

    func isSubmittingReply(topicId: UInt64) -> Bool {
        submittingReplyTopicIDs.contains(topicId)
    }

    func isMutatingPost(postId: UInt64) -> Bool {
        mutatingPostIDs.contains(postId)
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

        let sessionStore = try await appViewModel.sessionStoreValue()
        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !submittingReplyTopicIDs.contains(topicId) else {
            return
        }

        submittingReplyTopicIDs.insert(topicId)
        defer { submittingReplyTopicIDs.remove(topicId) }

        do {
            errorMessage = nil
            let createdReply = try await FireAPMManager.shared.withSpan(
                .topicReplySubmit,
                metadata: [
                    "topic_id": String(topicId),
                    "reply_to_post_number": replyToPostNumber.map(String.init) ?? "root"
                ]
            ) {
                try await appViewModel.performWriteWithCloudflareRetry {
                    try await sessionStore.createReply(
                        topicID: topicId,
                        raw: trimmed,
                        replyToPostNumber: replyToPostNumber
                    )
                }
            }
            await appViewModel.syncSessionSnapshotIfAvailable(from: sessionStore)
            applyCreatedReply(createdReply, topicId: topicId)
            try? await refreshTopicDetailAfterMutation(topicId: topicId, sessionStore: sessionStore)
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
            errorMessage = error.localizedDescription
            throw error
        }
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

        let sessionStore = try await appViewModel.sessionStoreValue()
        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postID) else {
            return try await sessionStore.fetchPost(postID: postID)
        }

        setMutatingPost(true, topicId: topicID, postId: postID)
        defer { setMutatingPost(false, topicId: topicID, postId: postID) }

        do {
            errorMessage = nil
            let updatedPost = try await appViewModel.performWriteWithCloudflareRetry {
                try await sessionStore.updatePost(
                    postID: postID,
                    raw: trimmedRaw,
                    editReason: editReason
                )
            }
            await appViewModel.syncSessionSnapshotIfAvailable(from: sessionStore)
            try? await refreshTopicDetailAfterMutation(topicId: topicID, sessionStore: sessionStore)
            await appViewModel.refreshHomeFeedIfPossible(force: false)
            return updatedPost
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func deletePost(topicID: UInt64, postID: UInt64) async throws {
        try await performPostManagementMutation(topicID: topicID, postID: postID) { sessionStore in
            try await sessionStore.deletePost(postID: postID)
        }
    }

    func recoverPost(topicID: UInt64, postID: UInt64) async throws {
        try await performPostManagementMutation(topicID: topicID, postID: postID) { sessionStore in
            try await sessionStore.recoverPost(postID: postID)
        }
    }

    func flagPost(
        topicID: UInt64,
        postID: UInt64,
        flagTypeID: UInt32,
        message: String?
    ) async throws {
        let trimmedMessage = message?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try await performPostManagementMutation(topicID: topicID, postID: postID) { sessionStore in
            try await sessionStore.flagPost(
                postID: postID,
                flagTypeID: flagTypeID,
                message: trimmedMessage?.isEmpty == true ? nil : trimmedMessage
            )
        }
    }

    func loadPostActionTypesIfNeeded(force: Bool = false) async {
        if isLoadingPostActionTypes {
            return
        }
        if hasLoadedPostActionTypes && !force {
            return
        }

        guard let sessionStore = try? await appViewModel.sessionStoreValue() else {
            return
        }

        isLoadingPostActionTypes = true
        defer { isLoadingPostActionTypes = false }

        do {
            let types = try await appViewModel.performWithCloudflareRecovery(
                operation: "加载举报类型"
            ) {
                try await sessionStore.fetchPostActionTypes()
            }
            postActionTypes = types
            hasLoadedPostActionTypes = true
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            appViewModel.topicDetailLogger()?.warning(
                "failed to load post action types: \(error.localizedDescription)"
            )
            hasLoadedPostActionTypes = true
        }
    }

    func loadPostReplyContextIfNeeded(
        topicID: UInt64,
        post: TopicPostState,
        force: Bool = false
    ) async {
        guard force
            || postRepliesByPostID[post.id] == nil
            || postReplyHistoryByPostID[post.id] == nil else {
            return
        }
        guard !loadingPostReplyContextIDs.contains(post.id) else {
            return
        }
        guard let sessionStore = try? await appViewModel.sessionStoreValue() else {
            return
        }

        loadingPostReplyContextIDs.insert(post.id)
        postReplyContextErrorsByPostID[post.id] = nil
        defer { loadingPostReplyContextIDs.remove(post.id) }

        do {
            let replies = try await appViewModel.performWithCloudflareRecovery(
                operation: "加载帖子回复"
            ) {
                try await self.fetchReplyContextReplies(
                    topicID: topicID,
                    post: post,
                    sessionStore: sessionStore
                )
            }
            let replyHistory = try await appViewModel.performWithCloudflareRecovery(
                operation: "加载回复来源"
            ) {
                post.replyToPostNumber != nil
                    ? try await sessionStore.fetchPostReplyHistory(postID: post.id)
                    : []
            }
            postRepliesByPostID[post.id] = replies
            postReplyHistoryByPostID[post.id] = replyHistory

            let refreshedPosts = replies + replyHistory
            if !refreshedPosts.isEmpty {
                applyHydratedTopicPostsIfNeeded(
                    topicId: topicID,
                    posts: refreshedPosts,
                    exhaustedPostIDs: []
                )
            }
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            postReplyContextErrorsByPostID[post.id] = error.localizedDescription
        }
    }

    private func fetchReplyContextReplies(
        topicID: UInt64,
        post: TopicPostState,
        sessionStore: FireSessionStore
    ) async throws -> [TopicPostState] {
        guard post.replyCount > 0 else {
            return []
        }

        let replyIDs = orderedUniquePostIDs(
            try await sessionStore.fetchPostReplyIds(postID: post.id)
        )
        guard !replyIDs.isEmpty else {
            return try await sessionStore.fetchPostReplies(postID: post.id, after: 1)
        }

        var replies: [TopicPostState] = []
        var startIndex = 0
        while startIndex < replyIDs.count {
            let endIndex = min(startIndex + Self.replyContextPostBatchSize, replyIDs.count)
            let batchIDs = Array(replyIDs[startIndex..<endIndex])
            replies.append(
                contentsOf: try await sessionStore.fetchTopicPosts(
                    topicID: topicID,
                    postIDs: batchIDs
                )
            )
            startIndex = endIndex
        }
        return replies
    }

    private func orderedUniquePostIDs(_ ids: [UInt64]) -> [UInt64] {
        var seen: Set<UInt64> = []
        var result: [UInt64] = []
        for id in ids where id > 0 && !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    func setPostLiked(
        topicId: UInt64,
        postId: UInt64,
        liked: Bool
    ) async throws {
        let sessionStore = try await appViewModel.sessionStoreValue()
        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postId) else {
            return
        }

        setMutatingPost(true, topicId: topicId, postId: postId)
        defer { setMutatingPost(false, topicId: topicId, postId: postId) }

        do {
            errorMessage = nil
            let update = try await appViewModel.performWriteWithCloudflareRetry {
                if liked {
                    try await sessionStore.likePost(postID: postId)
                } else {
                    try await sessionStore.unlikePost(postID: postId)
                }
            }
            await appViewModel.syncSessionSnapshotIfAvailable(from: sessionStore)
            if let update {
                applyPostReactionUpdate(topicId: topicId, postId: postId, update: update)
            } else {
                try? await refreshTopicDetailAfterMutation(topicId: topicId, sessionStore: sessionStore)
            }
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
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

        let sessionStore = try await appViewModel.sessionStoreValue()
        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postId) else {
            return
        }

        setMutatingPost(true, topicId: topicId, postId: postId)
        defer { setMutatingPost(false, topicId: topicId, postId: postId) }

        do {
            errorMessage = nil
            let update = try await appViewModel.performWriteWithCloudflareRetry {
                try await sessionStore.togglePostReaction(
                    postID: postId,
                    reactionID: trimmedReactionID
                )
            }
            applyPostReactionUpdate(topicId: topicId, postId: postId, update: update)
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func performPostManagementMutation(
        topicID: UInt64,
        postID: UInt64,
        operation: @escaping (FireSessionStore) async throws -> Void
    ) async throws {
        let sessionStore = try await appViewModel.sessionStoreValue()
        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postID) else {
            return
        }

        setMutatingPost(true, topicId: topicID, postId: postID)
        defer { setMutatingPost(false, topicId: topicID, postId: postID) }

        do {
            errorMessage = nil
            try await appViewModel.performWriteWithCloudflareRetry {
                try await operation(sessionStore)
            }
            await appViewModel.syncSessionSnapshotIfAvailable(from: sessionStore)
            try? await refreshTopicDetailAfterMutation(topicId: topicID, sessionStore: sessionStore)
            await appViewModel.refreshHomeFeedIfPossible(force: false)
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func refreshTopicDetailAfterMutation(topicId: UInt64) async {
        guard let sessionStore = try? await appViewModel.sessionStoreValue() else {
            return
        }
        try? await refreshTopicDetailAfterMutation(topicId: topicId, sessionStore: sessionStore)
    }

    private func refreshTopicDetailAfterMutation(
        topicId: UInt64,
        sessionStore: FireSessionStore
    ) async throws {
        let screen = try await performWithTimeout(30, operation: "刷新话题详情") { [appViewModel] in
            try await appViewModel.performWithCloudflareRecovery(
                operation: "刷新话题详情"
            ) {
                try await sessionStore.fetchTopicScreen(
                    query: TopicScreenQueryState(
                        topicId: topicId,
                        targetPostNumber: nil,
                        rootPageSize: 10,
                        trackVisit: false,
                    )
                )
            }
        }
        applyTopicScreen(screen, topicId: topicId)
    }

    private func scheduleTopicDetailRefresh(topicId: UInt64) {
        pendingTopicDetailRefreshTasks[topicId]?.cancel()
        pendingTopicDetailRefreshTasks[topicId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            guard let self, let store = self.appViewModel.currentSessionStore() else { return }
            guard self.topicDetails[topicId] != nil else { return }
            let anchorPostNumber = self.activeAnchorPostNumber(topicId: topicId)
            do {
                let screen = try await self.performWithTimeout(30, operation: "刷新话题详情") { [appViewModel = self.appViewModel] in
                    try await appViewModel.performWithCloudflareRecovery(
                        operation: "刷新话题详情"
                    ) {
                        try await store.fetchTopicScreen(
                            query: TopicScreenQueryState(
                                topicId: topicId,
                                targetPostNumber: anchorPostNumber,
                                rootPageSize: 10,
                                trackVisit: false,
                            )
                        )
                    }
                }
                self.applyTopicScreen(screen, topicId: topicId)
            } catch {
                if await self.appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                    self.appViewModel.topicDetailLogger()?.notice(
                        "recoverable session error swallowed during topic detail refresh topic_id=\(topicId)"
                    )
                    return
                }
                self.appViewModel.topicDetailLogger()?.error(
                    "topic detail background refresh failed topic_id=\(topicId) error=\(error.localizedDescription)"
                )
            }
        }
    }

    private func refreshTopicPresenceState(topicId: UInt64) {
        guard let store = appViewModel.currentSessionStore() else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let presence = try? await store.topicReplyPresenceState(topicId: topicId) else {
                return
            }
            self.applyTopicPresenceState(presence)
        }
    }

    private func applyTopicPresenceState(_ state: TopicPresenceState) {
        let currentUserID = appViewModel.session.bootstrap.currentUserId
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

    func retainedTopicDetailIDs(visibleTopicIDs: Set<UInt64>) -> Set<UInt64> {
        let activeTopicIDs = activeTopicDetailOwnerTokens.compactMap { topicId, owners in
            owners.isEmpty ? nil : topicId
        }
        return visibleTopicIDs.union(activeTopicIDs)
    }

    private func pruneInactiveTopicDetailState(
        retaining retainedTopicIDs: Set<UInt64>,
        visibleTopicIDs: Set<UInt64>
    ) {
        let trackedTopicIDs = Set(topicDetails.keys)
            .union(topicWindowStates.keys)
            .union(topicPresenceUsersByTopic.keys)
            .union(topicAiSummaries.keys)
            .union(loadingTopicAiSummaryIDs)
            .union(unavailableTopicAiSummaryIDs)
            .union(topicAiSummaryErrorsByTopicID.keys)
            .union(topicAiSummaryTasks.keys)
            .union(loadingTopicIDs)
            .union(loadingMoreTopicPostIDs)
            .union(topicPostPreloadTasks.keys)
            .union(pendingTopicDetailRefreshTasks.keys)
            .union(topicPresenceHeartbeatTasks.keys)
        let inactiveTopicIDs = trackedTopicIDs.subtracting(retainedTopicIDs)
        guard !inactiveTopicIDs.isEmpty else {
            return
        }

        let activeTopicIDs = retainedTopicIDs.subtracting(visibleTopicIDs)
        appViewModel.topicDetailLogger()?.notice(
            "pruning inactive topic detail state retained_active_topic_ids=\(Self.formattedTopicIDs(activeTopicIDs)) pruned_topic_ids=\(Self.formattedTopicIDs(inactiveTopicIDs))"
        )

        for topicId in inactiveTopicIDs.sorted() {
            evictTopicDetailState(topicId: topicId, reason: "topic list refresh pruned inactive detail")
        }
    }

    private static func formattedTopicIDs(_ topicIDs: Set<UInt64>) -> String {
        topicIDs.sorted().map(String.init).joined(separator: ",")
    }

    private func activeAnchorPostNumber(topicId: UInt64) -> UInt32? {
        topicWindowStates[topicId]?.activeAnchorPostNumber
            ?? topicDetailTargetPostNumbers[topicId]
    }

    private func clearTransientAnchor(topicId: UInt64) {
        topicDetailTargetPostNumbers.removeValue(forKey: topicId)
        if let window = topicWindowStates[topicId] {
            topicWindowStates[topicId] = window.clearingTransientAnchor()
        }
    }

    private func evictTopicDetailState(topicId: UInt64, reason: String) {
        topicScreens.removeValue(forKey: topicId)
        topicResponseRowsByTopic.removeValue(forKey: topicId)
        topicResponseCursorsByTopic.removeValue(forKey: topicId)
        topicMaxLoadedPostNumbers.removeValue(forKey: topicId)
        let removedDetail = topicDetails.removeValue(forKey: topicId) != nil
        let removedRenderState = topicRenderStates.removeValue(forKey: topicId) != nil
        topicRenderCaches.removeValue(forKey: topicId)
        let removedWindow = topicWindowStates.removeValue(forKey: topicId) != nil
        let removedPresence = topicPresenceUsersByTopic.removeValue(forKey: topicId) != nil
        let removedAiSummary = topicAiSummaries.removeValue(forKey: topicId) != nil
        let removedAiSummaryUnavailable = unavailableTopicAiSummaryIDs.remove(topicId) != nil
        let removedAiSummaryError = topicAiSummaryErrorsByTopicID.removeValue(forKey: topicId) != nil
        topicListRevisions.removeValue(forKey: topicId)
        let removedLoadingTopic = loadingTopicIDs.remove(topicId) != nil
        let removedLoadingMore = loadingMoreTopicPostIDs.remove(topicId) != nil
        let removedLoadingAiSummary = loadingTopicAiSummaryIDs.remove(topicId) != nil
        let refreshTask = pendingTopicDetailRefreshTasks.removeValue(forKey: topicId)
        let presenceTask = topicPresenceHeartbeatTasks.removeValue(forKey: topicId)
        let preloadTask = topicPostPreloadTasks.removeValue(forKey: topicId)
        let aiSummaryTask = topicAiSummaryTasks.removeValue(forKey: topicId)
        refreshTask?.cancel()
        presenceTask?.cancel()
        preloadTask?.cancel()
        aiSummaryTask?.cancel()

        guard removedDetail
            || removedRenderState
            || removedWindow
            || removedPresence
            || removedAiSummary
            || removedAiSummaryUnavailable
            || removedAiSummaryError
            || removedLoadingTopic
            || removedLoadingMore
            || removedLoadingAiSummary
            || refreshTask != nil
            || presenceTask != nil
            || preloadTask != nil
            || aiSummaryTask != nil
        else {
            return
        }

        appViewModel.topicDetailLogger()?.notice(
            "evicted topic detail state topic_id=\(topicId) reason=\(reason)"
        )
    }

    private func cacheTopicDetail(
        _ detail: TopicDetailState,
        topicId: UInt64
    ) -> TopicDetailState {
        var cachedDetail = detail
        cachedDetail.postStream = TopicPostStreamState(
            posts: FireTopicPresentation.mergeTopicPosts(
                existing: detail.postStream.posts,
                incoming: [],
                orderedPostIDs: detail.postStream.stream
            ),
            stream: detail.postStream.stream
        )

        let didUpdateDetail = topicDetails[topicId] != cachedDetail
        if didUpdateDetail {
            topicDetails[topicId] = cachedDetail
        }
        if let maxLoadedPostNumber = cachedDetail.postStream.posts.map(\.postNumber).max() {
            topicMaxLoadedPostNumbers[topicId] = maxLoadedPostNumber
        } else {
            topicMaxLoadedPostNumbers.removeValue(forKey: topicId)
        }

        let previousRenderCache = topicRenderCaches[topicId]
        let renderCache: FireTopicDetailRenderCache
        if let screen = topicScreens[topicId],
           let responseRows = topicResponseRowsByTopic[topicId] {
            renderCache = FireTopicPresentation.detailRenderCache(
                screen: screen,
                responseRows: responseRows,
                baseURLString: renderBaseURLString,
                previous: previousRenderCache
            )
        } else {
            renderCache = FireTopicPresentation.detailRenderCache(
                from: cachedDetail,
                baseURLString: renderBaseURLString,
                previous: previousRenderCache
            )
        }
        topicRenderCaches[topicId] = renderCache

        let didUpdateRenderState =
            previousRenderCache?.baseURLString != renderCache.baseURLString
            || previousRenderCache?.rowInputs != renderCache.rowInputs
            || previousRenderCache?.contentInputsByPostID != renderCache.contentInputsByPostID
        if didUpdateRenderState {
            topicRenderStates[topicId] = renderCache.renderState
        }
        if didUpdateDetail || didUpdateRenderState {
            bumpTopicListRevision(topicId: topicId)
        }
        return cachedDetail
    }

    private func applyTopicDetail(
        _ incomingDetail: TopicDetailState,
        topicId: UInt64,
        seededExhaustedPostIDs: Set<UInt64> = []
    ) {
        var detail = incomingDetail
        if let previousDetail = topicDetails[topicId] {
            detail.postStream.posts = FireTopicPresentation.mergeTopicPosts(
                existing: previousDetail.postStream.posts,
                incoming: detail.postStream.posts,
                orderedPostIDs: detail.postStream.stream
            )
        }
        detail = cacheTopicDetail(detail, topicId: topicId)

        refreshTopicWindowState(
            topicId: topicId,
            detail: detail,
            anchorPostNumber: activeAnchorPostNumber(topicId: topicId),
            requestedRange: topicWindowStates[topicId]?.requestedRange,
            pendingScrollTarget: topicWindowStates[topicId]?.pendingScrollTarget
                ?? topicDetailTargetPostNumbers[topicId]
        )

        if !seededExhaustedPostIDs.isEmpty {
            topicWindowStates[topicId]?.exhaustedPostIDs.formUnion(seededExhaustedPostIDs)
        }

        if hasMissingPostsInRequestedRange(topicId: topicId) {
            Task {
                await hydrateTopicPostsToTargetIfNeeded(topicId: topicId)
            }
        }

        loadTopicAiSummaryIfNeeded(topicId: topicId, detail: detail)
    }

    func reloadTopicAiSummary(topicId: UInt64) {
        guard let detail = topicDetails[topicId] else { return }
        loadTopicAiSummaryIfNeeded(topicId: topicId, detail: detail, force: true)
    }

    private func loadTopicAiSummaryIfNeeded(
        topicId: UInt64,
        detail: TopicDetailState,
        force: Bool = false
    ) {
        guard detail.summarizable || detail.hasCachedSummary || detail.hasSummary else {
            return
        }
        guard force
            || topicAiSummaries[topicId] == nil
                && !loadingTopicAiSummaryIDs.contains(topicId)
                && !unavailableTopicAiSummaryIDs.contains(topicId) else {
            return
        }

        topicAiSummaryTasks[topicId]?.cancel()
        let clearedUnavailable = unavailableTopicAiSummaryIDs.remove(topicId) != nil
        let clearedError = topicAiSummaryErrorsByTopicID.removeValue(forKey: topicId) != nil
        setLoadingTopicAiSummary(true, topicId: topicId)
        if clearedUnavailable || clearedError {
            bumpTopicListRevision(topicId: topicId)
        }

        topicAiSummaryTasks[topicId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.setLoadingTopicAiSummary(false, topicId: topicId)
                self.topicAiSummaryTasks.removeValue(forKey: topicId)
            }

            do {
                let sessionStore = try await self.appViewModel.sessionStoreValue()
                let summary = try await self.appViewModel.performWithCloudflareRecovery(
                    operation: "加载 AI 摘要"
                ) {
                    try await sessionStore.fetchTopicAiSummary(
                        topicID: topicId,
                        skipAgeCheck: false
                    )
                }

                if let summary,
                   !summary.summarizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let didChangeSummary = self.topicAiSummaries[topicId] != summary
                    self.topicAiSummaries[topicId] = summary
                    let clearedUnavailable = self.unavailableTopicAiSummaryIDs.remove(topicId) != nil
                    let clearedError = self.topicAiSummaryErrorsByTopicID.removeValue(forKey: topicId) != nil
                    if didChangeSummary || clearedUnavailable || clearedError {
                        self.bumpTopicListRevision(topicId: topicId)
                    }
                } else {
                    let removedSummary = self.topicAiSummaries.removeValue(forKey: topicId) != nil
                    let insertedUnavailable = self.unavailableTopicAiSummaryIDs.insert(topicId).inserted
                    if removedSummary || insertedUnavailable {
                        self.bumpTopicListRevision(topicId: topicId)
                    }
                }
            } catch {
                if await self.appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                    self.appViewModel.topicDetailLogger()?.notice(
                        "recoverable session error swallowed during topic AI summary load topic_id=\(topicId)"
                    )
                    return
                }
                if self.topicAiSummaryErrorsByTopicID[topicId] != error.localizedDescription {
                    self.topicAiSummaryErrorsByTopicID[topicId] = error.localizedDescription
                    self.bumpTopicListRevision(topicId: topicId)
                }
                self.appViewModel.topicDetailLogger()?.error(
                    "topic AI summary load failed topic_id=\(topicId) error=\(error.localizedDescription)"
                )
            }
        }
    }

    private func prehydrateAnchoredContextBeforeDisplayIfNeeded(
        detail: TopicDetailState,
        topicId: UInt64,
        anchorPostNumber: UInt32?,
        previousWindow: FireTopicDetailWindowState?,
        pendingScrollTarget: UInt32?,
        sessionStore: FireSessionStore
    ) async throws -> (detail: TopicDetailState, exhaustedPostIDs: Set<UInt64>) {
        guard anchorPostNumber != nil || pendingScrollTarget != nil else {
            return (detail, previousWindow?.exhaustedPostIDs ?? [])
        }

        let window = resolvedTopicWindowState(
            detail: detail,
            previousWindow: previousWindow,
            anchorPostNumber: anchorPostNumber,
            requestedRange: previousWindow?.requestedRange,
            pendingScrollTarget: pendingScrollTarget
        )
        let missingPostIDs = FireTopicPresentation.missingPostIDs(
            orderedPostIDs: detail.postStream.stream,
            in: window.requestedRange,
            loadedPostIDs: Set(detail.postStream.posts.map(\.id)),
            excluding: window.exhaustedPostIDs
        )
        guard !missingPostIDs.isEmpty else {
            return (detail, window.exhaustedPostIDs)
        }

        return try await Self.hydrateRequestedRange(
            detail: detail,
            window: window
        ) { [appViewModel] batchPostIDs in
            try await appViewModel.performWithCloudflareRecovery(
                operation: "加载更多帖子"
            ) {
                try await sessionStore.fetchTopicPosts(
                    topicID: topicId,
                    postIDs: batchPostIDs
                )
            }
        }
    }

    static func hydrateRequestedRange(
        detail: TopicDetailState,
        window: FireTopicDetailWindowState,
        fetchPosts: @escaping @Sendable ([UInt64]) async throws -> [TopicPostState]
    ) async throws -> (detail: TopicDetailState, exhaustedPostIDs: Set<UInt64>) {
        var hydratedDetail = detail
        var exhaustedPostIDs = window.exhaustedPostIDs

        while true {
            let missingPostIDs = FireTopicPresentation.missingPostIDs(
                orderedPostIDs: hydratedDetail.postStream.stream,
                in: window.requestedRange,
                loadedPostIDs: Set(hydratedDetail.postStream.posts.map(\.id)),
                excluding: exhaustedPostIDs
            )
            guard !missingPostIDs.isEmpty else {
                return (hydratedDetail, exhaustedPostIDs)
            }

            let batchPostIDs = Array(missingPostIDs.prefix(topicPostPageSize))
            let fetchedPosts = try await fetchPosts(batchPostIDs)
            let returnedPostIDs = Set(fetchedPosts.map(\.id))
            exhaustedPostIDs.formUnion(
                batchPostIDs.filter { !returnedPostIDs.contains($0) }
            )

            guard !fetchedPosts.isEmpty else {
                continue
            }

            hydratedDetail.postStream.posts = FireTopicPresentation.mergeTopicPosts(
                existing: hydratedDetail.postStream.posts,
                incoming: fetchedPosts,
                orderedPostIDs: hydratedDetail.postStream.stream
            )
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

        let previousStreamCount = detail.postStream.stream.count
        detail = cacheTopicDetail(detail, topicId: topicId)

        var requestedRange = topicWindowStates[topicId]?.requestedRange
        if let window = topicWindowStates[topicId],
           window.requestedRange.upperBound >= previousStreamCount {
            requestedRange = window.requestedRange.lowerBound..<detail.postStream.stream.count
        }

        refreshTopicWindowState(
            topicId: topicId,
            detail: detail,
            anchorPostNumber: activeAnchorPostNumber(topicId: topicId),
            requestedRange: requestedRange,
            pendingScrollTarget: topicWindowStates[topicId]?.pendingScrollTarget
        )
    }

    private func expandRequestedRangeIfNeeded(
        topicId: UInt64,
        visiblePostNumbers: Set<UInt32>
    ) async {
        guard let detail = topicDetails[topicId],
              var window = topicWindowStates[topicId] else {
            return
        }

        let previousRange = window.requestedRange
        let visibleIndices = visiblePostNumbers.compactMap { postNumber in
            streamIndex(forPostNumber: postNumber, in: detail)
        }

        if let minVisibleIndex = visibleIndices.min(),
           let maxVisibleIndex = visibleIndices.max() {
            let shouldExpandBackward = window.requestedRange.lowerBound > 0
                && minVisibleIndex <= window.requestedRange.lowerBound + Self.topicPostPrefetchThreshold
            let shouldExpandForward = window.requestedRange.upperBound < detail.postStream.stream.count
                && maxVisibleIndex >= max(
                    window.requestedRange.lowerBound,
                    window.requestedRange.upperBound - Self.topicPostPrefetchThreshold - 1
                )

            if shouldExpandBackward || shouldExpandForward {
                window.requestedRange = Self.expandedRequestedRange(
                    current: window.requestedRange,
                    totalCount: detail.postStream.stream.count,
                    expandBackward: shouldExpandBackward,
                    expandForward: shouldExpandForward,
                    anchorIndex: streamIndex(forPostNumber: window.activeAnchorPostNumber, in: detail)
                )
                topicWindowStates[topicId] = window
            }
        }

        if topicWindowStates[topicId]?.requestedRange != previousRange
            || hasMissingPostsInRequestedRange(topicId: topicId) {
            await hydrateTopicPostsToTargetIfNeeded(topicId: topicId)
        }
    }

    private func hydrateTopicPostsToTargetIfNeeded(topicId: UInt64) async {
        guard let sessionStore = appViewModel.currentSessionStore() else {
            return
        }
        guard !Task.isCancelled else {
            return
        }
        guard !loadingMoreTopicPostIDs.contains(topicId) else {
            return
        }

        setLoadingMoreTopicPosts(true, topicId: topicId)
        defer { setLoadingMoreTopicPosts(false, topicId: topicId) }

        var hydratedPosts: [TopicPostState] = []
        var hydratedPostIDs: Set<UInt64> = []
        var exhaustedPostIDs: Set<UInt64> = []

        while !Task.isCancelled {
            guard let detail = topicDetails[topicId],
                  let window = topicWindowStates[topicId] else {
                return
            }

            let missingPostIDs = FireTopicPresentation.missingPostIDs(
                orderedPostIDs: detail.postStream.stream,
                in: window.requestedRange,
                loadedPostIDs: Set(detail.postStream.posts.map(\.id)).union(hydratedPostIDs),
                excluding: window.exhaustedPostIDs.union(exhaustedPostIDs)
            )
            guard !missingPostIDs.isEmpty else {
                if !hydratedPosts.isEmpty || !exhaustedPostIDs.isEmpty {
                    applyHydratedTopicPostsIfNeeded(
                        topicId: topicId,
                        posts: hydratedPosts,
                        exhaustedPostIDs: exhaustedPostIDs
                    )
                    hydratedPosts.removeAll()
                    hydratedPostIDs.removeAll()
                    exhaustedPostIDs.removeAll()
                    continue
                }
                if advanceRequestedRangeTowardPendingScrollTargetIfNeeded(
                    topicId: topicId,
                    detail: detail,
                    window: window
                ) {
                    continue
                }
                applyHydratedTopicPostsIfNeeded(
                    topicId: topicId,
                    posts: hydratedPosts,
                    exhaustedPostIDs: exhaustedPostIDs
                )
                return
            }

            let batchPostIDs = Array(missingPostIDs.prefix(Self.topicPostPageSize))

            do {
                let fetchedPosts = try await appViewModel.performWithCloudflareRecovery(
                    operation: "加载更多帖子"
                ) {
                    try await sessionStore.fetchTopicPosts(
                        topicID: topicId,
                        postIDs: batchPostIDs
                    )
                }
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
                if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
                updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
                return
            }
        }

        applyHydratedTopicPostsIfNeeded(
            topicId: topicId,
            posts: hydratedPosts,
            exhaustedPostIDs: exhaustedPostIDs
        )
    }

    private func advanceRequestedRangeTowardPendingScrollTargetIfNeeded(
        topicId: UInt64,
        detail: TopicDetailState,
        window: FireTopicDetailWindowState
    ) -> Bool {
        guard let target = window.pendingScrollTarget,
              !window.loadedPostNumbers.contains(target) else {
            return false
        }

        let loadedPostNumbersInWindow = loadedPostNumbers(
            in: window.requestedRange,
            detail: detail
        )
        guard let nextRange = Self.nextRequestedRangeForUnresolvedTarget(
            postNumber: target,
            current: window.requestedRange,
            totalCount: detail.postStream.stream.count,
            loadedPostNumbersInCurrentRange: loadedPostNumbersInWindow
        ), nextRange != window.requestedRange else {
            return false
        }

        topicWindowStates[topicId]?.requestedRange = nextRange
        return true
    }

    private func loadedPostNumbers(
        in range: Range<Int>,
        detail: TopicDetailState
    ) -> [UInt32] {
        let indexByPostID = Dictionary(
            uniqueKeysWithValues: detail.postStream.stream.enumerated().map { index, postID in
                (postID, index)
            }
        )
        return detail.postStream.posts.compactMap { post in
            guard let index = indexByPostID[post.id],
                  range.contains(index) else {
                return nil
            }
            return post.postNumber
        }
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
              let currentWindow = topicWindowStates[topicId] else {
            return
        }

        topicWindowStates[topicId]?.exhaustedPostIDs.formUnion(exhaustedPostIDs)

        guard !posts.isEmpty else {
            if let target = topicWindowStates[topicId]?.pendingScrollTarget,
               isScrollTargetExhausted(topicId: topicId, postNumber: target) {
                markScrollTargetSatisfied(topicId: topicId, postNumber: target)
            }
            return
        }

        currentDetail.postStream.posts = FireTopicPresentation.mergeTopicPosts(
            existing: currentDetail.postStream.posts,
            incoming: posts,
            orderedPostIDs: currentDetail.postStream.stream
        )
        let cachedDetail = cacheTopicDetail(currentDetail, topicId: topicId)

        refreshTopicWindowState(
            topicId: topicId,
            detail: cachedDetail,
            anchorPostNumber: currentWindow.activeAnchorPostNumber,
            requestedRange: currentWindow.requestedRange,
            pendingScrollTarget: currentWindow.pendingScrollTarget
        )

        if let target = topicWindowStates[topicId]?.pendingScrollTarget,
           isScrollTargetExhausted(topicId: topicId, postNumber: target) {
            markScrollTargetSatisfied(topicId: topicId, postNumber: target)
        }
    }

    private func hasMissingPostsInRequestedRange(topicId: UInt64) -> Bool {
        guard let detail = topicDetails[topicId],
              let window = topicWindowStates[topicId] else {
            return false
        }

        let missingPostIDs = FireTopicPresentation.missingPostIDs(
            orderedPostIDs: detail.postStream.stream,
            in: window.requestedRange,
            loadedPostIDs: Set(detail.postStream.posts.map(\.id)),
            excluding: window.exhaustedPostIDs
        )
        return !missingPostIDs.isEmpty
    }

    private func refreshTopicWindowState(
        topicId: UInt64,
        detail: TopicDetailState,
        anchorPostNumber: UInt32?,
        requestedRange: Range<Int>?,
        pendingScrollTarget: UInt32?
    ) {
        topicWindowStates[topicId] = resolvedTopicWindowState(
            detail: detail,
            previousWindow: topicWindowStates[topicId],
            anchorPostNumber: anchorPostNumber,
            requestedRange: requestedRange,
            pendingScrollTarget: pendingScrollTarget
        )
    }

    private func resolvedTopicWindowState(
        detail: TopicDetailState,
        previousWindow: FireTopicDetailWindowState?,
        anchorPostNumber: UInt32?,
        requestedRange: Range<Int>?,
        pendingScrollTarget: UInt32?
    ) -> FireTopicDetailWindowState {
        let loadedPostNumbers = Set(detail.postStream.posts.map(\.postNumber))
        let loadedPostIDs = Set(detail.postStream.posts.map(\.id))
        var loadedIndices = IndexSet()
        for (index, postID) in detail.postStream.stream.enumerated() {
            if loadedPostIDs.contains(postID) {
                loadedIndices.insert(index)
            }
        }

        let resolvedAnchor = pendingScrollTarget ?? anchorPostNumber ?? previousWindow?.pendingScrollTarget
        let anchorIndex = streamIndex(forPostNumber: resolvedAnchor, in: detail)
        let anchorChanged = resolvedAnchor != previousWindow?.activeAnchorPostNumber
        let resolvedRequestedRange = resolveRequestedRange(
            requestedRange,
            previousWindow: previousWindow,
            totalCount: detail.postStream.stream.count,
            anchorIndex: anchorIndex,
            loadedIndices: loadedIndices,
            anchorChanged: anchorChanged
        )

        return FireTopicDetailWindowState(
            anchorPostNumber: resolvedAnchor,
            requestedRange: resolvedRequestedRange,
            loadedIndices: loadedIndices,
            loadedPostNumbers: loadedPostNumbers,
            exhaustedPostIDs: previousWindow?.exhaustedPostIDs ?? [],
            pendingScrollTarget: pendingScrollTarget
        )
    }

    private func resolveRequestedRange(
        _ requestedRange: Range<Int>?,
        previousWindow: FireTopicDetailWindowState?,
        totalCount: Int,
        anchorIndex: Int?,
        loadedIndices: IndexSet,
        anchorChanged: Bool
    ) -> Range<Int> {
        guard totalCount > 0 else {
            return 0..<0
        }

        if let requestedRange {
            return clampedRequestedRange(
                requestedRange,
                totalCount: totalCount,
                anchorIndex: anchorIndex,
                loadedIndices: loadedIndices
            )
        }

        if let previousWindow, !anchorChanged {
            return clampedRequestedRange(
                previousWindow.requestedRange,
                totalCount: totalCount,
                anchorIndex: anchorIndex,
                loadedIndices: loadedIndices
            )
        }

        return Self.initialRequestedRange(
            totalCount: totalCount,
            anchorIndex: anchorIndex,
            loadedIndices: loadedIndices
        )
    }

    private func clampedRequestedRange(
        _ requestedRange: Range<Int>,
        totalCount: Int,
        anchorIndex: Int?,
        loadedIndices: IndexSet
    ) -> Range<Int> {
        let clamped = requestedRange.clamped(to: 0..<totalCount)
        guard !clamped.isEmpty else {
            return Self.initialRequestedRange(
                totalCount: totalCount,
                anchorIndex: anchorIndex,
                loadedIndices: loadedIndices
            )
        }

        if let anchorIndex, !clamped.contains(anchorIndex) {
            return Self.initialRequestedRange(
                totalCount: totalCount,
                anchorIndex: anchorIndex,
                loadedIndices: loadedIndices
            )
        }

        let lowerBound = min(clamped.lowerBound, loadedIndices.first ?? clamped.lowerBound)
        let upperBound = max(clamped.upperBound, (loadedIndices.last.map { $0 + 1 }) ?? clamped.upperBound)
        return Self.boundedRequestedRange(
            lowerBound: lowerBound,
            upperBound: upperBound,
            totalCount: totalCount,
            anchorIndex: anchorIndex
        )
    }

    private func streamIndex(forPostNumber postNumber: UInt32?, in detail: TopicDetailState) -> Int? {
        guard let postNumber,
              let postID = detail.postStream.posts.first(where: { $0.postNumber == postNumber })?.id else {
            return nil
        }
        return detail.postStream.stream.firstIndex(of: postID)
    }

    nonisolated static func scrollTargetIsExhausted(
        postNumber: UInt32,
        window: FireTopicDetailWindowState,
        orderedPostIDs: [UInt64],
        loadedPostIDs: Set<UInt64>
    ) -> Bool {
        if window.loadedPostNumbers.contains(postNumber) {
            return false
        }

        let hasMissingInWindow = !FireTopicPresentation.missingPostIDs(
            orderedPostIDs: orderedPostIDs,
            in: window.requestedRange,
            loadedPostIDs: loadedPostIDs,
            excluding: window.exhaustedPostIDs
        ).isEmpty
        if hasMissingInWindow {
            return false
        }

        let wholeStreamResolved = FireTopicPresentation.missingPostIDs(
            orderedPostIDs: orderedPostIDs,
            in: 0..<orderedPostIDs.count,
            loadedPostIDs: loadedPostIDs,
            excluding: window.exhaustedPostIDs
        ).isEmpty
        if window.activeAnchorPostNumber == postNumber && !wholeStreamResolved {
            return false
        }

        return true
    }

    nonisolated static func nextRequestedRangeForUnresolvedTarget(
        postNumber: UInt32,
        current: Range<Int>,
        totalCount: Int,
        loadedPostNumbersInCurrentRange: [UInt32]
    ) -> Range<Int>? {
        guard totalCount > 0 else {
            return nil
        }
        guard current.lowerBound > 0 || current.upperBound < totalCount else {
            return nil
        }

        let estimatedIndex = max(0, min(Int(postNumber) - 1, totalCount - 1))
        if !current.contains(estimatedIndex) {
            return boundedRequestedRange(
                lowerBound: estimatedIndex - (topicPostPageSize / 2),
                upperBound: estimatedIndex + (topicPostPageSize / 2) + 1,
                totalCount: totalCount,
                anchorIndex: nil
            )
        }

        let direction: FireTopicDetailSearchDirection
        if let maxLoadedPostNumber = loadedPostNumbersInCurrentRange.max(),
           postNumber > maxLoadedPostNumber {
            direction = .forward
        } else if let minLoadedPostNumber = loadedPostNumbersInCurrentRange.min(),
                  postNumber < minLoadedPostNumber {
            direction = .backward
        } else if totalCount - current.upperBound >= current.lowerBound {
            direction = .forward
        } else {
            direction = .backward
        }

        return nextDirectionalSearchRange(
            current: current,
            totalCount: totalCount,
            direction: direction
        )
    }

    private nonisolated static func nextDirectionalSearchRange(
        current: Range<Int>,
        totalCount: Int,
        direction: FireTopicDetailSearchDirection
    ) -> Range<Int>? {
        guard totalCount > 0 else {
            return nil
        }

        let pageSize = topicPostPageSize
        let maxWindowSize = FireTopicDetailWindowState.maxWindowSize
        let currentCount = current.count

        switch direction {
        case .backward:
            if current.lowerBound > 0 {
                return previousDirectionalSearchRange(
                    current: current,
                    totalCount: totalCount,
                    pageSize: pageSize,
                    maxWindowSize: maxWindowSize,
                    currentCount: currentCount
                )
            }
            guard current.upperBound < totalCount else {
                return nil
            }
            return nextForwardSearchRange(
                current: current,
                totalCount: totalCount,
                pageSize: pageSize,
                maxWindowSize: maxWindowSize,
                currentCount: currentCount
            )
        case .forward:
            if current.upperBound < totalCount {
                return nextForwardSearchRange(
                    current: current,
                    totalCount: totalCount,
                    pageSize: pageSize,
                    maxWindowSize: maxWindowSize,
                    currentCount: currentCount
                )
            }
            guard current.lowerBound > 0 else {
                return nil
            }
            return previousDirectionalSearchRange(
                current: current,
                totalCount: totalCount,
                pageSize: pageSize,
                maxWindowSize: maxWindowSize,
                currentCount: currentCount
            )
        }
    }

    private nonisolated static func previousDirectionalSearchRange(
        current: Range<Int>,
        totalCount: Int,
        pageSize: Int,
        maxWindowSize: Int,
        currentCount: Int
    ) -> Range<Int> {
        if currentCount >= maxWindowSize {
            let lowerBound = max(0, current.lowerBound - pageSize)
            let upperBound = min(totalCount, lowerBound + currentCount)
            return lowerBound..<upperBound
        }
        return boundedRequestedRange(
            lowerBound: current.lowerBound - pageSize,
            upperBound: current.upperBound,
            totalCount: totalCount,
            anchorIndex: nil
        )
    }

    private nonisolated static func nextForwardSearchRange(
        current: Range<Int>,
        totalCount: Int,
        pageSize: Int,
        maxWindowSize: Int,
        currentCount: Int
    ) -> Range<Int> {
        if currentCount >= maxWindowSize {
            let upperBound = min(totalCount, current.upperBound + pageSize)
            let lowerBound = max(0, upperBound - currentCount)
            return lowerBound..<upperBound
        }
        return boundedRequestedRange(
            lowerBound: current.lowerBound,
            upperBound: current.upperBound + pageSize,
            totalCount: totalCount,
            anchorIndex: nil
        )
    }

    nonisolated static func initialRequestedRange(
        totalCount: Int,
        anchorIndex: Int?,
        loadedIndices: IndexSet
    ) -> Range<Int> {
        guard totalCount > 0 else {
            return 0..<0
        }

        let loadedLowerBound = loadedIndices.first ?? anchorIndex ?? 0
        let loadedUpperBound = (loadedIndices.last.map { $0 + 1 }) ?? min(totalCount, loadedLowerBound + 1)
        let desiredLowerBound: Int
        if let anchorIndex {
            desiredLowerBound = anchorIndex - (topicPostPageSize / 2)
        } else {
            desiredLowerBound = min(loadedLowerBound, loadedUpperBound - topicPostPageSize)
        }

        return boundedRequestedRange(
            lowerBound: min(desiredLowerBound, loadedLowerBound),
            upperBound: max(loadedUpperBound, loadedLowerBound + topicPostPageSize),
            totalCount: totalCount,
            anchorIndex: anchorIndex
        )
    }

    nonisolated static func expandedRequestedRange(
        current: Range<Int>,
        totalCount: Int,
        expandBackward: Bool,
        expandForward: Bool,
        anchorIndex: Int?
    ) -> Range<Int> {
        let lowerBound = expandBackward ? current.lowerBound - topicPostPageSize : current.lowerBound
        let upperBound = expandForward ? current.upperBound + topicPostForwardExpansionSize : current.upperBound
        return boundedRequestedRange(
            lowerBound: lowerBound,
            upperBound: upperBound,
            totalCount: totalCount,
            anchorIndex: anchorIndex
        )
    }

    nonisolated static func boundedRequestedRange(
        lowerBound: Int,
        upperBound: Int,
        totalCount: Int,
        anchorIndex: Int?
    ) -> Range<Int> {
        guard totalCount > 0 else {
            return 0..<0
        }

        var lowerBound = max(0, min(lowerBound, totalCount))
        var upperBound = max(lowerBound, min(upperBound, totalCount))
        if lowerBound == upperBound {
            upperBound = min(totalCount, lowerBound + 1)
        }

        if upperBound - lowerBound <= FireTopicDetailWindowState.maxWindowSize {
            return lowerBound..<upperBound
        }

        if let anchorIndex {
            let maxLowerBound = max(0, totalCount - FireTopicDetailWindowState.maxWindowSize)
            let minimumLowerBound = max(0, anchorIndex - FireTopicDetailWindowState.maxWindowSize + 1)
            let maximumLowerBound = min(anchorIndex, maxLowerBound)
            lowerBound = max(minimumLowerBound, min(maximumLowerBound, lowerBound))
            upperBound = min(totalCount, lowerBound + FireTopicDetailWindowState.maxWindowSize)
            lowerBound = max(0, upperBound - FireTopicDetailWindowState.maxWindowSize)
            return lowerBound..<upperBound
        }

        upperBound = min(totalCount, lowerBound + FireTopicDetailWindowState.maxWindowSize)
        lowerBound = max(0, upperBound - FireTopicDetailWindowState.maxWindowSize)
        return lowerBound..<upperBound
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
        if var screen = topicScreens[topicId] {
            if screen.body.post.id == postId {
                screen.body.post = post
            }
            topicScreens[topicId] = screen
        }
        if var responseRows = topicResponseRowsByTopic[topicId],
           let rowIndex = responseRows.firstIndex(where: { $0.post.id == postId }) {
            responseRows[rowIndex].post = post
            topicResponseRowsByTopic[topicId] = responseRows
        }
        _ = cacheTopicDetail(detail, topicId: topicId)
    }

    private func performWithTimeout<T>(
        _ seconds: Double,
        operation: String,
        _ body: @escaping () async throws -> T
    ) async throws -> T {
        let work = Task { try await body() }
        let timer = Task {
            try? await Task.sleep(for: .seconds(seconds))
            work.cancel()
        }
        defer { timer.cancel() }
        do {
            return try await work.value
        } catch {
            if work.isCancelled && !Task.isCancelled {
                appViewModel.topicDetailLogger()?.error(
                    "topic detail fetch timed out operation=\(operation) seconds=\(seconds)"
                )
                throw FireTopicDetailTimeoutError(operation: operation, seconds: seconds)
            }
            throw error
        }
    }
}

struct FireTopicDetailTimeoutError: LocalizedError {
    let operation: String
    let seconds: Double
    var errorDescription: String? {
        "\(operation)超时（\(Int(seconds))s），请稍后重试"
    }
}
