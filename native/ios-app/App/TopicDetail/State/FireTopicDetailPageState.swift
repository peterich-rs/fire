import Foundation

/// Controller-local page state for the topic-detail screen.
///
/// Combines store-backed data snapshots with page-local ephemeral UI state.
/// The controller builds a new `FireTopicDetailPageState` whenever relevant
/// store publications arrive, then hands it to `FireTopicDetailSnapshotAssembler`
/// to produce an immutable render snapshot.
///
/// All stored values are value types so that the assembler can safely compare
/// them across snapshot cycles without coordination.
struct FireTopicDetailPageState {

    // MARK: - Store-Backed Entity State

    /// Current loaded topic detail, or `nil` if not yet loaded.
    let detail: TopicDetailState?

    /// Precise layout + presentation render state, or `nil` if not yet available.
    let renderState: FireTopicDetailRenderState?

    /// Post lookup keyed by post ID, built from the loaded post stream.
    let postLookup: [UInt64: TopicPostState]

    /// AI summary for the topic, or `nil` if not loaded or unavailable.
    let topicAiSummary: TopicAiSummaryState?

    // MARK: - Store-Backed Loading Flags

    let isLoadingTopic: Bool
    let isLoadingMoreTopicPosts: Bool
    let loadMoreTopicPostsError: String?
    let isLoadingTopicAiSummary: Bool
    let hasMoreTopicPosts: Bool

    // MARK: - Store-Backed Notices and Errors

    let detailError: String?
    let detailNotice: FireTopicDetailStatusMessage?
    let topicAiSummaryError: String?

    // MARK: - Store-Backed Per-Item State

    /// IDs of posts whose reply context is currently loading.
    let loadingPostReplyContextIDs: Set<UInt64>

    /// IDs of posts currently accepting a mutation request.
    let mutatingPostIDs: Set<UInt64>

    /// Presence users actively typing in this topic.
    let typingUsers: [TopicPresenceUserState]

    // MARK: - Store-Backed Revision Token

    /// Opaque revision token that bumps on any entity or loading-flag change.
    let topicCollectionRevision: UInt64

    // MARK: - Route and Scroll State

    /// Pending post-number scroll target, if any.
    let pendingScrollTarget: UInt32?

    // MARK: - Page-Local Session State

    /// Current username from the session bootstrap.
    let currentUsername: String?

    /// Base URL for rendering links and share URLs.
    let baseURLString: String

    /// Whether the current session can perform write interactions.
    let canWriteInteractions: Bool

    // MARK: - Page-Local Ephemeral UI State

    /// Set of post IDs whose overflow text the reader has explicitly expanded.
    let expandedPostTextIDs: Set<UInt64>

    /// Set of post IDs whose reply-root thread the reader has expanded.
    let expandedReplyRootPostIDs: Set<UInt64>

    /// Current quick-reply composer context.
    let composerContext: FireReplyComposerContext?

    /// Current quick-reply draft text.
    let replyDraft: String

    /// Current quick-reply validation or submission error.
    let quickReplyError: String?

    /// Whether the quick-reply action is currently in flight.
    let isSubmittingReply: Bool

    /// Minimum reply length enforced by the current session.
    let minimumReplyLength: Int

    // MARK: - Route Inputs (immutable per-page constants)

    /// The original topic row from the navigation route.
    let row: FireTopicRowPresentation

    /// Category presentation for the topic's category, if available.
    let displayedCategory: FireTopicCategoryPresentation?

    // MARK: - Convenience

    var topic: TopicSummaryState {
        row.topic
    }
}

// MARK: - Predicate Helpers

extension FireTopicDetailPageState {

    func isMutatingPost(_ postID: UInt64) -> Bool {
        mutatingPostIDs.contains(postID)
    }

    func isPostTextExpanded(_ postID: UInt64) -> Bool {
        expandedPostTextIDs.contains(postID)
    }

    func isReplyThreadExpanded(_ postID: UInt64) -> Bool {
        expandedReplyRootPostIDs.contains(postID)
    }

    func isLoadingPostReplyContext(_ postID: UInt64) -> Bool {
        loadingPostReplyContextIDs.contains(postID)
    }
}
