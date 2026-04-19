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
    case originalPost(topicID: UInt64)
    case stats(topicID: UInt64)
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
    let topicTitle: String
    let categoryToken: String?
    let tagNames: [String]
    let participantTokens: [String]
    let statusLabels: [String]
    let excerptText: String?
    let displayedReplyCount: UInt32
    let displayedViewsCount: UInt32
    let displayedInteractionCount: UInt32?
    let loadedReplyCount: Int
    let totalReplyCount: Int
    let displayedFloorCount: Int
    let isPrivateMessageThread: Bool
    let isLoadingTopic: Bool
    let detailError: String?
    let hasMoreTopicPosts: Bool
    let isLoadingMoreTopicPosts: Bool
    let canWriteInteractions: Bool
    let topicVoteToken: String?
    let originalPostToken: String?
    let replyRowTokens: [String]
}

struct FireTopicDetailCollectionView: View {
    @EnvironmentObject private var topicDetailStore: FireTopicDetailStore
    @Environment(\.colorScheme) private var colorScheme

    let viewModel: FireAppViewModel
    let row: FireTopicRowPresentation
    let detail: TopicDetailState?
    let renderState: FireTopicDetailRenderState?
    let pendingScrollTarget: UInt32?
    let canWriteInteractions: Bool
    let onVisiblePostNumbersChanged: (Set<UInt32>) -> Void
    let onRefresh: () async -> Void
    let onScrollTargetHandled: (UInt32) -> Void
    let onOpenComposer: (TopicPostState?) -> Void
    let onOpenImage: (FireCookedImage) -> Void
    let onToggleLike: (TopicPostState) -> Void
    let onSelectReaction: (TopicPostState, String) -> Void
    let onEditPost: (TopicPostState) -> Void
    let onVotePoll: (TopicPostState, PollState, [String]) -> Void
    let onUnvotePoll: (TopicPostState, PollState) -> Void
    let onToggleTopicVote: () async -> Void
    let onShowTopicVoters: () async -> Void

    private var topic: TopicSummaryState {
        row.topic
    }

    private var detailError: String? {
        topicDetailStore.errorMessage
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

    private var postLookup: [UInt64: TopicPostState] {
        Dictionary(uniqueKeysWithValues: (detail?.postStream.posts ?? []).map { ($0.id, $0) })
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

    private var hasMoreTopicPosts: Bool {
        topicDetailStore.hasMoreTopicPosts(topicId: topic.id)
    }

    private var isLoadingTopic: Bool {
        topicDetailStore.isLoadingTopic(topicId: topic.id)
    }

    private var isLoadingMoreTopicPosts: Bool {
        topicDetailStore.isLoadingMoreTopicPosts(topicId: topic.id)
    }

    private var sections: [FireListSectionModel<FireTopicDetailCollectionSection, FireTopicDetailCollectionItem>] {
        let topicItems: [FireTopicDetailCollectionItem] = [
            .header(topicID: topic.id),
            .originalPost(topicID: topic.id),
            .stats(topicID: topic.id),
        ]

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

    private var contentVersion: FireTopicDetailCollectionContentVersion {
        FireTopicDetailCollectionContentVersion(
            topicTitle: displayedTopicTitle,
            categoryToken: displayedCategory.map {
                "\($0.id)|\($0.slug)|\($0.displayName)|\($0.colorHex ?? "")"
            },
            tagNames: displayedTagNames,
            participantTokens: displayedParticipants.map {
                "\($0.userId)|\($0.username ?? "")|\($0.name ?? "")"
            },
            statusLabels: row.statusLabels,
            excerptText: row.excerptText,
            displayedReplyCount: displayedReplyCount,
            displayedViewsCount: displayedViewsCount,
            displayedInteractionCount: displayedInteractionCount,
            loadedReplyCount: loadedReplyCount,
            totalReplyCount: detail.map { max(Int($0.postsCount) - 1, 0) } ?? Int(topic.replyCount),
            displayedFloorCount: displayedFloorCount,
            isPrivateMessageThread: isPrivateMessageThread,
            isLoadingTopic: isLoadingTopic,
            detailError: detailError,
            hasMoreTopicPosts: hasMoreTopicPosts,
            isLoadingMoreTopicPosts: isLoadingMoreTopicPosts,
            canWriteInteractions: canWriteInteractions,
            topicVoteToken: detail.flatMap { detail in
                guard !isPrivateMessageThread,
                      detail.canVote || detail.userVoted || detail.voteCount > 0 else {
                    return nil
                }
                return "\(detail.canVote)|\(detail.userVoted)|\(detail.voteCount)"
            },
            originalPostToken: originalPost.map { post in
                Self.postContentToken(
                    post,
                    renderContent: originalPostRenderContent,
                    isMutating: topicDetailStore.isMutatingPost(postId: post.id)
                )
            },
            replyRowTokens: replyRows.enumerated().map { index, row in
                let post = postLookup[row.entry.postId]
                return Self.replyRowToken(
                    row: row,
                    post: post,
                    renderContent: renderState?.contentByPostID[row.entry.postId],
                    showsThreadLine: showsTimelineThreadLine(in: replyRows, at: index),
                    isMutating: post.map { topicDetailStore.isMutatingPost(postId: $0.id) } ?? false
                )
            }
        )
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
        FireCollectionHost(
            sections: sections,
            contentVersion: contentVersion,
            backgroundColor: .systemBackground,
            animatingDifferences: true,
            onVisibleItemsChanged: handleVisibleItemsChanged(_:),
            onRefresh: onRefresh,
            scrollRequest: scrollRequest,
            onScrollRequestCompleted: handleScrollRequestCompleted(_:),
            makeLayout: Self.makeLayout,
            rowContent: rowView(for:)
        )
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
    private func rowView(for item: FireTopicDetailCollectionItem) -> some View {
        switch item {
        case .header:
            headerRow
        case .originalPost:
            originalPostRow
        case .stats:
            statsRow
        case .repliesHeader:
            repliesHeaderRow
        case .bodyState:
            bodyStateRow
        case let .reply(key):
            replyRow(for: key)
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
    private var originalPostRow: some View {
        Group {
            if let originalPost,
               let originalRenderContent = originalPostRenderContent {
                FireSwipeToReplyContainer(enabled: canWriteInteractions) {
                    onOpenComposer(originalPost)
                } content: {
                    FirePostRow(
                        post: originalPost,
                        renderContent: originalRenderContent,
                        depth: 0,
                        replyContext: nil,
                        showsThreadLine: false,
                        baseURLString: baseURLString,
                        canWriteInteractions: canWriteInteractions,
                        isMutating: topicDetailStore.isMutatingPost(postId: originalPost.id),
                        onOpenImage: onOpenImage,
                        onToggleLike: onToggleLike,
                        onSelectReaction: onSelectReaction,
                        onEditPost: onEditPost,
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

            if let detail,
               !isPrivateMessageThread,
               detail.canVote || detail.userVoted || detail.voteCount > 0 {
                topicVotePanel(detail)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        await topicDetailStore.loadTopicDetail(topicId: topic.id, force: true)
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
                    await topicDetailStore.loadTopicDetail(topicId: topic.id, force: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private func replyRow(for key: FireTopicDetailCollectionReplyKey) -> some View {
        let replyIndex = replyRows.firstIndex(where: {
            $0.entry.postId == key.postID && $0.entry.postNumber == key.postNumber
        })
        let row = replyIndex.map { replyRows[$0] }
        let showsDivider = replyIndex.map { $0 != replyRows.count - 1 } ?? false

        VStack(spacing: 0) {
            if let row,
               let post = postLookup[row.entry.postId] {
                FireSwipeToReplyContainer(enabled: canWriteInteractions) {
                    onOpenComposer(post)
                } content: {
                    FirePostRow(
                        post: post,
                        renderContent: renderState?.contentByPostID[row.entry.postId]
                            ?? FireTopicPresentation.renderContent(
                                from: post.cooked,
                                baseURLString: baseURLString
                            ),
                        depth: Int(row.entry.depth),
                        replyContext: row.entry.parentPostNumber.map { "回复 #\($0)" },
                        showsThreadLine: showsTimelineThreadLine(in: replyRows, at: replyIndex ?? 0),
                        baseURLString: baseURLString,
                        canWriteInteractions: canWriteInteractions,
                        isMutating: topicDetailStore.isMutatingPost(postId: post.id),
                        onOpenImage: onOpenImage,
                        onToggleLike: onToggleLike,
                        onSelectReaction: onSelectReaction,
                        onEditPost: onEditPost,
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
                    topicDetailStore.preloadTopicPostsIfNeeded(
                        topicId: topic.id,
                        visiblePostNumbers: seedVisiblePostNumbers
                    )
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

    private static func postContentToken(
        _ post: TopicPostState,
        renderContent: FireTopicPostRenderContent?,
        isMutating: Bool
    ) -> String {
        let imageToken = renderContent?.imageAttachments.map(\.id).joined(separator: ",") ?? ""
        var parts: [String] = []
        parts.reserveCapacity(15)
        parts.append(String(post.id))
        parts.append(String(post.postNumber))
        parts.append(post.username)
        parts.append(post.avatarTemplate ?? "")
        parts.append(post.createdAt ?? "")
        parts.append(post.cooked)
        parts.append(String(post.replyToPostNumber ?? 0))
        parts.append(String(post.acceptedAnswer))
        parts.append(String(post.canEdit))
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