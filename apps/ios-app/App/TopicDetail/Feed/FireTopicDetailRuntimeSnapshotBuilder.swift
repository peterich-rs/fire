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

    /// The only post-row item builder. The original post, reply rows, and
    /// in-place refreshes all go through here so equal state yields equal
    /// tokens.
    func makePostItem(
        id: String,
        kind: FireTopicDetailRuntimeItemKind,
        replyIndex: Int?,
        context: FireTopicDetailRuntimePostContext
    ) -> FireTopicDetailRuntimeItem {
        let bands = makeMessageBands(context)
        return FireTopicDetailRuntimeItem(
            id: id,
            kind: kind,
            postID: context.post.id,
            postNumber: context.post.postNumber,
            replyIndex: replyIndex,
            replyShowsThreadLine: context.showsThreadLine,
            replyShowsDivider: context.showsDivider,
            replyShortcutCount: context.replyShortcutCount,
            isReplyThreadExpanded: context.isReplyThreadExpanded,
            contentToken: AnyHashable(postLayoutContentToken(context)),
            inPlaceUpdateToken: AnyHashable(FireTopicDetailPostInPlaceToken(
                interaction: postInteractionToken(context.post),
                bands: bands
            )),
            messageBands: bands
        )
    }

    /// Rebuilds a post item from current state. Items whose post context is
    /// gone come back unchanged.
    func refreshedPostItem(_ item: FireTopicDetailRuntimeItem) -> FireTopicDetailRuntimeItem {
        guard let context = postContext(for: item) else { return item }
        return makePostItem(
            id: item.id,
            kind: item.kind,
            replyIndex: item.replyIndex,
            context: context
        )
    }

    func makeMessageBands(_ context: FireTopicDetailRuntimePostContext) -> FireTopicDetailMessageBands {
        let post = context.post
        let expansion = context.textExpansionState
        let quote = AnyHashable([
            context.replyContext ?? "",
            context.replyTargetPostNumber.map(String.init) ?? "",
        ].joined(separator: "\u{1F}"))
        let showMore = AnyHashable([
            String(expansion.isExpanded),
            String(expansion.isCollapsible),
            context.replyShortcutCount.map(String.init) ?? "",
            String(context.isReplyThreadExpanded),
            String(context.isLoadingReplyContext),
        ].joined(separator: "\u{1F}"))
        let actionsChrome = [
            String(canWriteInteractions),
            String(isMutatingPost(post.id)),
            String(isSearchHighlighted(postID: post.id)),
        ]
        let reactionsChrome = [
            String(canWriteInteractions),
            String(isReactionPickerExpanded(post.id)),
        ]
        let thread = AnyHashable([
            String(context.showsThreadLine),
            String(context.showsDivider),
        ].joined(separator: "\u{1F}"))

        if let row = rowsByPostID[post.id] {
            return FireTopicDetailMessageBands(
                author: AnyHashable(row.authorBandChecksum),
                quote: quote,
                images: AnyHashable(row.textBandChecksum),
                text: AnyHashable([
                    String(row.textBandChecksum),
                    String(expansion.isExpanded),
                ].joined(separator: "\u{1F}")),
                showMore: showMore,
                actions: AnyHashable(([String(row.actionsBandChecksum)] + actionsChrome)
                    .joined(separator: "\u{1F}")),
                reactions: AnyHashable(([String(row.reactionsBandChecksum)] + reactionsChrome)
                    .joined(separator: "\u{1F}")),
                thread: thread
            )
        }

        let segments = context.renderContent.segments
        let imageToken = segments.compactMap { segment -> String? in
            switch segment {
            case .image, .onebox:
                return segment.signatureToken
            case .text, .quote:
                return nil
            }
        }.joined(separator: "\u{1F}")
        let textToken = segments.compactMap { segment -> String? in
            switch segment {
            case .text, .quote:
                return segment.signatureToken
            case .image, .onebox:
                return nil
            }
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
            quote: quote,
            images: AnyHashable(imageToken),
            text: AnyHashable([
                textToken,
                Self.pollsContentToken(post.polls),
                FirePostBoostDisplay.contentToken(for: post.boosts),
                String(post.hidden),
                String(expansion.isExpanded),
            ].joined(separator: "\u{1F}")),
            showMore: showMore,
            actions: AnyHashable(([
                String(post.canEdit),
                String(post.canDelete),
                String(post.canRecover),
                String(post.canBoost),
                String(post.bookmarked),
                String(post.hidden),
            ] + actionsChrome).joined(separator: "\u{1F}")),
            reactions: AnyHashable(([
                Self.reactionsContentToken(post.reactions),
                post.currentUserReaction?.id ?? "",
                String(post.likeCount),
            ] + reactionsChrome).joined(separator: "\u{1F}")),
            thread: thread
        )
    }

    /// Changes whenever the row must be re-measured.
    func postLayoutContentToken(_ context: FireTopicDetailRuntimePostContext) -> String {
        let post = context.post
        let localLayout = [
            String(canWriteInteractions),
            String(context.replyContext != nil),
            String(context.replyShortcutCount != nil),
            String(context.isReplyThreadExpanded),
            String(isReactionPickerExpanded(post.id)),
            String(context.textExpansionState.isExpanded),
            String(context.textExpansionState.isCollapsible),
        ]
        if let row = rowsByPostID[post.id] {
            return ([String(row.layoutChecksum)] + localLayout).joined(separator: "\u{1F}")
        }
        return ([
            String(post.id),
            FirePostAuthorMetadataDisplay.contentToken(for: post),
            context.renderContent.signature.token,
            Self.pollsContentToken(post.polls),
            FirePostBoostDisplay.contentToken(for: post.boosts),
            String(!post.reactions.isEmpty),
            String(post.hidden),
            String(post.canEdit),
            String(post.canDelete),
            String(post.canRecover),
            String(post.canBoost),
        ] + localLayout).joined(separator: "\u{1F}")
    }

    /// Server-side row identity outside the bands: fields the cell only reads
    /// on tap (bookmark name, accept-answer menu, reply count) still refresh
    /// the node's payload.
    func postInteractionToken(_ post: TopicPostState) -> String {
        if let row = rowsByPostID[post.id] {
            return String(row.interactionChecksum)
        }
        return [
            String(post.id),
            String(post.postNumber),
            post.username,
            post.avatarTemplate ?? "",
            post.createdAt ?? "",
            post.updatedAt ?? "",
            String(post.likeCount),
            String(post.replyCount),
            Self.reactionsContentToken(post.reactions),
            post.currentUserReaction?.id ?? "",
            String(post.acceptedAnswer),
            String(post.canAcceptAnswer),
            String(post.canUnacceptAnswer),
            String(post.canEdit),
            String(post.canDelete),
            String(post.canRecover),
            String(post.canBoost),
            String(post.hidden),
            String(post.bookmarked),
            String(post.bookmarkId ?? 0),
            post.bookmarkName ?? "",
            post.bookmarkReminderAt ?? "",
        ].joined(separator: "\u{1F}")
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
