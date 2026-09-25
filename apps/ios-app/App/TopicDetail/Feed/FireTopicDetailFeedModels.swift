import Foundation
import UIKit

enum FireTopicDetailRuntimeSection: Sendable {
    case main
}

struct FireTopicDetailStatusMessage: Hashable, Sendable {
    let title: String?
    let message: String
    let retryable: Bool
    let emphasizesError: Bool
}

enum FireTopicDetailRuntimeItemKind: Hashable, Sendable {
    case header
    case aiSummary
    case originalPost
    case stats
    case topicVote
    case repliesHeader
    case bodyState
    case reply
    case replyFooter
    case notice
}

struct FireTopicDetailRuntimeItem: Hashable, @unchecked Sendable {
    let id: String
    let kind: FireTopicDetailRuntimeItemKind
    let postID: UInt64?
    let postNumber: UInt32?
    let replyIndex: Int?
    let replyShowsThreadLine: Bool
    let replyShowsDivider: Bool
    let replyShortcutCount: UInt32?
    let isReplyThreadExpanded: Bool
    let contentToken: AnyHashable
    let inPlaceUpdateToken: AnyHashable?
    let messageBands: FireTopicDetailMessageBands?
    let statusMessage: FireTopicDetailStatusMessage?

    init(
        id: String,
        kind: FireTopicDetailRuntimeItemKind,
        postID: UInt64?,
        postNumber: UInt32?,
        replyIndex: Int?,
        replyShowsThreadLine: Bool = false,
        replyShowsDivider: Bool = false,
        replyShortcutCount: UInt32? = nil,
        isReplyThreadExpanded: Bool = false,
        contentToken: AnyHashable,
        inPlaceUpdateToken: AnyHashable? = nil,
        messageBands: FireTopicDetailMessageBands? = nil,
        statusMessage: FireTopicDetailStatusMessage? = nil
    ) {
        self.id = id
        self.kind = kind
        self.postID = postID
        self.postNumber = postNumber
        self.replyIndex = replyIndex
        self.replyShowsThreadLine = replyShowsThreadLine
        self.replyShowsDivider = replyShowsDivider
        self.replyShortcutCount = replyShortcutCount
        self.isReplyThreadExpanded = isReplyThreadExpanded
        self.contentToken = contentToken
        self.inPlaceUpdateToken = inPlaceUpdateToken
        self.messageBands = messageBands
        self.statusMessage = statusMessage
    }

    /// Identity-only equality for diff planning. Use `hasSameRenderedContent`
    /// when comparing what the reader should actually see on screen.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    func hasSameRenderedContent(as other: Self) -> Bool {
        id == other.id
            && kind == other.kind
            && postID == other.postID
            && postNumber == other.postNumber
            && replyIndex == other.replyIndex
            && replyShowsThreadLine == other.replyShowsThreadLine
            && replyShowsDivider == other.replyShowsDivider
            && replyShortcutCount == other.replyShortcutCount
            && isReplyThreadExpanded == other.isReplyThreadExpanded
            && contentToken == other.contentToken
            && statusMessage == other.statusMessage
    }

    func needsVisibleNodeUpdate(comparedTo other: Self) -> Bool {
        hasSameRenderedContent(as: other)
            && inPlaceUpdateToken != other.inPlaceUpdateToken
    }

    func changedMessageBands(from previous: FireTopicDetailRuntimeItem) -> Set<FireTopicDetailMessageBand> {
        guard let messageBands, let previousBands = previous.messageBands else {
            return Set(FireTopicDetailMessageBand.allCases)
        }
        return messageBands.changed(from: previousBands)
    }
}

struct FireTopicDetailRuntimeSnapshot: Sendable {
    let items: [FireTopicDetailRuntimeItem]
    let replyIndexByPostID: [UInt64: Int]
}

struct FireTopicDetailRuntimePostContext {
    let post: TopicPostState
    let renderContent: FireTopicPostRenderContent
    let depth: Int
    let replyContext: String?
    let replyTargetPostNumber: UInt32?
    let showsThreadLine: Bool
    let showsDivider: Bool
    let replyShortcutCount: UInt32?
    let isReplyThreadExpanded: Bool
    let isLoadingReplyContext: Bool
    let textExpansionState: FirePostTextExpansionState
    /// Original/main post keeps actions in the nav toolbar; only replies show cell `...`.
    let allowsInlineOverflowActions: Bool
}

struct FireTopicDetailReplyDisplayPlan {
    struct DisplayedRow {
        let row: FirePreparedTopicTimelineRow
        let sourceIndex: Int
        let showsThreadLine: Bool
        let showsDivider: Bool
        let replyShortcutCount: UInt32?
        let isReplyThreadExpanded: Bool
    }

    let rows: [DisplayedRow]
    let sourceIndexByPostID: [UInt64: Int]
}

struct FireTopicDetailReplyThreadIndex {
    let rootIndexBySourceIndex: [Int: Int]
    let secondaryIndicesByRoot: [Int: [Int]]
}

final class FireTopicDetailRuntimeInteractions {
    let isMutatingPost: (UInt64) -> Bool
    let isPostTextExpanded: (UInt64) -> Bool
    let isReplyThreadExpanded: (UInt64) -> Bool
    let isLoadingPostReplyContext: (UInt64) -> Bool
    let onVisiblePostNumbersChanged: (Set<UInt32>) -> Void
    let onRefresh: () async -> Void
    let onLoadTopicDetail: () async -> Void
    let onScrollTargetHandled: (UInt32) -> Void
    let onLoadMoreTopicPosts: () -> Bool
    let onReloadTopicAiSummary: () -> Void
    let onToggleTopicAiSummaryExpanded: () -> Void
    let onOpenComposer: (TopicPostState?) -> Void
    let onOpenPostNumber: (UInt32) -> Void
    let onOpenPostReplies: (TopicPostState) -> Void
    let onLinkTapped: (URL) -> Void
    let onOpenProfile: (String) -> Void
    let onOpenImage: (FireCookedImage) -> Void
    let onToggleLike: (TopicPostState) -> Void
    let onSelectReaction: (TopicPostState, String) -> Void
    let onToggleReactionPicker: (TopicPostState) -> Void
    let onBoostPost: (TopicPostState) -> Void
    let quickReactionOptionsProvider: () -> [FireReactionOption]
    let isReactionPickerExpanded: (UInt64) -> Bool
    let onQuotePost: (TopicPostState) -> Void
    let onEditPost: (TopicPostState) -> Void
    let onBookmarkPost: (TopicPostState) -> Void
    let onDeletePost: (TopicPostState) -> Void
    let onRecoverPost: (TopicPostState) -> Void
    let onFlagPost: (TopicPostState) -> Void
    let onExpandPostText: (TopicPostState) -> Void
    let onVotePoll: (TopicPostState, PollState, [String]) -> Void
    let onUnvotePoll: (TopicPostState, PollState) -> Void
    let onToggleTopicVote: () async -> Void
    let onShowTopicVoters: () async -> Void
    let onOpenCategory: (FireTopicCategoryPresentation) -> Void
    let onOpenTag: (String) -> Void

    init(
        isMutatingPost: @escaping (UInt64) -> Bool,
        isPostTextExpanded: @escaping (UInt64) -> Bool,
        isReplyThreadExpanded: @escaping (UInt64) -> Bool,
        isLoadingPostReplyContext: @escaping (UInt64) -> Bool,
        onVisiblePostNumbersChanged: @escaping (Set<UInt32>) -> Void,
        onRefresh: @escaping () async -> Void,
        onLoadTopicDetail: @escaping () async -> Void,
        onScrollTargetHandled: @escaping (UInt32) -> Void,
        onLoadMoreTopicPosts: @escaping () -> Bool,
        onReloadTopicAiSummary: @escaping () -> Void,
        onToggleTopicAiSummaryExpanded: @escaping () -> Void,
        onOpenComposer: @escaping (TopicPostState?) -> Void,
        onOpenPostNumber: @escaping (UInt32) -> Void,
        onOpenPostReplies: @escaping (TopicPostState) -> Void,
        onLinkTapped: @escaping (URL) -> Void,
        onOpenProfile: @escaping (String) -> Void,
        onOpenImage: @escaping (FireCookedImage) -> Void,
        onToggleLike: @escaping (TopicPostState) -> Void,
        onSelectReaction: @escaping (TopicPostState, String) -> Void,
        onToggleReactionPicker: @escaping (TopicPostState) -> Void,
        onBoostPost: @escaping (TopicPostState) -> Void,
        quickReactionOptionsProvider: @escaping () -> [FireReactionOption],
        isReactionPickerExpanded: @escaping (UInt64) -> Bool,
        onQuotePost: @escaping (TopicPostState) -> Void,
        onEditPost: @escaping (TopicPostState) -> Void,
        onBookmarkPost: @escaping (TopicPostState) -> Void,
        onDeletePost: @escaping (TopicPostState) -> Void,
        onRecoverPost: @escaping (TopicPostState) -> Void,
        onFlagPost: @escaping (TopicPostState) -> Void,
        onExpandPostText: @escaping (TopicPostState) -> Void,
        onVotePoll: @escaping (TopicPostState, PollState, [String]) -> Void,
        onUnvotePoll: @escaping (TopicPostState, PollState) -> Void,
        onToggleTopicVote: @escaping () async -> Void,
        onShowTopicVoters: @escaping () async -> Void,
        onOpenCategory: @escaping (FireTopicCategoryPresentation) -> Void,
        onOpenTag: @escaping (String) -> Void
    ) {
        self.isMutatingPost = isMutatingPost
        self.isPostTextExpanded = isPostTextExpanded
        self.isReplyThreadExpanded = isReplyThreadExpanded
        self.isLoadingPostReplyContext = isLoadingPostReplyContext
        self.onVisiblePostNumbersChanged = onVisiblePostNumbersChanged
        self.onRefresh = onRefresh
        self.onLoadTopicDetail = onLoadTopicDetail
        self.onScrollTargetHandled = onScrollTargetHandled
        self.onLoadMoreTopicPosts = onLoadMoreTopicPosts
        self.onReloadTopicAiSummary = onReloadTopicAiSummary
        self.onToggleTopicAiSummaryExpanded = onToggleTopicAiSummaryExpanded
        self.onOpenComposer = onOpenComposer
        self.onOpenPostNumber = onOpenPostNumber
        self.onOpenPostReplies = onOpenPostReplies
        self.onLinkTapped = onLinkTapped
        self.onOpenProfile = onOpenProfile
        self.onOpenImage = onOpenImage
        self.onToggleLike = onToggleLike
        self.onSelectReaction = onSelectReaction
        self.onToggleReactionPicker = onToggleReactionPicker
        self.onBoostPost = onBoostPost
        self.quickReactionOptionsProvider = quickReactionOptionsProvider
        self.isReactionPickerExpanded = isReactionPickerExpanded
        self.onQuotePost = onQuotePost
        self.onEditPost = onEditPost
        self.onBookmarkPost = onBookmarkPost
        self.onDeletePost = onDeletePost
        self.onRecoverPost = onRecoverPost
        self.onFlagPost = onFlagPost
        self.onExpandPostText = onExpandPostText
        self.onVotePoll = onVotePoll
        self.onUnvotePoll = onUnvotePoll
        self.onToggleTopicVote = onToggleTopicVote
        self.onShowTopicVoters = onShowTopicVoters
        self.onOpenCategory = onOpenCategory
        self.onOpenTag = onOpenTag
    }
}

struct FireTopicDetailRuntimeConfiguration: @unchecked Sendable {
    let viewModel: FireAppViewModel?
    let displayedCategory: FireTopicCategoryPresentation?
    let currentUsername: String?
    let row: FireTopicRowPresentation
    let baseURLString: String
    let snapshot: TopicDetailUiSnapshotState?
    let detail: TopicDetailState?
    let renderState: FireTopicDetailRenderState?
    let pendingScrollTarget: UInt32?
    let detailError: String?
    let detailNotice: FireTopicDetailStatusMessage?
    let hasMoreTopicPosts: Bool
    let isLoadingTopic: Bool
    let isLoadingMoreTopicPosts: Bool
    let loadMoreTopicPostsError: String?
    let topicAiSummary: TopicAiSummaryState?
    let isLoadingTopicAiSummary: Bool
    let topicAiSummaryError: String?
    let isTopicAiSummaryExpanded: Bool
    let topicCollectionRevision: UInt64
    let canWriteInteractions: Bool
    let postLookup: [UInt64: TopicPostState]
    let interactionState: FireTopicDetailInteractionState
    let activeSearchPostID: UInt64?
    let snapshotInvalidationToken: AnyHashable
    let interactions: FireTopicDetailRuntimeInteractions

    var isMutatingPost: (UInt64) -> Bool { interactionState.isMutatingPost }
    func isSearchHighlighted(postID: UInt64) -> Bool {
        activeSearchPostID == postID
    }
    var isPostTextExpanded: (UInt64) -> Bool { interactionState.isPostTextExpanded }
    var isReplyThreadExpanded: (UInt64) -> Bool { interactionState.isReplyThreadExpanded }
    var isLoadingPostReplyContext: (UInt64) -> Bool { interactionState.isLoadingPostReplyContext }
    var onVisiblePostNumbersChanged: (Set<UInt32>) -> Void { interactions.onVisiblePostNumbersChanged }
    var onRefresh: () async -> Void { interactions.onRefresh }
    var onLoadTopicDetail: () async -> Void { interactions.onLoadTopicDetail }
    var onScrollTargetHandled: (UInt32) -> Void { interactions.onScrollTargetHandled }
    var onLoadMoreTopicPosts: () -> Bool { interactions.onLoadMoreTopicPosts }
    var onReloadTopicAiSummary: () -> Void { interactions.onReloadTopicAiSummary }
    var onToggleTopicAiSummaryExpanded: () -> Void { interactions.onToggleTopicAiSummaryExpanded }
    var onOpenComposer: (TopicPostState?) -> Void { interactions.onOpenComposer }
    var onOpenPostNumber: (UInt32) -> Void { interactions.onOpenPostNumber }
    var onOpenPostReplies: (TopicPostState) -> Void { interactions.onOpenPostReplies }
    var onLinkTapped: (URL) -> Void { interactions.onLinkTapped }
    var onOpenProfile: (String) -> Void { interactions.onOpenProfile }
    var onOpenImage: (FireCookedImage) -> Void { interactions.onOpenImage }
    var onToggleLike: (TopicPostState) -> Void { interactions.onToggleLike }
    var onSelectReaction: (TopicPostState, String) -> Void { interactions.onSelectReaction }
    var onToggleReactionPicker: (TopicPostState) -> Void { interactions.onToggleReactionPicker }
    var onBoostPost: (TopicPostState) -> Void { interactions.onBoostPost }
    var quickReactionOptions: [FireReactionOption] { interactions.quickReactionOptionsProvider() }
    var isReactionPickerExpanded: (UInt64) -> Bool { interactions.isReactionPickerExpanded }
    var onQuotePost: (TopicPostState) -> Void { interactions.onQuotePost }
    var onEditPost: (TopicPostState) -> Void { interactions.onEditPost }
    var onBookmarkPost: (TopicPostState) -> Void { interactions.onBookmarkPost }
    var onDeletePost: (TopicPostState) -> Void { interactions.onDeletePost }
    var onRecoverPost: (TopicPostState) -> Void { interactions.onRecoverPost }
    var onFlagPost: (TopicPostState) -> Void { interactions.onFlagPost }
    var onExpandPostText: (TopicPostState) -> Void { interactions.onExpandPostText }
    var onVotePoll: (TopicPostState, PollState, [String]) -> Void { interactions.onVotePoll }
    var onUnvotePoll: (TopicPostState, PollState) -> Void { interactions.onUnvotePoll }
    var onToggleTopicVote: () async -> Void { interactions.onToggleTopicVote }
    var onShowTopicVoters: () async -> Void { interactions.onShowTopicVoters }
    var onOpenCategory: (FireTopicCategoryPresentation) -> Void { interactions.onOpenCategory }
    var onOpenTag: (String) -> Void { interactions.onOpenTag }

    var topic: TopicSummaryState {
        row.topic
    }

    var displayedTopicTitle: String {
        let trimmedDetailTitle = (snapshot?.chrome.title ?? detail?.title)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedDetailTitle.isEmpty {
            return trimmedDetailTitle
        }
        let trimmedRowTitle = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedRowTitle.isEmpty ? "话题 \(topic.id)" : trimmedRowTitle
    }

    var displayedReplyCount: UInt32 {
        snapshot?.chrome.replyCount ?? detail?.replyCount ?? topic.replyCount
    }

    var displayedViewsCount: UInt32 {
        snapshot?.chrome.views ?? detail?.views ?? topic.views
    }

    var displayedCategoryId: UInt64? {
        snapshot?.chrome.categoryId ?? detail?.categoryId ?? topic.categoryId
    }

    var displayedTagNames: [String] {
        let detailTags = (snapshot?.chrome.tags ?? detail?.tags.map(\.name) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return detailTags.isEmpty ? row.tagNames : detailTags
    }

    var isPrivateMessageThread: Bool {
        FireTopicPresentation.isPrivateMessageArchetype(snapshot?.chrome.archetype ?? detail?.archetype)
    }

    var displayedParticipants: [TopicParticipantState] {
        guard isPrivateMessageThread else {
            return []
        }

        let source: [TopicParticipantState]
        if let participants = snapshot?.chrome.participants, !participants.isEmpty {
            source = participants.map {
                TopicParticipantState(
                    userId: $0.userId,
                    username: $0.username,
                    name: $0.name,
                    avatarTemplate: nil
                )
            }
        } else if !(detail?.details.participants.isEmpty ?? true) {
            source = detail?.details.participants ?? []
        } else {
            source = topic.participants
        }
        let currentUsername = currentUsername?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var participants: [TopicParticipantState] = []
        for participant in source {
            let normalizedUsername = participant.username?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let currentUsername,
               normalizedUsername?.caseInsensitiveCompare(currentUsername) == .orderedSame {
                continue
            }

            let stableID = normalizedUsername?.lowercased() ?? "id:\(participant.userId)"
            if participants.contains(where: {
                ($0.username?.lowercased() ?? "id:\($0.userId)") == stableID
            }) {
                continue
            }
            participants.append(participant)
        }
        return participants
    }

    var displayedInteractionCount: UInt32? {
        if let snapshot {
            return snapshot.chrome.likeCount
        }
        return detail.map(FireTopicPresentation.interactionCount(for:))
    }

    var loadedReplyCount: Int {
        availableReplyRows.count
    }

    var displayedFloorCount: Int {
        availableReplyRows.count
    }

    var totalReplyCount: Int {
        Int(snapshot?.chrome.replyCount ?? detail?.replyCount ?? topic.replyCount)
    }

    var showsTopicVote: Bool {
        if let chrome = snapshot?.chrome, !isPrivateMessageThread {
            return chrome.canVote || chrome.userVoted || chrome.voteCount > 0
        }
        guard let detail, !isPrivateMessageThread else {
            return false
        }
        return detail.canVote || detail.userVoted || detail.voteCount > 0
    }

    var resolvedPostLookup: [UInt64: TopicPostState] {
        if let snapshot {
            return Dictionary(uniqueKeysWithValues: snapshot.rows.map {
                ($0.postId, FireTopicDetailUiProjection.post(from: $0))
            })
        }
        return postLookup
    }

    var originalRow: FirePreparedTopicTimelineRow? {
        if let row = snapshot?.rows.first(where: \.isOriginalPost) ?? snapshot?.rows.first {
            return FirePreparedTopicTimelineRow(entry: FireTopicDetailUiProjection.timelineEntry(from: row))
        }
        return renderState?.originalRow
    }

    var originalPost: TopicPostState? {
        if let originalRow {
            return resolvedPostLookup[originalRow.entry.postId]
        }
        return detail?.postStream.posts.min(by: { $0.postNumber < $1.postNumber })
    }

    var replyRows: [FirePreparedTopicTimelineRow] {
        if let snapshot {
            return snapshot.rows.filter { !$0.isOriginalPost }.map {
                FirePreparedTopicTimelineRow(entry: FireTopicDetailUiProjection.timelineEntry(from: $0))
            }
        }
        return renderState?.replyRows ?? []
    }

    var availableReplyRows: [FirePreparedTopicTimelineRow] {
        if snapshot != nil {
            return replyRows.filter { resolvedPostLookup[$0.entry.postId] != nil }
        }
        return replyRows.filter {
            postLookup[$0.entry.postId] != nil
                && renderState?.contentByPostID[$0.entry.postId] != nil
        }
    }

    var originalPostRenderContent: FireTopicPostRenderContent? {
        if let post = originalPost, snapshot != nil {
            return FireTopicPresentation.renderContent(from: post)
        }
        guard let originalRow else { return nil }
        return renderState?.contentByPostID[originalRow.entry.postId]
    }

    var canRenderOriginalPost: Bool {
        originalPost != nil && originalPostRenderContent != nil
    }

    var isWaitingForPostRender: Bool {
        let hasSource = snapshot?.phase == .ready || detail != nil
        return hasSource && !canRenderOriginalPost
    }

    var replyFooterState: FireTopicDetailRuntimeReplyFooterState {
        guard snapshot != nil || detail != nil else {
            return .none
        }
        if let loadMoreTopicPostsError,
           !loadMoreTopicPostsError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .loadFailed(loadMoreTopicPostsError)
        }
        if isLoadingMoreTopicPosts {
            return .loadingFooter
        }
        if hasMoreTopicPosts {
            return .loadMoreAvailable
        }
        if totalReplyCount == 0 {
            return .emptyPrompt
        }
        if availableReplyRows.isEmpty {
            return .none
        }
        return .endReached
    }


    func postContext(for item: FireTopicDetailRuntimeItem) -> FireTopicDetailRuntimePostContext? {
        switch item.kind {
        case .originalPost:
            guard let post = originalPost,
                  let renderContent = originalPostRenderContent else {
                return nil
            }
            return FireTopicDetailRuntimePostContext(
                post: post,
                renderContent: renderContent,
                depth: 0,
                replyContext: nil,
                replyTargetPostNumber: nil,
                showsThreadLine: false,
                showsDivider: false,
                replyShortcutCount: nil,
                isReplyThreadExpanded: false,
                isLoadingReplyContext: false,
                textExpansionState: .disabled,
                // OP also exposes reply / react / boost primary actions.
                allowsInlineOverflowActions: true
            )

        case .reply:
            // The feed item carries its reply index; keep the bounds checks here so stale items cannot index the filtered reply list.
            guard let postID = item.postID,
                  let post = postLookup[postID],
                  let renderContent = renderState?.contentByPostID[postID],
                  let index = item.replyIndex,
                  index >= 0,
                  index < availableReplyRows.count,
                  availableReplyRows[index].entry.postId == postID else {
                return nil
            }
            let row = availableReplyRows[index]
            return FireTopicDetailRuntimePostContext(
                post: post,
                renderContent: renderContent,
                depth: Self.displayDepth(for: row),
                replyContext: FireTopicPresentation.replyContextLabel(
                    for: post,
                    preferredPostNumber: row.entry.parentPostNumber
                ),
                replyTargetPostNumber: FireTopicPresentation.replyTargetPostNumber(
                    for: post,
                    preferredPostNumber: row.entry.parentPostNumber
                ),
                showsThreadLine: item.replyShowsThreadLine,
                showsDivider: item.replyShowsDivider,
                replyShortcutCount: item.replyShortcutCount,
                isReplyThreadExpanded: item.isReplyThreadExpanded,
                isLoadingReplyContext: isLoadingPostReplyContext(post.id),
                textExpansionState: FirePostTextExpansionState(
                    isCollapsible: true,
                    isExpanded: isPostTextExpanded(post.id)
                ),
                allowsInlineOverflowActions: true
            )

        default:
            return nil
        }
    }

    func scrollItem(for postNumber: UInt32) -> FireTopicDetailRuntimeItem? {
        makeSnapshot().items.first { $0.postNumber == postNumber }
    }
}

enum FireTopicDetailRuntimeReplyFooterState: Equatable {
    case none
    case loadMoreAvailable
    case loadingFooter
    case loadFailed(String)
    case endReached
    case emptyPrompt

    private static let loadFailedPrefix = "loadFailed\u{1F}"

    var contentToken: String {
        switch self {
        case .none:
            return "none"
        case .loadMoreAvailable:
            return "loadMoreAvailable"
        case .loadingFooter:
            return "loadingFooter"
        case let .loadFailed(message):
            return Self.loadFailedPrefix + message
        case .endReached:
            return "endReached"
        case .emptyPrompt:
            return "emptyPrompt"
        }
    }

    var identityToken: String {
        switch self {
        case .none:
            return "none"
        case .loadMoreAvailable:
            return "loadMoreAvailable"
        case .loadingFooter:
            return "loadingFooter"
        case .loadFailed:
            return "loadFailed"
        case .endReached:
            return "endReached"
        case .emptyPrompt:
            return "emptyPrompt"
        }
    }

    static func fromContentToken(_ token: String) -> Self? {
        switch token {
        case Self.none.contentToken:
            return FireTopicDetailRuntimeReplyFooterState.none
        case Self.loadMoreAvailable.contentToken:
            return .loadMoreAvailable
        case Self.loadingFooter.contentToken:
            return .loadingFooter
        case Self.endReached.contentToken:
            return .endReached
        case Self.emptyPrompt.contentToken:
            return .emptyPrompt
        default:
            guard token.hasPrefix(Self.loadFailedPrefix) else {
                return nil
            }
            return .loadFailed(String(token.dropFirst(Self.loadFailedPrefix.count)))
        }
    }
}
