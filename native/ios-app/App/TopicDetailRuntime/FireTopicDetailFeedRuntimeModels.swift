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
    let contentToken: AnyHashable

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
    let isMutatingPost: (UInt64) -> Bool
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
            return hasMoreTopicPosts ? .loadingFooter : .empty
        }
        return isLoadingMoreTopicPosts ? .loadingFooter : .none
    }

    func fallbackRenderContent(for post: TopicPostState) -> FireTopicPostRenderContent {
        let plainText = post.raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FireTopicPostRenderContent(
            plainText: plainText.isEmpty ? "加载中…" : plainText,
            attributedText: nil,
            imageAttachments: [],
            signature: FireTopicPostRenderSignature.make(
                source: plainText.isEmpty ? "加载中…" : plainText,
                imageAttachments: []
            )
        )
    }

    func makeSnapshot() -> FireTopicDetailRuntimeSnapshot {
        var items: [FireTopicDetailRuntimeItem] = []
        var replyIndexByPostID: [UInt64: Int] = [:]
        for (index, row) in replyRows.enumerated() {
            replyIndexByPostID[row.entry.postId] = index
        }

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
            for (index, row) in replyRows.enumerated() {
                let post = postLookup[row.entry.postId]
                let renderContent = renderState?.contentByPostID[row.entry.postId]
                items.append(.init(
                    id: "reply:\(row.entry.postId):\(row.entry.postNumber)",
                    kind: .reply,
                    postID: row.entry.postId,
                    postNumber: row.entry.postNumber,
                    replyIndex: index,
                    contentToken: AnyHashable("\(index)|\(post.map { postContentToken($0, renderContent: renderContent) } ?? "missing")")
                ))
            }

            if replyFooterState != .none {
                items.append(.init(
                    id: "reply-footer:\(topic.id)",
                    kind: .replyFooter,
                    postID: nil,
                    postNumber: nil,
                    replyIndex: nil,
                    contentToken: AnyHashable("\(String(reflecting: replyFooterState))")
                ))
            }
        }

        return FireTopicDetailRuntimeSnapshot(items: items, replyIndexByPostID: replyIndexByPostID)
    }

    func postContext(for item: FireTopicDetailRuntimeItem) -> FireTopicDetailRuntimePostContext? {
        switch item.kind {
        case .originalPost:
            guard let post = originalPost else { return nil }
            return FireTopicDetailRuntimePostContext(
                post: post,
                renderContent: originalPostRenderContent ?? fallbackRenderContent(for: post),
                depth: 0,
                replyContext: nil,
                replyTargetPostNumber: nil,
                showsThreadLine: false,
                showsDivider: true
            )

        case .reply:
            // The runtime item carries its reply index; keep the bounds checks here so stale items cannot index replyRows.
            guard let postID = item.postID,
                  let post = postLookup[postID],
                  let index = item.replyIndex,
                  index >= 0,
                  index < replyRows.count,
                  replyRows[index].entry.postId == postID else {
                return nil
            }
            let row = replyRows[index]
            return FireTopicDetailRuntimePostContext(
                post: post,
                renderContent: renderState?.contentByPostID[postID] ?? fallbackRenderContent(for: post),
                depth: Int(row.entry.depth),
                replyContext: FireTopicDetailCollectionView.replyContextLabel(
                    for: post,
                    preferredPostNumber: row.entry.parentPostNumber
                ),
                replyTargetPostNumber: FireTopicDetailCollectionView.replyTargetPostNumber(
                    for: post,
                    preferredPostNumber: row.entry.parentPostNumber
                ),
                showsThreadLine: showsTimelineThreadLine(at: index),
                showsDivider: index != replyRows.count - 1
            )

        default:
            return nil
        }
    }

    func scrollItem(for postNumber: UInt32) -> FireTopicDetailRuntimeItem? {
        makeSnapshot().items.first { $0.postNumber == postNumber }
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
        parts.append(String(reflecting: post.reactions))
        parts.append(post.currentUserReaction?.id ?? "")
        parts.append(String(reflecting: post.polls))
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
    case loadingFooter
    case empty
}
