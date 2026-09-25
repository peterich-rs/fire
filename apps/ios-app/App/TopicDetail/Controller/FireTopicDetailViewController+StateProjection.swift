import Foundation

@MainActor
extension FireTopicDetailViewController {
    func buildCurrentRouteState(topicId: UInt64) -> FireTopicDetailRouteState {
        let chrome = topicDetailStore.snapshot(for: topicId)?.chrome
        return FireTopicDetailRouteState(
            currentUsername: viewModel.session.bootstrap.currentUsername,
            baseURLString: baseURLString,
            canWriteInteractions: canWriteInteractions,
            row: row,
            displayedCategory: viewModel.categoryPresentation(for: chrome?.categoryId ?? row.topic.categoryId)
        )
    }

    func buildCurrentFeedState(topicId: UInt64) -> FireTopicDetailFeedState {
        let snapshot = topicDetailStore.snapshot(for: topicId)
        let posts = snapshot.map(FireTopicDetailUiProjection.posts(from:)) ?? []
        return FireTopicDetailFeedState(
            detail: nil,
            renderState: nil,
            postLookup: Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) }),
            isLoadingTopic: snapshot?.phase == .loading,
            isLoadingMoreTopicPosts: snapshot?.isLoadingMore ?? false,
            loadMoreTopicPostsError: snapshot?.loadMoreError,
            hasMoreTopicPosts: snapshot?.hasMore ?? false,
            detailError: Self.loadErrorMessage(snapshot?.loadError),
            detailNotice: snapshot?.notice.map {
                FireTopicDetailStatusMessage(
                    title: $0.title,
                    message: $0.message,
                    retryable: $0.retryable,
                    emphasizesError: $0.emphasizesError
                )
            },
            topicCollectionRevision: snapshot?.collectionRevision ?? 0,
            pendingScrollTarget: snapshot?.scrollTargetPostNumber
        )
    }

    func buildCurrentChromeState(topicId: UInt64) -> FireTopicDetailChromeState {
        FireTopicDetailChromeState(
            detail: nil,
            row: row,
            baseURLString: baseURLString,
            canWriteInteractions: canWriteInteractions
        )
    }

    func buildCurrentComposerState(topicId: UInt64) -> FireTopicDetailComposerState {
        let snapshot = topicDetailStore.snapshot(for: topicId)
        return FireTopicDetailComposerState(
            typingUsers: snapshot?.composer.typingUsers ?? [],
            composerContext: composerContext,
            replyDraft: replyDraft,
            quickReplyError: quickReplyError,
            isSubmittingReply: snapshot?.composer.isSubmitting ?? false,
            minimumReplyLength: minimumReplyLength,
            canWriteInteractions: canWriteInteractions
        )
    }

    func buildCurrentSidecarState(topicId: UInt64) -> FireTopicDetailSidecarState {
        let sidecar = topicDetailStore.snapshot(for: topicId)?.sidecar
        let summary = sidecar?.summarizedText.map { text in
            TopicAiSummaryState(
                summarizedText: text,
                algorithm: sidecar?.algorithm,
                outdated: sidecar?.outdated ?? false,
                canRegenerate: sidecar?.canRegenerate ?? false,
                newPostsSinceSummary: sidecar?.newPostsSinceSummary ?? 0,
                updatedAt: sidecar?.updatedAt
            )
        }
        return FireTopicDetailSidecarState(
            topicAiSummary: summary,
            isLoadingTopicAiSummary: sidecar?.isLoading ?? false,
            topicAiSummaryError: sidecar?.error
        )
    }

    func buildCurrentInteractionState() -> FireTopicDetailInteractionState {
        let rows = topicDetailStore.snapshot(for: row.topic.id)?.rows ?? []
        return FireTopicDetailInteractionState(
            mutatingPostIDs: Set(rows.filter(\.isMutating).map(\.postId)),
            loadingPostReplyContextIDs: Set(rows.filter(\.isLoadingReplyContext).map(\.postId)),
            expandedPostTextIDs: expandedPostTextIDs,
            expandedReplyRootPostIDs: expandedReplyRootPostIDs,
            expandedReactionPickerPostIDs: expandedReactionPickerPostIDs
        )
    }

    private static func loadErrorMessage(_ error: TopicDetailLoadErrorState?) -> String? {
        switch error {
        case .network:
            return "网络错误"
        case .loginRequired:
            return "需要登录"
        case .unrecoverable(let message):
            return message
        case nil:
            return nil
        }
    }

    func buildCurrentPageState() -> FireTopicDetailPageState {
        let topicId = row.topic.id
        return FireTopicDetailPageState(
            feed: buildCurrentFeedState(topicId: topicId),
            chrome: buildCurrentChromeState(topicId: topicId),
            composer: buildCurrentComposerState(topicId: topicId),
            sidecar: buildCurrentSidecarState(topicId: topicId),
            interaction: buildCurrentInteractionState(),
            route: buildCurrentRouteState(topicId: topicId)
        )
    }
}
