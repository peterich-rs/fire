import Foundation

/// Store-backed data that can change the structural topic-detail feed.
struct FireTopicDetailFeedState {

    let detail: TopicDetailState?
    let renderState: FireTopicDetailRenderState?
    let postLookup: [UInt64: TopicPostState]
    let isLoadingTopic: Bool
    let isLoadingMoreTopicPosts: Bool
    let loadMoreTopicPostsError: String?
    let hasMoreTopicPosts: Bool
    let detailError: String?
    let detailNotice: FireTopicDetailStatusMessage?
    let topicCollectionRevision: UInt64
    let pendingScrollTarget: UInt32?
}

/// Toolbar-level state. Changes here should not rebuild feed items.
struct FireTopicDetailChromeState {
    let detail: TopicDetailState?
    let row: FireTopicRowPresentation
    let baseURLString: String
    let canWriteInteractions: Bool
}

/// Quick-reply state. Typing and validation changes should only apply chrome.
struct FireTopicDetailComposerState {
    let typingUsers: [TopicPresenceUserState]
    let composerContext: FireReplyComposerContext?
    let replyDraft: String
    let quickReplyError: String?
    let isSubmittingReply: Bool
    let minimumReplyLength: Int
    let canWriteInteractions: Bool
}

/// Sidecar state rendered outside the core post stream.
struct FireTopicDetailSidecarState {
    let topicAiSummary: TopicAiSummaryState?
    let isLoadingTopicAiSummary: Bool
    let topicAiSummaryError: String?
}

/// Per-item interaction state used for targeted item refresh and visible-node updates.
struct FireTopicDetailInteractionState: Equatable {
    let mutatingPostIDs: Set<UInt64>
    let loadingPostReplyContextIDs: Set<UInt64>
    let postReplyContextErrorsByPostID: [UInt64: String]
    let expandedPostTextIDs: Set<UInt64>
    let expandedReplyRootPostIDs: Set<UInt64>

    static let empty = FireTopicDetailInteractionState(
        mutatingPostIDs: [],
        loadingPostReplyContextIDs: [],
        postReplyContextErrorsByPostID: [:],
        expandedPostTextIDs: [],
        expandedReplyRootPostIDs: []
    )

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

    func postReplyContextError(_ postID: UInt64) -> String? {
        postReplyContextErrorsByPostID[postID]
    }
}

/// Route/session constants needed by feed construction.
struct FireTopicDetailRouteState {
    let currentUsername: String?
    let baseURLString: String
    let canWriteInteractions: Bool
    let row: FireTopicRowPresentation
    let displayedCategory: FireTopicCategoryPresentation?

    var topic: TopicSummaryState {
        row.topic
    }
}

/// Controller-local page state for the topic-detail screen.
///
/// The controller keeps feed, chrome, composer, sidecar, and interaction state
/// as separate domains so local UI changes can apply only the affected surface.
struct FireTopicDetailPageState {

    let feed: FireTopicDetailFeedState
    let chrome: FireTopicDetailChromeState
    let composer: FireTopicDetailComposerState
    let sidecar: FireTopicDetailSidecarState
    let interaction: FireTopicDetailInteractionState
    let route: FireTopicDetailRouteState

    var topic: TopicSummaryState {
        route.topic
    }

    var detail: TopicDetailState? {
        feed.detail
    }

    var pendingScrollTarget: UInt32? {
        feed.pendingScrollTarget
    }
}

struct FireTopicDetailSnapshotInput: @unchecked Sendable {
    let configuration: FireTopicDetailRuntimeConfiguration
    let toolbarState: FireTopicDetailToolbarState
    let quickReplyState: FireTopicDetailQuickReplyState
    let pendingScrollTarget: UInt32?
    let invalidationToken: AnyHashable
}
