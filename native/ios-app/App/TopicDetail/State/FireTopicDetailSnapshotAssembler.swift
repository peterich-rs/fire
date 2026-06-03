import Foundation

/// Maps `FireTopicDetailPageState` to an immutable `FireTopicDetailPageSnapshot`.
///
/// The assembler is a stateless service — it holds no mutable state and
/// produces a new snapshot on every call to `buildSnapshot(from:for:)`.
///
/// The conversion logic delegates to the existing `FireTopicDetailRuntimeConfiguration`
/// and its authoritative `makeSnapshot()` implementation to produce stable item
/// identities, `contentToken`, and `inPlaceUpdateToken` values.
///
/// Threading: must be called on the main actor (all store state is `@MainActor`).
@MainActor
struct FireTopicDetailSnapshotAssembler {

    // MARK: - Build

    /// Builds an immutable page snapshot from the current page state.
    ///
    /// - Parameters:
    ///   - state: The current page state, assembled by the controller.
    ///   - viewModel: The app view model used for interaction closures and query helpers.
    func buildSnapshot(
        from state: FireTopicDetailPageState,
        viewModel: FireAppViewModel
    ) -> FireTopicDetailPageSnapshot {
        // Build the configuration from page state. The configuration delegates
        // item token computation to the shared presentation helpers used by the
        // existing runtime, so token semantics are stable across the migration.
        let configuration = makeConfiguration(from: state, viewModel: viewModel)
        let runtimeSnapshot = configuration.makeSnapshot()

        let invalidationToken = AnyHashable(FireTopicDetailSnapshotInvalidationToken(
            topicID: state.topic.id,
            topicCollectionRevision: state.topicCollectionRevision,
            pendingScrollTarget: state.pendingScrollTarget,
            detailError: state.detailError ?? "",
            detailNotice: state.detailNotice,
            hasDetail: state.detail != nil,
            isLoadingTopic: state.isLoadingTopic,
            isLoadingMoreTopicPosts: state.isLoadingMoreTopicPosts,
            hasMoreTopicPosts: state.hasMoreTopicPosts,
            canWriteInteractions: state.canWriteInteractions,
            currentUsername: state.currentUsername ?? "",
            baseURLString: state.baseURLString,
            expandedPostTextIDs: state.expandedPostTextIDs,
            expandedReplyRootPostIDs: state.expandedReplyRootPostIDs,
            loadingPostReplyContextIDs: state.loadingPostReplyContextIDs
        ))

        return FireTopicDetailPageSnapshot(
            items: runtimeSnapshot.items,
            replyIndexByPostID: runtimeSnapshot.replyIndexByPostID,
            canWriteInteractions: state.canWriteInteractions,
            hasDetail: state.detail != nil,
            pendingScrollTarget: state.pendingScrollTarget,
            invalidationToken: invalidationToken
        )
    }

    // MARK: - Configuration Builder

    private func makeConfiguration(
        from state: FireTopicDetailPageState,
        viewModel: FireAppViewModel
    ) -> FireTopicDetailRuntimeConfiguration {
        FireTopicDetailRuntimeConfiguration(
            viewModel: viewModel,
            displayedCategory: state.displayedCategory,
            currentUsername: state.currentUsername,
            row: state.row,
            baseURLString: state.baseURLString,
            detail: state.detail,
            renderState: state.renderState,
            pendingScrollTarget: state.pendingScrollTarget,
            detailError: state.detailError,
            detailNotice: state.detailNotice,
            hasMoreTopicPosts: state.hasMoreTopicPosts,
            isLoadingTopic: state.isLoadingTopic,
            isLoadingMoreTopicPosts: state.isLoadingMoreTopicPosts,
            topicAiSummary: state.topicAiSummary,
            isLoadingTopicAiSummary: state.isLoadingTopicAiSummary,
            topicAiSummaryError: state.topicAiSummaryError,
            topicCollectionRevision: state.topicCollectionRevision,
            canWriteInteractions: state.canWriteInteractions,
            postLookup: state.postLookup,
            snapshotInvalidationToken: AnyHashable(state.topicCollectionRevision),
            isMutatingPost: { _ in false },
            isPostTextExpanded: { state.expandedPostTextIDs.contains($0) },
            isReplyThreadExpanded: { state.expandedReplyRootPostIDs.contains($0) },
            isLoadingPostReplyContext: { state.loadingPostReplyContextIDs.contains($0) },
            onVisiblePostNumbersChanged: { _ in },
            onRefresh: { },
            onLoadTopicDetail: { },
            onScrollTargetHandled: { _ in },
            onPreloadTopicPosts: { _ in },
            onLoadMoreTopicPosts: { false },
            onReloadTopicAiSummary: { },
            onOpenComposer: { _ in },
            onOpenPostNumber: { _ in },
            onOpenPostReplies: { _ in },
            onLinkTapped: { _ in },
            onOpenImage: { _ in },
            onToggleLike: { _ in },
            onSelectReaction: { _, _ in },
            onEditPost: { _ in },
            onBookmarkPost: { _ in },
            onDeletePost: { _ in },
            onRecoverPost: { _ in },
            onFlagPost: { _ in },
            onExpandPostText: { _ in },
            onVotePoll: { _, _, _ in },
            onUnvotePoll: { _, _ in },
            onToggleTopicVote: { },
            onShowTopicVoters: { },
            onOpenCategory: { _ in },
            onOpenTag: { _ in }
        )
    }
}

// MARK: - Invalidation Token

/// Equatable invalidation token used to detect snapshot staleness.
private struct FireTopicDetailSnapshotInvalidationToken: Hashable {
    let topicID: UInt64
    let topicCollectionRevision: UInt64
    let pendingScrollTarget: UInt32?
    let detailError: String
    let detailNotice: FireTopicDetailStatusMessage?
    let hasDetail: Bool
    let isLoadingTopic: Bool
    let isLoadingMoreTopicPosts: Bool
    let hasMoreTopicPosts: Bool
    let canWriteInteractions: Bool
    let currentUsername: String
    let baseURLString: String
    let expandedPostTextIDs: Set<UInt64>
    let expandedReplyRootPostIDs: Set<UInt64>
    let loadingPostReplyContextIDs: Set<UInt64>
}
