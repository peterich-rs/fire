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
    let contentToken: AnyHashable
    let inPlaceUpdateToken: AnyHashable?
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
        contentToken: AnyHashable,
        inPlaceUpdateToken: AnyHashable? = nil,
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
        self.contentToken = contentToken
        self.inPlaceUpdateToken = inPlaceUpdateToken
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
            && contentToken == other.contentToken
            && statusMessage == other.statusMessage
    }

    func needsVisibleNodeUpdate(comparedTo other: Self) -> Bool {
        hasSameRenderedContent(as: other)
            && inPlaceUpdateToken != other.inPlaceUpdateToken
    }
}

struct FireTopicDetailRuntimeSnapshot {
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
    let isLoadingReplyContext: Bool
    let replyContextError: String?
    let textExpansionState: FirePostTextExpansionState
}

private struct FireTopicDetailReplyDisplayPlan {
    struct DisplayedRow {
        let row: FirePreparedTopicTimelineRow
        let sourceIndex: Int
        let showsThreadLine: Bool
        let showsDivider: Bool
        let replyShortcutCount: UInt32?
    }

    let rows: [DisplayedRow]
    let sourceIndexByPostID: [UInt64: Int]
}

private struct FireTopicDetailReplyThreadIndex {
    let rootIndexBySourceIndex: [Int: Int]
    let secondaryIndicesByRoot: [Int: [Int]]
}

enum FireTopicDetailReplyContextLoadPolicy {
    static func shouldLoadReplyContext(
        for post: TopicPostState,
        replyRows: [FirePreparedTopicTimelineRow],
        postLookup: [UInt64: TopicPostState]
    ) -> Bool {
        let declaredReplyCount = Int(post.replyCount)
        guard declaredReplyCount > 0 else {
            return false
        }
        return loadedSecondaryReplyCount(
            rootPostNumber: post.postNumber,
            replyRows: replyRows,
            postLookup: postLookup
        ) < declaredReplyCount
    }

    static func loadedSecondaryReplyCount(
        rootPostNumber: UInt32,
        replyRows: [FirePreparedTopicTimelineRow],
        postLookup: [UInt64: TopicPostState]
    ) -> Int {
        var rowByPostNumber: [UInt32: FirePreparedTopicTimelineRow] = [:]
        rowByPostNumber.reserveCapacity(replyRows.count)
        for row in replyRows where postLookup[row.entry.postId] != nil {
            rowByPostNumber[row.entry.postNumber] = row
        }

        func resolvesToRoot(_ row: FirePreparedTopicTimelineRow, visiting: inout Set<UInt32>) -> Bool {
            guard row.entry.postNumber != rootPostNumber else {
                return false
            }
            guard visiting.insert(row.entry.postNumber).inserted else {
                return false
            }
            guard let parentPostNumber = row.entry.parentPostNumber else {
                return false
            }
            if parentPostNumber == rootPostNumber {
                return true
            }
            guard let parentRow = rowByPostNumber[parentPostNumber] else {
                return false
            }
            return resolvesToRoot(parentRow, visiting: &visiting)
        }

        return replyRows.reduce(0) { partial, row in
            guard postLookup[row.entry.postId] != nil else {
                return partial
            }
            var visiting = Set<UInt32>()
            return partial + (resolvesToRoot(row, visiting: &visiting) ? 1 : 0)
        }
    }
}

final class FireTopicDetailRuntimeInteractions {
    let isMutatingPost: (UInt64) -> Bool
    let isPostTextExpanded: (UInt64) -> Bool
    let isReplyThreadExpanded: (UInt64) -> Bool
    let isLoadingPostReplyContext: (UInt64) -> Bool
    let postReplyContextError: (UInt64) -> String?
    let onVisiblePostNumbersChanged: (Set<UInt32>) -> Void
    let onRefresh: () async -> Void
    let onLoadTopicDetail: () async -> Void
    let onScrollTargetHandled: (UInt32) -> Void
    let onLoadMoreTopicPosts: () -> Bool
    let onReloadTopicAiSummary: () -> Void
    let onOpenComposer: (TopicPostState?) -> Void
    let onOpenPostNumber: (UInt32) -> Void
    let onOpenPostReplies: (TopicPostState) -> Void
    let onLinkTapped: (URL) -> Void
    let onOpenProfile: (String) -> Void
    let onOpenImage: (FireCookedImage) -> Void
    let onToggleLike: (TopicPostState) -> Void
    let onSelectReaction: (TopicPostState, String) -> Void
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
        postReplyContextError: @escaping (UInt64) -> String?,
        onVisiblePostNumbersChanged: @escaping (Set<UInt32>) -> Void,
        onRefresh: @escaping () async -> Void,
        onLoadTopicDetail: @escaping () async -> Void,
        onScrollTargetHandled: @escaping (UInt32) -> Void,
        onLoadMoreTopicPosts: @escaping () -> Bool,
        onReloadTopicAiSummary: @escaping () -> Void,
        onOpenComposer: @escaping (TopicPostState?) -> Void,
        onOpenPostNumber: @escaping (UInt32) -> Void,
        onOpenPostReplies: @escaping (TopicPostState) -> Void,
        onLinkTapped: @escaping (URL) -> Void,
        onOpenProfile: @escaping (String) -> Void,
        onOpenImage: @escaping (FireCookedImage) -> Void,
        onToggleLike: @escaping (TopicPostState) -> Void,
        onSelectReaction: @escaping (TopicPostState, String) -> Void,
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
        self.postReplyContextError = postReplyContextError
        self.onVisiblePostNumbersChanged = onVisiblePostNumbersChanged
        self.onRefresh = onRefresh
        self.onLoadTopicDetail = onLoadTopicDetail
        self.onScrollTargetHandled = onScrollTargetHandled
        self.onLoadMoreTopicPosts = onLoadMoreTopicPosts
        self.onReloadTopicAiSummary = onReloadTopicAiSummary
        self.onOpenComposer = onOpenComposer
        self.onOpenPostNumber = onOpenPostNumber
        self.onOpenPostReplies = onOpenPostReplies
        self.onLinkTapped = onLinkTapped
        self.onOpenProfile = onOpenProfile
        self.onOpenImage = onOpenImage
        self.onToggleLike = onToggleLike
        self.onSelectReaction = onSelectReaction
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
    let topicCollectionRevision: UInt64
    let canWriteInteractions: Bool
    let postLookup: [UInt64: TopicPostState]
    let interactionState: FireTopicDetailInteractionState
    let snapshotInvalidationToken: AnyHashable
    let interactions: FireTopicDetailRuntimeInteractions

    var isMutatingPost: (UInt64) -> Bool { interactionState.isMutatingPost }
    var isPostTextExpanded: (UInt64) -> Bool { interactionState.isPostTextExpanded }
    var isReplyThreadExpanded: (UInt64) -> Bool { interactionState.isReplyThreadExpanded }
    var isLoadingPostReplyContext: (UInt64) -> Bool { interactionState.isLoadingPostReplyContext }
    var postReplyContextError: (UInt64) -> String? { interactionState.postReplyContextError }
    var onVisiblePostNumbersChanged: (Set<UInt32>) -> Void { interactions.onVisiblePostNumbersChanged }
    var onRefresh: () async -> Void { interactions.onRefresh }
    var onLoadTopicDetail: () async -> Void { interactions.onLoadTopicDetail }
    var onScrollTargetHandled: (UInt32) -> Void { interactions.onScrollTargetHandled }
    var onLoadMoreTopicPosts: () -> Bool { interactions.onLoadMoreTopicPosts }
    var onReloadTopicAiSummary: () -> Void { interactions.onReloadTopicAiSummary }
    var onOpenComposer: (TopicPostState?) -> Void { interactions.onOpenComposer }
    var onOpenPostNumber: (UInt32) -> Void { interactions.onOpenPostNumber }
    var onOpenPostReplies: (TopicPostState) -> Void { interactions.onOpenPostReplies }
    var onLinkTapped: (URL) -> Void { interactions.onLinkTapped }
    var onOpenProfile: (String) -> Void { interactions.onOpenProfile }
    var onOpenImage: (FireCookedImage) -> Void { interactions.onOpenImage }
    var onToggleLike: (TopicPostState) -> Void { interactions.onToggleLike }
    var onSelectReaction: (TopicPostState, String) -> Void { interactions.onSelectReaction }
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
        let trimmedDetailTitle = detail?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedDetailTitle.isEmpty {
            return trimmedDetailTitle
        }
        let trimmedRowTitle = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedRowTitle.isEmpty ? "话题 \(topic.id)" : trimmedRowTitle
    }

    var displayedReplyCount: UInt32 {
        if let detail {
            return detail.replyCount
        }
        return topic.replyCount
    }

    var displayedViewsCount: UInt32 {
        detail?.views ?? topic.views
    }

    var displayedCategoryId: UInt64? {
        detail?.categoryId ?? topic.categoryId
    }

    var displayedTagNames: [String] {
        let detailTags = detail?.tags
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        return detailTags.isEmpty ? row.tagNames : detailTags
    }

    var isPrivateMessageThread: Bool {
        FireTopicPresentation.isPrivateMessageArchetype(detail?.archetype)
    }

    var displayedParticipants: [TopicParticipantState] {
        guard isPrivateMessageThread else {
            return []
        }

        let source = !(detail?.details.participants.isEmpty ?? true)
            ? detail?.details.participants ?? []
            : topic.participants
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
        detail.map(FireTopicPresentation.interactionCount(for:))
    }

    var loadedReplyCount: Int {
        availableReplyRows.count
    }

    var displayedFloorCount: Int {
        availableReplyRows.count
    }

    var totalReplyCount: Int {
        detail.map { Int($0.replyCount) } ?? Int(topic.replyCount)
    }

    var showsTopicVote: Bool {
        guard let detail, !isPrivateMessageThread else {
            return false
        }
        return detail.canVote || detail.userVoted || detail.voteCount > 0
    }

    var originalRow: FirePreparedTopicTimelineRow? {
        renderState?.originalRow
    }

    var originalPost: TopicPostState? {
        if let originalRow {
            return postLookup[originalRow.entry.postId]
        }
        return detail?.postStream.posts.min(by: { $0.postNumber < $1.postNumber })
    }

    var replyRows: [FirePreparedTopicTimelineRow] {
        renderState?.replyRows ?? []
    }

    private var availableReplyRows: [FirePreparedTopicTimelineRow] {
        // The feed only renders replies whose backing post entity is present.
        // This keeps transient store/render-state skew from producing placeholder rows.
        replyRows.filter { postLookup[$0.entry.postId] != nil }
    }

    var originalPostRenderContent: FireTopicPostRenderContent? {
        guard let originalRow else { return nil }
        return renderState?.contentByPostID[originalRow.entry.postId]
    }

    var replyFooterState: FireTopicDetailRuntimeReplyFooterState {
        guard detail != nil else {
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

    func makeSnapshot() -> FireTopicDetailRuntimeSnapshot {
        var items: [FireTopicDetailRuntimeItem] = []
        let replyDisplayPlan = makeReplyDisplayPlan()
        let replyIndexByPostID = replyDisplayPlan.sourceIndexByPostID
        let currentReplyFooterState = replyFooterState

        items.append(.init(
            id: "header:\(topic.id)",
            kind: .header,
            postID: nil,
            postNumber: nil,
            replyIndex: nil,
            contentToken: AnyHashable([
                displayedTopicTitle,
                displayedCategory.map { "\($0.id)|\($0.slug)|\($0.displayName)|\($0.colorHex ?? "")" } ?? "",
                displayedTagNames.joined(separator: ","),
                displayedParticipants.map {
                    "\($0.userId)|\($0.username ?? "")|\($0.name ?? "")"
                }.joined(separator: ";"),
                row.statusLabels.joined(separator: ","),
                String(isPrivateMessageThread),
            ])
        ))

        if topicAiSummary != nil || isLoadingTopicAiSummary || topicAiSummaryError != nil {
            items.append(.init(
                id: "ai-summary:\(topic.id)",
                kind: .aiSummary,
                postID: nil,
                postNumber: nil,
                replyIndex: nil,
                contentToken: AnyHashable([
                    topicAiSummary.map(Self.topicAiSummaryContentToken(_:)) ?? "",
                    String(isLoadingTopicAiSummary),
                    topicAiSummaryError ?? "",
                ])
            ))
        }

        items.append(.init(
            id: "original:\(topic.id)",
            kind: .originalPost,
            postID: originalPost?.id,
            postNumber: originalPost?.postNumber,
            replyIndex: nil,
            contentToken: AnyHashable(
                originalPost.map {
                    postLayoutContentToken(
                        $0,
                        renderContent: originalPostRenderContent,
                        replyShortcutCount: nil,
                        textExpansionState: .disabled
                    )
                } ?? "missing"
            ),
            inPlaceUpdateToken: AnyHashable(
                originalPost.map {
                    postContentToken(
                        $0,
                        renderContent: originalPostRenderContent,
                        replyContext: nil,
                        replyTargetPostNumber: nil,
                        isLoadingReplyContext: false,
                        replyContextError: nil,
                        textExpansionState: .disabled
                    )
                } ?? "missing"
            )
        ))

        items.append(.init(
            id: "stats:\(topic.id)",
            kind: .stats,
            postID: nil,
            postNumber: nil,
            replyIndex: nil,
            contentToken: AnyHashable([
                String(displayedReplyCount),
                String(displayedViewsCount),
                displayedInteractionCount.map(String.init) ?? "",
            ])
        ))

        if showsTopicVote {
            items.append(.init(
                id: "topic-vote:\(topic.id)",
                kind: .topicVote,
                postID: nil,
                postNumber: nil,
                replyIndex: nil,
                contentToken: AnyHashable([
                    String(detail?.canVote ?? false),
                    String(detail?.userVoted ?? false),
                    String(detail?.voteCount ?? 0),
                    String(canWriteInteractions),
                ])
            ))
        }

        items.append(.init(
            id: "replies-header:\(topic.id)",
            kind: .repliesHeader,
            postID: nil,
            postNumber: nil,
            replyIndex: nil,
            contentToken: AnyHashable([
                String(loadedReplyCount),
                String(totalReplyCount),
                String(displayedFloorCount),
                String(detail != nil),
            ])
        ))

        if let detailNotice {
            items.append(.init(
                id: "notice:\(topic.id)",
                kind: .notice,
                postID: nil,
                postNumber: nil,
                replyIndex: nil,
                contentToken: AnyHashable([
                    detailNotice.title ?? "",
                    detailNotice.message,
                    String(detailNotice.retryable),
                    String(detailNotice.emphasizesError),
                ]),
                statusMessage: detailNotice
            ))
        }

        if detail == nil {
            items.append(.init(
                id: "body-state:\(topic.id)",
                kind: .bodyState,
                postID: nil,
                postNumber: nil,
                replyIndex: nil,
                contentToken: AnyHashable("\(isLoadingTopic)|\(detailError ?? "")")
            ))
        } else {
            for displayedRow in replyDisplayPlan.rows {
                let row = displayedRow.row
                let post = postLookup[row.entry.postId]
                let renderContent = renderState?.contentByPostID[row.entry.postId]
                let replyContext = post.map {
                    FireTopicPresentation.replyContextLabel(
                        for: $0,
                        preferredPostNumber: row.entry.parentPostNumber
                    )
                } ?? nil
                let replyTargetPostNumber = post.map {
                    FireTopicPresentation.replyTargetPostNumber(
                        for: $0,
                        preferredPostNumber: row.entry.parentPostNumber
                    )
                } ?? nil
                let textExpansionState = post.map {
                    FirePostTextExpansionState(
                        isCollapsible: true,
                        isExpanded: isPostTextExpanded($0.id)
                    )
                } ?? .disabled
                let isLoadingReplyContext = post.map { isLoadingPostReplyContext($0.id) } ?? false
                items.append(.init(
                    id: "reply:\(row.entry.postId):\(row.entry.postNumber)",
                    kind: .reply,
                    postID: row.entry.postId,
                    postNumber: row.entry.postNumber,
                    replyIndex: displayedRow.sourceIndex,
                    replyShowsThreadLine: displayedRow.showsThreadLine,
                    replyShowsDivider: displayedRow.showsDivider,
                    replyShortcutCount: displayedRow.replyShortcutCount,
                    contentToken: AnyHashable([
                        String(displayedRow.sourceIndex),
                        post.map {
                            postLayoutContentToken(
                                $0,
                                renderContent: renderContent,
                                replyShortcutCount: displayedRow.replyShortcutCount,
                                textExpansionState: textExpansionState
                            )
                        } ?? "missing",
                        String(displayedRow.showsThreadLine),
                        String(displayedRow.showsDivider),
                    ].joined(separator: "\u{1F}")),
                    inPlaceUpdateToken: AnyHashable(
                        post.map {
                            postContentToken(
                                $0,
                                renderContent: renderContent,
                                replyContext: replyContext,
                                replyTargetPostNumber: replyTargetPostNumber,
                                isLoadingReplyContext: isLoadingReplyContext,
                                replyContextError: post.map { postReplyContextError($0.id) } ?? nil,
                                textExpansionState: textExpansionState
                            )
                        } ?? "missing"
                    )
                ))
            }

            if currentReplyFooterState != .none {
                items.append(.init(
                    id: "reply-footer:\(topic.id):\(currentReplyFooterState.identityToken)",
                    kind: .replyFooter,
                    postID: nil,
                    postNumber: nil,
                    replyIndex: nil,
                    contentToken: AnyHashable(currentReplyFooterState.contentToken)
                ))
            }
        }

        return FireTopicDetailRuntimeSnapshot(items: items, replyIndexByPostID: replyIndexByPostID)
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
                isLoadingReplyContext: false,
                replyContextError: nil,
                textExpansionState: .disabled
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
                isLoadingReplyContext: isLoadingPostReplyContext(post.id),
                replyContextError: postReplyContextError(post.id),
                textExpansionState: FirePostTextExpansionState(
                    isCollapsible: true,
                    isExpanded: isPostTextExpanded(post.id)
                )
            )

        default:
            return nil
        }
    }

    func scrollItem(for postNumber: UInt32) -> FireTopicDetailRuntimeItem? {
        makeSnapshot().items.first { $0.postNumber == postNumber }
    }

    private func makeReplyDisplayPlan() -> FireTopicDetailReplyDisplayPlan {
        var sourceIndexByPostID: [UInt64: Int] = [:]
        sourceIndexByPostID.reserveCapacity(availableReplyRows.count)
        for (index, row) in availableReplyRows.enumerated() {
            sourceIndexByPostID[row.entry.postId] = index
        }

        let threadIndex = makeReplyThreadIndex()
        let rootIndices = threadIndex.rootIndexBySourceIndex
            .compactMap { sourceIndex, rootIndex in sourceIndex == rootIndex ? rootIndex : nil }
            .sorted()
        let secondaryIndicesByRoot = threadIndex.secondaryIndicesByRoot

        var displayedRows: [FireTopicDetailReplyDisplayPlan.DisplayedRow] = []
        displayedRows.reserveCapacity(replyRows.count)

        for rootIndex in rootIndices {
            guard rootIndex >= 0, rootIndex < availableReplyRows.count else {
                continue
            }

            let rootRow = availableReplyRows[rootIndex]
            let secondaryIndices = secondaryIndicesByRoot[rootIndex] ?? []
            let selectedSecondaryIndices = isReplyThreadExpanded(rootRow.entry.postId)
                ? secondaryIndices
                : selectedAnchoredSecondaryIndices(from: secondaryIndices)
            let declaredReplyCount = postLookup[rootRow.entry.postId].map { Int($0.replyCount) } ?? 0
            let totalSecondaryCount = max(secondaryIndices.count, declaredReplyCount)
            let hiddenCount = max(totalSecondaryCount - selectedSecondaryIndices.count, 0)

            displayedRows.append(.init(
                row: rootRow,
                sourceIndex: rootIndex,
                showsThreadLine: false,
                showsDivider: true,
                replyShortcutCount: hiddenCount > 0 ? UInt32(clamping: hiddenCount) : nil
            ))

            for secondaryIndex in selectedSecondaryIndices {
                guard secondaryIndex >= 0, secondaryIndex < availableReplyRows.count else {
                    continue
                }
                displayedRows.append(.init(
                    row: availableReplyRows[secondaryIndex],
                    sourceIndex: secondaryIndex,
                    showsThreadLine: false,
                    showsDivider: true,
                    replyShortcutCount: nil
                ))
            }
        }

        if !displayedRows.isEmpty {
            let lastIndex = displayedRows.count - 1
            displayedRows[lastIndex] = .init(
                row: displayedRows[lastIndex].row,
                sourceIndex: displayedRows[lastIndex].sourceIndex,
                showsThreadLine: displayedRows[lastIndex].showsThreadLine,
                showsDivider: false,
                replyShortcutCount: displayedRows[lastIndex].replyShortcutCount
            )
        }

        return FireTopicDetailReplyDisplayPlan(
            rows: displayedRows,
            sourceIndexByPostID: sourceIndexByPostID
        )
    }

    private func makeReplyThreadIndex() -> FireTopicDetailReplyThreadIndex {
        var indexByPostNumber: [UInt32: Int] = [:]
        indexByPostNumber.reserveCapacity(availableReplyRows.count)
        for (index, row) in availableReplyRows.enumerated() {
            indexByPostNumber[row.entry.postNumber] = index
        }

        var memoizedRootIndexBySourceIndex: [Int: Int] = [:]
        memoizedRootIndexBySourceIndex.reserveCapacity(availableReplyRows.count)

        func rootIndex(for sourceIndex: Int, visiting: inout Set<Int>) -> Int {
            if let cached = memoizedRootIndexBySourceIndex[sourceIndex] {
                return cached
            }
            guard sourceIndex >= 0, sourceIndex < availableReplyRows.count else {
                return sourceIndex
            }
            guard visiting.insert(sourceIndex).inserted else {
                memoizedRootIndexBySourceIndex[sourceIndex] = sourceIndex
                return sourceIndex
            }

            let row = availableReplyRows[sourceIndex]
            let resolvedRootIndex: Int
            if row.entry.depth <= 1 {
                resolvedRootIndex = sourceIndex
            } else if let parentPostNumber = row.entry.parentPostNumber,
                      let parentIndex = indexByPostNumber[parentPostNumber],
                      parentIndex != sourceIndex {
                resolvedRootIndex = rootIndex(for: parentIndex, visiting: &visiting)
            } else {
                resolvedRootIndex = sourceIndex
            }

            visiting.remove(sourceIndex)
            memoizedRootIndexBySourceIndex[sourceIndex] = resolvedRootIndex
            return resolvedRootIndex
        }

        for index in availableReplyRows.indices {
            var visiting = Set<Int>()
            _ = rootIndex(for: index, visiting: &visiting)
        }

        var secondaryIndicesByRoot: [Int: [Int]] = [:]
        for index in availableReplyRows.indices {
            guard let rootIndex = memoizedRootIndexBySourceIndex[index],
                  rootIndex != index else {
                continue
            }
            secondaryIndicesByRoot[rootIndex, default: []].append(index)
        }

        for rootIndex in secondaryIndicesByRoot.keys {
            secondaryIndicesByRoot[rootIndex]?.sort()
        }

        return FireTopicDetailReplyThreadIndex(
            rootIndexBySourceIndex: memoizedRootIndexBySourceIndex,
            secondaryIndicesByRoot: secondaryIndicesByRoot
        )
    }

    private func selectedAnchoredSecondaryIndices(from indices: [Int]) -> [Int] {
        guard let pendingScrollTarget,
              !indices.isEmpty else {
            return []
        }

        let indexSet = Set(indices)
        var indexByPostNumber: [UInt32: Int] = [:]
        indexByPostNumber.reserveCapacity(availableReplyRows.count)
        for (index, row) in availableReplyRows.enumerated()
        where indexByPostNumber[row.entry.postNumber] == nil {
            indexByPostNumber[row.entry.postNumber] = index
        }
        guard var currentIndex = indices.first(where: { index in
            availableReplyRows[index].entry.postNumber == pendingScrollTarget
        }) else {
            return []
        }

        var selected = Set<Int>()
        while indexSet.contains(currentIndex),
              selected.insert(currentIndex).inserted {
            guard let parentPostNumber = availableReplyRows[currentIndex].entry.parentPostNumber,
                  let parentIndex = indexByPostNumber[parentPostNumber],
                  indexSet.contains(parentIndex) else {
                break
            }
            currentIndex = parentIndex
        }

        return selected.sorted()
    }

    private static func displayDepth(for row: FirePreparedTopicTimelineRow) -> Int {
        Int(row.entry.depth)
    }

    private func postLayoutContentToken(
        _ post: TopicPostState,
        renderContent: FireTopicPostRenderContent?,
        replyShortcutCount: UInt32?,
        textExpansionState: FirePostTextExpansionState
    ) -> String {
        [
            String(post.id),
            FirePostAuthorMetadataDisplay.contentToken(for: post),
            renderContent?.signature.token ?? "pending",
            Self.pollsContentToken(post.polls),
            FirePostBoostDisplay.contentToken(for: post.boosts),
            String(!post.reactions.isEmpty),
            String(replyShortcutCount != nil),
            String(textExpansionState.isExpanded),
            String(textExpansionState.isCollapsible),
        ].joined(separator: "\u{1F}")
    }

    private func postContentToken(
        _ post: TopicPostState,
        renderContent: FireTopicPostRenderContent?,
        replyContext: String?,
        replyTargetPostNumber: UInt32?,
        isLoadingReplyContext: Bool,
        replyContextError: String?,
        textExpansionState: FirePostTextExpansionState
    ) -> String {
        var parts: [String] = []
        parts.reserveCapacity(30)
        parts.append(String(post.id))
        parts.append(String(post.postNumber))
        parts.append(post.username)
        parts.append(FirePostAuthorMetadataDisplay.contentToken(for: post))
        parts.append(post.avatarTemplate ?? "")
        parts.append(post.createdAt ?? "")
        parts.append(post.updatedAt ?? "")
        parts.append(renderContent?.signature.token ?? "pending")
        parts.append(replyContext ?? "")
        parts.append(replyTargetPostNumber.map(String.init) ?? "")
        parts.append(String(post.likeCount))
        parts.append(String(post.replyCount))
        parts.append(Self.reactionsContentToken(post.reactions))
        parts.append(post.currentUserReaction?.id ?? "")
        parts.append(Self.pollsContentToken(post.polls))
        parts.append(FirePostBoostDisplay.contentToken(for: post.boosts))
        parts.append(String(post.acceptedAnswer))
        parts.append(String(post.canEdit))
        parts.append(String(post.canDelete))
        parts.append(String(post.canRecover))
        parts.append(String(post.hidden))
        parts.append(String(post.bookmarked))
        parts.append(String(post.bookmarkId ?? 0))
        parts.append(post.bookmarkName ?? "")
        parts.append(post.bookmarkReminderAt ?? "")
        parts.append(String(isLoadingReplyContext))
        parts.append(replyContextError ?? "")
        parts.append(String(textExpansionState.isExpanded))
        parts.append(String(textExpansionState.isCollapsible))
        parts.append(String(canWriteInteractions))
        parts.append(String(isMutatingPost(post.id)))
        return parts.joined(separator: "\u{1F}")
    }

    private static func reactionsContentToken(_ reactions: [TopicReactionState]) -> String {
        reactions.map { reaction in
            [
                reaction.id,
                reaction.kind ?? "",
                String(reaction.count),
                reaction.canUndo.map { String($0) } ?? "",
            ].joined(separator: "\u{1E}")
        }.joined(separator: "\u{1D}")
    }

    private static func pollsContentToken(_ polls: [PollState]) -> String {
        polls.map { poll in
            [
                String(poll.id),
                poll.name,
                poll.kind,
                poll.status,
                poll.results,
                String(poll.voters),
                poll.userVotes.joined(separator: "\u{1C}"),
                poll.options.map { option in
                    [
                        option.id,
                        option.html,
                        String(option.votes),
                    ].joined(separator: "\u{1B}")
                }.joined(separator: "\u{1A}"),
            ].joined(separator: "\u{1E}")
        }.joined(separator: "\u{1D}")
    }

    private static func topicAiSummaryContentToken(_ summary: TopicAiSummaryState) -> String {
        [
            summary.summarizedText,
            summary.algorithm ?? "",
            String(summary.outdated),
            String(summary.canRegenerate),
            String(summary.newPostsSinceSummary),
            summary.updatedAt ?? "",
        ].joined(separator: "\u{1F}")
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
