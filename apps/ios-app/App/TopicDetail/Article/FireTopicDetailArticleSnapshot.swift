import Foundation

extension FireTopicDetailRuntimeConfiguration {
    /// Title and tags, summary, body, reaction token, stats, topic vote.
    /// Reaction icons stay on the original-post cell and update through
    /// `inPlaceUpdateToken`. The body band is `contentToken`.
    func makeArticleItems() -> [FireTopicDetailRuntimeItem] {
        var items: [FireTopicDetailRuntimeItem] = []

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

        if let topicAiSummary {
            items.append(.init(
                id: "ai-summary:\(topic.id)",
                kind: .aiSummary,
                postID: nil,
                postNumber: nil,
                replyIndex: nil,
                contentToken: AnyHashable([
                    Self.topicAiSummaryContentToken(topicAiSummary),
                    String(isTopicAiSummaryExpanded),
                ])
            ))
        }

        if let originalPost,
           let originalPostRenderContent {
            items.append(.init(
                id: "original:\(topic.id)",
                kind: .originalPost,
                postID: originalPost.id,
                postNumber: originalPost.postNumber,
                replyIndex: nil,
                contentToken: AnyHashable(
                    postLayoutContentToken(
                        originalPost,
                        renderContent: originalPostRenderContent,
                        replyShortcutCount: nil,
                        textExpansionState: .disabled
                    )
                ),
                inPlaceUpdateToken: AnyHashable(
                    postContentToken(
                        originalPost,
                        renderContent: originalPostRenderContent,
                        replyContext: nil,
                        replyTargetPostNumber: nil,
                        isLoadingReplyContext: false,
                        textExpansionState: .disabled
                    )
                ),
                messageBands: makeMessageBands(
                    originalPost,
                    renderContent: originalPostRenderContent,
                    replyContext: nil,
                    replyShortcutCount: nil,
                    isReplyThreadExpanded: false,
                    showsThreadLine: false,
                    showsDivider: false,
                    textExpansionState: .disabled
                )
            ))
        }

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

        return items
    }
}
