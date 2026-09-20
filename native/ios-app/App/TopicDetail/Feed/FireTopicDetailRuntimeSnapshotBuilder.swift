import Foundation

extension FireTopicDetailRuntimeConfiguration {
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

    func makeReplyDisplayPlan() -> FireTopicDetailReplyDisplayPlan {
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
            let threadExpanded = isReplyThreadExpanded(rootRow.entry.postId)
            let selectedSecondaryIndices = threadExpanded
                ? secondaryIndices
                : selectedAnchoredSecondaryIndices(from: secondaryIndices)
            let declaredReplyCount = postLookup[rootRow.entry.postId].map { Int($0.replyCount) } ?? 0
            let totalSecondaryCount = max(secondaryIndices.count, declaredReplyCount)
            let hiddenCount = max(totalSecondaryCount - selectedSecondaryIndices.count, 0)
            // Keep the bubble control after expand so the user can collapse again.
            let shortcutCount: UInt32?
            if totalSecondaryCount > 0 {
                shortcutCount = UInt32(clamping: threadExpanded ? totalSecondaryCount : max(hiddenCount, 1))
            } else {
                shortcutCount = nil
            }

            displayedRows.append(.init(
                row: rootRow,
                sourceIndex: rootIndex,
                showsThreadLine: false,
                showsDivider: true,
                replyShortcutCount: shortcutCount,
                isReplyThreadExpanded: threadExpanded
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
                    replyShortcutCount: nil,
                    isReplyThreadExpanded: false
                ))
            }
        }

        if !displayedRows.isEmpty {
            for index in displayedRows.indices {
                let row = displayedRows[index]
                let currentDepth = Int(row.row.entry.depth)
                let nextDepth = displayedRows.indices.contains(index + 1)
                    ? Int(displayedRows[index + 1].row.entry.depth)
                    : 0
                displayedRows[index] = .init(
                    row: row.row,
                    sourceIndex: row.sourceIndex,
                    showsThreadLine: nextDepth > currentDepth,
                    showsDivider: index < displayedRows.count - 1,
                    replyShortcutCount: row.replyShortcutCount,
                    isReplyThreadExpanded: row.isReplyThreadExpanded
                )
            }
        }

        return FireTopicDetailReplyDisplayPlan(
            rows: displayedRows,
            sourceIndexByPostID: sourceIndexByPostID
        )
    }

    func makeReplyThreadIndex() -> FireTopicDetailReplyThreadIndex {
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

    func selectedAnchoredSecondaryIndices(from indices: [Int]) -> [Int] {
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

    static func displayDepth(for row: FirePreparedTopicTimelineRow) -> Int {
        Int(row.entry.depth)
    }

    func postLayoutContentToken(
        _ post: TopicPostState,
        renderContent: FireTopicPostRenderContent?,
        replyShortcutCount: UInt32?,
        isReplyThreadExpanded: Bool = false,
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
            String(isReplyThreadExpanded),
            String(isReactionPickerExpanded(post.id)),
            String(textExpansionState.isExpanded),
            String(textExpansionState.isCollapsible),
        ].joined(separator: "\u{1F}")
    }

    func postContentToken(
        _ post: TopicPostState,
        renderContent: FireTopicPostRenderContent?,
        replyContext: String?,
        replyTargetPostNumber: UInt32?,
        isLoadingReplyContext: Bool,
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
        parts.append(String(isLoadingReplyContext))
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
        parts.append(String(textExpansionState.isExpanded))
        parts.append(String(textExpansionState.isCollapsible))
        parts.append(String(isReactionPickerExpanded(post.id)))
        parts.append(String(canWriteInteractions))
        parts.append(String(isMutatingPost(post.id)))
        parts.append(String(isSearchHighlighted(postID: post.id)))
        return parts.joined(separator: "\u{1F}")
    }

    static func reactionsContentToken(_ reactions: [TopicReactionState]) -> String {
        reactions.map { reaction in
            [
                reaction.id,
                reaction.kind ?? "",
                String(reaction.count),
                reaction.canUndo.map { String($0) } ?? "",
            ].joined(separator: "\u{1E}")
        }.joined(separator: "\u{1D}")
    }

    static func pollsContentToken(_ polls: [PollState]) -> String {
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

    static func topicAiSummaryContentToken(_ summary: TopicAiSummaryState) -> String {
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
