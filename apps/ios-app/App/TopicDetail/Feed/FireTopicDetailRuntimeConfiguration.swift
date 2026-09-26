import Foundation
import UIKit

struct FireTopicDetailRuntimeConfiguration: @unchecked Sendable {
    let viewModel: FireAppViewModel?
    let displayedCategory: FireTopicCategoryPresentation?
    let currentUsername: String?
    let row: FireTopicRowPresentation
    let baseURLString: String
    let snapshot: FireTopicDetailSnapshot?
    let rowsByPostID: [UInt64: TopicDetailUiRowState]
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
    var onAcceptSolution: (TopicPostState, Bool) -> Void { interactions.onAcceptSolution }
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
        postLookup
    }

    var originalRow: FirePreparedTopicTimelineRow? {
        renderState?.originalRow
    }

    var originalPost: TopicPostState? {
        if let originalRow {
            return resolvedPostLookup[originalRow.entry.postId]
        }
        return detail?.postStream.posts.min(by: { $0.postNumber < $1.postNumber })
    }

    var replyRows: [FirePreparedTopicTimelineRow] {
        renderState?.replyRows ?? []
    }

    var availableReplyRows: [FirePreparedTopicTimelineRow] {
        replyRows
    }

    var originalPostRenderContent: FireTopicPostRenderContent? {
        guard let originalRow else { return nil }
        return renderState?.contentByPostID[originalRow.entry.postId]
    }

    var canRenderOriginalPost: Bool {
        originalPost != nil && originalPostRenderContent != nil
    }

    /// Topic content is available from the Rust snapshot or the legacy detail object.
    var hasLoadedTopic: Bool {
        snapshot?.phase == .ready || detail != nil
    }

    var isWaitingForPostRender: Bool {
        hasLoadedTopic && !canRenderOriginalPost
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
            return originalPostContext()

        case .reply:
            // The feed item carries its reply index; keep the bounds checks here so stale items cannot index the filtered reply list.
            guard let postID = item.postID,
                  let post = resolvedPostLookup[postID],
                  let renderContent = renderState?.contentByPostID[postID],
                  let index = item.replyIndex,
                  index >= 0,
                  index < availableReplyRows.count,
                  availableReplyRows[index].entry.postId == postID else {
                return nil
            }
            return replyPostContext(
                post: post,
                renderContent: renderContent,
                row: availableReplyRows[index],
                showsThreadLine: item.replyShowsThreadLine,
                showsDivider: item.replyShowsDivider,
                replyShortcutCount: item.replyShortcutCount,
                isReplyThreadExpanded: item.isReplyThreadExpanded
            )

        default:
            return nil
        }
    }

    func originalPostContext() -> FireTopicDetailRuntimePostContext? {
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
    }

    func replyPostContext(
        post: TopicPostState,
        renderContent: FireTopicPostRenderContent,
        row: FirePreparedTopicTimelineRow,
        showsThreadLine: Bool,
        showsDivider: Bool,
        replyShortcutCount: UInt32?,
        isReplyThreadExpanded: Bool
    ) -> FireTopicDetailRuntimePostContext {
        FireTopicDetailRuntimePostContext(
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
            showsThreadLine: showsThreadLine,
            showsDivider: showsDivider,
            replyShortcutCount: replyShortcutCount,
            isReplyThreadExpanded: isReplyThreadExpanded,
            isLoadingReplyContext: isLoadingPostReplyContext(post.id),
            textExpansionState: FirePostTextExpansionState(
                isCollapsible: true,
                isExpanded: isPostTextExpanded(post.id)
            ),
            allowsInlineOverflowActions: true
        )
    }

    func scrollItem(for postNumber: UInt32) -> FireTopicDetailRuntimeItem? {
        makeSnapshot().items.first { $0.postNumber == postNumber }
    }
}
