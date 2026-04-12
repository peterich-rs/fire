import SwiftUI

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

    @ObservedObject var viewModel: FireAppViewModel
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
    @State private var hasScrolledToTarget = false
    @State private var bookmarkEditorContext: FireBookmarkEditorContext?
    @State private var selectedImage: FireCookedImage?
    @State private var postEditorContext: FirePostEditorContext?
    @State private var showingTopicEditor = false
    @State private var topicVoters: [VotedUserState] = []
    @State private var isLoadingTopicVoters = false
    @State private var showingTopicVoters = false
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

    private var detail: TopicDetailState? {
        viewModel.topicDetail(for: topic.id)
    }

    private var detailError: String? {
        viewModel.errorMessage
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

    private var threadPresentation: FireTopicThreadPresentation? {
        detail?.thread
    }

    private var flatPosts: [FireTopicFlatPostPresentation] {
        detail?.flatPosts ?? []
    }

    private var originalPost: TopicPostState? {
        if let originalPost = flatPosts.first(where: \.isOriginalPost)?.post {
            return originalPost
        }
        return detail?.postStream.posts.min(by: { $0.postNumber < $1.postNumber })
    }

    private var replyPosts: [FireTopicFlatPostPresentation] {
        guard let detail else {
            return []
        }

        let originalPostID = originalPost?.id
        let displayPosts = flatPosts.isEmpty
            ? detail.postStream.posts.map {
                FireTopicFlatPostPresentation(
                    post: $0,
                    depth: 0,
                    parentPostNumber: $0.replyToPostNumber,
                    showsThreadLine: false,
                    isOriginalPost: $0.id == originalPostID
                )
            }
            : flatPosts

        guard let originalPostID else {
            return displayPosts
        }

        return displayPosts.filter { $0.post.id != originalPostID }
    }

    private var reactionOptions: [FireReactionOption] {
        FireTopicPresentation.enabledReactionOptions(from: viewModel.session.bootstrap.enabledReactionIds)
    }

    private var typingUsers: [TopicPresenceUserState] {
        viewModel.topicPresenceUsers(for: topic.id)
    }

    private var nonHeartReactionOptions: [FireReactionOption] {
        reactionOptions.filter { $0.id != "heart" }
    }

    private var minimumReplyLength: Int {
        FireTopicPresentation.minimumReplyLength(from: viewModel.session.bootstrap.minPostLength)
    }

    private var baseURLString: String {
        let trimmed = viewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    private var canWriteInteractions: Bool {
        viewModel.session.readiness.canWriteAuthenticatedApi
    }

    private var topicShareURL: URL? {
        let trimmedSlug = displayedTopicSlug
        return URL(string: "\(baseURLString)/t/\(trimmedSlug.isEmpty ? "topic-\(topic.id)" : trimmedSlug)/\(topic.id)")
    }

    private var currentTopicNotificationLevel: FireTopicNotificationLevelOption {
        FireTopicNotificationLevelOption(rawValue: Int32(detail?.details.notificationLevel ?? 1)) ?? .regular
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
            hasLoadedDetail: detail != nil
        )
    }

    private var displayedReplyCount: UInt32 {
        if let detail {
            return max(detail.postsCount, 1) - 1
        }
        return topic.replyCount
    }

    private var loadedReplyCount: Int {
        guard let detail else {
            return 0
        }
        return max(detail.postStream.posts.count - 1, 0)
    }

    private var displayedInteractionCount: UInt32? {
        detail?.interactionCount
    }

    private var displayedViewsCount: UInt32 {
        detail?.views ?? topic.views
    }

    private var displayedFloorCount: Int {
        threadPresentation?.replySections.count ?? 0
    }

    private var trimmedReplyDraft: String {
        replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSubmittingReply: Bool {
        viewModel.isSubmittingReply(topicId: topic.id)
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
            && !viewModel.isMutatingPost(postId: post.id)
            && (post.currentUserReaction?.canUndo ?? true)
    }

    var body: some View {
        GeometryReader { geometry in
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
                    updateVisiblePostFrames(frames, viewportHeight: geometry.size.height)
                }
                .onChange(of: detail?.postStream.posts.count) { _, _ in
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
                    if detail?.details.canEdit == true {
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
                    }
                    .disabled(!canWriteInteractions)
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
                    await viewModel.loadTopicDetail(topicId: topic.id, force: true)
                },
                onDelete: context.bookmarkID.map { bookmarkID in
                    {
                        try await viewModel.deleteBookmark(bookmarkID: bookmarkID)
                        await viewModel.loadTopicDetail(topicId: topic.id, force: true)
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
                            await viewModel.loadTopicDetail(topicId: topic.id, force: true)
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
                            await viewModel.loadTopicDetail(topicId: topic.id, force: true)
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
                            replyToUsername: context.replyToUsername
                        )
                    ),
                    initialBody: replyDraft,
                    onReplySubmitted: {
                        replyDraft = ""
                        composerContext = nil
                        quickReplyError = nil
                        Task {
                            await viewModel.loadTopicDetail(topicId: topic.id, force: true)
                        }
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
            viewModel.clearTopicDetailAnchor(topicId: topic.id)
            await viewModel.loadTopicDetail(topicId: topic.id, force: true)
        }
        .onAppear {
            viewModel.beginTopicDetailLifecycle(topicId: topic.id, ownerToken: detailOwnerToken)
            viewModel.setAPMRoute("topic.detail.\(topic.id)")
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
            await viewModel.loadTopicDetail(topicId: topic.id, targetPostNumber: scrollToPostNumber)
        }
        .task(id: messageBusSubscriptionTaskID) {
            await viewModel.maintainTopicDetailSubscription(
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
                viewModel.beginTopicReplyPresence(topicId: topic.id)
            } else {
                Task {
                    await viewModel.endTopicReplyPresence(topicId: topic.id)
                }
            }
        }
        .onDisappear {
            viewModel.endTopicDetailLifecycle(topicId: topic.id, ownerToken: detailOwnerToken)
            viewModel.restoreTopLevelAPMRoute()
            Task {
                await timingTracker.stop()
                await viewModel.endTopicReplyPresence(topicId: topic.id)
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
        guard let scrollToPostNumber, !hasScrolledToTarget else { return }
        guard detail != nil else { return }
        hasScrolledToTarget = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(scrollToPostNumber, anchor: .top)
            }
        }
    }

    private var topicHeaderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(displayedTopicTitle)
                .font(.title3.weight(.bold))

            FlowLayout(spacing: 6, fallbackWidth: max(UIScreen.main.bounds.width - 40, 200)) {
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

            if let originalPost {
                FireSwipeToReplyContainer(enabled: canWriteInteractions) {
                    openComposer(replyToPost: originalPost)
                } content: {
                    FirePostRow(
                        post: originalPost,
                        depth: 0,
                        replyContext: nil,
                        showsThreadLine: false,
                        baseURLString: baseURLString,
                        canWriteInteractions: canWriteInteractions,
                        isMutating: viewModel.isMutatingPost(postId: originalPost.id),
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
            let displayPosts = replyPosts

            if displayPosts.isEmpty {
                if viewModel.hasMoreTopicPosts(topicId: topic.id) {
                    FireTopicPostsLoadingFooter()
                        .padding(.vertical, 16)
                        .task(id: topic.id) {
                            viewModel.preloadTopicPostsIfNeeded(
                                topicId: topic.id,
                                visibleReplyIndex: 0,
                                totalReplyCount: 1
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
                replyPostRows(displayPosts)

                if viewModel.isLoadingMoreTopicPosts(topicId: topic.id) {
                    FireTopicPostsLoadingFooter()
                        .padding(.top, 12)
                }
            }
        } else if viewModel.isLoadingTopic(topicId: topic.id) {
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
                        await viewModel.loadTopicDetail(topicId: topic.id, force: true)
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
                    await viewModel.loadTopicDetail(topicId: topic.id, force: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private func replyPostRows(_ displayPosts: [FireTopicFlatPostPresentation]) -> some View {
        ForEach(Array(displayPosts.enumerated()), id: \.element.post.id) { index, flatPost in
            FireSwipeToReplyContainer(enabled: canWriteInteractions) {
                openComposer(replyToPost: flatPost.post)
            } content: {
                FirePostRow(
                    post: flatPost.post,
                    depth: Int(flatPost.depth),
                    replyContext: flatPost.parentPostNumber.map { "回复 #\($0)" },
                    showsThreadLine: flatPost.showsThreadLine,
                    baseURLString: baseURLString,
                    canWriteInteractions: canWriteInteractions,
                    isMutating: viewModel.isMutatingPost(postId: flatPost.post.id),
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
            .id(flatPost.post.postNumber)
            .background(FireVisiblePostFrameReporter(postNumber: flatPost.post.postNumber))

            if index != displayPosts.count - 1 {
                Divider()
            }
        }
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

        let replyIndexByPostNumber = Dictionary(
            uniqueKeysWithValues: replyPosts.enumerated().map { ($1.post.postNumber, $0) }
        )
        guard let visibleReplyIndex = visiblePostNumbers.compactMap({ replyIndexByPostNumber[$0] }).max() else {
            return
        }

        viewModel.preloadTopicPostsIfNeeded(
            topicId: topic.id,
            visibleReplyIndex: visibleReplyIndex,
            totalReplyCount: replyPosts.count
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
                try await viewModel.submitReply(
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
            try await viewModel.setPostLiked(
                topicId: topic.id,
                postId: postId,
                liked: true
            )
        case ("heart", nil):
            try await viewModel.setPostLiked(
                topicId: topic.id,
                postId: postId,
                liked: false
            )
        default:
            try await viewModel.togglePostReaction(
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
            await viewModel.loadTopicDetail(topicId: topic.id, force: true)
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

private struct FirePostRow: View {
    let post: TopicPostState
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

    private var imageAttachments: [FireCookedImage] {
        FireTopicPresentation.imageAttachments(from: post.cooked, baseURLString: baseURLString)
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

                Text(plainTextFromHtml(rawHtml: post.cooked))
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)

                if !imageAttachments.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(imageAttachments) { attachment in
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: image.url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .tint(.white)
                case .success(let loadedImage):
                    loadedImage
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(16)
                case .failure:
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                        Text("图片加载失败")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.white)
                @unknown default:
                    EmptyView()
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(20)
            }
        }
    }
}

private struct FireSwipeToReplyContainer<Content: View>: View {
    let enabled: Bool
    let onSwipeReply: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var gestureDirection: GestureAxis? = nil
    @State private var replyTriggered = false

    private enum GestureAxis { case horizontal, vertical }

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
                    gestureDirection = abs(dx) > abs(dy) * 1.2 ? .horizontal : .vertical
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

    var body: some View {
        AsyncImage(url: image.url) { phase in
            switch phase {
            case .empty:
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                    ProgressView()
                }
            case .success(let loadedImage):
                loadedImage
                    .resizable()
                    .scaledToFill()
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
            @unknown default:
                EmptyView()
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
