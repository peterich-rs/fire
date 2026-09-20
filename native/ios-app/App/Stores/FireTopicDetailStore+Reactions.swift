import Foundation

@MainActor
extension FireTopicDetailStore {
    func setPostLiked(
        topicId: UInt64,
        postId: UInt64,
        liked: Bool
    ) async throws {
        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postId) else {
            // Another reaction for this post is already in-flight.
            throw CancellationError()
        }

        // Optimistic UI first — network settles in the background; revert on failure.
        let rollback = captureReactionSnapshot(topicId: topicId, postId: postId)
        applyOptimisticReactionChange(
            topicId: topicId,
            postId: postId,
            desiredReactionID: liked ? "heart" : nil
        )

        setMutatingPost(true, topicId: topicId, postId: postId)
        defer { setMutatingPost(false, topicId: topicId, postId: postId) }

        do {
            let sessionStore = try await appViewModel.sessionStoreValue()
            updateTopicErrorMessage(nil, topicId: topicId)
            let update = try await appViewModel.performWriteWithCloudflareRetry(
                originURL: topicCloudflareRecoveryURL(topicId: topicId)
            ) {
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
            if let rollback {
                restoreReactionSnapshot(rollback, topicId: topicId, postId: postId)
            }
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
            updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
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

        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postId) else {
            throw CancellationError()
        }

        let currentID = topicDetails[topicId]?
            .postStream.posts
            .first(where: { $0.id == postId })?
            .currentUserReaction?.id
        let desiredID = currentID == trimmedReactionID ? nil : trimmedReactionID

        // Optimistic UI first — network settles in the background; revert on failure.
        let rollback = captureReactionSnapshot(topicId: topicId, postId: postId)
        applyOptimisticReactionChange(
            topicId: topicId,
            postId: postId,
            desiredReactionID: desiredID
        )

        setMutatingPost(true, topicId: topicId, postId: postId)
        defer { setMutatingPost(false, topicId: topicId, postId: postId) }

        do {
            let sessionStore = try await appViewModel.sessionStoreValue()
            updateTopicErrorMessage(nil, topicId: topicId)
            let update = try await appViewModel.performWriteWithCloudflareRetry(
                originURL: topicCloudflareRecoveryURL(topicId: topicId)
            ) {
                try await sessionStore.togglePostReaction(
                    postID: postId,
                    reactionID: trimmedReactionID
                )
            }
            applyPostReactionUpdate(topicId: topicId, postId: postId, update: update)
        } catch {
            if let rollback {
                restoreReactionSnapshot(rollback, topicId: topicId, postId: postId)
            }
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
            updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
            throw error
        }
    }

    func captureReactionSnapshot(
        topicId: UInt64,
        postId: UInt64
    ) -> ReactionSnapshot? {
        guard let post = topicDetails[topicId]?.postStream.posts.first(where: { $0.id == postId }) else {
            return nil
        }
        return ReactionSnapshot(
            reactions: post.reactions,
            currentUserReaction: post.currentUserReaction,
            likeCount: post.likeCount
        )
    }

    func restoreReactionSnapshot(
        _ snapshot: ReactionSnapshot,
        topicId: UInt64,
        postId: UInt64
    ) {
        applyPostReactionUpdate(
            topicId: topicId,
            postId: postId,
            update: PostReactionUpdateState(
                reactions: snapshot.reactions,
                currentUserReaction: snapshot.currentUserReaction
            ),
            likeCountOverride: snapshot.likeCount
        )
    }

    /// Immediately mirrors the desired reaction in local state so chips feel instant.
    func applyOptimisticReactionChange(
        topicId: UInt64,
        postId: UInt64,
        desiredReactionID: String?
    ) {
        guard let post = topicDetails[topicId]?.postStream.posts.first(where: { $0.id == postId }) else {
            return
        }
        let currentID = post.currentUserReaction?.id
        guard currentID != desiredReactionID else { return }

        var reactions = post.reactions
        func adjustCount(for reactionID: String, delta: Int) {
            if let index = reactions.firstIndex(where: { $0.id == reactionID }) {
                let next = max(0, Int(reactions[index].count) + delta)
                if next == 0 {
                    reactions.remove(at: index)
                } else {
                    reactions[index] = TopicReactionState(
                        id: reactions[index].id,
                        kind: reactions[index].kind,
                        count: UInt32(next),
                        canUndo: reactions[index].canUndo
                    )
                }
            } else if delta > 0 {
                reactions.append(
                    TopicReactionState(
                        id: reactionID,
                        kind: nil,
                        count: UInt32(delta),
                        canUndo: true
                    )
                )
            }
        }

        if let currentID {
            adjustCount(for: currentID, delta: -1)
        }
        if let desiredReactionID {
            adjustCount(for: desiredReactionID, delta: 1)
        }

        let currentUserReaction = desiredReactionID.map {
            TopicReactionState(id: $0, kind: nil, count: 1, canUndo: true)
        }
        let heartCount = reactions.first(where: { $0.id == "heart" })?.count ?? 0
        applyPostReactionUpdate(
            topicId: topicId,
            postId: postId,
            update: PostReactionUpdateState(
                reactions: reactions,
                currentUserReaction: currentUserReaction
            ),
            likeCountOverride: heartCount
        )
    }

    func applyPostReactionUpdate(
        topicId: UInt64,
        postId: UInt64,
        update: PostReactionUpdateState,
        likeCountOverride: UInt32? = nil
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

        if let likeCountOverride {
            post.likeCount = likeCountOverride
        } else if let updatedHeartCount {
            post.likeCount = updatedHeartCount
        } else if previousHeartCount != nil || post.currentUserReaction?.id == "heart" {
            post.likeCount = 0
        }

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
        topicDetails[topicId] = detail
        topicPostLookups[topicId] = FireTopicPresentation.topicPostsByID(detail.postStream.posts)
        topicDetailFeedContentTokens[topicId] = FireTopicDetailFeedContentToken(detail: detail)
        bumpTopicInteractionRevision(topicId: topicId)
    }
}
