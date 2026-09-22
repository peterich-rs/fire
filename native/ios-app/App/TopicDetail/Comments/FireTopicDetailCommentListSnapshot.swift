import Foundation

struct FireTopicDetailCommentListSlice {
    let items: [FireTopicDetailRuntimeItem]
    let replyIndexByPostID: [UInt64: Int]
}

extension FireTopicDetailRuntimeConfiguration {
    /// Floor header, status, then one item per visible message, then the floor footer.
    func makeCommentListSlice() -> FireTopicDetailCommentListSlice {
        var items: [FireTopicDetailRuntimeItem] = []
        let replyDisplayPlan = makeReplyDisplayPlan()
        let currentReplyFooterState = replyFooterState

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

        if detail == nil || isWaitingForPostRender {
            items.append(.init(
                id: "body-state:\(topic.id)",
                kind: .bodyState,
                postID: nil,
                postNumber: nil,
                replyIndex: nil,
                contentToken: AnyHashable(
                    [
                        String(isLoadingTopic),
                        String(isWaitingForPostRender),
                        detailError ?? "",
                    ].joined(separator: "\u{1F}")
                )
            ))
            return FireTopicDetailCommentListSlice(
                items: items,
                replyIndexByPostID: replyDisplayPlan.sourceIndexByPostID
            )
        }

        for displayedRow in replyDisplayPlan.rows {
            let row = displayedRow.row
            let post = resolvedPostLookup[row.entry.postId]
            let renderContent = renderState?.contentByPostID[row.entry.postId]
                ?? post.flatMap { FireTopicPresentation.renderContent(from: $0) }
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
                isReplyThreadExpanded: displayedRow.isReplyThreadExpanded,
                contentToken: AnyHashable([
                    String(displayedRow.sourceIndex),
                    post.map {
                        postLayoutContentToken(
                            $0,
                            renderContent: renderContent,
                            replyShortcutCount: displayedRow.replyShortcutCount,
                            isReplyThreadExpanded: displayedRow.isReplyThreadExpanded,
                            textExpansionState: textExpansionState
                        )
                    } ?? "missing",
                    String(displayedRow.showsThreadLine),
                    String(displayedRow.showsDivider),
                    String(displayedRow.isReplyThreadExpanded),
                ].joined(separator: "\u{1F}")),
                inPlaceUpdateToken: AnyHashable(
                    post.map {
                        postContentToken(
                            $0,
                            renderContent: renderContent,
                            replyContext: replyContext,
                            replyTargetPostNumber: replyTargetPostNumber,
                            isLoadingReplyContext: isLoadingReplyContext,
                            textExpansionState: textExpansionState
                        )
                    } ?? "missing"
                ),
                messageBands: post.map {
                    makeMessageBands(
                        $0,
                        renderContent: renderContent,
                        replyContext: replyContext,
                        replyShortcutCount: displayedRow.replyShortcutCount,
                        isReplyThreadExpanded: displayedRow.isReplyThreadExpanded,
                        showsThreadLine: displayedRow.showsThreadLine,
                        showsDivider: displayedRow.showsDivider,
                        textExpansionState: textExpansionState
                    )
                }
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

        return FireTopicDetailCommentListSlice(
            items: items,
            replyIndexByPostID: replyDisplayPlan.sourceIndexByPostID
        )
    }
}
