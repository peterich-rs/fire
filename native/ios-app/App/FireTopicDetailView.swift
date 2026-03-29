import SwiftUI

struct FireTopicDetailView: View {
    @ObservedObject var viewModel: FireAppViewModel
    let topic: TopicSummaryState

    private var detail: TopicDetailState? {
        viewModel.topicDetail(for: topic.id)
    }

    private var detailError: String? {
        viewModel.errorMessage
    }

    private var category: FireTopicCategoryPresentation? {
        viewModel.categoryPresentation(for: topic.categoryId)
    }

    var body: some View {
        List {
            topicHeaderSection
            postsSection
        }
        .listStyle(.plain)
        .navigationTitle("话题")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            viewModel.loadTopicDetail(topicId: topic.id, force: true)
            try? await Task.sleep(for: .seconds(1))
        }
        .task {
            viewModel.loadTopicDetail(topicId: topic.id)
        }
    }

    // MARK: - Header

    private var topicHeaderSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(topic.title)
                    .font(.title3.weight(.bold))

                if let excerpt = FireTopicPresentation.previewText(from: topic.excerpt) {
                    Text(excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                HStack(spacing: 6) {
                    if let category {
                        let accent = Color(fireHex: category.colorHex) ?? FireTheme.accent
                        FireTopicPill(
                            label: category.displayName,
                            backgroundColor: accent.opacity(0.12),
                            foregroundColor: Color(fireHex: category.textColorHex) ?? accent
                        )
                    }

                    ForEach(FireTopicPresentation.tagNames(from: topic.tags), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }

                    ForEach(FireTopicPresentation.topicStatusLabels(for: topic), id: \.self) { label in
                        FireStatusChip(label: label, tone: .accent)
                    }
                }

                Divider()

                HStack(spacing: 20) {
                    statLabel(value: "\(topic.postsCount)", label: "帖子")
                    statLabel(value: "\(topic.replyCount)", label: "回复")
                    statLabel(value: "\(topic.views)", label: "浏览")
                    statLabel(value: "\(topic.likeCount)", label: "赞")
                }
                .padding(.vertical, 4)

                Divider()

                HStack(spacing: 8) {
                    if let lastPosterUsername = topic.lastPosterUsername {
                        FireAvatarView(avatarTemplate: nil, username: lastPosterUsername, size: 20)
                        Text(lastPosterUsername)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let lastPostedAt = FireTopicPresentation.compactTimestamp(topic.lastPostedAt) {
                        Text(lastPostedAt)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 4)
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

    // MARK: - Posts

    private var postsSection: some View {
        Section {
            if let detail {
                ForEach(Array(detail.postStream.posts.enumerated()), id: \.element.id) { index, post in
                    FirePostRow(
                        post: post,
                        showsThreadLine: index != detail.postStream.posts.count - 1
                    )
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
                        viewModel.loadTopicDetail(topicId: topic.id, force: true)
                    }
                    .buttonStyle(.bordered)
                    .tint(FireTheme.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                Button("加载帖子") {
                    viewModel.loadTopicDetail(topicId: topic.id, force: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        } header: {
            HStack {
                Text("帖子")
                Spacer()
                if let detail {
                    Text("\(detail.postStream.posts.count) 条")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Post Row

struct FirePostRow: View {
    let post: TopicPostState
    let showsThreadLine: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                FireAvatarView(
                    avatarTemplate: post.avatarTemplate,
                    username: post.username.isEmpty ? "?" : post.username,
                    size: 32
                )

                if showsThreadLine {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 6)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(post.username.isEmpty ? "Unknown" : post.username)
                        .font(.subheadline.weight(.semibold))

                    if let timestamp = FireTopicPresentation.compactTimestamp(post.createdAt) {
                        Text(timestamp)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if post.acceptedAnswer {
                        Label("已采纳", systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                    }

                    Text("#\(post.postNumber)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Text(FireTopicPresentation.plainText(from: post.cooked))
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    if post.likeCount > 0 {
                        Label("\(post.likeCount)", systemImage: "heart")
                    }
                    if post.replyCount > 0 {
                        Label("\(post.replyCount)", systemImage: "arrowshape.turn.up.left")
                    }
                    if let replyToPostNumber = post.replyToPostNumber {
                        Label("#\(replyToPostNumber)", systemImage: "arrow.turn.up.left")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
        }
    }
}
