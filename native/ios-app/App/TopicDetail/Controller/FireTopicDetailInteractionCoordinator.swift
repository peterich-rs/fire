import UIKit

@MainActor
extension FireTopicDetailViewController {
    func toggleReactionPicker(for post: TopicPostState) {
        if expandedReactionPickerPostIDs.contains(post.id) {
            collapseReactionPicker(animatedSnapshot: true)
            return
        }
        expandReactionPicker(for: post.id, markCoachmarkSeen: true)
    }

    func expandReactionPicker(for postID: UInt64, markCoachmarkSeen: Bool) {
        // Single open strip at a time keeps the feed calm.
        expandedReactionPickerPostIDs = [postID]
        if markCoachmarkSeen {
            FireTopicDetailReactionPickerCoachmark.markSeen()
        }
        applyLocalInteractionSnapshot()
        scheduleReactionPickerAutoCollapse()
    }

    func collapseReactionPicker(animatedSnapshot: Bool) {
        reactionPickerCollapseWorkItem?.cancel()
        reactionPickerCollapseWorkItem = nil
        guard !expandedReactionPickerPostIDs.isEmpty else { return }
        expandedReactionPickerPostIDs.removeAll()
        if animatedSnapshot {
            applyLocalInteractionSnapshot()
        }
    }

    func scheduleReactionPickerAutoCollapse() {
        reactionPickerCollapseWorkItem?.cancel()
        let expectedIDs = expandedReactionPickerPostIDs
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Ignore stale timers if the user already collapsed/changed the strip.
            guard self.expandedReactionPickerPostIDs == expectedIDs,
                  !expectedIDs.isEmpty else {
                return
            }
            self.collapseReactionPicker(animatedSnapshot: true)
        }
        reactionPickerCollapseWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.reactionPickerAutoCollapseSeconds,
            execute: work
        )
    }

    /// First device visit: when a writable reaction icon first becomes visible,
    /// auto-expand once so users discover the strip, then auto-collapse.
    func maybePresentReactionPickerCoachmark(visiblePostNumbers: Set<UInt32>) {
        guard !didAttemptReactionPickerCoachmark else { return }
        guard !FireTopicDetailReactionPickerCoachmark.hasSeen else {
            didAttemptReactionPickerCoachmark = true
            return
        }
        guard canWriteInteractions else { return }
        guard !visiblePostNumbers.isEmpty else { return }

        let posts = topicDetailStore.topicDetail(for: topic.id)?.postStream.posts ?? []
        guard let coachPost = posts.first(where: { post in
            visiblePostNumbers.contains(post.postNumber)
                && !post.hidden
        }) else {
            return
        }

        didAttemptReactionPickerCoachmark = true
        FireTopicDetailReactionPickerCoachmark.markSeen()
        expandReactionPicker(for: coachPost.id, markCoachmarkSeen: false)
    }

    func togglePostTextExpansion(for post: TopicPostState) {
        if expandedPostTextIDs.contains(post.id) {
            expandedPostTextIDs.remove(post.id)
        } else {
            expandedPostTextIDs.insert(post.id)
        }
        applyLocalInteractionSnapshot()
    }

    func openPostReplies(for post: TopicPostState) {
        if expandedReplyRootPostIDs.contains(post.id) {
            expandedReplyRootPostIDs.remove(post.id)
            applyLocalInteractionSnapshot()
            return
        }

        expandedReplyRootPostIDs.insert(post.id)
        applyLocalInteractionSnapshot()
        Task {
            await topicDetailStore.loadPostReplyContextIfNeeded(
                topicID: topic.id,
                post: post
            )
        }
    }

    func toggleLike(for post: TopicPostState) {
        applyReactionChange(
            from: post.currentUserReaction,
            to: post.currentUserReaction?.id == "heart" ? nil : "heart",
            postId: post.id
        )
    }

    func toggleReaction(_ reactionId: String, for post: TopicPostState) {
        let trimmedReactionID = reactionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReactionID.isEmpty else { return }
        applyReactionChange(
            from: post.currentUserReaction,
            to: post.currentUserReaction?.id == trimmedReactionID ? nil : trimmedReactionID,
            postId: post.id
        )
    }

    func presentReactionPicker(for post: TopicPostState) {
        // Kept for potential deep-link / overflow discovery; primary path is the
        // inline quick-reaction strip under the action icons.
        toggleReactionPicker(for: post)
    }

    func applyReactionChange(
        from currentReaction: TopicReactionState?,
        to desiredReactionID: String?,
        postId: UInt64
    ) {
        let currentReactionID = currentReaction?.id
        guard currentReactionID != desiredReactionID else { return }
        guard let toggledReactionID = desiredReactionID ?? currentReactionID, !toggledReactionID.isEmpty else {
            return
        }

        if currentReactionID != nil, currentReaction?.canUndo == false {
            modalRouter.presentNotice(message: "当前表情回应已超过可撤销时间，暂时不能修改。")
            return
        }

        Task { @MainActor in
            do {
                try await transitionReaction(
                    from: currentReactionID,
                    to: desiredReactionID,
                    toggledReactionId: toggledReactionID,
                    postId: postId
                )
                // Soft confirm — the chip already updated optimistically on tap.
                FireMotionHaptics.selection()
            } catch is CancellationError {
                // In-flight duplicate tap; optimistic UI already reflects intent.
            } catch {
                FireMotionHaptics.error()
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }

    func showReactionUsers(for post: TopicPostState, reactionID: String?) {
        Task { @MainActor in
            do {
                let groups = try await viewModel.topicInteraction.fetchReactionUsers(postID: post.id)
                let filteredGroups = groups.filter(for: reactionID)
                modalRouter.presentReactionUsers(groups: filteredGroups, reactionID: reactionID)
            } catch {
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }

    func transitionReaction(
        from currentReactionID: String?,
        to desiredReactionID: String?,
        toggledReactionId: String,
        postId: UInt64
    ) async throws {
        switch (currentReactionID, desiredReactionID) {
        case (nil, "heart"):
            try await viewModel.topicInteraction.setPostLiked(topicId: topic.id, postId: postId, liked: true)
        case ("heart", nil):
            try await viewModel.topicInteraction.setPostLiked(topicId: topic.id, postId: postId, liked: false)
        default:
            try await viewModel.topicInteraction.togglePostReaction(
                topicId: topic.id,
                postId: postId,
                reactionId: toggledReactionId
            )
        }
    }

    func confirmDelete(_ post: TopicPostState) {
        modalRouter.presentDeleteConfirmation(postNumber: post.postNumber) { [weak self] in
            self?.deletePost(
                FirePostManagementContext(postID: post.id, postNumber: post.postNumber)
            )
        }
    }

    func deletePost(_ context: FirePostManagementContext) {
        Task { @MainActor in
            do {
                try await topicDetailStore.deletePost(
                    topicID: topic.id,
                    postID: context.postID
                )
                modalRouter.presentNotice(message: "已删除 #\(context.postNumber)。")
            } catch {
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }

    func recoverPost(_ post: TopicPostState) {
        let context = FirePostManagementContext(postID: post.id, postNumber: post.postNumber)
        Task { @MainActor in
            do {
                try await topicDetailStore.recoverPost(
                    topicID: topic.id,
                    postID: context.postID
                )
                modalRouter.presentNotice(message: "已恢复 #\(context.postNumber)。")
            } catch {
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }

    func toggleTopicVote() async {
        guard let detail else { return }
        do {
            _ = try await viewModel.topicInteraction.voteTopic(
                topicID: topic.id,
                voted: !detail.userVoted,
                recoveryOriginURL: topicCloudflareRecoveryURL
            )
        } catch {
            modalRouter.presentNotice(message: error.localizedDescription)
        }
    }

    func presentTopicVoters() async {
        do {
            let voters = try await viewModel.topicInteraction.fetchTopicVoters(topicID: topic.id)
            modalRouter.presentTopicVoters(voters, isLoading: false)
        } catch {
            modalRouter.presentNotice(message: error.localizedDescription)
        }
    }

    func submitPollVote(
        for post: TopicPostState,
        poll: PollState,
        options: [String]
    ) {
        Task { @MainActor in
            do {
                _ = try await viewModel.topicInteraction.votePoll(
                    topicID: topic.id,
                    postID: post.id,
                    pollName: poll.name,
                    options: options,
                    recoveryOriginURL: topicCloudflareRecoveryURL
                )
            } catch {
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }

    func removePollVote(for post: TopicPostState, poll: PollState) {
        Task { @MainActor in
            do {
                _ = try await viewModel.topicInteraction.unvotePoll(
                    topicID: topic.id,
                    postID: post.id,
                    pollName: poll.name,
                    recoveryOriginURL: topicCloudflareRecoveryURL
                )
            } catch {
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }
}
