import Foundation

@MainActor
final class FireTopicDetailStore: ObservableObject {
    nonisolated private static let topicPostPageSize = 30
    nonisolated private static let topicPostPrefetchThreshold = 6

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
    private var topicWindowStates: [UInt64: FireTopicDetailWindowState] = [:]
    private var topicDetailTargetPostNumbers: [UInt64: UInt32] = [:]
    private var activeTopicDetailOwnerTokens: [UInt64: Set<String>] = [:]

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
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
        activeTopicDetailOwnerTokens = [:]
        topicDetailTargetPostNumbers = [:]
        topicWindowStates = [:]
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
        if !appViewModel.session.readiness.canReadAuthenticatedApi {
            applySession(appViewModel.session)
            return
        }

        if let targetPostNumber {
            topicDetailTargetPostNumbers[topicId] = targetPostNumber
        }

        let anchorPostNumber = activeAnchorPostNumber(topicId: topicId)

        if !force,
           let cachedDetail = topicDetails[topicId],
           !needsAnchoredReload(
               detail: cachedDetail,
               anchorPostNumber: anchorPostNumber,
               window: topicWindowStates[topicId]
           ) {
            errorMessage = nil
            refreshTopicWindowState(
                topicId: topicId,
                detail: cachedDetail,
                anchorPostNumber: anchorPostNumber,
                requestedRange: topicWindowStates[topicId]?.requestedRange,
                pendingScrollTarget: targetPostNumber ?? topicWindowStates[topicId]?.pendingScrollTarget
            )
            if hasMissingPostsInRequestedRange(topicId: topicId) {
                await hydrateTopicPostsToTargetIfNeeded(topicId: topicId)
            }
            return
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
            let detail = try await performWithTimeout(30, operation: "加载话题详情") { [appViewModel] in
                try await FireAPMManager.shared.withSpan(
                    .topicDetailInitialLoad,
                    metadata: ["topic_id": String(topicId)]
                ) {
                    try await appViewModel.performWithCloudflareRecovery(
                        operation: "加载话题详情"
                    ) {
                        try await sessionStore.fetchTopicDetailInitial(
                            query: TopicDetailQueryState(
                                topicId: topicId,
                                postNumber: anchorPostNumber,
                                trackVisit: true,
                                filter: nil,
                                usernameFilters: nil,
                                filterTopLevelReplies: false
                            )
                        )
                    }
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
                if topicDetails[topicId] == nil {
                    errorMessage = error.localizedDescription
                }
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func clearTopicDetailAnchor(topicId: UInt64) {
        clearTransientAnchor(topicId: topicId)
    }

    func pendingScrollTarget(topicId: UInt64) -> UInt32? {
        topicWindowStates[topicId]?.pendingScrollTarget
    }

    func isScrollTargetExhausted(topicId: UInt64, postNumber: UInt32) -> Bool {
        guard let window = topicWindowStates[topicId],
              let detail = topicDetails[topicId] else { return false }
        if window.loadedPostNumbers.contains(postNumber) {
            return false
        }
        let loadedPostIDs = Set(detail.postStream.posts.map(\.id))
        let hasMissingInWindow = !FireTopicPresentation.missingPostIDs(
            orderedPostIDs: detail.postStream.stream,
            in: window.requestedRange,
            loadedPostIDs: loadedPostIDs,
            excluding: window.exhaustedPostIDs
        ).isEmpty
        return !hasMissingInWindow
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
        guard let detail = topicDetails[topicId],
              let window = topicWindowStates[topicId] else {
            return false
        }
        let unresolvedPostIDs = FireTopicPresentation.missingPostIDs(
            orderedPostIDs: detail.postStream.stream,
            in: window.requestedRange,
            loadedPostIDs: Set(detail.postStream.posts.map(\.id)),
            excluding: window.exhaustedPostIDs
        )
        return !unresolvedPostIDs.isEmpty
            || window.requestedRange.lowerBound > 0
            || window.requestedRange.upperBound < detail.postStream.stream.count
    }

    func preloadTopicPostsIfNeeded(
        topicId: UInt64,
        visiblePostNumbers: Set<UInt32>
    ) {
        guard hasMoreTopicPosts(topicId: topicId) else { return }
        guard !loadingMoreTopicPostIDs.contains(topicId) else { return }
        guard topicPostPreloadTasks[topicId] == nil else { return }

        topicPostPreloadTasks[topicId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.topicPostPreloadTasks[topicId] = nil }
            await self.expandRequestedRangeIfNeeded(
                topicId: topicId,
                visiblePostNumbers: visiblePostNumbers
            )
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
        guard appViewModel.canStartAuthenticatedMutation else {
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
        guard appViewModel.canStartAuthenticatedMutation else {
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
        let detail = try await performWithTimeout(30, operation: "刷新话题详情") { [appViewModel] in
            try await appViewModel.performWithCloudflareRecovery(
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
            let anchorPostNumber = self.activeAnchorPostNumber(topicId: topicId)
            do {
                let detail = try await self.performWithTimeout(30, operation: "刷新话题详情") { [appViewModel = self.appViewModel] in
                    try await appViewModel.performWithCloudflareRecovery(
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
                }
                self.applyTopicDetail(detail, topicId: topicId)
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
        let removedDetail = topicDetails.removeValue(forKey: topicId) != nil
        let removedWindow = topicWindowStates.removeValue(forKey: topicId) != nil
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
            || removedWindow
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
        var detail = incomingDetail
        if let previousDetail = topicDetails[topicId] {
            detail.postStream.posts = FireTopicPresentation.mergeTopicPosts(
                existing: previousDetail.postStream.posts,
                incoming: detail.postStream.posts,
                orderedPostIDs: detail.postStream.stream
            )
        }
        detail = FireTopicPresentation.recomposedDetail(detail)
        topicDetails[topicId] = detail

        refreshTopicWindowState(
            topicId: topicId,
            detail: detail,
            anchorPostNumber: activeAnchorPostNumber(topicId: topicId),
            requestedRange: topicWindowStates[topicId]?.requestedRange,
            pendingScrollTarget: topicWindowStates[topicId]?.pendingScrollTarget
                ?? topicDetailTargetPostNumbers[topicId]
        )

        if hasMissingPostsInRequestedRange(topicId: topicId) {
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

        let previousStreamCount = detail.postStream.stream.count
        detail = FireTopicPresentation.recomposedDetail(detail)
        topicDetails[topicId] = detail

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

        loadingMoreTopicPostIDs.insert(topicId)
        defer { loadingMoreTopicPostIDs.remove(topicId) }

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
        let recomposed = FireTopicPresentation.recomposedDetail(currentDetail)
        topicDetails[topicId] = recomposed

        refreshTopicWindowState(
            topicId: topicId,
            detail: recomposed,
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
        let loadedPostNumbers = Set(detail.postStream.posts.map(\.postNumber))
        let loadedPostIDs = Set(detail.postStream.posts.map(\.id))
        var loadedIndices = IndexSet()
        for (index, postID) in detail.postStream.stream.enumerated() {
            if loadedPostIDs.contains(postID) {
                loadedIndices.insert(index)
            }
        }

        let previousWindow = topicWindowStates[topicId]
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

        topicWindowStates[topicId] = FireTopicDetailWindowState(
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
        let upperBound = expandForward ? current.upperBound + topicPostPageSize : current.upperBound
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
        topicDetails[topicId] = FireTopicPresentation.recomposedDetail(detail)
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
