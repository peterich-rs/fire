import Foundation

@MainActor
final class FireTopicDetailStore: ObservableObject {
    private static let topicPostPageSize = 30
    private static let topicPostPrefetchThreshold = 6

    @Published private(set) var topicDetails: [UInt64: TopicDetailState] = [:]
    @Published private(set) var topicPresenceUsersByTopic: [UInt64: [TopicPresenceUserState]] = [:]
    @Published private(set) var loadingMoreTopicPostIDs: Set<UInt64> = []
    @Published private(set) var loadingTopicIDs: Set<UInt64> = []
    @Published private(set) var submittingReplyTopicIDs: Set<UInt64> = []
    @Published private(set) var mutatingPostIDs: Set<UInt64> = []
    @Published var errorMessage: String?

    private let appViewModel: FireAppViewModel
    private var pendingTopicDetailRefreshTasks: [UInt64: Task<Void, Never>] = [:]
    private var topicPresenceHeartbeatTasks: [UInt64: Task<Void, Never>] = [:]
    private var topicPostPreloadTasks: [UInt64: Task<Void, Never>] = [:]
    private var topicPostPaginationStates: [UInt64: FireTopicPostPaginationState] = [:]
    private var topicDetailTargetPostNumbers: [UInt64: UInt32] = [:]
    private var activeTopicDetailOwnerTokens: [UInt64: Set<String>] = [:]

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    func applySession(_ session: SessionState) {
        guard session.readiness.canReadAuthenticatedApi else {
            reset()
            return
        }
    }

    func handleMessageBusStopped() {
        pendingTopicDetailRefreshTasks.values.forEach { $0.cancel() }
        pendingTopicDetailRefreshTasks = [:]
        topicPresenceHeartbeatTasks.values.forEach { $0.cancel() }
        topicPresenceHeartbeatTasks = [:]
        topicPresenceUsersByTopic = [:]
    }

    func reset() {
        pendingTopicDetailRefreshTasks.values.forEach { $0.cancel() }
        pendingTopicDetailRefreshTasks = [:]
        topicPresenceHeartbeatTasks.values.forEach { $0.cancel() }
        topicPresenceHeartbeatTasks = [:]
        topicPostPreloadTasks.values.forEach { $0.cancel() }
        topicPostPreloadTasks = [:]
        activeTopicDetailOwnerTokens = [:]
        topicDetailTargetPostNumbers = [:]
        topicPostPaginationStates = [:]
        topicDetails = [:]
        topicPresenceUsersByTopic = [:]
        loadingMoreTopicPostIDs = []
        loadingTopicIDs = []
        submittingReplyTopicIDs = []
        mutatingPostIDs = []
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
        if topicDetails[topicId] != nil && !force {
            return
        }
        if !appViewModel.session.readiness.canReadAuthenticatedApi {
            reset()
            return
        }

        if let targetPostNumber {
            topicDetailTargetPostNumbers[topicId] = targetPostNumber
        }

        let hadCachedDetail = topicDetails[topicId] != nil
        appViewModel.topicDetailLogger()?.debug(
            "loading topic detail topic_id=\(topicId) force=\(force) had_cache=\(hadCachedDetail) target_post=\(String(describing: targetPostNumber))"
        )
        loadingTopicIDs.insert(topicId)
        defer { loadingTopicIDs.remove(topicId) }

        do {
            let sessionStore = try await appViewModel.sessionStoreValue()
            errorMessage = nil
            let detail = try await FireAPMManager.shared.withSpan(
                .topicDetailInitialLoad,
                metadata: ["topic_id": String(topicId)]
            ) {
                try await appViewModel.performWithCloudflareRecovery(
                    operation: "加载话题详情"
                ) {
                    try await sessionStore.fetchTopicDetailInitial(
                        query: TopicDetailQueryState(
                            topicId: topicId,
                            postNumber: targetPostNumber,
                            trackVisit: true,
                            filter: nil,
                            usernameFilters: nil,
                            filterTopLevelReplies: false
                        )
                    )
                }
            }
            applyTopicDetail(detail, topicId: topicId)
            appViewModel.topicDetailLogger()?.debug(
                "loaded topic detail topic_id=\(topicId) loaded_posts=\(detail.postStream.posts.count) stream_posts=\(detail.postStream.stream.count)"
            )
        } catch {
            appViewModel.topicDetailLogger()?.error(
                "topic detail load failed topic_id=\(topicId) error=\(error.localizedDescription)"
            )
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
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
        guard appViewModel.session.readiness.canWriteAuthenticatedApi else { return }
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
        guard appViewModel.session.readiness.canWriteAuthenticatedApi else {
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
        guard appViewModel.session.readiness.canWriteAuthenticatedApi else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postID) else {
            return try await sessionStore.fetchPost(postID: postID)
        }

        mutatingPostIDs.insert(postID)
        defer { mutatingPostIDs.remove(postID) }

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

    func setPostLiked(
        topicId: UInt64,
        postId: UInt64,
        liked: Bool
    ) async throws {
        let sessionStore = try await appViewModel.sessionStoreValue()
        guard appViewModel.session.readiness.canWriteAuthenticatedApi else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postId) else {
            return
        }

        mutatingPostIDs.insert(postId)
        defer { mutatingPostIDs.remove(postId) }

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
        guard appViewModel.session.readiness.canWriteAuthenticatedApi else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postId) else {
            return
        }

        mutatingPostIDs.insert(postId)
        defer { mutatingPostIDs.remove(postId) }

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
        let detail = try await appViewModel.performWithCloudflareRecovery(
            operation: "刷新话题详情"
        ) {
            try await sessionStore.fetchTopicDetailInitial(
                query: TopicDetailQueryState(
                    topicId: topicId,
                    postNumber: nil,
                    trackVisit: false,
                    filter: nil,
                    usernameFilters: nil,
                    filterTopLevelReplies: false
                )
            )
        }
        applyTopicDetail(detail, topicId: topicId)
    }

    private func scheduleTopicDetailRefresh(topicId: UInt64) {
        pendingTopicDetailRefreshTasks[topicId]?.cancel()
        pendingTopicDetailRefreshTasks[topicId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            guard let self, let store = self.appViewModel.currentSessionStore() else { return }
            guard self.topicDetails[topicId] != nil else { return }
            let anchorPostNumber = self.topicDetailTargetPostNumbers[topicId]
            do {
                let detail = try await self.appViewModel.performWithCloudflareRecovery(
                    operation: "刷新话题详情"
                ) {
                    try await store.fetchTopicDetailInitial(
                        query: TopicDetailQueryState(
                            topicId: topicId,
                            postNumber: anchorPostNumber,
                            trackVisit: false,
                            filter: nil,
                            usernameFilters: nil,
                            filterTopLevelReplies: false
                        )
                    )
                }
                self.applyTopicDetail(detail, topicId: topicId)
            } catch {
                _ = await self.appViewModel.handleRecoverableSessionErrorIfNeeded(error)
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

        appViewModel.topicDetailLogger()?.notice(
            "evicted topic detail state topic_id=\(topicId) reason=\(reason)"
        )
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
            max(
                previousWasFullyLoaded ? detail.postStream.stream.count : previousTargetLoadedCount,
                loadedWindowCount
            ),
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
        guard let sessionStore = appViewModel.currentSessionStore() else {
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
                errorMessage = error.localizedDescription
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
}
