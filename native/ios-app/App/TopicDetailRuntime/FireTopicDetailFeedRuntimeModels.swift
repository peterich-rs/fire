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
    let contentToken: AnyHashable

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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
            imageAttachments: []
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
            contentToken: AnyHashable("\(displayedTopicTitle)|\(row.statusLabels.joined(separator: ","))")
        ))

        if topicAiSummary != nil || isLoadingTopicAiSummary || topicAiSummaryError != nil {
            items.append(.init(
                id: "ai-summary:\(topic.id)",
                kind: .aiSummary,
                postID: nil,
                postNumber: nil,
                contentToken: AnyHashable("\(topicAiSummary?.summarizedText ?? "")|\(isLoadingTopicAiSummary)|\(topicAiSummaryError ?? "")")
            ))
        }

        items.append(.init(
            id: "original:\(topic.id)",
            kind: .originalPost,
            postID: originalPost?.id,
            postNumber: originalPost?.postNumber,
            contentToken: AnyHashable(originalPost.map { postContentToken($0, renderContent: originalPostRenderContent) } ?? "missing")
        ))

        items.append(.init(
            id: "stats:\(topic.id)",
            kind: .stats,
            postID: nil,
            postNumber: nil,
            contentToken: AnyHashable("\(displayedReplyCount)|\(displayedViewsCount)")
        ))

        items.append(.init(
            id: "replies-header:\(topic.id)",
            kind: .repliesHeader,
            postID: nil,
            postNumber: nil,
            contentToken: AnyHashable("\(replyRows.count)|\(detail?.postsCount ?? topic.replyCount)")
        ))

        if detail == nil {
            items.append(.init(
                id: "body-state:\(topic.id)",
                kind: .bodyState,
                postID: nil,
                postNumber: nil,
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
                    contentToken: AnyHashable("\(index)|\(post.map { postContentToken($0, renderContent: renderContent) } ?? "missing")")
                ))
            }

            if replyFooterState != .none {
                items.append(.init(
                    id: "reply-footer:\(topic.id)",
                    kind: .replyFooter,
                    postID: nil,
                    postNumber: nil,
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
            guard let postID = item.postID,
                  let post = postLookup[postID],
                  let index = replyRows.firstIndex(where: { $0.entry.postId == postID }) else {
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
        "\(post.id)|\(post.cooked.hashValue)|\(post.likeCount)|\(post.reactions.count)|\(post.polls.count)|\(renderContent?.imageAttachments.count ?? 0)|\(isMutatingPost(post.id))"
    }

    private func showsTimelineThreadLine(at index: Int) -> Bool {
        guard index >= 0, index < replyRows.count else { return false }
        if index < replyRows.count - 1 {
            return true
        }
        return replyRows[index].entry.depth > 1
    }
}

enum FireTopicDetailRuntimeReplyFooterState: Equatable {
    case none
    case loadingFooter
    case empty
}
