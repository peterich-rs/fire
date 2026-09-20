import Foundation

@MainActor
extension FireTopicDetailStore {
    func submitReply(
        topicId: UInt64,
        raw: String,
        replyToPostNumber: UInt32?
    ) async throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }

        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !submittingReplyTopicIDs.contains(topicId) else {
            return
        }

        setSubmittingReply(true, topicId: topicId)
        defer { setSubmittingReply(false, topicId: topicId) }

        do {
            let sessionStore = try await appViewModel.sessionStoreValue()
            updateTopicErrorMessage(nil, topicId: topicId)
            let createdReply = try await FireAPMManager.shared.withSpan(
                .topicReplySubmit,
                metadata: [
                    "topic_id": String(topicId),
                    "reply_to_post_number": replyToPostNumber.map(String.init) ?? "root"
                ]
            ) {
                try await appViewModel.performWriteWithCloudflareRetry(
                    originURL: topicCloudflareRecoveryURL(topicId: topicId)
                ) {
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
            updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
            throw error
        }
    }

    func createBoost(
        topicId: UInt64,
        postId: UInt64,
        raw: String
    ) async throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }
        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postId) else {
            throw CancellationError()
        }

        setMutatingPost(true, topicId: topicId, postId: postId)
        defer { setMutatingPost(false, topicId: topicId, postId: postId) }

        do {
            let sessionStore = try await appViewModel.sessionStoreValue()
            updateTopicErrorMessage(nil, topicId: topicId)
            let boost = try await appViewModel.performWriteWithCloudflareRetry(
                originURL: topicCloudflareRecoveryURL(topicId: topicId)
            ) {
                try await sessionStore.createBoost(postID: postId, raw: trimmed)
            }
            await appViewModel.syncSessionSnapshotIfAvailable(from: sessionStore)
            applyCreatedBoost(boost, topicId: topicId, postId: postId)
            try? await refreshTopicDetailAfterMutation(topicId: topicId, sessionStore: sessionStore)
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
            updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
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

        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        if mutatingPostIDs.contains(postID) {
            let sessionStore = try await appViewModel.sessionStoreValue()
            return try await sessionStore.fetchPost(postID: postID)
        }

        setMutatingPost(true, topicId: topicID, postId: postID)
        defer { setMutatingPost(false, topicId: topicID, postId: postID) }

        do {
            let sessionStore = try await appViewModel.sessionStoreValue()
            updateTopicErrorMessage(nil, topicId: topicID)
            let updatedPost = try await appViewModel.performWriteWithCloudflareRetry(
                originURL: topicCloudflareRecoveryURL(topicId: topicID)
            ) {
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
            updateTopicErrorMessage(error.localizedDescription, topicId: topicID)
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

        isLoadingPostActionTypes = true
        defer { isLoadingPostActionTypes = false }

        guard let sessionStore = try? await appViewModel.sessionStoreValue() else {
            return
        }

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
        setLoadingPostReplyContext(true, topicId: topicID, postId: post.id)
        setPostReplyContextError(nil, topicId: topicID, postId: post.id)
        defer { setLoadingPostReplyContext(false, topicId: topicID, postId: post.id) }

        guard let sessionStore = try? await appViewModel.sessionStoreValue() else {
            return
        }

        do {
            let recoveryURL = topicCloudflareRecoveryURL(topicId: topicID)
            let replies = try await appViewModel.performWithCloudflareRecovery(
                operation: "加载帖子回复",
                originURL: recoveryURL
            ) {
                try await self.fetchReplyContextReplies(
                    topicID: topicID,
                    post: post,
                    sessionStore: sessionStore
                )
            }
            let replyHistory = try await appViewModel.performWithCloudflareRecovery(
                operation: "加载回复来源",
                originURL: recoveryURL
            ) {
                post.replyToPostNumber != nil
                    ? try await sessionStore.fetchPostReplyHistory(postID: post.id)
                    : []
            }
            postRepliesByPostID[post.id] = replies
            postReplyHistoryByPostID[post.id] = replyHistory

            let refreshedPosts = replies + replyHistory
            if !refreshedPosts.isEmpty {
                if let replyRows = applyReplyContextRowsIfPossible(
                    topicId: topicID,
                    rootPost: post,
                    contextPosts: refreshedPosts
                ),
                   let sourceSnapshot = topicSourceSnapshots[topicID],
                   let treePresentation = topicTreePresentations[topicID] {
                    let detail = rebuildTopicDetail(
                        sourceSnapshot: sourceSnapshot,
                        treePresentation: treePresentation,
                        topicId: topicID
                    )
                    _ = replyRows
                    await buildTopicDetailRenderUpdate(detail: detail, topicId: topicID)
                } else {
                    await applyHydratedTopicPostsIfNeeded(
                        topicId: topicID,
                        posts: refreshedPosts,
                        exhaustedPostIDs: []
                    )
                }
            }
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            setPostReplyContextError(error.localizedDescription, topicId: topicID, postId: post.id)
        }
    }

    func applyReplyContextRowsIfPossible(
        topicId: UInt64,
        rootPost: TopicPostState,
        contextPosts: [TopicPostState]
    ) -> [TopicTreeRowState]? {
        guard var treePresentation = topicTreePresentations[topicId],
              var sourceSnapshot = topicSourceSnapshots[topicId] else {
            return nil
        }

        let existingRows = treePresentation.replyRows
        let mergedRows = Self.mergeReplyContextTreeRows(
            existingRows: existingRows,
            bodyPostNumber: sourceSnapshot.body.post.postNumber,
            rootPost: rootPost,
            contextPosts: contextPosts
        )
        guard mergedRows != existingRows else {
            return nil
        }

        treePresentation.replyRows = mergedRows
        sourceSnapshot.loadedPosts = FireTopicPresentation.mergeTopicPosts(
            existing: sourceSnapshot.loadedPosts,
            incoming: contextPosts,
            orderedPostIDs: sourceSnapshot.rawStreamIds
        )
        topicTreePresentations[topicId] = treePresentation
        topicSourceSnapshots[topicId] = sourceSnapshot
        return mergedRows
    }

    func fetchReplyContextReplies(
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
            return []
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

    func orderedUniquePostIDs(_ ids: [UInt64]) -> [UInt64] {
        var seen: Set<UInt64> = []
        var result: [UInt64] = []
        for id in ids where id > 0 && !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    func votePoll(
        topicId: UInt64,
        postId: UInt64,
        pollName: String,
        options: [String],
        recoveryOriginURL: URL?
    ) async throws -> PollState {
        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postId) else {
            throw FireTopicInteractionError.unavailable
        }

        setMutatingPost(true, topicId: topicId, postId: postId)
        defer { setMutatingPost(false, topicId: topicId, postId: postId) }

        let sessionStore = try await appViewModel.sessionStoreValue()
        updateTopicErrorMessage(nil, topicId: topicId)
        do {
            let poll = try await appViewModel.performWriteWithCloudflareRetry(originURL: recoveryOriginURL) {
                try await sessionStore.votePoll(
                    postID: postId,
                    pollName: pollName,
                    options: options
                )
            }
            await appViewModel.syncSessionSnapshotIfAvailable(from: sessionStore)
            try? await refreshTopicDetailAfterMutation(topicId: topicId, sessionStore: sessionStore)
            return poll
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
            updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
            throw error
        }
    }

    func unvotePoll(
        topicId: UInt64,
        postId: UInt64,
        pollName: String,
        recoveryOriginURL: URL?
    ) async throws -> PollState {
        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postId) else {
            throw FireTopicInteractionError.unavailable
        }

        setMutatingPost(true, topicId: topicId, postId: postId)
        defer { setMutatingPost(false, topicId: topicId, postId: postId) }

        let sessionStore = try await appViewModel.sessionStoreValue()
        updateTopicErrorMessage(nil, topicId: topicId)
        do {
            let poll = try await appViewModel.performWriteWithCloudflareRetry(originURL: recoveryOriginURL) {
                try await sessionStore.unvotePoll(postID: postId, pollName: pollName)
            }
            await appViewModel.syncSessionSnapshotIfAvailable(from: sessionStore)
            try? await refreshTopicDetailAfterMutation(topicId: topicId, sessionStore: sessionStore)
            return poll
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
            updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
            throw error
        }
    }

    func performPostManagementMutation(
        topicID: UInt64,
        postID: UInt64,
        operation: @escaping (FireSessionStore) async throws -> Void
    ) async throws {
        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postID) else {
            return
        }

        setMutatingPost(true, topicId: topicID, postId: postID)
        defer { setMutatingPost(false, topicId: topicID, postId: postID) }

        do {
            let sessionStore = try await appViewModel.sessionStoreValue()
            updateTopicErrorMessage(nil, topicId: topicID)
            try await appViewModel.performWriteWithCloudflareRetry(
                originURL: topicCloudflareRecoveryURL(topicId: topicID)
            ) {
                try await operation(sessionStore)
            }
            await appViewModel.syncSessionSnapshotIfAvailable(from: sessionStore)
            try? await refreshTopicDetailAfterMutation(topicId: topicID, sessionStore: sessionStore)
            await appViewModel.refreshHomeFeedIfPossible(force: false)
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
            updateTopicErrorMessage(error.localizedDescription, topicId: topicID)
            throw error
        }
    }

    func refreshTopicDetailAfterMutation(topicId: UInt64) async {
        guard let sessionStore = try? await appViewModel.sessionStoreValue() else {
            return
        }
        try? await refreshTopicDetailAfterMutation(topicId: topicId, sessionStore: sessionStore)
    }

    func refreshTopicDetailAfterMutation(
        topicId: UInt64,
        sessionStore: FireSessionStore
    ) async throws {
        let payload = try await fetchTopicDetailPagePayload(
            topicId: topicId,
            targetPostNumber: nil,
            trackVisit: false,
            forceLoad: false,
            sessionStore: sessionStore,
            tracksInitialLoadAPM: false
        )
        await applyTopicDetailPagePayload(
            payload,
            detailNotice: nil,
            topicId: topicId
        )
    }

    func refreshTopicDetailPageFromNetwork(
        topicId: UInt64,
        targetPostNumber: UInt32?,
        sessionStore: FireSessionStore
    ) async throws -> FireTopicDetailPagePayload {
        try await fetchTopicDetailPagePayload(
            topicId: topicId,
            targetPostNumber: targetPostNumber,
            trackVisit: false,
            forceLoad: false,
            sessionStore: sessionStore,
            tracksInitialLoadAPM: false
        )
    }

    func applyCreatedBoost(
        _ boost: TopicPostBoostState,
        topicId: UInt64,
        postId: UInt64
    ) {
        guard var detail = topicDetails[topicId] else { return }
        guard let postIndex = detail.postStream.posts.firstIndex(where: { $0.id == postId }) else {
            return
        }

        var post = detail.postStream.posts[postIndex]
        if !post.boosts.contains(where: { $0.id == boost.id }) {
            post.boosts.append(boost)
        }
        // Own boost consumes the create permission until a refresh restores it.
        post.canBoost = false
        detail.postStream.posts[postIndex] = post

        if var sourceSnapshot = topicSourceSnapshots[topicId] {
            if sourceSnapshot.body.post.id == postId {
                sourceSnapshot.body.post = post
            }
            if let loadedIndex = sourceSnapshot.loadedPosts.firstIndex(where: { $0.id == postId }) {
                sourceSnapshot.loadedPosts[loadedIndex] = post
            }
            topicSourceSnapshots[topicId] = sourceSnapshot
        }

        _ = cacheTopicDetail(detail, topicId: topicId)
        bumpTopicCollectionRevision(topicId: topicId)
    }

    func applyCreatedReply(_ reply: TopicPostState, topicId: UInt64) {
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
            detail.replyCount = max(
                detail.replyCount + 1,
                detail.postsCount > 0 ? detail.postsCount - 1 : 0
            )
        }
        detail.highestPostNumber = max(detail.highestPostNumber, reply.postNumber)
        detail.lastReadPostNumber = max(detail.lastReadPostNumber ?? 0, reply.postNumber)

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
        appViewModel.patchHomeTopicCounts(from: detail)
    }
}
