import Foundation

struct FireTopicDetailSnapshot {
    var topicId: UInt64
    var generation: UInt64
    var phase: TopicDetailPhaseState
    var loadError: TopicDetailLoadErrorState?
    var notice: TopicDetailNoticeState?
    var hasMore: Bool
    var isLoadingMore: Bool
    var loadMoreError: String?
    var scrollTargetPostNumber: UInt32?
    var collectionRevision: UInt64
    var chromeRevision: UInt64
    var sidecarRevision: UInt64
    var interactionRevision: UInt64
    var composerRevision: UInt64
    var chrome: TopicDetailChromeState
    var composer: TopicDetailComposerModelState
    var sidecar: TopicDetailSidecarModelState
    var rows: [TopicDetailUiRowState]
    var rowsByPostID: [UInt64: TopicDetailUiRowState]
    var focusedReplyContext: TopicDetailReplyContextState?
    var flagTypes: [PostActionTypeState]
    var homeRowPatch: TopicHomeRowCountPatchState?

    init(full: TopicDetailUiSnapshotState) {
        topicId = full.topicId
        generation = full.generation
        phase = full.phase
        loadError = full.loadError
        notice = full.notice
        hasMore = full.hasMore
        isLoadingMore = full.isLoadingMore
        loadMoreError = full.loadMoreError
        scrollTargetPostNumber = full.scrollTargetPostNumber
        collectionRevision = full.collectionRevision
        chromeRevision = full.chromeRevision
        sidecarRevision = full.sidecarRevision
        interactionRevision = full.interactionRevision
        composerRevision = full.composerRevision
        chrome = full.chrome
        composer = full.composer
        sidecar = full.sidecar
        rows = full.rows
        rowsByPostID = Dictionary(uniqueKeysWithValues: full.rows.map { ($0.postId, $0) })
        focusedReplyContext = full.focusedReplyContext
        flagTypes = full.flagTypes
        homeRowPatch = full.homeRowPatch
    }
}

extension TopicDetailUiRowState {
    var rowFingerprint: FireTopicDetailRowFingerprint {
        FireTopicDetailRowFingerprint(
            postId: postId,
            postNumber: postNumber,
            rootPostNumber: rootPostNumber,
            parentPostNumber: parentPostNumber,
            depth: depth,
            hasChildren: hasChildren,
            isLastSibling: isLastSibling,
            descendantCount: descendantCount,
            replyCount: replyCount,
            isOriginalPost: isOriginalPost,
            layoutChecksum: layoutChecksum,
            interactionChecksum: interactionChecksum
        )
    }
}

struct FireTopicDetailRowFingerprint: Equatable {
    let postId: UInt64
    let postNumber: UInt32
    let rootPostNumber: UInt32
    let parentPostNumber: UInt32?
    let depth: UInt16
    let hasChildren: Bool
    let isLastSibling: Bool
    let descendantCount: UInt32
    let replyCount: UInt32
    let isOriginalPost: Bool
    let layoutChecksum: UInt64
    let interactionChecksum: UInt64
}
