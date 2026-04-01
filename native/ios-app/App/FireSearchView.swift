import SwiftUI

struct FireSearchView: View {
    @ObservedObject var viewModel: FireAppViewModel

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
        List {
            Section {
                Picker("搜索范围", selection: scopeBinding) {
                    ForEach(FireSearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let errorMessage = viewModel.searchErrorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if viewModel.isSearching && viewModel.searchResult == nil {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 24)
                }
            } else if let result = viewModel.searchResult {
                resultSection(result)
            } else {
                placeholderSection
            }
        }
        .listStyle(.plain)
        .navigationTitle("搜索")
        .searchable(text: $viewModel.searchQuery, prompt: "搜索话题、帖子、用户")
        .onSubmit(of: .search) {
            viewModel.submitSearch(reset: true)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("搜索") {
                    viewModel.submitSearch(reset: true)
                }
                .disabled(trimmedQuery.isEmpty || viewModel.isSearching)
            }
        }
    }

    @ViewBuilder
    private func resultSection(_ result: SearchResultState) -> some View {
        let topicIndex = Dictionary(
            result.topics.map { ($0.id, $0) },
            uniquingKeysWith: { _, newest in newest }
        )

        if !result.topics.isEmpty {
            Section("话题") {
                ForEach(result.topics, id: \.id) { topic in
                    NavigationLink {
                        FireTopicDetailView(viewModel: viewModel, row: topicRow(for: topic))
                    } label: {
                        FireTopicRow(
                            row: topicRow(for: topic),
                            category: viewModel.categoryPresentation(for: topic.categoryId)
                        )
                    }
                }
            }
        }

        if !result.posts.isEmpty {
            Section("帖子") {
                ForEach(result.posts, id: \.id) { post in
                    if let row = postRow(for: post, topicIndex: topicIndex) {
                        NavigationLink {
                            FireTopicDetailView(viewModel: viewModel, row: row)
                        } label: {
                            FireSearchPostRow(post: post, row: row)
                        }
                    } else {
                        FireSearchPostRow(post: post, row: nil)
                    }
                }
            }
        }

        if !result.users.isEmpty {
            Section("用户") {
                ForEach(result.users, id: \.id) { user in
                    FireSearchUserRow(user: user)
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
                        } else {
                            Label("加载更多", systemImage: "arrow.down.circle")
                                .foregroundStyle(FireTheme.accent)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .disabled(viewModel.isSearching || viewModel.isAppendingSearch)
            }
        }

        if result.posts.isEmpty && result.topics.isEmpty && result.users.isEmpty {
            Section {
                Text("没有找到相关结果。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var placeholderSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("输入关键词后回车或点右上角搜索。")
                    .font(.subheadline)
                Text("支持 Discourse DSL，例如 `in:bookmarks`、`tags:flutter`、`status:open`。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

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
                unseen: false,
                unreadPosts: 0,
                newPosts: 0,
                lastReadPostNumber: nil,
                highestPostNumber: max(topic.postsCount, 1),
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
                Text("@\(post.username)")
                Text("#\(post.postNumber)")
                if let timestampText = FireTopicPresentation.compactTimestamp(
                    unixMs: post.createdTimestampUnixMs
                ) {
                    Text(timestampText)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

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
