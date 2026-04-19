import Photos
import SwiftUI

enum FireTopicDetailViewState {
    static func resolvedDetail(
        liveDetail: TopicDetailState?,
        cachedDetail: TopicDetailState?
    ) -> TopicDetailState? {
        liveDetail ?? cachedDetail
    }

    static func syncedCachedDetail(
        topicId: UInt64,
        topicDetails: [UInt64: TopicDetailState]
    ) -> TopicDetailState? {
        topicDetails[topicId]
    }

    static func syncedCachedRenderState(
        topicId: UInt64,
        topicRenderStates: [UInt64: FireTopicDetailRenderState]
    ) -> FireTopicDetailRenderState? {
        topicRenderStates[topicId]
    }

    static func hasLoadedDetailForSubscription(liveDetail: TopicDetailState?) -> Bool {
        liveDetail != nil
    }
}

private struct FireReplyComposerContext: Identifiable, Equatable {
    let topicId: UInt64
    let postId: UInt64?
    let replyToPostNumber: UInt32?
    let replyToUsername: String?

    var id: String {
        "\(topicId)-\(postId ?? 0)-\(replyToPostNumber ?? 0)"
    }

    var targetSummary: String {
        if let replyToUsername, !replyToUsername.isEmpty {
            return "回复 \(replyToUsername)"
        }
        if let replyToPostNumber {
            return "回复 #\(replyToPostNumber)"
        }
        return "回复话题"
    }

    var placeholder: String {
        if let replyToUsername, !replyToUsername.isEmpty {
            return "回复\(replyToUsername):"
        }
        return "快速回复…"
    }
}

private struct FirePostEditorContext: Identifiable, Equatable {
    let postID: UInt64
    let postNumber: UInt32

    var id: UInt64 { postID }
}

private enum FireTopicNotificationLevelOption: Int32, CaseIterable, Identifiable {
    case muted = 0
    case regular = 1
    case tracking = 2
    case watching = 3

    var id: Int32 { rawValue }

    var title: String {
        switch self {
        case .muted: "静音"
        case .regular: "普通"
        case .tracking: "跟踪"
        case .watching: "关注"
        }
    }
}

struct FireTopicDetailView: View {
    fileprivate static let scrollCoordinateSpaceName = "fire-topic-detail-scroll"

    static func topicDetailSubscriptionTaskID(
        topicId: UInt64,
        canOpenMessageBus: Bool,
        hasLoadedDetail: Bool
    ) -> String {
        "\(topicId)-\(canOpenMessageBus)-\(hasLoadedDetail)"
    }

    @EnvironmentObject private var topicDetailStore: FireTopicDetailStore
    let viewModel: FireAppViewModel
    let row: FireTopicRowPresentation
    let scrollToPostNumber: UInt32?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var composerContext: FireReplyComposerContext?
    @State private var advancedComposerContext: FireReplyComposerContext?
    @State private var replyDraft = ""
    @State private var composerNotice: String?
    @State private var quickReplyError: String?
    @State private var timingTracker: FireTopicTimingTracker
    @State private var detailOwnerToken: String
    @State private var bookmarkEditorContext: FireBookmarkEditorContext?
    @State private var selectedImage: FireCookedImage?
    @State private var postEditorContext: FirePostEditorContext?
    @State private var showingTopicEditor = false
    @State private var topicVoters: [VotedUserState] = []
    @State private var isLoadingTopicVoters = false
    @State private var showingTopicVoters = false
    @State private var cachedDetail: TopicDetailState?
    @State private var cachedRenderState: FireTopicDetailRenderState?
    @FocusState private var isReplyFieldFocused: Bool

    init(viewModel: FireAppViewModel, row: FireTopicRowPresentation, scrollToPostNumber: UInt32? = nil) {
        self.viewModel = viewModel
        self.row = row
        self.scrollToPostNumber = scrollToPostNumber
        _timingTracker = State(initialValue: FireTopicTimingTracker(topicId: row.topic.id))
        _detailOwnerToken = State(initialValue: Self.makeDetailOwnerToken(topicId: row.topic.id))
    }

    private var topic: TopicSummaryState {
        row.topic
    }

    private var liveDetail: TopicDetailState? {
        topicDetailStore.topicDetail(for: topic.id)
    }

    private var liveRenderState: FireTopicDetailRenderState? {
        topicDetailStore.topicRenderState(for: topic.id)
    }

    private var detail: TopicDetailState? {
        FireTopicDetailViewState.resolvedDetail(
            liveDetail: liveDetail,
            cachedDetail: cachedDetail
        )
    }

    private var renderState: FireTopicDetailRenderState? {
        liveRenderState ?? cachedRenderState
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

    private var displayedTopicSlug: String {
        let trimmedDetailSlug = detail?.slug.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedDetailSlug.isEmpty {
            return trimmedDetailSlug
        }
        return topic.slug.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var renderedPostNumbers: Set<UInt32> {
        renderState?.renderedPostNumbers ?? []
    }

    private var reactionOptions: [FireReactionOption] {
        FireTopicPresentation.enabledReactionOptions(from: viewModel.session.bootstrap.enabledReactionIds)
    }

    private var typingUsers: [TopicPresenceUserState] {
        topicDetailStore.topicPresenceUsers(for: topic.id)
    }

    private var pendingScrollTarget: UInt32? {
        topicDetailStore.pendingScrollTarget(topicId: topic.id)
    }

    private var nonHeartReactionOptions: [FireReactionOption] {
        reactionOptions.filter { $0.id != "heart" }
    }

    private var minimumReplyLength: Int {
        let minLength = isPrivateMessageThread
            ? viewModel.session.bootstrap.minPersonalMessagePostLength
            : viewModel.session.bootstrap.minPostLength
        return FireTopicPresentation.minimumReplyLength(from: minLength)
    }

    private var baseURLString: String {
        let trimmed = viewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    private var canWriteInteractions: Bool {
        viewModel.canStartAuthenticatedMutation
    }

    private var topicShareURL: URL? {
        let trimmedSlug = displayedTopicSlug
        return URL(string: "\(baseURLString)/t/\(trimmedSlug.isEmpty ? "topic-\(topic.id)" : trimmedSlug)/\(topic.id)")
    }

    private var currentTopicNotificationLevel: FireTopicNotificationLevelOption {
        FireTopicNotificationLevelOption(rawValue: Int32(detail?.details.notificationLevel ?? 1)) ?? .regular
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

    private var topicBookmarkContext: FireBookmarkEditorContext {
        FireBookmarkEditorContext(
            bookmarkID: detail?.bookmarkId,
            bookmarkableID: topic.id,
            bookmarkableType: "Topic",
            title: displayedTopicTitle,
            initialName: detail?.bookmarkName,
            initialReminderAt: detail?.bookmarkReminderAt,
            allowsDelete: detail?.bookmarkId != nil
        )
    }

    private var messageBusSubscriptionTaskID: String {
        Self.topicDetailSubscriptionTaskID(
            topicId: topic.id,
            canOpenMessageBus: viewModel.session.readiness.canOpenMessageBus,
            hasLoadedDetail: FireTopicDetailViewState.hasLoadedDetailForSubscription(
                liveDetail: liveDetail
            )
        )
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

    private var trimmedReplyDraft: String {
        replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSubmittingReply: Bool {
        topicDetailStore.isSubmittingReply(topicId: topic.id)
    }

    private var composerTargetPost: TopicPostState? {
        guard let postId = composerContext?.postId else {
            return nil
        }
        return detail?.postStream.posts.first(where: { $0.id == postId })
    }

    private var replyPrompt: String {
        composerContext?.placeholder ?? "快速回复…"
    }

    private func canChangeReaction(for post: TopicPostState) -> Bool {
        canWriteInteractions
            && !topicDetailStore.isMutatingPost(postId: post.id)
            && (post.currentUserReaction?.canUndo ?? true)
    }

    var body: some View {
        return GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        topicHeaderSection
                            .padding(.bottom, 18)
                        postsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .coordinateSpace(name: Self.scrollCoordinateSpaceName)
                .onPreferenceChange(FireVisiblePostFramePreferenceKey.self) { frames in
                    updateVisiblePostFrames(
                        frames,
                        viewportHeight: geometry.size.height
                    )
                }
                .onChange(of: detail?.postStream.posts.count) { _, _ in
                    scrollToTargetPostIfNeeded(proxy: scrollProxy)
                }
                .task(id: pendingScrollTarget) {
                    scrollToTargetPostIfNeeded(proxy: scrollProxy)
                }
            }
        }
        .navigationTitle("话题")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let topicShareURL {
                    ShareLink(item: topicShareURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                Menu {
                    if detail?.details.canEdit == true && !isPrivateMessageThread {
                        Button {
                            showingTopicEditor = true
                        } label: {
                            Label("编辑话题", systemImage: "pencil")
                        }

                        Divider()
                    }

                    Button {
                        bookmarkEditorContext = topicBookmarkContext
                    } label: {
                        Label(
                            detail?.bookmarked == true ? "编辑书签" : "添加书签",
                            systemImage: detail?.bookmarked == true ? "bookmark.fill" : "bookmark"
                        )
                    }
                    .disabled(!canWriteInteractions)

                    Divider()

                    if !isPrivateMessageThread {
                        ForEach(FireTopicNotificationLevelOption.allCases) { option in
                            Button {
                                Task {
                                    await updateTopicNotificationLevel(option)
                                }
                            } label: {
                                if option == currentTopicNotificationLevel {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                            .disabled(!canWriteInteractions)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if canWriteInteractions {
                quickReplyBar
            }
        }
        .sheet(item: $bookmarkEditorContext) { context in
            FireBookmarkEditorSheet(
                context: context,
                onSave: { name, reminderAt in
                    if let bookmarkID = context.bookmarkID {
                        try await viewModel.updateBookmark(
                            bookmarkID: bookmarkID,
                            name: name,
                            reminderAt: reminderAt
                        )
                    } else {
                        _ = try await viewModel.createBookmark(
                            bookmarkableID: context.bookmarkableID,
                            bookmarkableType: context.bookmarkableType,
                            name: name,
                            reminderAt: reminderAt
                        )
                    }
                    await topicDetailStore.loadTopicDetail(topicId: topic.id, force: true)
                },
                onDelete: context.bookmarkID.map { bookmarkID in
                    {
                        try await viewModel.deleteBookmark(bookmarkID: bookmarkID)
                        await topicDetailStore.loadTopicDetail(topicId: topic.id, force: true)
                    }
                }
            )
        }
        .sheet(item: $postEditorContext) { context in
            NavigationStack {
                FirePostEditorView(
                    viewModel: viewModel,
                    topicID: topic.id,
                    postID: context.postID,
                    postNumber: context.postNumber,
                    onSaved: {
                        Task {
                            await topicDetailStore.loadTopicDetail(topicId: topic.id, force: true)
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingTopicEditor) {
            NavigationStack {
                FireTopicEditorView(
                    viewModel: viewModel,
                    topicID: topic.id,
                    initialTitle: detail?.title ?? topic.title,
                    initialCategoryID: detail?.categoryId ?? topic.categoryId,
                    initialTags: detail?.tags.map(\.name) ?? row.tagNames,
                    onSaved: {
                        Task {
                            await topicDetailStore.loadTopicDetail(topicId: topic.id, force: true)
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingTopicVoters) {
            NavigationStack {
                FireTopicVotersSheet(
                    voters: topicVoters,
                    isLoading: isLoadingTopicVoters
                )
            }
        }
        .fullScreenCover(item: $advancedComposerContext) { context in
            NavigationStack {
                FireComposerView(
                    viewModel: viewModel,
                    route: FireComposerRoute(
                        kind: .advancedReply(
                            topicID: topic.id,
                            topicTitle: displayedTopicTitle,
                            categoryID: displayedCategoryId,
                            replyToPostNumber: context.replyToPostNumber,
                            replyToUsername: context.replyToUsername,
                            isPrivateMessage: isPrivateMessageThread
                        )
                    ),
                    initialBody: replyDraft,
                    onReplySubmitted: {
                        replyDraft = ""
                        composerContext = nil
                        quickReplyError = nil
                        Task {
                            await topicDetailStore.loadTopicDetail(topicId: topic.id, force: true)
                        }
                    },
                    onSubmissionNotice: { message in
                        composerNotice = message
                    }
                )
            }
        }
        .fullScreenCover(item: $selectedImage) { image in
            FireTopicImageViewer(image: image)
        }
        .scrollDismissesKeyboard(.interactively)
        .alert("提示", isPresented: Binding(
            get: { composerNotice != nil },
            set: { presenting in
                if !presenting {
                    composerNotice = nil
                }
            }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(composerNotice ?? "")
        }
        .refreshable {
            timingTracker.recordInteraction()
            topicDetailStore.clearTopicDetailAnchor(topicId: topic.id)
            await topicDetailStore.loadTopicDetail(topicId: topic.id, force: true)
        }
        .onAppear {
            topicDetailStore.beginTopicDetailLifecycle(topicId: topic.id, ownerToken: detailOwnerToken)
            viewModel.setAPMRoute("topic.detail.\(topic.id)")
            if let current = liveDetail {
                cachedDetail = current
            }
            if let current = liveRenderState {
                cachedRenderState = current
            }
        }
        .onReceive(topicDetailStore.$topicDetails) { dict in
            cachedDetail = FireTopicDetailViewState.syncedCachedDetail(
                topicId: topic.id,
                topicDetails: dict
            )
        }
        .onReceive(topicDetailStore.$topicRenderStates) { dict in
            cachedRenderState = FireTopicDetailViewState.syncedCachedRenderState(
                topicId: topic.id,
                topicRenderStates: dict
            )
        }
        .task(id: topic.id) {
            timingTracker.start { topicId, topicTimeMs, timings in
                await viewModel.reportTopicTimings(
                    topicId: topicId,
                    topicTimeMs: topicTimeMs,
                    timings: timings
                )
            }
            await timingTracker.setSceneActive(scenePhase == .active)
            await topicDetailStore.loadTopicDetail(
                topicId: topic.id,
                targetPostNumber: scrollToPostNumber
            )
        }
        .task(id: messageBusSubscriptionTaskID) {
            await topicDetailStore.maintainTopicDetailSubscription(
                topicId: topic.id,
                ownerToken: detailOwnerToken
            )
        }
        .onChange(of: scenePhase) { _, phase in
            Task {
                await timingTracker.setSceneActive(phase == .active)
            }
        }
        .onChange(of: isReplyFieldFocused) { _, isFocused in
            if isFocused {
                topicDetailStore.beginTopicReplyPresence(topicId: topic.id)
            } else {
                Task {
                    await topicDetailStore.endTopicReplyPresence(topicId: topic.id)
                }
            }
        }
        .onDisappear {
            topicDetailStore.endTopicDetailLifecycle(
                topicId: topic.id,
                ownerToken: detailOwnerToken,
                visibleTopicIDs: viewModel.currentVisibleTopicIDs()
            )
            viewModel.restoreTopLevelAPMRoute()
            Task {
                await timingTracker.stop()
                await topicDetailStore.endTopicReplyPresence(topicId: topic.id)
            }
        }
        .onChange(of: replyDraft) { _, _ in
            if quickReplyError != nil {
                quickReplyError = nil
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    timingTracker.recordInteraction()
                }
        )
        .simultaneousGesture(TapGesture().onEnded {
            timingTracker.recordInteraction()
            dismissKeyboard()
        })
    }

    private static func makeDetailOwnerToken(topicId: UInt64) -> String {
        "ios.topic-detail.\(topicId).\(UUID().uuidString.lowercased())"
    }

    private func scrollToTargetPostIfNeeded(proxy: ScrollViewProxy) {
        guard let target = pendingScrollTarget else {
            return
        }

        if topicDetailStore.isScrollTargetExhausted(topicId: topic.id, postNumber: target) {
            topicDetailStore.markScrollTargetSatisfied(topicId: topic.id, postNumber: target)
            return
        }

        guard renderedPostNumbers.contains(target) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
        topicDetailStore.markScrollTargetSatisfied(topicId: topic.id, postNumber: target)
    }

    private var topicHeaderSection: some View {
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
                                backgroundColor: FireTheme.categoryChipBackground(accent: accent, isDark: colorScheme == .dark),
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

            if let originalPost,
               let originalRenderContent = originalPostRenderContent {
                FireSwipeToReplyContainer(enabled: canWriteInteractions) {
                    openComposer(replyToPost: originalPost)
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
                        onOpenImage: { selectedImage = $0 },
                        onToggleLike: { toggleLike(for: $0) },
                        onSelectReaction: { post, reactionId in
                            toggleReaction(reactionId, for: post)
                        },
                        onEditPost: { postEditorContext = FirePostEditorContext(postID: $0.id, postNumber: $0.postNumber) },
                        onVotePoll: { post, poll, options in
                            submitPollVote(for: post, poll: poll, options: options)
                        },
                        onUnvotePoll: { post, poll in
                            removePollVote(for: post, poll: poll)
                        }
                    )
                }
                .id(originalPost.postNumber)
                .background(FireVisiblePostFrameReporter(postNumber: originalPost.postNumber))
            } else if let excerpt = row.excerptText {
                Text(excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
        .padding(.vertical, 4)
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

    private var postsSectionHeader: some View {
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
    }

    @ViewBuilder
    private var postsSection: some View {
        postsSectionHeader
            .padding(.bottom, 14)

        if detail != nil {
            let displayRows = replyRows

            if displayRows.isEmpty {
                if topicDetailStore.hasMoreTopicPosts(topicId: topic.id) {
                    FireTopicPostsLoadingFooter()
                        .padding(.vertical, 16)
                        .task(id: topic.id) {
                            let seedVisiblePostNumbers = originalPost.map { Set([ $0.postNumber ]) } ?? []
                            topicDetailStore.preloadTopicPostsIfNeeded(
                                topicId: topic.id,
                                visiblePostNumbers: seedVisiblePostNumbers
                            )
                        }
                } else {
                    Text("还没有回复")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                }
            } else {
                replyPostRows(displayRows)

                if topicDetailStore.isLoadingMoreTopicPosts(topicId: topic.id) {
                    FireTopicPostsLoadingFooter()
                        .padding(.top, 12)
                }
            }
        } else if topicDetailStore.isLoadingTopic(topicId: topic.id) {
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
            .padding(.vertical, 20)
        } else {
            Button("加载帖子") {
                Task {
                    await topicDetailStore.loadTopicDetail(topicId: topic.id, force: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private func replyPostRows(_ displayRows: [FirePreparedTopicTimelineRow]) -> some View {
        ForEach(Array(displayRows.enumerated()), id: \.element.id) { index, row in
            Group {
                if let post = postLookup[row.entry.postId] {
                    FireSwipeToReplyContainer(enabled: canWriteInteractions) {
                        openComposer(replyToPost: post)
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
                            showsThreadLine: showsTimelineThreadLine(in: displayRows, at: index),
                            baseURLString: baseURLString,
                            canWriteInteractions: canWriteInteractions,
                            isMutating: topicDetailStore.isMutatingPost(postId: post.id),
                            onOpenImage: { selectedImage = $0 },
                            onToggleLike: { toggleLike(for: $0) },
                            onSelectReaction: { post, reactionId in
                                toggleReaction(reactionId, for: post)
                            },
                            onEditPost: { postEditorContext = FirePostEditorContext(postID: $0.id, postNumber: $0.postNumber) },
                            onVotePoll: { post, poll, options in
                                submitPollVote(for: post, poll: poll, options: options)
                            },
                            onUnvotePoll: { post, poll in
                                removePollVote(for: post, poll: poll)
                            }
                        )
                    }
                } else {
                    FireTopicPostPlaceholder(depth: Int(row.entry.depth))
                }
            }
            .id(row.entry.postNumber)
            .background(FireVisiblePostFrameReporter(postNumber: row.entry.postNumber))

            if index != displayRows.count - 1 {
                Divider()
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
                    Task { await toggleTopicVote() }
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
                    Task { await presentTopicVoters() }
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

    private func updateVisiblePostFrames(
        _ frames: [UInt32: CGRect],
        viewportHeight: CGFloat
    ) {
        let visiblePostNumbers = Set(
            frames.compactMap { postNumber, frame in
                frame.maxY > 0 && frame.minY < viewportHeight ? postNumber : nil
            }
        )
        timingTracker.updateVisiblePostNumbers(visiblePostNumbers)

        topicDetailStore.preloadTopicPostsIfNeeded(
            topicId: topic.id,
            visiblePostNumbers: visiblePostNumbers
        )
    }

    private var quickReplyBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !typingUsers.isEmpty {
                FireTypingPresenceStrip(
                    users: typingUsers,
                    baseURLString: baseURLString
                )
            }

            if let composerContext, let targetPost = composerTargetPost {
                let canChangeTargetReaction = canChangeReaction(for: targetPost)
                FlowLayout(spacing: 8, fallbackWidth: max(UIScreen.main.bounds.width - 32, 200)) {
                    Button {
                        toggleLike(for: targetPost)
                    } label: {
                        composerReactionPill(symbol: "❤️", label: "赞")
                    }
                    .buttonStyle(.plain)
                    .disabled(!canChangeTargetReaction)

                    ForEach(nonHeartReactionOptions) { option in
                        Button {
                            toggleReaction(option.id, for: targetPost)
                        } label: {
                            composerReactionPill(symbol: option.symbol, label: option.label)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canChangeTargetReaction)
                    }
                }

                HStack(spacing: 8) {
                    Text(composerContext.targetSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FireTheme.accent)

                    Spacer()

                    Button {
                        clearComposerTarget()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(FireTheme.tertiaryInk)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    openAdvancedComposer()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(FireTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(Color(.secondarySystemBackground))
                        )
                }
                .buttonStyle(.plain)

                TextField(replyPrompt, text: $replyDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($isReplyFieldFocused)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit {
                        submitQuickReply()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )

                Button {
                    submitQuickReply()
                } label: {
                    if isSubmittingReply {
                        ProgressView()
                            .frame(width: 34, height: 34)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(
                                trimmedReplyDraft.isEmpty ? Color(.tertiaryLabel) : FireTheme.accent
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(trimmedReplyDraft.isEmpty || isSubmittingReply)
            }

            if let quickReplyError {
                Text(quickReplyError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !trimmedReplyDraft.isEmpty && trimmedReplyDraft.count < minimumReplyLength {
                Text("回复至少需要 \(minimumReplyLength) 个字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private func composerReactionPill(symbol: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(symbol)
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
        )
        .foregroundStyle(.primary)
    }

    private func openComposer(replyToPost: TopicPostState?) {
        composerContext = FireReplyComposerContext(
            topicId: topic.id,
            postId: replyToPost?.id,
            replyToPostNumber: replyToPost?.postNumber,
            replyToUsername: replyToPost?.username
        )
        isReplyFieldFocused = true
    }

    private func clearComposerTarget() {
        composerContext = nil
    }

    private func openAdvancedComposer() {
        advancedComposerContext = composerContext
            ?? FireReplyComposerContext(
                topicId: topic.id,
                postId: nil,
                replyToPostNumber: nil,
                replyToUsername: nil
            )
        dismissKeyboard()
    }

    private func dismissKeyboard() {
        isReplyFieldFocused = false
    }

    private func submitQuickReply() {
        let trimmed = trimmedReplyDraft
        guard !trimmed.isEmpty else {
            quickReplyError = "回复内容不能为空。"
            return
        }
        guard trimmed.count >= minimumReplyLength else {
            quickReplyError = "回复至少需要 \(minimumReplyLength) 个字。"
            return
        }

        let topicId = composerContext?.topicId ?? topic.id
        let replyToPostNumber = composerContext?.replyToPostNumber
        quickReplyError = nil

        Task { @MainActor in
            do {
                try await topicDetailStore.submitReply(
                    topicId: topicId,
                    raw: trimmed,
                    replyToPostNumber: replyToPostNumber
                )
                replyDraft = ""
                composerContext = nil
                dismissKeyboard()
            } catch {
                let message = error.localizedDescription
                if message.localizedCaseInsensitiveContains("pending review") {
                    composerNotice = "回复已提交，等待审核。"
                    replyDraft = ""
                    composerContext = nil
                    dismissKeyboard()
                    return
                }
                quickReplyError = message
            }
        }
    }

    private func toggleLike(for post: TopicPostState) {
        applyReactionChange(
            from: post.currentUserReaction,
            to: post.currentUserReaction?.id == "heart" ? nil : "heart",
            postId: post.id
        )
    }

    private func toggleReaction(_ reactionId: String, for post: TopicPostState) {
        let trimmedReactionID = reactionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReactionID.isEmpty else {
            return
        }

        applyReactionChange(
            from: post.currentUserReaction,
            to: post.currentUserReaction?.id == trimmedReactionID ? nil : trimmedReactionID,
            postId: post.id
        )
    }

    private func applyReactionChange(
        from currentReaction: TopicReactionState?,
        to desiredReactionID: String?,
        postId: UInt64
    ) {
        let currentReactionID = currentReaction?.id
        guard currentReactionID != desiredReactionID else {
            return
        }
        guard let toggledReactionID = desiredReactionID ?? currentReactionID, !toggledReactionID.isEmpty else {
            return
        }

        if currentReactionID != nil, currentReaction?.canUndo == false {
            composerNotice = "当前表情回应已超过可撤销时间，暂时不能修改。"
            return
        }

        Task { @MainActor in
            do {
                try await transitionReaction(
                    from: currentReactionID,
                    to: desiredReactionID,
                    toggledReactionId: toggledReactionID,
                    postId: postId
                )
            } catch {
                composerNotice = error.localizedDescription
            }
        }
    }

    private func transitionReaction(
        from currentReactionID: String?,
        to desiredReactionID: String?,
        toggledReactionId: String,
        postId: UInt64
    ) async throws {
        switch (currentReactionID, desiredReactionID) {
        case (nil, "heart"):
            try await topicDetailStore.setPostLiked(
                topicId: topic.id,
                postId: postId,
                liked: true
            )
        case ("heart", nil):
            try await topicDetailStore.setPostLiked(
                topicId: topic.id,
                postId: postId,
                liked: false
            )
        default:
            try await topicDetailStore.togglePostReaction(
                topicId: topic.id,
                postId: postId,
                reactionId: toggledReactionId
            )
        }
    }

    private func updateTopicNotificationLevel(_ option: FireTopicNotificationLevelOption) async {
        do {
            try await viewModel.setTopicNotificationLevel(
                topicID: topic.id,
                notificationLevel: option.rawValue
            )
            await topicDetailStore.loadTopicDetail(topicId: topic.id, force: true)
        } catch {
            composerNotice = error.localizedDescription
        }
    }

    private func toggleTopicVote() async {
        guard let detail else { return }
        do {
            _ = try await viewModel.voteTopic(
                topicID: topic.id,
                voted: !detail.userVoted
            )
        } catch {
            composerNotice = error.localizedDescription
        }
    }

    private func presentTopicVoters() async {
        isLoadingTopicVoters = true
        showingTopicVoters = true
        defer { isLoadingTopicVoters = false }

        do {
            topicVoters = try await viewModel.fetchTopicVoters(topicID: topic.id)
        } catch {
            topicVoters = []
            composerNotice = error.localizedDescription
        }
    }

    private func submitPollVote(
        for post: TopicPostState,
        poll: PollState,
        options: [String]
    ) {
        Task { @MainActor in
            do {
                _ = try await viewModel.votePoll(
                    topicID: topic.id,
                    postID: post.id,
                    pollName: poll.name,
                    options: options
                )
            } catch {
                composerNotice = error.localizedDescription
            }
        }
    }

    private func removePollVote(for post: TopicPostState, poll: PollState) {
        Task { @MainActor in
            do {
                _ = try await viewModel.unvotePoll(
                    topicID: topic.id,
                    postID: post.id,
                    pollName: poll.name
                )
            } catch {
                composerNotice = error.localizedDescription
            }
        }
    }
}

private struct FireVisiblePostFrameReporter: View {
    let postNumber: UInt32

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: FireVisiblePostFramePreferenceKey.self,
                value: [
                    postNumber: proxy.frame(in: .named(FireTopicDetailView.scrollCoordinateSpaceName))
                ]
            )
        }
    }
}

private struct FireVisiblePostFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UInt32: CGRect] = [:]

    static func reduce(value: inout [UInt32: CGRect], nextValue: () -> [UInt32: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct FireTypingPresenceStrip: View {
    let users: [TopicPresenceUserState]
    let baseURLString: String

    private var summary: String {
        let names = users.prefix(3).map(\.username)
        let leading = names.joined(separator: "、")
        if users.count > 3 {
            return "\(leading) 等 \(users.count) 人正在输入"
        }
        return "\(leading) 正在输入"
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: -8) {
                ForEach(Array(users.prefix(3)), id: \.id) { user in
                    FireAvatarView(
                        avatarTemplate: user.avatarTemplate ?? "",
                        username: user.username,
                        size: 22,
                        baseURLString: baseURLString
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 1)
                    )
                }
            }

            Text(summary)
                .font(.caption.weight(.medium))
                .foregroundStyle(FireTheme.subtleInk)

            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

private struct FireTopicPostsLoadingFooter: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在加载后续评论…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
    }
}

private struct FireTopicPostPlaceholder: View {
    let depth: Int

    private static let maxVisualDepth = 3

    private var indentWidth: CGFloat {
        CGFloat(min(depth, Self.maxVisualDepth)) * 20
    }

    var body: some View {
        HStack(alignment: .top, spacing: depth > 0 ? 6 : 10) {
            if depth > 0 {
                Color.clear.frame(width: indentWidth)
            }

            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: depth > 0 ? 26 : 32, height: depth > 0 ? 26 : 32)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 120, height: 12)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(maxWidth: .infinity)
                    .frame(height: 12)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 160, height: 12)
            }
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
    }
}

enum FireTopicReplySwipeAxis: Equatable {
    case horizontal
    case vertical
    case reservedForNavigationBack
}

enum FireTopicReplySwipePolicy {
    static let backNavigationReservedWidth: CGFloat = 32

    static func resolvedAxis(
        startLocationX: CGFloat,
        translationWidth: CGFloat,
        translationHeight: CGFloat
    ) -> FireTopicReplySwipeAxis {
        if startLocationX <= backNavigationReservedWidth {
            return .reservedForNavigationBack
        }

        return abs(translationWidth) > abs(translationHeight) * 1.2
            ? .horizontal
            : .vertical
    }
}

private struct FirePostRow: View {
    let post: TopicPostState
    let renderContent: FireTopicPostRenderContent
    let depth: Int
    let replyContext: String?
    let showsThreadLine: Bool
    let baseURLString: String
    let canWriteInteractions: Bool
    let isMutating: Bool
    let onOpenImage: (FireCookedImage) -> Void
    let onToggleLike: (TopicPostState) -> Void
    let onSelectReaction: (TopicPostState, String) -> Void
    let onEditPost: (TopicPostState) -> Void
    let onVotePoll: (TopicPostState, PollState, [String]) -> Void
    let onUnvotePoll: (TopicPostState, PollState) -> Void

    private static let maxVisualDepth = 3

    private var indentWidth: CGFloat {
        CGFloat(min(depth, Self.maxVisualDepth)) * 20
    }

    private var canChangeReaction: Bool {
        canWriteInteractions && !isMutating && (post.currentUserReaction?.canUndo ?? true)
    }

    var body: some View {
        HStack(alignment: .top, spacing: depth > 0 ? 6 : 10) {
            if depth > 0 {
                Color.clear.frame(width: indentWidth)
            }

            VStack(spacing: 0) {
                FireAvatarView(
                    avatarTemplate: post.avatarTemplate,
                    username: post.username.isEmpty ? "?" : post.username,
                    size: depth > 0 ? 26 : 32,
                    baseURLString: baseURLString
                )

                if showsThreadLine {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 6)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(post.username.isEmpty ? "Unknown" : post.username)
                        .font(.subheadline.weight(.semibold))

                    if let replyContext {
                        Text(replyContext)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(FireTheme.accent)
                    }

                    if let timestamp = FireTopicPresentation.compactTimestamp(post.createdAt) {
                        Text(timestamp)
                            .font(.caption2)
                            .foregroundStyle(FireTheme.tertiaryInk)
                    }

                    Spacer()

                    if post.acceptedAnswer {
                        Label("已采纳", systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                    }

                    Text("#\(post.postNumber)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(FireTheme.tertiaryInk)

                    if post.canEdit {
                        Menu {
                            Button {
                                onEditPost(post)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(FireTheme.tertiaryInk)
                                .frame(width: 20, height: 20)
                        }
                    }
                }

                Text(renderContent.plainText)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)

                if !renderContent.imageAttachments.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(renderContent.imageAttachments) { attachment in
                            Button {
                                onOpenImage(attachment)
                            } label: {
                                FireCookedImageCard(image: attachment)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !post.polls.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(post.polls, id: \.name) { poll in
                            FirePollCard(
                                poll: poll,
                                canInteract: canWriteInteractions && !isMutating,
                                onSubmit: { selectedOptions in
                                    onVotePoll(post, poll, selectedOptions)
                                },
                                onRemoveVote: {
                                    onUnvotePoll(post, poll)
                                }
                            )
                        }
                    }
                }

                if !post.reactions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(post.reactions, id: \.id) { reaction in
                                let option = FireTopicPresentation.reactionOption(for: reaction.id)
                                Button {
                                    if reaction.id == "heart" {
                                        onToggleLike(post)
                                    } else {
                                        onSelectReaction(post, reaction.id)
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(option.symbol)
                                        Text("\(reaction.count)")
                                            .font(.caption.monospacedDigit())
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(
                                                post.currentUserReaction?.id == reaction.id
                                                    ? FireTheme.accent.opacity(0.14)
                                                    : Color(.tertiarySystemFill)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(!canChangeReaction)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct FirePollCard: View {
    let poll: PollState
    let canInteract: Bool
    let onSubmit: ([String]) -> Void
    let onRemoveVote: () -> Void

    @State private var selectedOptionIDs: Set<String>

    init(
        poll: PollState,
        canInteract: Bool,
        onSubmit: @escaping ([String]) -> Void,
        onRemoveVote: @escaping () -> Void
    ) {
        self.poll = poll
        self.canInteract = canInteract
        self.onSubmit = onSubmit
        self.onRemoveVote = onRemoveVote
        _selectedOptionIDs = State(initialValue: Set(poll.userVotes))
    }

    private var allowsMultipleSelection: Bool {
        poll.kind.localizedCaseInsensitiveContains("multiple")
    }

    private var isClosed: Bool {
        poll.status.localizedCaseInsensitiveContains("closed")
    }

    private var canSubmitSelection: Bool {
        canInteract && !isClosed && !selectedOptionIDs.isEmpty && selectedOptionIDs != Set(poll.userVotes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(poll.name.ifEmpty("投票"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FireTheme.ink)

                Spacer()

                Text("\(poll.voters) 人参与")
                    .font(.caption)
                    .foregroundStyle(FireTheme.tertiaryInk)
            }

            VStack(spacing: 8) {
                ForEach(poll.options, id: \.id) { option in
                    Button {
                        toggleSelection(optionID: option.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedOptionIDs.contains(option.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedOptionIDs.contains(option.id) ? FireTheme.accent : FireTheme.tertiaryInk)

                            Text(plainTextFromHtml(rawHtml: option.html).ifEmpty(option.id))
                                .font(.subheadline)
                                .foregroundStyle(FireTheme.ink)
                                .multilineTextAlignment(.leading)

                            Spacer()

                            Text("\(option.votes)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(FireTheme.tertiaryInk)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedOptionIDs.contains(option.id) ? FireTheme.accent.opacity(0.10) : Color(.tertiarySystemFill))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canInteract || isClosed)
                }
            }

            HStack(spacing: 12) {
                if !poll.userVotes.isEmpty {
                    Button {
                        onRemoveVote()
                    } label: {
                        Label("撤销投票", systemImage: "arrow.uturn.left")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(FireTheme.subtleInk)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canInteract || isClosed)
                }

                Spacer()

                if canSubmitSelection {
                    Button {
                        onSubmit(selectedOptionIDs.sorted())
                    } label: {
                        Text("提交")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(FireTheme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(FireTheme.softSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: poll.userVotes) { _, newValue in
            selectedOptionIDs = Set(newValue)
        }
    }

    private func toggleSelection(optionID: String) {
        if allowsMultipleSelection {
            if selectedOptionIDs.contains(optionID) {
                selectedOptionIDs.remove(optionID)
            } else {
                selectedOptionIDs.insert(optionID)
            }
        } else {
            if selectedOptionIDs.contains(optionID) {
                selectedOptionIDs.removeAll()
            } else {
                selectedOptionIDs = Set([optionID])
            }
        }
    }
}

private struct FireTopicVotersSheet: View {
    let voters: [VotedUserState]
    let isLoading: Bool

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 20)
                    Spacer()
                }
            } else if voters.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.3")
                        .font(.title2)
                        .foregroundStyle(FireTheme.subtleInk)
                    Text("暂时还没有投票用户")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FireTheme.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ForEach(voters, id: \.id) { voter in
                    HStack(spacing: 12) {
                        FireAvatarView(
                            avatarTemplate: voter.avatarTemplate,
                            username: voter.username,
                            size: 40
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text((voter.name ?? "").ifEmpty(voter.username))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(FireTheme.ink)
                            Text("@\(voter.username)")
                                .font(.caption)
                                .foregroundStyle(FireTheme.subtleInk)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("投票用户")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FireTopicImageViewer: View {
    let image: FireCookedImage

    private enum InteractionMode {
        case idle
        case zooming
        case panning
        case dismissing
    }

    private enum DragMode {
        case pan
        case dismiss
        case ignore
    }

    private enum ToolbarAction {
        case share
        case save
    }

    private enum PhotoSaveError: Error {
        case unknownFailure
    }

    @Environment(\.dismiss) private var dismiss
    @State private var interactionMode: InteractionMode = .idle
    @State private var activeDragMode: DragMode?
    @State private var activeToolbarAction: ToolbarAction?
    @State private var sharedImage: UIImage?
    @State private var isShowingShareSheet = false
    @State private var isShowingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var steadyZoomScale: CGFloat = 1
    @State private var gestureZoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    @State private var dismissOffset: CGSize = .zero

    private let minimumZoomScale: CGFloat = 1
    private let maximumZoomScale: CGFloat = 4
    private let dismissThreshold: CGFloat = 140
    private let dismissProgressDistance: CGFloat = 220
    private let imagePadding: CGFloat = 16

    private var imageRequest: FireRemoteImageRequest {
        FireRemoteImageRequest(url: image.url)
    }

    private var shareSubject: String {
        let fileName = image.url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return fileName.isEmpty ? "Fire 帖子图片" : fileName
    }

    private var effectiveZoomScale: CGFloat {
        clampedScale(steadyZoomScale * gestureZoomScale)
    }

    private var dismissProgress: CGFloat {
        min(max(dismissOffset.height / dismissProgressDistance, 0), 1)
    }

    private var backgroundOpacity: Double {
        Double(max(0.22, 1 - dismissProgress * 0.78))
    }

    private var contentScale: CGFloat {
        let dismissScale = max(0.88, 1 - dismissProgress * 0.12)
        return effectiveZoomScale * dismissScale
    }

    private var isToolbarBusy: Bool {
        activeToolbarAction != nil
    }

    var body: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size

            ZStack {
                Color.black
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea()

                FireRemoteImage(request: imageRequest) { loadedImage in
                    Image(uiImage: loadedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(imagePadding)
                } placeholder: { state in
                    switch state {
                    case .loading, .missingRequest:
                        ProgressView()
                            .tint(.white)
                    case .failure:
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                            Text("图片加载失败")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(contentScale)
                .offset(displayOffset(in: containerSize))
                .simultaneousGesture(magnificationGesture(in: containerSize))

                VStack {
                    HStack(spacing: 12) {
                        Spacer()

                        viewerControlButton(
                            systemName: "square.and.arrow.up",
                            isBusy: activeToolbarAction == .share,
                            action: { Task { await handleShareAction() } }
                        )
                        .disabled(isToolbarBusy)

                        viewerControlButton(
                            systemName: "arrow.down.to.line",
                            isBusy: activeToolbarAction == .save,
                            action: { Task { await handleSaveAction() } }
                        )
                        .disabled(isToolbarBusy)

                        viewerControlButton(systemName: "xmark", action: {
                            dismiss()
                        })
                    }
                    .padding(.top, proxy.safeAreaInsets.top + 12)
                    .padding(.horizontal, 16)

                    Spacer()
                }
                .opacity(max(0.4, backgroundOpacity))
            }
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture(in: containerSize))
        }
        .sheet(isPresented: $isShowingShareSheet, onDismiss: {
            sharedImage = nil
        }) {
            if let sharedImage {
                FireActivityShareSheet(
                    activityItems: [sharedImage],
                    subject: shareSubject
                )
            }
        }
        .alert(alertTitle, isPresented: $isShowingAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func viewerControlButton(
        systemName: String,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .frame(width: 42, height: 42)
            .background(
                Circle()
                    .fill(Color.black.opacity(0.34))
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func handleShareAction() async {
        guard activeToolbarAction == nil else { return }

        activeToolbarAction = .share
        defer { activeToolbarAction = nil }

        do {
            let resolvedImage = try await FireRemoteImagePipeline.shared.loadImage(for: imageRequest)
            sharedImage = resolvedImage
            isShowingShareSheet = true
        } catch {
            presentAlert(
                title: "无法分享图片",
                message: "图片还没加载完成或下载失败，请稍后再试。"
            )
        }
    }

    @MainActor
    private func handleSaveAction() async {
        guard activeToolbarAction == nil else { return }

        activeToolbarAction = .save
        defer { activeToolbarAction = nil }

        let resolvedImage: UIImage
        do {
            resolvedImage = try await FireRemoteImagePipeline.shared.loadImage(for: imageRequest)
        } catch {
            presentAlert(
                title: "无法保存图片",
                message: "图片还没加载完成或下载失败，请稍后再试。"
            )
            return
        }

        let authorizationStatus = await photoLibraryAuthorizationStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            presentAlert(
                title: "无法保存到相册",
                message: "Fire 需要照片权限才能把当前图片保存到相册，请在系统设置里允许添加照片。"
            )
            return
        }

        do {
            try await saveImageToPhotoLibrary(resolvedImage)
            presentAlert(
                title: "已保存到相册",
                message: "当前帖子图片已经保存到系统相册。"
            )
        } catch {
            presentAlert(
                title: "保存失败",
                message: "系统暂时无法写入相册，请稍后再试。"
            )
        }
    }

    @MainActor
    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        isShowingAlert = true
    }

    private func photoLibraryAuthorizationStatus() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func saveImageToPhotoLibrary(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoSaveError.unknownFailure)
                }
            }
        }
    }

    private func magnificationGesture(in containerSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                activeDragMode = nil
                dismissOffset = .zero
                interactionMode = .zooming
                gestureZoomScale = value
            }
            .onEnded { value in
                let resolvedScale = clampedScale(steadyZoomScale * value)
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    steadyZoomScale = resolvedScale
                    gestureZoomScale = 1
                    if resolvedScale <= minimumZoomScale + 0.01 {
                        resetTransformState()
                    } else {
                        panOffset = clampedPanOffset(panOffset, in: containerSize, scale: resolvedScale)
                        interactionMode = .panning
                    }
                }
            }
    }

    private func dragGesture(in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                handleDragChanged(value, in: containerSize)
            }
            .onEnded { value in
                handleDragEnded(value, in: containerSize)
            }
    }

    private func handleDragChanged(_ value: DragGesture.Value, in containerSize: CGSize) {
        guard interactionMode != .zooming else { return }

        if activeDragMode == nil {
            if effectiveZoomScale > minimumZoomScale + 0.01 {
                activeDragMode = .pan
                dragStartOffset = panOffset
            } else if value.translation.height > 0,
                        abs(value.translation.height) > abs(value.translation.width) {
                activeDragMode = .dismiss
            } else {
                activeDragMode = .ignore
            }
        }

        switch activeDragMode {
        case .pan:
            interactionMode = .panning
            dismissOffset = .zero
            let proposedOffset = CGSize(
                width: dragStartOffset.width + value.translation.width,
                height: dragStartOffset.height + value.translation.height
            )
            panOffset = clampedPanOffset(proposedOffset, in: containerSize, scale: effectiveZoomScale)
        case .dismiss:
            interactionMode = .dismissing
            let horizontalDrift = value.translation.width * 0.18
            let verticalOffset = value.translation.height > dismissThreshold
                ? dismissThreshold + (value.translation.height - dismissThreshold) * 0.72
                : value.translation.height
            dismissOffset = CGSize(width: horizontalDrift, height: verticalOffset)
        case .ignore, .none:
            break
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, in containerSize: CGSize) {
        defer { activeDragMode = nil }

        switch activeDragMode {
        case .pan:
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                panOffset = clampedPanOffset(panOffset, in: containerSize, scale: effectiveZoomScale)
            }
            interactionMode = effectiveZoomScale > minimumZoomScale + 0.01 ? .panning : .idle
        case .dismiss:
            let projectedDismissDistance = max(value.translation.height, value.predictedEndTranslation.height)
            if projectedDismissDistance > dismissThreshold {
                dismiss()
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    dismissOffset = .zero
                    interactionMode = effectiveZoomScale > minimumZoomScale + 0.01 ? .panning : .idle
                }
            }
        case .ignore, .none:
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                dismissOffset = .zero
            }
            interactionMode = effectiveZoomScale > minimumZoomScale + 0.01 ? .panning : .idle
        }
    }

    private func displayOffset(in containerSize: CGSize) -> CGSize {
        let clampedPan = clampedPanOffset(panOffset, in: containerSize, scale: effectiveZoomScale)
        return CGSize(
            width: clampedPan.width + dismissOffset.width,
            height: clampedPan.height + dismissOffset.height
        )
    }

    private func resetTransformState() {
        steadyZoomScale = minimumZoomScale
        gestureZoomScale = 1
        panOffset = .zero
        dragStartOffset = .zero
        dismissOffset = .zero
        interactionMode = .idle
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumZoomScale), maximumZoomScale)
    }

    private func clampedPanOffset(_ proposedOffset: CGSize, in containerSize: CGSize, scale: CGFloat) -> CGSize {
        let maxOffset = maximumPanOffset(in: containerSize, scale: scale)
        return CGSize(
            width: min(max(proposedOffset.width, -maxOffset.width), maxOffset.width),
            height: min(max(proposedOffset.height, -maxOffset.height), maxOffset.height)
        )
    }

    private func maximumPanOffset(in containerSize: CGSize, scale: CGFloat) -> CGSize {
        guard scale > minimumZoomScale else {
            return .zero
        }

        let fittedSize = fittedImageSize(in: containerSize)
        let scaledSize = CGSize(width: fittedSize.width * scale, height: fittedSize.height * scale)
        return CGSize(
            width: max((scaledSize.width - fittedSize.width) / 2, 0),
            height: max((scaledSize.height - fittedSize.height) / 2, 0)
        )
    }

    private func fittedImageSize(in containerSize: CGSize) -> CGSize {
        let availableWidth = max(containerSize.width - imagePadding * 2, 1)
        let availableHeight = max(containerSize.height - imagePadding * 2, 1)

        guard let aspectRatio = image.aspectRatio, aspectRatio > 0 else {
            return CGSize(width: availableWidth, height: availableHeight)
        }

        let containerAspectRatio = availableWidth / availableHeight
        if aspectRatio > containerAspectRatio {
            return CGSize(width: availableWidth, height: availableWidth / aspectRatio)
        }
        return CGSize(width: availableHeight * aspectRatio, height: availableHeight)
    }
}

private struct FireSwipeToReplyContainer<Content: View>: View {
    let enabled: Bool
    let onSwipeReply: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var gestureDirection: FireTopicReplySwipeAxis? = nil
    @State private var replyTriggered = false

    private let triggerThreshold: CGFloat = 55
    private let maxOffset: CGFloat = 75

    var body: some View {
        if enabled {
            swipeableContent
        } else {
            content()
        }
    }

    private var swipeableContent: some View {
        content()
            .offset(x: offset)
            .background(alignment: .leading) {
                if offset > 4 {
                    replyIndicator
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(swipeGesture)
    }

    private var replyIndicator: some View {
        Image(systemName: "arrowshape.turn.up.left.fill")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(replyTriggered ? FireTheme.accent : FireTheme.tertiaryInk)
            .scaleEffect(min(offset / triggerThreshold, 1.0))
            .opacity(Double(min(offset / (triggerThreshold * 0.5), 1.0)))
            .frame(width: 32, height: 32)
            .padding(.leading, 4)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height

                if gestureDirection == nil {
                    gestureDirection = FireTopicReplySwipePolicy.resolvedAxis(
                        startLocationX: value.startLocation.x,
                        translationWidth: dx,
                        translationHeight: dy
                    )
                }

                guard gestureDirection == .horizontal, dx > 0 else { return }

                let dampened = dx > triggerThreshold
                    ? triggerThreshold + (dx - triggerThreshold) * 0.25
                    : dx
                withAnimation(.interactiveSpring()) {
                    offset = min(dampened, maxOffset)
                }

                if offset >= triggerThreshold && !replyTriggered {
                    replyTriggered = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            .onEnded { _ in
                if replyTriggered {
                    onSwipeReply()
                }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    offset = 0
                }
                gestureDirection = nil
                replyTriggered = false
            }
    }
}

private struct FireCookedImageCard: View {
    let image: FireCookedImage

    private var fallbackAspectRatio: CGFloat {
        image.aspectRatio ?? 1.45
    }

    private var imageRequest: FireRemoteImageRequest {
        FireRemoteImageRequest(url: image.url)
    }

    var body: some View {
        FireRemoteImage(request: imageRequest) { loadedImage in
            Image(uiImage: loadedImage)
                .resizable()
                .scaledToFill()
        } placeholder: { state in
            switch state {
            case .loading, .missingRequest:
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                    ProgressView()
                }
            case .failure:
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("图片加载失败")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(fallbackAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        }
    }
}
