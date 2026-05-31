import Foundation
import UIKit

enum FireTopicDetailRuntimeSection: Sendable {
    case main
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

    init(
        id: String,
        kind: FireTopicDetailRuntimeItemKind,
        postID: UInt64?,
        postNumber: UInt32?,
        replyIndex: Int?,
        replyShowsThreadLine: Bool = false,
        replyShowsDivider: Bool = false,
        replyShortcutCount: UInt32? = nil,
        contentToken: AnyHashable
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
    }

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

struct FireTopicDetailRuntimeConfiguration {
    let viewModel: FireAppViewModel?
    let displayedCategory: FireTopicCategoryPresentation?
    let currentUsername: String?
    let row: FireTopicRowPresentation
    let baseURLString: String
    let detail: TopicDetailState?
    let renderState: FireTopicDetailRenderState?
    let pendingScrollTarget: UInt32?
    let detailError: String?
    let hasMoreTopicPosts: Bool
    let isLoadingTopic: Bool
    let isLoadingMoreTopicPosts: Bool
    let topicAiSummary: TopicAiSummaryState?
    let isLoadingTopicAiSummary: Bool
    let topicAiSummaryError: String?
    let topicCollectionRevision: UInt64
    let canWriteInteractions: Bool
    let postLookup: [UInt64: TopicPostState]
    let snapshotInvalidationToken: AnyHashable
    let isMutatingPost: (UInt64) -> Bool
    let isPostTextExpanded: (UInt64) -> Bool
    let isReplyThreadExpanded: (UInt64) -> Bool
    let isLoadingPostReplyContext: (UInt64) -> Bool
    let onVisiblePostNumbersChanged: (Set<UInt32>) -> Void
    let onRefresh: () async -> Void
    let onLoadTopicDetail: () async -> Void
    let onScrollTargetHandled: (UInt32) -> Void
    let onPreloadTopicPosts: (Set<UInt32>) -> Void
    let onLoadMoreTopicPosts: () -> Void
    let onReloadTopicAiSummary: () -> Void
    let onOpenComposer: (TopicPostState?) -> Void
    let onOpenPostNumber: (UInt32) -> Void
    let onOpenPostReplies: (TopicPostState) -> Void
    let onLinkTapped: (URL) -> Void
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
            return max(detail.postsCount, 1) - 1
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
        replyRows.count
    }

    var displayedFloorCount: Int {
        replyRows.count
    }

    var totalReplyCount: Int {
        detail.map { max(Int($0.postsCount) - 1, 0) } ?? Int(topic.replyCount)
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

    var originalPostRenderContent: FireTopicPostRenderContent? {
        guard let originalRow else { return nil }
        return renderState?.contentByPostID[originalRow.entry.postId]
    }

    var replyFooterState: FireTopicDetailRuntimeReplyFooterState {
        guard detail != nil else {
            return .none
        }
        if replyRows.isEmpty {
            return hasMoreTopicPosts || isLoadingMoreTopicPosts ? .loadingFooter : .empty
        }
        if isLoadingMoreTopicPosts {
            return .loadingFooter
        }
        return .none
    }

    func makeSnapshot() -> FireTopicDetailRuntimeSnapshot {
        var items: [FireTopicDetailRuntimeItem] = []
        let replyDisplayPlan = makeReplyDisplayPlan()
        let replyIndexByPostID = replyDisplayPlan.sourceIndexByPostID

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
            contentToken: AnyHashable(originalPost.map { postContentToken($0, renderContent: originalPostRenderContent) } ?? "missing")
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
                let textExpansionToken = post.map { String(isPostTextExpanded($0.id)) } ?? "missing"
                let replyContextLoadingToken = post.map { String(isLoadingPostReplyContext($0.id)) } ?? "missing"
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
                        post.map { postContentToken($0, renderContent: renderContent) } ?? "missing",
                        String(displayedRow.showsThreadLine),
                        String(displayedRow.showsDivider),
                        displayedRow.replyShortcutCount.map(String.init) ?? "",
                        textExpansionToken,
                        replyContextLoadingToken,
                    ].joined(separator: "\u{1F}"))
                ))
            }

            if replyFooterState != .none {
                items.append(.init(
                    id: "reply-footer:\(topic.id)",
                    kind: .replyFooter,
                    postID: nil,
                    postNumber: nil,
                    replyIndex: nil,
                    contentToken: AnyHashable(replyFooterState.contentToken)
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
                showsDivider: true,
                replyShortcutCount: nil,
                isLoadingReplyContext: false,
                textExpansionState: .disabled
            )

        case .reply:
            // The runtime item carries its reply index; keep the bounds checks here so stale items cannot index replyRows.
            guard let postID = item.postID,
                  let post = postLookup[postID],
                  let index = item.replyIndex,
                  index >= 0,
                  index < replyRows.count,
                  replyRows[index].entry.postId == postID,
                  let renderContent = renderState?.contentByPostID[postID] else {
                return nil
            }
            let row = replyRows[index]
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
        sourceIndexByPostID.reserveCapacity(replyRows.count)
        for (index, row) in replyRows.enumerated() {
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
            guard rootIndex >= 0, rootIndex < replyRows.count else {
                continue
            }

            let rootRow = replyRows[rootIndex]
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
                guard secondaryIndex >= 0, secondaryIndex < replyRows.count else {
                    continue
                }
                displayedRows.append(.init(
                    row: replyRows[secondaryIndex],
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
        indexByPostNumber.reserveCapacity(replyRows.count)
        for (index, row) in replyRows.enumerated() {
            indexByPostNumber[row.entry.postNumber] = index
        }

        var memoizedRootIndexBySourceIndex: [Int: Int] = [:]
        memoizedRootIndexBySourceIndex.reserveCapacity(replyRows.count)

        func rootIndex(for sourceIndex: Int, visiting: inout Set<Int>) -> Int {
            if let cached = memoizedRootIndexBySourceIndex[sourceIndex] {
                return cached
            }
            guard sourceIndex >= 0, sourceIndex < replyRows.count else {
                return sourceIndex
            }
            guard visiting.insert(sourceIndex).inserted else {
                memoizedRootIndexBySourceIndex[sourceIndex] = sourceIndex
                return sourceIndex
            }

            let row = replyRows[sourceIndex]
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

        for index in replyRows.indices {
            var visiting = Set<Int>()
            _ = rootIndex(for: index, visiting: &visiting)
        }

        var secondaryIndicesByRoot: [Int: [Int]] = [:]
        for index in replyRows.indices {
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
        indexByPostNumber.reserveCapacity(replyRows.count)
        for (index, row) in replyRows.enumerated() where indexByPostNumber[row.entry.postNumber] == nil {
            indexByPostNumber[row.entry.postNumber] = index
        }
        guard var currentIndex = indices.first(where: { index in
            replyRows[index].entry.postNumber == pendingScrollTarget
        }) else {
            return []
        }

        var selected = Set<Int>()
        while indexSet.contains(currentIndex),
              selected.insert(currentIndex).inserted {
            guard let parentPostNumber = replyRows[currentIndex].entry.parentPostNumber,
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

    private func postContentToken(
        _ post: TopicPostState,
        renderContent: FireTopicPostRenderContent?
    ) -> String {
        var parts: [String] = []
        parts.reserveCapacity(23)
        parts.append(String(post.id))
        parts.append(String(post.postNumber))
        parts.append(post.username)
        parts.append(post.avatarTemplate ?? "")
        parts.append(post.createdAt ?? "")
        parts.append(post.updatedAt ?? "")
        parts.append(renderContent?.signature.token ?? "pending")
        parts.append(String(post.likeCount))
        parts.append(String(post.replyCount))
        parts.append(Self.reactionsContentToken(post.reactions))
        parts.append(post.currentUserReaction?.id ?? "")
        parts.append(Self.pollsContentToken(post.polls))
        parts.append(String(post.acceptedAnswer))
        parts.append(String(post.canEdit))
        parts.append(String(post.canDelete))
        parts.append(String(post.canRecover))
        parts.append(String(post.hidden))
        parts.append(String(post.bookmarked))
        parts.append(String(post.bookmarkId ?? 0))
        parts.append(post.bookmarkName ?? "")
        parts.append(post.bookmarkReminderAt ?? "")
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

    private func showsTimelineThreadLine(at index: Int) -> Bool {
        guard index >= 0, index < replyRows.count - 1 else {
            return false
        }
        return replyRows[index + 1].entry.depth >= replyRows[index].entry.depth
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
    case loadMore
    case loadingFooter
    case empty

    var contentToken: String {
        switch self {
        case .none:
            return "none"
        case .loadMore:
            return "loadMore"
        case .loadingFooter:
            return "loadingFooter"
        case .empty:
            return "empty"
        }
    }
}
