import SwiftUI

struct FireSearchView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @FocusState private var isSearchFieldFocused: Bool
    @State private var hasAppeared = false
    @State private var selectedRoute: FireAppRoute?

    private var trimmedQuery: String {
        viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var scopeBinding: Binding<FireSearchScope> {
        Binding(
            get: { viewModel.searchScope },
            set: { viewModel.setSearchScope($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()
            contentArea
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedRoute) { route in
            FireAppRouteDestinationView(viewModel: viewModel, route: route)
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            viewModel.resetSearch()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isSearchFieldFocused = true
            }
        }
    }

    // MARK: - Search Header

    private var searchHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(FireTheme.tertiaryInk)

                TextField("搜索话题、帖子、用户…", text: $viewModel.searchQuery)
                    .focused($isSearchFieldFocused)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        viewModel.submitSearch(reset: true)
                    }

                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.resetSearch()
                        isSearchFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(FireTheme.tertiaryInk)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(FireTheme.softSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(FireTheme.divider, lineWidth: 0.5)
            )

            Picker("搜索范围", selection: scopeBinding) {
                ForEach(FireSearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isSearching && viewModel.searchResult == nil {
            VStack(spacing: 8) {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                Text("搜索中…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let result = viewModel.searchResult {
            resultList(result)
        } else if let errorMessage = viewModel.searchErrorMessage {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(FireTheme.warning)
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("重试") {
                    viewModel.submitSearch(reset: true)
                }
                .buttonStyle(.bordered)
                .tint(FireTheme.accent)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            placeholderView
        }
    }

    // MARK: - Results

    private func resultList(_ result: SearchResultState) -> some View {
        let topicIndex = Dictionary(
            result.topics.map { ($0.id, $0) },
            uniquingKeysWith: { _, newest in newest }
        )

        return List {
            if let errorMessage = viewModel.searchErrorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if !result.topics.isEmpty {
                Section("话题") {
                    ForEach(result.topics, id: \.id) { topic in
                        let row = topicRow(for: topic)
                        Button {
                            selectedRoute = .topic(
                                topicId: topic.id,
                                postNumber: nil,
                                preview: FireTopicRoutePreview(row: row)
                            )
                        } label: {
                            FireTopicRow(
                                row: row,
                                category: viewModel.categoryPresentation(for: topic.categoryId)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !result.posts.isEmpty {
                Section("帖子") {
                    ForEach(result.posts, id: \.id) { post in
                        if let row = postRow(for: post, topicIndex: topicIndex) {
                            Button {
                                selectedRoute = .topic(
                                    topicId: row.topic.id,
                                    postNumber: post.postNumber,
                                    preview: FireTopicRoutePreview(row: row)
                                )
                            } label: {
                                FireSearchPostRow(post: post, row: row)
                            }
                            .buttonStyle(.plain)
                        } else {
                            FireSearchPostRow(post: post, row: nil)
                        }
                    }
                }
            }

            if !result.users.isEmpty {
                Section("用户") {
                    ForEach(result.users, id: \.id) { user in
                        Button {
                            selectedRoute = .profile(username: user.username)
                        } label: {
                            FireSearchUserRow(user: user)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if viewModel.canLoadMoreSearchResults {
                Section {
                    Button {
                        viewModel.submitSearch(reset: false)
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isAppendingSearch {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("加载更多", systemImage: "arrow.down.circle")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(FireTheme.accent)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(viewModel.isSearching || viewModel.isAppendingSearch)
                }
            }

            if result.posts.isEmpty && result.topics.isEmpty && result.users.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.title)
                            .foregroundStyle(FireTheme.tertiaryInk)
                        Text("没有找到相关结果")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer()
                    .frame(height: 40)

                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(FireTheme.tertiaryInk)

                VStack(spacing: 8) {
                    Text("搜索 LinuxDo")
                        .font(.headline)
                    Text("输入关键词搜索话题、帖子或用户")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    dslHintRow("in:bookmarks", "搜索书签内容")
                    dslHintRow("tags:flutter", "按标签搜索")
                    dslHintRow("status:open", "搜索未关闭话题")
                    dslHintRow("@username", "搜索特定用户内容")
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func dslHintRow(_ keyword: String, _ hint: String) -> some View {
        HStack(spacing: 10) {
            Text(keyword)
                .font(.caption.monospaced())
                .foregroundStyle(FireTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(FireTheme.softSurface)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Row Builders

    private func postRow(
        for post: SearchPostState,
        topicIndex: [UInt64: SearchTopicState]
    ) -> FireTopicRowPresentation? {
        guard let topicID = post.topicId else {
            return nil
        }
        let topic = topicIndex[topicID]
            ?? SearchTopicState(
                id: topicID,
                title: post.topicTitleHeadline ?? "话题 \(topicID)",
                slug: "",
                categoryId: nil,
                tags: [],
                postsCount: max(post.postNumber, 1),
                views: 0,
                closed: false,
                archived: false
            )
        let excerpt = previewTextFromHtml(rawHtml: post.blurb)
        return topicRow(for: topic, excerptText: excerpt)
    }

    private func topicRow(
        for topic: SearchTopicState,
        excerptText: String? = nil
    ) -> FireTopicRowPresentation {
        let statusLabels = {
            var labels: [String] = []
            if topic.closed {
                labels.append("已关闭")
            }
            if topic.archived {
                labels.append("已归档")
            }
            return labels
        }()

        return TopicRowState(
            topic: TopicSummaryState(
                id: topic.id,
                title: topic.title,
                slug: topic.slug,
                postsCount: topic.postsCount,
                replyCount: topic.postsCount > 0 ? topic.postsCount - 1 : 0,
                views: topic.views,
                likeCount: 0,
                excerpt: excerptText,
                createdAt: nil,
                lastPostedAt: nil,
                lastPosterUsername: nil,
                categoryId: topic.categoryId,
                pinned: false,
                visible: true,
                closed: topic.closed,
                archived: topic.archived,
                tags: topic.tags.map { TopicTagState(id: nil, name: $0, slug: nil) },
                posters: [],
                participants: [],
                unseen: false,
                unreadPosts: 0,
                newPosts: 0,
                lastReadPostNumber: nil,
                highestPostNumber: max(topic.postsCount, 1),
                bookmarkedPostNumber: nil,
                bookmarkId: nil,
                bookmarkName: nil,
                bookmarkReminderAt: nil,
                bookmarkableType: nil,
                hasAcceptedAnswer: false,
                canHaveAnswer: false
            ),
            excerptText: excerptText,
            originalPosterUsername: nil,
            originalPosterAvatarTemplate: nil,
            tagNames: topic.tags,
            statusLabels: statusLabels,
            isPinned: false,
            isClosed: topic.closed,
            isArchived: topic.archived,
            hasAcceptedAnswer: false,
            hasUnreadPosts: false,
            createdTimestampUnixMs: nil,
            activityTimestampUnixMs: nil,
            lastPosterUsername: nil
        )
    }
}

// MARK: - Post Row

private struct FireSearchPostRow: View {
    let post: SearchPostState
    let row: FireTopicRowPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.topicTitleHeadline ?? row?.topic.title ?? "帖子结果")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(previewTextFromHtml(rawHtml: post.blurb) ?? post.blurb)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 10) {
                Label(post.username, systemImage: "person")
                Label("#\(post.postNumber)", systemImage: "number")
                if post.likeCount > 0 {
                    Label("\(post.likeCount)", systemImage: "heart")
                }
                if let timestampText = FireTopicPresentation.compactTimestamp(
                    unixMs: post.createdTimestampUnixMs
                ) {
                    Label(timestampText, systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - User Row

private struct FireSearchUserRow: View {
    let user: SearchUserState

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(FireTheme.chromeStrong)
                    .frame(width: 42, height: 42)

                Text(monogramForUsername(username: user.username))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FireTheme.ink)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(user.name ?? user.username)
                    .font(.headline)
                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
