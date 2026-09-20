import Foundation

@MainActor
extension FireTopicDetailStore {
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
            let lastMessageId = topicSourceSnapshots[topicId]?.header.messageBusLastId
                ?? topicDetails[topicId]?.messageBusLastId
            try await store.subscribeTopicDetailChannel(
                topicId: topicId,
                ownerToken: ownerToken,
                lastMessageId: lastMessageId
            )
            try await store.subscribeTopicReactionChannel(topicId: topicId, ownerToken: ownerToken)
            try await store.subscribeTopicPollsChannel(topicId: topicId, ownerToken: ownerToken)
        } catch {
            try? await store.unsubscribeTopicPollsChannel(topicId: topicId, ownerToken: ownerToken)
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
            setTopicPresenceUsers([], topicId: topicId)
        }

        defer {
            Task {
                await self.endTopicReplyPresence(topicId: topicId)
                self.setTopicPresenceUsers([], topicId: topicId)
                try? await store.unsubscribeTopicReplyPresenceChannel(topicId: topicId, ownerToken: ownerToken)
                try? await store.unsubscribeTopicPollsChannel(topicId: topicId, ownerToken: ownerToken)
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

    func setTopicDetailScrollInteractionActive(
        _ isActive: Bool,
        topicId: UInt64,
        drainDeferredRefresh: Bool = true
    ) {
        let previous = topicScrollInteractionStates[topicId] ?? false
        if isActive {
            topicScrollInteractionStates[topicId] = true
        } else {
            topicScrollInteractionStates.removeValue(forKey: topicId)
        }
        guard previous != isActive, !isActive, drainDeferredRefresh else { return }

        if let deferredPayload = deferredTopicDetailRefreshPayloads.removeValue(forKey: topicId) {
            deferredTopicDetailRefreshTopicIDs.remove(topicId)
            Task { @MainActor [weak self] in
                await self?.applyTopicDetailPagePayload(
                    deferredPayload,
                    detailNotice: nil,
                    topicId: topicId
                )
            }
            return
        }

        guard deferredTopicDetailRefreshTopicIDs.remove(topicId) != nil,
              let store = appViewModel.currentSessionStore(),
              topicDetails[topicId] != nil else {
            return
        }

        Task { @MainActor [weak self] in
            await self?.refreshTopicDetailFromMessageBus(topicId: topicId, sessionStore: store)
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

    func scheduleTopicDetailRefresh(topicId: UInt64) {
        pendingTopicDetailRefreshTasks[topicId]?.cancel()
        pendingTopicDetailRefreshTasks[topicId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            guard let self, let store = self.appViewModel.currentSessionStore() else { return }
            await self.refreshTopicDetailFromMessageBus(topicId: topicId, sessionStore: store)
        }
    }

    func refreshTopicDetailFromMessageBus(
        topicId: UInt64,
        sessionStore: FireSessionStore
    ) async {
        guard topicDetails[topicId] != nil else { return }
        if topicScrollInteractionStates[topicId] == true {
            deferredTopicDetailRefreshTopicIDs.insert(topicId)
            return
        }

        do {
            let payload = try await refreshTopicDetailPageFromNetwork(
                topicId: topicId,
                targetPostNumber: nil,
                sessionStore: sessionStore
            )
            guard topicDetails[topicId] != nil else { return }
            if topicScrollInteractionStates[topicId] == true {
                deferredTopicDetailRefreshPayloads[topicId] = payload
                deferredTopicDetailRefreshTopicIDs.insert(topicId)
                return
            }
            deferredTopicDetailRefreshTopicIDs.remove(topicId)
            deferredTopicDetailRefreshPayloads.removeValue(forKey: topicId)
            await applyTopicDetailPagePayload(
                payload,
                detailNotice: nil,
                topicId: topicId
            )
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                appViewModel.topicDetailLogger()?.notice(
                    "recoverable session error swallowed during topic detail refresh topic_id=\(topicId)"
                )
                return
            }
            appViewModel.topicDetailLogger()?.error(
                "topic detail background refresh failed topic_id=\(topicId) error=\(error.localizedDescription)"
            )
        }
    }

    func refreshTopicPresenceState(topicId: UInt64) {
        guard let store = appViewModel.currentSessionStore() else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let presence = try? await store.topicReplyPresenceState(topicId: topicId) else {
                return
            }
            self.applyTopicPresenceState(presence)
        }
    }

    func applyTopicPresenceState(_ state: TopicPresenceState) {
        let currentUserID = appViewModel.session.bootstrap.currentUserId
        let filteredUsers = state.users.filter { user in
            guard let currentUserID else { return true }
            return user.id != currentUserID
        }
        setTopicPresenceUsers(filteredUsers, topicId: state.topicId)
    }

    func retainedTopicDetailIDs(visibleTopicIDs: Set<UInt64>) -> Set<UInt64> {
        let activeTopicIDs = activeTopicDetailOwnerTokens.compactMap { topicId, owners in
            owners.isEmpty ? nil : topicId
        }
        return visibleTopicIDs.union(activeTopicIDs)
    }

    func pruneInactiveTopicDetailState(
        retaining retainedTopicIDs: Set<UInt64>,
        visibleTopicIDs: Set<UInt64>
    ) {
        let trackedTopicIDs = Set(topicDetails.keys)
            .union(topicWindowStates.keys)
            .union(topicPresenceUsersByTopic.keys)
            .union(errorMessagesByTopicID.keys)
            .union(topicAiSummaries.keys)
            .union(loadingTopicAiSummaryIDs)
            .union(unavailableTopicAiSummaryIDs)
            .union(topicAiSummaryErrorsByTopicID.keys)
            .union(topicAiSummaryTasks.keys)
            .union(topicChromeRevisions.keys)
            .union(topicSidecarRevisions.keys)
            .union(topicInteractionRevisions.keys)
            .union(topicScrollInteractionStates.keys)
            .union(deferredTopicDetailRefreshTopicIDs)
            .union(deferredTopicDetailRefreshPayloads.keys)
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

    func activeAnchorPostNumber(topicId: UInt64) -> UInt32? {
        topicWindowStates[topicId]?.activeAnchorPostNumber
            ?? topicDetailTargetPostNumbers[topicId]
    }

    func clearTransientAnchor(topicId: UInt64) {
        setPendingScrollTarget(nil, topicId: topicId)
        if let window = topicWindowStates[topicId] {
            topicWindowStates[topicId] = window.clearingTransientAnchor()
        }
    }

    func evictTopicDetailState(topicId: UInt64, reason: String) {
        topicSourceSnapshots.removeValue(forKey: topicId)
        topicDetailNoticesByTopic.removeValue(forKey: topicId)
        topicRecoverySlugsByTopic.removeValue(forKey: topicId)
        topicTreePresentations.removeValue(forKey: topicId)
        topicSourceCursorsByTopic.removeValue(forKey: topicId)
        topicPostLookups.removeValue(forKey: topicId)
        pendingVisiblePostNumbersByTopic.removeValue(forKey: topicId)
        topicScrollInteractionStates.removeValue(forKey: topicId)
        deferredTopicDetailRefreshTopicIDs.remove(topicId)
        deferredTopicDetailRefreshPayloads.removeValue(forKey: topicId)
        topicDetailFeedContentTokens.removeValue(forKey: topicId)
        topicDetailChromeContentTokens.removeValue(forKey: topicId)
        let removedDetail = topicDetails.removeValue(forKey: topicId) != nil
        let removedRenderState = topicRenderStates.removeValue(forKey: topicId) != nil
        topicRenderCaches.removeValue(forKey: topicId)
        topicRenderGenerations.removeValue(forKey: topicId)
        let removedWindow = topicWindowStates.removeValue(forKey: topicId) != nil
        let removedPresence = topicPresenceUsersByTopic.removeValue(forKey: topicId) != nil
        let removedError = errorMessagesByTopicID.removeValue(forKey: topicId) != nil
        let removedAiSummary = topicAiSummaries.removeValue(forKey: topicId) != nil
        let removedAiSummaryUnavailable = unavailableTopicAiSummaryIDs.remove(topicId) != nil
        let removedAiSummaryError = topicAiSummaryErrorsByTopicID.removeValue(forKey: topicId) != nil
        topicCollectionRevisions.removeValue(forKey: topicId)
        topicChromeRevisions.removeValue(forKey: topicId)
        topicSidecarRevisions.removeValue(forKey: topicId)
        topicInteractionRevisions.removeValue(forKey: topicId)
        let removedLoadingTopic = loadingTopicIDs.remove(topicId) != nil
        let removedLoadingMore = loadingMoreTopicPostIDs.remove(topicId) != nil
        let removedLoadMoreError = loadMoreTopicPostErrorsByTopicID.removeValue(forKey: topicId) != nil
        let removedLoadingAiSummary = loadingTopicAiSummaryIDs.remove(topicId) != nil
        let refreshTask = pendingTopicDetailRefreshTasks.removeValue(forKey: topicId)
        let presenceTask = topicPresenceHeartbeatTasks.removeValue(forKey: topicId)
        let preloadTask = topicPostPreloadTasks.removeValue(forKey: topicId)
        let visibleRangeTask = topicVisibleRangeTasks.removeValue(forKey: topicId)
        let renderTask = topicRenderTasks.removeValue(forKey: topicId)
        let aiSummaryTask = topicAiSummaryTasks.removeValue(forKey: topicId)
        refreshTask?.cancel()
        presenceTask?.cancel()
        preloadTask?.cancel()
        visibleRangeTask?.cancel()
        renderTask?.cancel()
        aiSummaryTask?.cancel()

        guard removedDetail
            || removedRenderState
            || removedWindow
            || removedPresence
            || removedError
            || removedAiSummary
            || removedAiSummaryUnavailable
            || removedAiSummaryError
            || removedLoadingTopic
            || removedLoadingMore
            || removedLoadMoreError
            || removedLoadingAiSummary
            || refreshTask != nil
            || presenceTask != nil
            || preloadTask != nil
            || visibleRangeTask != nil
            || renderTask != nil
            || aiSummaryTask != nil
        else {
            return
        }

        appViewModel.topicDetailLogger()?.notice(
            "evicted topic detail state topic_id=\(topicId) reason=\(reason)"
        )
    }
}
