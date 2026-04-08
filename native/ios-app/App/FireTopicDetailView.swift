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

struct FireTopicDetailView: View {
    fileprivate static let scrollCoordinateSpaceName = "fire-topic-detail-scroll"

    @ObservedObject var viewModel: FireAppViewModel
    let row: FireTopicRowPresentation
    let scrollToPostNumber: UInt32?

    @Environment(\.scenePhase) private var scenePhase
    @State private var composerContext: FireReplyComposerContext?
    @State private var replyDraft = ""
    @State private var composerNotice: String?
    @State private var quickReplyError: String?
    @State private var timingTracker: FireTopicTimingTracker
    @State private var detailOwnerToken: String
    @State private var hasScrolledToTarget = false
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

    private var category: FireTopicCategoryPresentation? {
        viewModel.categoryPresentation(for: topic.categoryId)
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

    private var messageBusSubscriptionTaskID: String {
        "\(topic.id)-\(viewModel.session.readiness.canOpenMessageBus)"
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

    private var displayedLikeCount: UInt32 {
        detail?.likeCount ?? topic.likeCount
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
        .safeAreaInset(edge: .bottom) {
            if canWriteInteractions {
                quickReplyBar
            }
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
            Text(topic.title)
                .font(.title3.weight(.bold))

            FlowLayout(spacing: 6, fallbackWidth: max(UIScreen.main.bounds.width - 40, 200)) {
                if let category {
                    let accent = Color(fireHex: category.colorHex) ?? FireTheme.accent
                    NavigationLink {
                        FireFilteredTopicListView(
                            viewModel: viewModel,
                            title: category.displayName,
                            categorySlug: category.slug,
                            categoryId: category.id,
                            parentCategorySlug: nil,
                            tag: nil
                        )
                    } label: {
                        FireTopicPill(
                            label: category.displayName,
                            backgroundColor: accent.opacity(0.12),
                            foregroundColor: Color(fireHex: category.textColorHex) ?? accent
                        )
                    }
                    .buttonStyle(.plain)
                }

                ForEach(row.tagNames, id: \.self) { tagName in
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
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                ForEach(row.statusLabels, id: \.self) { label in
                    FireStatusChip(label: label, tone: .accent)
                }
            }

            if let originalPost {
                FirePostRow(
                    post: originalPost,
                    depth: 0,
                    replyContext: nil,
                    showsThreadLine: false,
                    baseURLString: baseURLString,
                    reactionOptions: reactionOptions,
                    canWriteInteractions: canWriteInteractions,
                    isMutating: viewModel.isMutatingPost(postId: originalPost.id),
                    onReply: { openComposer(replyToPost: $0) },
                    onToggleLike: { toggleLike(for: $0) },
                    onSelectReaction: { post, reactionId in
                        toggleReaction(reactionId, for: post)
                    }
                )
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
                statLabel(value: "\(displayedLikeCount)", label: "赞")
            }
            .padding(.vertical, 4)
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
            FirePostRow(
                post: flatPost.post,
                depth: Int(flatPost.depth),
                replyContext: flatPost.parentPostNumber.map { "回复 #\($0)" },
                showsThreadLine: flatPost.showsThreadLine,
                baseURLString: baseURLString,
                reactionOptions: reactionOptions,
                canWriteInteractions: canWriteInteractions,
                isMutating: viewModel.isMutatingPost(postId: flatPost.post.id),
                onReply: { openComposer(replyToPost: $0) },
                onToggleLike: { toggleLike(for: $0) },
                onSelectReaction: { post, reactionId in
                    toggleReaction(reactionId, for: post)
                }
            )
            .id(flatPost.post.postNumber)
            .background(FireVisiblePostFrameReporter(postNumber: flatPost.post.postNumber))

            if index != displayPosts.count - 1 {
                Divider()
            }
        }
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
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
    let reactionOptions: [FireReactionOption]
    let canWriteInteractions: Bool
    let isMutating: Bool
    let onReply: (TopicPostState) -> Void
    let onToggleLike: (TopicPostState) -> Void
    let onSelectReaction: (TopicPostState, String) -> Void

    private static let maxVisualDepth = 3

    private var indentWidth: CGFloat {
        CGFloat(min(depth, Self.maxVisualDepth)) * 20
    }

    private var imageAttachments: [FireCookedImage] {
        FireTopicPresentation.imageAttachments(from: post.cooked, baseURLString: baseURLString)
    }

    private var currentReactionOption: FireReactionOption? {
        guard let currentReaction = post.currentUserReaction, currentReaction.id != "heart" else {
            return nil
        }
        return FireTopicPresentation.reactionOption(for: currentReaction.id)
    }

    private var nonHeartReactionOptions: [FireReactionOption] {
        reactionOptions.filter { $0.id != "heart" }
    }

    private var isHeartSelected: Bool {
        post.currentUserReaction?.id == "heart"
    }

    private var totalReactionCount: UInt32 {
        let total = post.reactions.reduce(UInt32(0)) { partialResult, reaction in
            partialResult + reaction.count
        }
        return total > 0 ? total : post.likeCount
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
                }

                Text(plainTextFromHtml(rawHtml: post.cooked))
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)

                if !imageAttachments.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(imageAttachments) { attachment in
                            Link(destination: attachment.url) {
                                FireCookedImageCard(image: attachment)
                            }
                            .buttonStyle(.plain)
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

                HStack(spacing: 12) {
                    if canWriteInteractions {
                        Button {
                            onToggleLike(post)
                        } label: {
                            FirePostMetaAction(
                                systemImage: isHeartSelected ? "heart.fill" : "heart",
                                value: totalReactionCount > 0 ? "\(totalReactionCount)" : nil,
                                tint: isHeartSelected ? .red : FireTheme.tertiaryInk
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canChangeReaction)

                        if !nonHeartReactionOptions.isEmpty {
                            Menu {
                                ForEach(nonHeartReactionOptions) { option in
                                    Button("\(option.symbol) \(option.label)") {
                                        onSelectReaction(post, option.id)
                                    }
                                }
                            } label: {
                                FirePostMetaAction(
                                    systemImage: "face.smiling",
                                    value: currentReactionOption.map { "\($0.symbol)" },
                                    tint: currentReactionOption == nil ? FireTheme.tertiaryInk : FireTheme.accent
                                )
                            }
                            .disabled(!canChangeReaction)
                        }

                        Button {
                            onReply(post)
                        } label: {
                            FirePostMetaAction(
                                systemImage: "arrowshape.turn.up.left",
                                value: post.replyCount > 0 ? "\(post.replyCount)" : nil,
                                tint: FireTheme.tertiaryInk
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isMutating)
                    } else if post.replyCount > 0 {
                        FirePostMetaAction(
                            systemImage: "arrowshape.turn.up.left",
                            value: "\(post.replyCount)",
                            tint: FireTheme.tertiaryInk
                        )
                    }

                    Spacer()
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct FirePostMetaAction: View {
    let systemImage: String
    let value: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            if let value {
                Text(value)
                    .font(.caption.monospacedDigit())
            }
        }
        .font(.caption2)
        .foregroundStyle(tint)
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
