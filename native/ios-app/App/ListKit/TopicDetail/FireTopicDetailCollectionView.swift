import SwiftUI
import UIKit

enum FireTopicDetailCollectionSection: Int, Hashable {
    case topic
    case replies
}

struct FireTopicDetailCollectionReplyKey: Hashable {
    let postID: UInt64
    let postNumber: UInt32
}

enum FireTopicDetailCollectionItem: Hashable {
    case header(topicID: UInt64)
    case aiSummary(topicID: UInt64)
    case originalPost(topicID: UInt64)
    case stats(topicID: UInt64)
    case topicVote(topicID: UInt64)
    case repliesHeader(topicID: UInt64)
    case bodyState(topicID: UInt64)
    case reply(FireTopicDetailCollectionReplyKey)
    case replyFooter(topicID: UInt64)
}

enum FireTopicDetailCollectionAdapter {
    static func visiblePostNumbers(
        from items: [FireTopicDetailCollectionItem],
        originalPostNumber: UInt32?
    ) -> Set<UInt32> {
        Set(items.compactMap { visiblePostNumber(for: $0, originalPostNumber: originalPostNumber) })
    }

    static func visiblePostNumber(
        for item: FireTopicDetailCollectionItem,
        originalPostNumber: UInt32?
    ) -> UInt32? {
        switch item {
        case .originalPost:
            return originalPostNumber
        case let .reply(key):
            return key.postNumber
        default:
            return nil
        }
    }

    static func scrollItem(
        for postNumber: UInt32,
        topicID: UInt64,
        originalPostNumber: UInt32?,
        replyRows: [FirePreparedTopicTimelineRow]
    ) -> FireTopicDetailCollectionItem? {
        if originalPostNumber == postNumber {
            return .originalPost(topicID: topicID)
        }

        if let row = replyRows.first(where: { $0.entry.postNumber == postNumber }) {
            return .reply(
                FireTopicDetailCollectionReplyKey(
                    postID: row.entry.postId,
                    postNumber: row.entry.postNumber
                )
            )
        }

        return nil
    }
}

private struct FireTopicDetailCollectionContentVersion: Hashable {
    let topicID: UInt64
    let topicCollectionRevision: UInt64
    let canWriteInteractions: Bool
    let baseURLString: String
    let replyLayoutSnapshotRevision: UInt64
}

struct FireTopicDetailCollectionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var layoutManager = FirePostLayoutManager()
    @State private var contentWidth: CGFloat?

    let viewModel: FireAppViewModel
    let row: FireTopicRowPresentation
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

    static func replyTargetPostNumber(
        for post: TopicPostState,
        preferredPostNumber: UInt32?
    ) -> UInt32? {
        preferredPostNumber ?? post.replyToPostNumber
    }

    static func replyContextLabel(
        for post: TopicPostState,
        preferredPostNumber: UInt32?
    ) -> String? {
        let targetPostNumber = replyTargetPostNumber(
            for: post,
            preferredPostNumber: preferredPostNumber
        )
        guard let targetPostNumber, targetPostNumber > 0 else {
            return nil
        }

        let canUseReplyUser = preferredPostNumber == nil
            || preferredPostNumber == post.replyToPostNumber
        if canUseReplyUser {
            let username = post.replyToUser?.username
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !username.isEmpty {
                return "回复 @\(username)"
            }
        }

        return "回复 #\(targetPostNumber)"
    }

    private var topic: TopicSummaryState {
        row.topic
    }

    private var displayedTopicTitle: String {
        let trimmedDetailTitle = detail?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedDetailTitle.isEmpty {
            return trimmedDetailTitle
        }

        let trimmedRowTitle = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedRowTitle.isEmpty ? "话题 \(topic.id)" : trimmedRowTitle
    }

    private var displayedCategoryId: UInt64? {
        detail?.categoryId ?? topic.categoryId
    }

    private var displayedCategory: FireTopicCategoryPresentation? {
        viewModel.categoryPresentation(for: displayedCategoryId)
    }

    private var displayedTagNames: [String] {
        let detailTags = detail?.tags
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        return detailTags.isEmpty ? row.tagNames : detailTags
    }

    private var isPrivateMessageThread: Bool {
        FireTopicPresentation.isPrivateMessageArchetype(detail?.archetype)
    }

    private var displayedParticipants: [TopicParticipantState] {
        guard isPrivateMessageThread else {
            return []
        }

        let source = !(detail?.details.participants.isEmpty ?? true)
            ? detail?.details.participants ?? []
            : topic.participants
        var participants: [TopicParticipantState] = []
        let currentUsername = viewModel.session.bootstrap.currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines)

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

    private var originalRow: FirePreparedTopicTimelineRow? {
        renderState?.originalRow
    }

    private var originalPost: TopicPostState? {
        if let originalRow {
            return postLookup[originalRow.entry.postId]
        }
        return detail?.postStream.posts.min(by: { $0.postNumber < $1.postNumber })
    }

    private var originalPostRenderContent: FireTopicPostRenderContent? {
        guard let originalRow else {
            return nil
        }
        return renderState?.contentByPostID[originalRow.entry.postId]
    }

    private func fallbackRenderContent(for post: TopicPostState) -> FireTopicPostRenderContent {
        let plainText = post.raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FireTopicPostRenderContent(
            plainText: plainText.isEmpty ? "加载中…" : plainText,
            attributedText: nil,
            imageAttachments: []
        )
    }

    private var replyRows: [FirePreparedTopicTimelineRow] {
        renderState?.replyRows ?? []
    }

    private var displayedReplyCount: UInt32 {
        if let detail {
            return max(detail.postsCount, 1) - 1
        }
        return topic.replyCount
    }

    private var loadedReplyCount: Int {
        replyRows.count
    }

    private var displayedInteractionCount: UInt32? {
        detail.map(FireTopicPresentation.interactionCount(for:))
    }

    private var displayedViewsCount: UInt32 {
        detail?.views ?? topic.views
    }

    private var displayedFloorCount: Int {
        replyRows.count
    }

    private var baseURLString: String {
        let trimmed = viewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    private var showsTopicVote: Bool {
        guard let detail, !isPrivateMessageThread else {
            return false
        }
        return detail.canVote || detail.userVoted || detail.voteCount > 0
    }

    private var showsTopicAiSummary: Bool {
        topicAiSummary != nil || isLoadingTopicAiSummary || topicAiSummaryError != nil
    }

    private var contentVersion: FireTopicDetailCollectionContentVersion {
        FireTopicDetailCollectionContentVersion(
            topicID: topic.id,
            topicCollectionRevision: topicCollectionRevision,
            canWriteInteractions: canWriteInteractions,
            baseURLString: baseURLString,
            replyLayoutSnapshotRevision: layoutManager.currentSnapshotRevision
        )
    }

    private var sections: [FireListSectionModel<FireTopicDetailCollectionSection, FireTopicDetailCollectionItem>] {
        var topicItems: [FireTopicDetailCollectionItem] = [
            .header(topicID: topic.id),
        ]
        if showsTopicAiSummary {
            topicItems.append(.aiSummary(topicID: topic.id))
        }
        topicItems.append(.originalPost(topicID: topic.id))
        topicItems.append(.stats(topicID: topic.id))
        if showsTopicVote {
            topicItems.append(.topicVote(topicID: topic.id))
        }

        var replyItems: [FireTopicDetailCollectionItem] = [
            .repliesHeader(topicID: topic.id)
        ]

        if detail == nil {
            replyItems.append(.bodyState(topicID: topic.id))
        } else {
            replyItems.append(contentsOf: replyRows.map { row in
                .reply(
                    FireTopicDetailCollectionReplyKey(
                        postID: row.entry.postId,
                        postNumber: row.entry.postNumber
                    )
                )
            })

            if replyFooterState != .none {
                replyItems.append(.replyFooter(topicID: topic.id))
            }
        }

        return [
            FireListSectionModel(id: .topic, items: topicItems),
            FireListSectionModel(id: .replies, items: replyItems),
        ]
    }

    private var replyFooterState: FireTopicDetailReplyFooterState {
        guard detail != nil else {
            return .none
        }

        if replyRows.isEmpty {
            return hasMoreTopicPosts ? .loadingFooter : .empty
        }

        return isLoadingMoreTopicPosts ? .loadingFooter : .none
    }

    private func itemContentToken(
        for item: FireTopicDetailCollectionItem,
        replyIndexByPostID: [UInt64: Int]
    ) -> AnyHashable {
        switch item {
        case .header:
            return AnyHashable([
                displayedTopicTitle,
                displayedCategory.map { "\($0.id)|\($0.slug)|\($0.displayName)|\($0.colorHex ?? "")" } ?? "",
                displayedTagNames.joined(separator: ","),
                displayedParticipants.map {
                    "\($0.userId)|\($0.username ?? "")|\($0.name ?? "")"
                }.joined(separator: ";"),
                row.statusLabels.joined(separator: ","),
                String(isPrivateMessageThread),
            ])
        case .aiSummary:
            return AnyHashable([
                topicAiSummary.map(Self.topicAiSummaryContentToken(_:)) ?? "",
                String(isLoadingTopicAiSummary),
                topicAiSummaryError ?? "",
            ])
        case .originalPost:
            let postToken = originalPost.map { post in
                Self.postContentToken(
                    post,
                    renderContent: originalPostRenderContent,
                    isMutating: isMutatingPost(post.id)
                )
            }
            return AnyHashable([
                postToken ?? "",
                row.excerptText ?? "",
                String(canWriteInteractions),
            ])
        case .stats:
            return AnyHashable([
                String(displayedReplyCount),
                String(displayedViewsCount),
                displayedInteractionCount.map(String.init) ?? "",
            ])
        case .topicVote:
            let voteToken = detail.flatMap { detail -> String? in
                guard !isPrivateMessageThread,
                      detail.canVote || detail.userVoted || detail.voteCount > 0 else {
                    return nil
                }
                return "\(detail.canVote)|\(detail.userVoted)|\(detail.voteCount)"
            }
            return AnyHashable([
                voteToken ?? "",
                String(canWriteInteractions),
            ])
        case .repliesHeader:
            let total = detail.map { max(Int($0.postsCount) - 1, 0) } ?? Int(topic.replyCount)
            return AnyHashable([
                String(loadedReplyCount),
                String(total),
                String(displayedFloorCount),
                String(detail != nil),
            ])
        case .bodyState:
            return AnyHashable([
                String(isLoadingTopic),
                detailError ?? "",
            ])
        case let .reply(key):
            guard let index = replyIndexByPostID[key.postID],
                  index < replyRows.count,
                  replyRows[index].entry.postNumber == key.postNumber else {
                return AnyHashable("missing|\(key.postID)|\(key.postNumber)")
            }
            let row = replyRows[index]
            let post = postLookup[row.entry.postId]
            let mode = replyCellMode(
                for: key,
                replyIndexByPostID: replyIndexByPostID
            )
            let token = Self.replyRowToken(
                row: row,
                post: post,
                renderContent: renderState?.contentByPostID[row.entry.postId],
                showsThreadLine: showsTimelineThreadLine(in: replyRows, at: index),
                isMutating: post.map { isMutatingPost($0.id) } ?? false
            )
            return AnyHashable("\(token)|mode:\(String(reflecting: mode))|\(canWriteInteractions)")
        case .replyFooter:
            return AnyHashable([
                String(reflecting: replyFooterState),
                String(replyRows.isEmpty),
                String(topic.id),
            ])
        }
    }

    private var scrollRequest: FireCollectionScrollRequest<FireTopicDetailCollectionItem>? {
        guard let pendingScrollTarget,
              let item = FireTopicDetailCollectionAdapter.scrollItem(
                  for: pendingScrollTarget,
                  topicID: topic.id,
                  originalPostNumber: originalPost?.postNumber,
                  replyRows: replyRows
              ) else {
            return nil
        }

        return FireCollectionScrollRequest(itemID: item)
    }

    var body: some View {
        // Build the reply-index map once per render and reuse it for every token and
        // row lookup. Without this, FireCollectionHost's per-item token rebuild would
        // trigger an O(N) firstIndex scan per item — O(N²) across a full pass, which
        // stalls typing and scrolling once a thread has dozens of replies loaded.
        let replyIndexByPostID = makeReplyIndexByPostID()
        return FireCollectionHost(
            sections: sections,
            contentVersion: contentVersion,
            itemContentToken: { item in
                itemContentToken(for: item, replyIndexByPostID: replyIndexByPostID)
            },
            backgroundColor: .systemBackground,
            animatingDifferences: true,
            onVisibleItemsChanged: handleVisibleItemsChanged(_:),
            onPrefetchItems: handlePrefetchItems(_:),
            onRefresh: onRefresh,
            onContentWidthChanged: handleContentWidthChanged(_:),
            updatePolicy: .deferWhileScrolling,
            scrollRequest: scrollRequest,
            onScrollRequestCompleted: handleScrollRequestCompleted(_:),
            shouldUseNativeCell: { item in
                shouldUseNativeCell(for: item, replyIndexByPostID: replyIndexByPostID)
            },
            nativeCellProvider: { collectionView, indexPath, item in
                nativeCellProvider(collectionView: collectionView, indexPath: indexPath, item: item, replyIndexByPostID: replyIndexByPostID)
            },
            makeLayout: Self.makeLayout,
            rowContent: { item in
                rowView(for: item, replyIndexByPostID: replyIndexByPostID)
            }
        )
        .onChange(of: topicCollectionRevision) { _, _ in
            enqueueLayoutsForAllReplies()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIContentSizeCategory.didChangeNotification)) { _ in
            handleContentSizeCategoryChanged()
        }
    }

    private func makeReplyIndexByPostID() -> [UInt64: Int] {
        var map: [UInt64: Int] = [:]
        map.reserveCapacity(replyRows.count)
        for (index, row) in replyRows.enumerated() {
            map[row.entry.postId] = index
        }
        return map
    }

    private static func makeLayout() -> UICollectionViewLayout {
        FireCollectionLayouts.plainList()
    }

    private func handleVisibleItemsChanged(_ items: [FireTopicDetailCollectionItem]) {
        onVisiblePostNumbersChanged(
            FireTopicDetailCollectionAdapter.visiblePostNumbers(
                from: items,
                originalPostNumber: originalPost?.postNumber
            )
        )
    }

    private func handlePrefetchItems(_ items: [FireTopicDetailCollectionItem]) {
        let postNumbers = FireTopicDetailCollectionAdapter.visiblePostNumbers(
            from: items,
            originalPostNumber: originalPost?.postNumber
        )
        guard !postNumbers.isEmpty else { return }
        onPreloadTopicPosts(postNumbers)

        // Enqueue layout calculation for prefetched reply items
        let replyIndexByPostID = makeReplyIndexByPostID()
        for item in items {
            guard case let .reply(key) = item,
                  let index = replyIndexByPostID[key.postID],
                  index < replyRows.count,
                  let post = postLookup[key.postID],
                  let renderContent = renderState?.contentByPostID[key.postID] else {
                continue
            }
            enqueueLayoutIfNeeded(
                post: post,
                renderContent: renderContent,
                replyRow: replyRows[index],
                replyIndex: index
            )
        }
    }

    private func handleContentWidthChanged(_ width: CGFloat) {
        if contentWidth != width {
            contentWidth = width
            let newTrait = makeTraitSignature(for: width)
            layoutManager.updateTraitSignature(newTrait)
            enqueueLayoutsForAllReplies()
        }
    }

    private func handleContentSizeCategoryChanged() {
        guard let contentWidth else {
            return
        }

        let trait = makeTraitSignature(for: contentWidth)
        layoutManager.updateTraitSignature(trait)
        enqueueLayoutsForAllReplies()
    }

    private func makeTraitSignature(for width: CGFloat) -> FirePostLayoutTraitSignature {
        FirePostLayoutTraitSignature(
            contentWidthPixels: Int(width.rounded()),
            contentSizeCategory: UIApplication.shared.preferredContentSizeCategory.rawValue
        )
    }

    private func shouldUseNativeCell(
        for item: FireTopicDetailCollectionItem,
        replyIndexByPostID: [UInt64: Int]
    ) -> Bool {
        guard case let .reply(key) = item else {
            return false
        }

        guard let index = replyIndexByPostID[key.postID],
              index < replyRows.count,
              postLookup[key.postID] != nil else {
            return false
        }

        let mode = replyCellMode(
            for: key,
            replyIndexByPostID: replyIndexByPostID
        )

        switch mode {
        case .native:
            return true
        case .hostedPoll, .hostedPlaceholder, .hostedLayoutMiss:
            return false
        }
    }

    private func replyCellMode(
        for key: FireTopicDetailCollectionReplyKey,
        replyIndexByPostID: [UInt64: Int]
    ) -> FireReplyCellMode {
        guard let index = replyIndexByPostID[key.postID],
              index < replyRows.count else {
            return .hostedPlaceholder
        }

        guard let post = postLookup[key.postID] else {
            return .hostedPlaceholder
        }

        if !post.polls.isEmpty {
            return .hostedPoll
        }

        guard let layoutKey = makeLayoutKey(
            post: post,
            renderContent: renderState?.contentByPostID[post.id],
            replyRow: replyRows[index],
            replyIndex: index
        ) else {
            return .hostedLayoutMiss
        }

        if layoutManager.layout(forKey: layoutKey) != nil {
            return .native
        }

        return .hostedLayoutMiss
    }

    private func nativeCellProvider(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireTopicDetailCollectionItem,
        replyIndexByPostID: [UInt64: Int]
    ) -> UICollectionViewCell? {
        guard case let .reply(key) = item,
              let index = replyIndexByPostID[key.postID],
              index < replyRows.count,
              let post = postLookup[key.postID] else {
            return nil
        }

        let renderContent = renderState?.contentByPostID[post.id] ?? fallbackRenderContent(for: post)
        guard let layoutKey = makeLayoutKey(
            post: post,
            renderContent: renderContent,
            replyRow: replyRows[index],
            replyIndex: index
        ) else {
            return nil
        }

        guard let layout = layoutManager.layout(forKey: layoutKey) else {
            return nil
        }

        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: FirePostCollectionViewCell.reuseID,
            for: indexPath
        ) as? FirePostCollectionViewCell

        guard let cell else { return nil }

        let showsDivider = index != replyRows.count - 1
        let payload = FirePostCellRenderPayload(
            post: post,
            renderContent: renderContent,
            baseURLString: baseURLString,
            canWriteInteractions: canWriteInteractions,
            isMutating: isMutatingPost(post.id),
            replyContext: Self.replyContextLabel(
                for: post,
                preferredPostNumber: replyRows[index].entry.parentPostNumber
            ),
            replyTargetPostNumber: Self.replyTargetPostNumber(
                for: post,
                preferredPostNumber: replyRows[index].entry.parentPostNumber
            ),
            showsDivider: showsDivider
        )

        let callbacks = FirePostCellCallbacks(
            onLinkTapped: onLinkTapped,
            onOpenImage: onOpenImage,
            onToggleLike: onToggleLike,
            onSelectReaction: onSelectReaction,
            onEditPost: onEditPost,
            onBookmarkPost: onBookmarkPost,
            onDeletePost: onDeletePost,
            onRecoverPost: onRecoverPost,
            onFlagPost: onFlagPost,
            onOpenReplyTarget: onOpenPostNumber,
            onOpenReplies: onOpenPostReplies,
            onVotePoll: onVotePoll,
            onUnvotePoll: onUnvotePoll,
            onSwipeReply: { post in
                onOpenComposer(post)
            }
        )

        cell.bind(layout: layout, payload: payload, callbacks: callbacks)
        return cell
    }

    private func makeLayoutKey(
        post: TopicPostState,
        renderContent: FireTopicPostRenderContent?,
        replyRow: FirePreparedTopicTimelineRow,
        replyIndex: Int
    ) -> FirePostCellLayoutKey? {
        guard let contentWidth, contentWidth > 0 else {
            return nil
        }

        let contentHash = post.cooked.hashValue
        let textContentID = "post:\(post.id)|hash:\(contentHash)|images:\(renderContent?.imageAttachments.count ?? 0)"
        let imageSignature = renderContent?.imageAttachments.map(\.id) ?? []
        let hasReactions = !post.reactions.isEmpty
        let showsDivider = replyIndex != replyRows.count - 1

        let trait = makeTraitSignature(for: contentWidth)

        return FirePostCellLayoutKey(
            postID: post.id,
            depth: Int(replyRow.entry.depth),
            showsThreadLine: showsTimelineThreadLine(in: replyRows, at: replyIndex),
            showsDivider: showsDivider,
            replyTargetPostNumber: replyRow.entry.parentPostNumber,
            replyContext: Self.replyContextLabel(
                for: post,
                preferredPostNumber: replyRow.entry.parentPostNumber
            ),
            textContentID: textContentID,
            imageSignature: imageSignature,
            pollSignature: post.polls.map { UInt64(bitPattern: Int64($0.name.hashValue)) },
            hasReactions: hasReactions,
            acceptedAnswer: post.acceptedAnswer,
            trait: trait
        )
    }

    private func enqueueLayoutIfNeeded(
        post: TopicPostState,
        renderContent: FireTopicPostRenderContent,
        replyRow: FirePreparedTopicTimelineRow,
        replyIndex: Int
    ) {
        guard post.polls.isEmpty,
              let key = makeLayoutKey(
            post: post,
            renderContent: renderContent,
            replyRow: replyRow,
            replyIndex: replyIndex
        ) else {
            return
        }

        guard layoutManager.layout(forKey: key) == nil else {
            return
        }

        let trait = key.trait
        layoutManager.enqueueCalculation(
            key: key,
            attributedText: renderContent.attributedText,
            images: renderContent.imageAttachments,
            trait: trait
        )
    }

    private func enqueueLayoutsForAllReplies() {
        for (index, row) in replyRows.enumerated() {
            guard let post = postLookup[row.entry.postId],
                  let renderContent = renderState?.contentByPostID[row.entry.postId] else {
                continue
            }
            enqueueLayoutIfNeeded(
                post: post,
                renderContent: renderContent,
                replyRow: row,
                replyIndex: index
            )
        }
    }

    private func handleScrollRequestCompleted(_ item: FireTopicDetailCollectionItem) {
        guard let postNumber = FireTopicDetailCollectionAdapter.visiblePostNumber(
            for: item,
            originalPostNumber: originalPost?.postNumber
        ) else {
            return
        }
        onScrollTargetHandled(postNumber)
    }

    @ViewBuilder
    private func rowView(
        for item: FireTopicDetailCollectionItem,
        replyIndexByPostID: [UInt64: Int]
    ) -> some View {
        switch item {
        case .header:
            headerRow
        case .aiSummary:
            topicAiSummaryRow
        case .originalPost:
            originalPostRow
        case .stats:
            statsRow
        case .topicVote:
            topicVoteRow
        case .repliesHeader:
            repliesHeaderRow
        case .bodyState:
            bodyStateRow
        case let .reply(key):
            replyRow(for: key, replyIndexByPostID: replyIndexByPostID)
        case .replyFooter:
            replyFooterRow
        }
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(displayedTopicTitle)
                .font(.title3.weight(.bold))

            FlowLayout(spacing: 6, fallbackWidth: max(UIScreen.main.bounds.width - 40, 200)) {
                if isPrivateMessageThread {
                    FireStatusChip(label: "私信", tone: .accent)

                    ForEach(displayedParticipants, id: \.userId) { participant in
                        let label = (participant.name ?? "").ifEmpty(participant.username ?? "用户 \(participant.userId)")
                        Text("@\(label)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.indigo.opacity(0.12), in: Capsule())
                    }
                } else {
                    if let displayedCategory {
                        let accent = Color(fireHex: displayedCategory.colorHex) ?? FireTheme.accent
                        NavigationLink {
                            FireFilteredTopicListView(
                                viewModel: viewModel,
                                title: displayedCategory.displayName,
                                categorySlug: displayedCategory.slug,
                                categoryId: displayedCategory.id,
                                parentCategorySlug: nil,
                                tag: nil
                            )
                        } label: {
                            FireTopicPill(
                                label: displayedCategory.displayName,
                                backgroundColor: FireTheme.categoryChipBackground(
                                    accent: accent,
                                    isDark: colorScheme == .dark
                                ),
                                foregroundColor: accent
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(displayedTagNames, id: \.self) { tagName in
                        NavigationLink {
                            FireFilteredTopicListView(
                                viewModel: viewModel,
                                title: "#\(tagName)",
                                categorySlug: nil,
                                categoryId: nil,
                                parentCategorySlug: nil,
                                tag: tagName
                            )
                        } label: {
                            Text("#\(tagName)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(FireTheme.tagChipForeground)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(FireTheme.tagChipBackground)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(row.statusLabels, id: \.self) { label in
                        FireStatusChip(label: label, tone: .accent)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var topicAiSummaryRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FireTheme.accent)
                Text("AI 摘要")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if topicAiSummary?.outdated == true {
                    Text("有新回复")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FireTheme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(FireTheme.warning.opacity(0.12), in: Capsule())
                }
            }

            if let topicAiSummary {
                Text(topicAiSummary.summarizedText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                let metadata = topicAiSummaryMetadata(topicAiSummary)
                if !metadata.isEmpty {
                    Text(metadata.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if isLoadingTopicAiSummary {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在加载摘要…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let topicAiSummaryError {
                HStack(spacing: 8) {
                    Text(topicAiSummaryError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button("重试") {
                        onReloadTopicAiSummary()
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var originalPostRow: some View {
        Group {
            if let originalPost {
                let renderContent = originalPostRenderContent
                    ?? fallbackRenderContent(for: originalPost)
                FireSwipeToReplyContainer(enabled: canWriteInteractions) {
                    onOpenComposer(originalPost)
                } content: {
                    FirePostRow(
                        post: originalPost,
                        renderContent: renderContent,
                        depth: 0,
                        replyContext: nil,
                        replyTargetPostNumber: nil,
                        showsThreadLine: false,
                        baseURLString: baseURLString,
                        canWriteInteractions: canWriteInteractions,
                        isMutating: isMutatingPost(originalPost.id),
                        onLinkTapped: onLinkTapped,
                        onOpenImage: onOpenImage,
                        onToggleLike: onToggleLike,
                        onSelectReaction: onSelectReaction,
                        onEditPost: onEditPost,
                        onBookmarkPost: onBookmarkPost,
                        onDeletePost: onDeletePost,
                        onRecoverPost: onRecoverPost,
                        onFlagPost: onFlagPost,
                        onOpenReplyTarget: onOpenPostNumber,
                        onOpenReplies: onOpenPostReplies,
                        onVotePoll: onVotePoll,
                        onUnvotePoll: onUnvotePoll
                    )
                }
            } else if let excerpt = row.excerptText {
                Text(excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            HStack(spacing: 20) {
                statLabel(value: "\(displayedReplyCount)", label: "回复")
                statLabel(value: "\(displayedViewsCount)", label: "浏览")
                statLabel(value: displayedInteractionCount.map(String.init) ?? "…", label: "互动")
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var topicVoteRow: some View {
        if let detail, showsTopicVote {
            topicVotePanel(detail)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statLabel(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var repliesHeaderRow: some View {
        HStack {
            Text("回复")
                .font(.headline)
            Spacer()
            if let detail {
                let totalReplyCount = max(Int(detail.postsCount) - 1, 0)
                if loadedReplyCount < totalReplyCount {
                    Text("已加载 \(loadedReplyCount) / \(totalReplyCount) 条")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(totalReplyCount) 条 · \(displayedFloorCount) 楼")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var bodyStateRow: some View {
        if isLoadingTopic {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    ProgressView()
                    Text("加载中…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 30)
                Spacer()
            }
            .padding(.horizontal, 16)
        } else if let detailError {
            VStack(spacing: 8) {
                Text(detailError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("重试") {
                    Task {
                        await onLoadTopicDetail()
                    }
                }
                .buttonStyle(.bordered)
                .tint(FireTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        } else {
            Button("加载帖子") {
                Task {
                    await onLoadTopicDetail()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private func replyRow(
        for key: FireTopicDetailCollectionReplyKey,
        replyIndexByPostID: [UInt64: Int]
    ) -> some View {
        let replyIndex: Int? = {
            guard let idx = replyIndexByPostID[key.postID],
                  idx < replyRows.count,
                  replyRows[idx].entry.postNumber == key.postNumber else {
                return nil
            }
            return idx
        }()
        let row = replyIndex.map { replyRows[$0] }
        let showsDivider = replyIndex.map { $0 != replyRows.count - 1 } ?? false

        VStack(spacing: 0) {
            if let row,
               let post = postLookup[row.entry.postId] {
                let renderContent = renderState?.contentByPostID[row.entry.postId]
                    ?? fallbackRenderContent(for: post)
                FireSwipeToReplyContainer(enabled: canWriteInteractions) {
                    onOpenComposer(post)
                } content: {
                    FirePostRow(
                        post: post,
                        renderContent: renderContent,
                        depth: Int(row.entry.depth),
                        replyContext: Self.replyContextLabel(
                            for: post,
                            preferredPostNumber: row.entry.parentPostNumber
                        ),
                        replyTargetPostNumber: Self.replyTargetPostNumber(
                            for: post,
                            preferredPostNumber: row.entry.parentPostNumber
                        ),
                        showsThreadLine: showsTimelineThreadLine(in: replyRows, at: replyIndex ?? 0),
                        baseURLString: baseURLString,
                        canWriteInteractions: canWriteInteractions,
                        isMutating: isMutatingPost(post.id),
                        onLinkTapped: onLinkTapped,
                        onOpenImage: onOpenImage,
                        onToggleLike: onToggleLike,
                        onSelectReaction: onSelectReaction,
                        onEditPost: onEditPost,
                        onBookmarkPost: onBookmarkPost,
                        onDeletePost: onDeletePost,
                        onRecoverPost: onRecoverPost,
                        onFlagPost: onFlagPost,
                        onOpenReplyTarget: onOpenPostNumber,
                        onOpenReplies: onOpenPostReplies,
                        onVotePoll: onVotePoll,
                        onUnvotePoll: onUnvotePoll
                    )
                }
            } else if let row {
                FireTopicPostPlaceholder(depth: Int(row.entry.depth))
            }

            if showsDivider {
                Divider()
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var replyFooterRow: some View {
        switch replyFooterState {
        case .none:
            Color.clear.frame(height: 0)
        case .empty:
            Text("还没有回复")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
        case .loadingFooter:
            FireTopicPostsLoadingFooter()
                .padding(.horizontal, 16)
                .padding(.vertical, replyRows.isEmpty ? 16 : 12)
                .task(id: topic.id) {
                    guard replyRows.isEmpty else { return }
                    let seedVisiblePostNumbers = originalPost.map { Set([$0.postNumber]) } ?? []
                    onPreloadTopicPosts(seedVisiblePostNumbers)
                }
        }
    }

    private func showsTimelineThreadLine(in rows: [FirePreparedTopicTimelineRow], at index: Int) -> Bool {
        guard index < rows.count - 1 else {
            return false
        }
        return rows[index + 1].entry.depth >= rows[index].entry.depth
    }

    private func topicVotePanel(_ detail: TopicDetailState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("\(detail.voteCount) 票", systemImage: "hand.thumbsup.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FireTheme.accent)

                if detail.userVoted {
                    Text("你已投票")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    Task { await onToggleTopicVote() }
                } label: {
                    Text(detail.userVoted ? "取消投票" : "投一票")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(detail.userVoted ? FireTheme.subtleInk : .white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            detail.userVoted ? FireTheme.softSurface : FireTheme.accent,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canWriteInteractions)

                Button {
                    Task { await onShowTopicVoters() }
                } label: {
                    Label("查看投票用户", systemImage: "person.3")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(FireTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(FireTheme.softSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private static func replyRowToken(
        row: FirePreparedTopicTimelineRow,
        post: TopicPostState?,
        renderContent: FireTopicPostRenderContent?,
        showsThreadLine: Bool,
        isMutating: Bool
    ) -> String {
        [
            String(row.entry.postId),
            String(row.entry.postNumber),
            String(row.entry.parentPostNumber ?? 0),
            String(row.entry.depth),
            String(showsThreadLine),
            post.map { postContentToken($0, renderContent: renderContent, isMutating: isMutating) } ?? "missing",
        ].joined(separator: "|")
    }

    private func topicAiSummaryMetadata(_ summary: TopicAiSummaryState) -> [String] {
        var metadata: [String] = []
        if let updatedAt = FireTopicPresentation.formatTimestamp(summary.updatedAt) {
            metadata.append("更新 \(updatedAt)")
        }
        if summary.outdated, summary.newPostsSinceSummary > 0 {
            metadata.append("\(summary.newPostsSinceSummary) 条新回复")
        }
        if let algorithm = summary.algorithm?.trimmingCharacters(in: .whitespacesAndNewlines),
           !algorithm.isEmpty {
            metadata.append(algorithm)
        }
        if summary.canRegenerate {
            metadata.append("可重新生成")
        }
        return metadata
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

    private static func postContentToken(
        _ post: TopicPostState,
        renderContent: FireTopicPostRenderContent?,
        isMutating: Bool
    ) -> String {
        let imageToken = renderContent?.imageAttachments.map(\.id).joined(separator: ",") ?? ""
        var parts: [String] = []
        parts.reserveCapacity(26)
        parts.append(String(post.id))
        parts.append(String(post.postNumber))
        parts.append(post.username)
        parts.append(post.avatarTemplate ?? "")
        parts.append(post.createdAt ?? "")
        parts.append(post.cooked)
        parts.append(String(post.replyCount))
        parts.append(String(post.replyToPostNumber ?? 0))
        parts.append(post.replyToUser?.username ?? "")
        parts.append(post.replyToUser?.name ?? "")
        parts.append(post.replyToUser?.avatarTemplate ?? "")
        parts.append(String(post.acceptedAnswer))
        parts.append(String(post.canEdit))
        parts.append(String(post.canDelete))
        parts.append(String(post.canRecover))
        parts.append(String(post.hidden))
        parts.append(String(post.bookmarked))
        parts.append(String(post.bookmarkId ?? 0))
        parts.append(post.bookmarkName ?? "")
        parts.append(post.bookmarkReminderAt ?? "")
        parts.append(String(reflecting: post.reactions))
        parts.append(String(reflecting: post.currentUserReaction))
        parts.append(String(reflecting: post.polls))
        parts.append(renderContent?.plainText ?? "")
        parts.append(imageToken)
        parts.append(String(isMutating))
        return parts.joined(separator: "\u{1F}")
    }
}

private enum FireTopicDetailReplyFooterState: Hashable {
    case none
    case empty
    case loadingFooter
}
