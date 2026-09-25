import Foundation

extension FireTopicDetailRuntimeConfiguration {
    func makeSnapshot(
        reusingComments cached: FireTopicDetailRuntimeSnapshot? = nil
    ) -> FireTopicDetailRuntimeSnapshot {
        let article = makeArticleItems()
        if let cached {
            return FireTopicDetailRuntimeSnapshot(
                items: article + cached.commentItems,
                replyIndexByPostID: cached.replyIndexByPostID
            )
        }
        let comments = makeCommentListSlice()
        return FireTopicDetailRuntimeSnapshot(
            items: article + comments.items,
            replyIndexByPostID: comments.replyIndexByPostID
        )
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
            let declaredReplyCount = resolvedPostLookup[rootRow.entry.postId].map { Int($0.replyCount) } ?? 0
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

    func makeMessageBands(
        _ post: TopicPostState,
        renderContent: FireTopicPostRenderContent?,
        replyContext: String?,
        replyShortcutCount: UInt32?,
        isReplyThreadExpanded: Bool,
        showsThreadLine: Bool,
        showsDivider: Bool,
        textExpansionState: FirePostTextExpansionState
    ) -> FireTopicDetailMessageBands {
        let segments = renderContent?.segments ?? []
        let imageToken = segments.compactMap { segment -> String? in
            switch segment {
            case .image, .onebox:
                return segment.signatureToken
            case .text:
                return nil
            }
        }.joined(separator: "\u{1F}")
        let textToken = segments.compactMap { segment -> String? in
            guard case .text = segment else { return nil }
            return segment.signatureToken
        }.joined(separator: "\u{1F}")
        return FireTopicDetailMessageBands(
            author: AnyHashable([
                post.username,
                post.name ?? "",
                post.avatarTemplate ?? "",
                FirePostAuthorMetadataDisplay.contentToken(for: post),
                post.createdAt ?? "",
                String(post.postNumber),
                String(post.acceptedAnswer),
            ].joined(separator: "\u{1F}")),
            quote: AnyHashable(replyContext ?? ""),
            images: AnyHashable(imageToken),
            text: AnyHashable([
                textToken,
                Self.pollsContentToken(post.polls),
                FirePostBoostDisplay.contentToken(for: post.boosts),
                String(post.hidden),
            ].joined(separator: "\u{1F}")),
            showMore: AnyHashable([
                String(textExpansionState.isExpanded),
                String(textExpansionState.isCollapsible),
                String(replyShortcutCount ?? 0),
                String(replyShortcutCount != nil),
                String(isReplyThreadExpanded),
            ].joined(separator: "\u{1F}")),
            actions: AnyHashable([
                String(canWriteInteractions),
                String(isMutatingPost(post.id)),
                String(post.canEdit),
                String(post.canDelete),
                String(post.canRecover),
                String(post.canBoost),
                String(post.bookmarked),
                String(isSearchHighlighted(postID: post.id)),
            ].joined(separator: "\u{1F}")),
            reactions: AnyHashable([
                Self.reactionsContentToken(post.reactions),
                post.currentUserReaction?.id ?? "",
                String(post.likeCount),
                String(isReactionPickerExpanded(post.id)),
            ].joined(separator: "\u{1F}")),
            thread: AnyHashable([
                String(showsThreadLine),
                String(showsDivider),
            ].joined(separator: "\u{1F}"))
        )
    }

    func postLayoutContentToken(
        _ post: TopicPostState,
        renderContent: FireTopicPostRenderContent?,
        replyShortcutCount: UInt32?,
        isReplyThreadExpanded: Bool = false,
        textExpansionState: FirePostTextExpansionState
    ) -> String {
        if let row = snapshot?.rows.first(where: { $0.postId == post.id }) {
            return [
                String(row.layoutChecksum),
                String(replyShortcutCount != nil),
                String(isReplyThreadExpanded),
                String(isReactionPickerExpanded(post.id)),
                String(textExpansionState.isExpanded),
                String(textExpansionState.isCollapsible),
            ].joined(separator: "\u{1F}")
        }
        return [
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
        if let row = snapshot?.rows.first(where: { $0.postId == post.id }) {
            let localChrome = [
                String(textExpansionState.isExpanded),
                String(textExpansionState.isCollapsible),
                String(isReactionPickerExpanded(post.id)),
                String(isSearchHighlighted(postID: post.id)),
                String(canWriteInteractions),
            ].joined(separator: "\u{1F}")
            return [String(row.interactionChecksum), localChrome].joined(separator: "\u{1F}")
        }
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
