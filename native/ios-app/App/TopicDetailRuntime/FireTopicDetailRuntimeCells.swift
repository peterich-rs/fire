import SwiftUI
import UIKit

final class FireTopicDetailTextCell: UICollectionViewCell {
    static let reuseID = "FireTopicDetailTextCell"

    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        contentView.backgroundColor = .systemBackground
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .label

        bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.numberOfLines = 0
        bodyLabel.textColor = .secondaryLabel

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(bodyLabel)
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    func configure(title: String?, body: String?) {
        titleLabel.text = title
        titleLabel.isHidden = (title ?? "").isEmpty
        bodyLabel.text = body
        bodyLabel.isHidden = (body ?? "").isEmpty
        accessibilityLabel = [title, body]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configure(title: nil, body: nil)
    }
}

final class FireTopicDetailActionCell: UICollectionViewCell {
    static let reuseID = "FireTopicDetailActionCell"

    private let button = UIButton(type: .system)
    private var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        contentView.backgroundColor = .systemBackground
        button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in
            self?.action?()
        }, for: .touchUpInside)
        contentView.addSubview(button)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            button.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            button.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 34),
        ])
    }

    func configure(title: String, action: @escaping () -> Void) {
        button.setTitle(title, for: .normal)
        self.action = action
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        button.setTitle(nil, for: .normal)
        action = nil
    }
}

final class FireTopicDetailHostingCell: UICollectionViewCell {
    static let reuseID = "FireTopicDetailHostingCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()
        contentView.backgroundColor = .systemBackground
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(configuration: FireTopicDetailRuntimeConfiguration, item: FireTopicDetailRuntimeItem) {
        backgroundConfiguration = .clear()
        contentConfiguration = UIHostingConfiguration {
            FireTopicDetailHostedRow(configuration: configuration, item: item)
        }
        .margins(.all, 0)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentConfiguration = nil
    }
}

struct FireTopicDetailHostedRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let configuration: FireTopicDetailRuntimeConfiguration
    let item: FireTopicDetailRuntimeItem

    var body: some View {
        content
            .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .header:
            headerRow
        case .aiSummary:
            topicAiSummaryRow
        case .originalPost:
            hostedPostRow
        case .stats:
            statsRow
        case .topicVote:
            topicVoteRow
        case .repliesHeader:
            repliesHeaderRow
        case .bodyState:
            bodyStateRow
        case .reply:
            hostedPostRow
        case .replyFooter:
            replyFooterRow
        case .notice:
            Text("正在显示缓存内容")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(configuration.displayedTopicTitle)
                .font(.title3.weight(.bold))

            FlowLayout(spacing: 6, fallbackWidth: max(UIScreen.main.bounds.width - 40, 200)) {
                if configuration.isPrivateMessageThread {
                    FireStatusChip(label: "私信", tone: .accent)

                    ForEach(configuration.displayedParticipants, id: \.userId) { participant in
                        let label = (participant.name ?? "").ifEmpty(participant.username ?? "用户 \(participant.userId)")
                        Text("@\(label)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.indigo.opacity(0.12), in: Capsule())
                    }
                } else {
                    if let displayedCategory = configuration.displayedCategory {
                        let accent = Color(fireHex: displayedCategory.colorHex) ?? FireTheme.accent
                        if let viewModel = configuration.viewModel {
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
                                categoryPill(displayedCategory: displayedCategory, accent: accent)
                            }
                            .buttonStyle(.plain)
                        } else {
                            categoryPill(displayedCategory: displayedCategory, accent: accent)
                        }
                    }

                    ForEach(configuration.displayedTagNames, id: \.self) { tagName in
                        if let viewModel = configuration.viewModel {
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
                                tagPill(tagName)
                            }
                            .buttonStyle(.plain)
                        } else {
                            tagPill(tagName)
                        }
                    }

                    ForEach(configuration.row.statusLabels, id: \.self) { label in
                        FireStatusChip(label: label, tone: .accent)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryPill(
        displayedCategory: FireTopicCategoryPresentation,
        accent: Color
    ) -> some View {
        FireTopicPill(
            label: displayedCategory.displayName,
            backgroundColor: FireTheme.categoryChipBackground(
                accent: accent,
                isDark: colorScheme == .dark
            ),
            foregroundColor: accent
        )
    }

    private func tagPill(_ tagName: String) -> some View {
        Text("#\(tagName)")
            .font(.caption2.weight(.medium))
            .foregroundStyle(FireTheme.tagChipForeground)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(FireTheme.tagChipBackground)
            .clipShape(Capsule())
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
                if configuration.topicAiSummary?.outdated == true {
                    Text("有新回复")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FireTheme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(FireTheme.warning.opacity(0.12), in: Capsule())
                }
            }

            if let topicAiSummary = configuration.topicAiSummary {
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
            } else if configuration.isLoadingTopicAiSummary {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在加载摘要…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let topicAiSummaryError = configuration.topicAiSummaryError {
                HStack(spacing: 8) {
                    Text(topicAiSummaryError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button("重试") {
                        configuration.onReloadTopicAiSummary()
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
    private var hostedPostRow: some View {
        if let context = configuration.postContext(for: item) {
            VStack(spacing: 0) {
                FireSwipeToReplyContainer(enabled: configuration.canWriteInteractions) {
                    configuration.onOpenComposer(context.post)
                } content: {
                    FirePostRow(
                        post: context.post,
                        renderContent: context.renderContent,
                        depth: context.depth,
                        replyContext: context.replyContext,
                        replyTargetPostNumber: context.replyTargetPostNumber,
                        showsThreadLine: context.showsThreadLine,
                        baseURLString: configuration.baseURLString,
                        canWriteInteractions: configuration.canWriteInteractions,
                        isMutating: configuration.isMutatingPost(context.post.id),
                        onLinkTapped: configuration.onLinkTapped,
                        onOpenImage: configuration.onOpenImage,
                        onToggleLike: configuration.onToggleLike,
                        onSelectReaction: configuration.onSelectReaction,
                        onEditPost: configuration.onEditPost,
                        onBookmarkPost: configuration.onBookmarkPost,
                        onDeletePost: configuration.onDeletePost,
                        onRecoverPost: configuration.onRecoverPost,
                        onFlagPost: configuration.onFlagPost,
                        onOpenReplyTarget: configuration.onOpenPostNumber,
                        onOpenReplies: configuration.onOpenPostReplies,
                        onVotePoll: configuration.onVotePoll,
                        onUnvotePoll: configuration.onUnvotePoll
                    )
                }

                if item.kind == .reply, context.showsDivider {
                    Divider()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, item.kind == .originalPost ? 12 : 0)
            .padding(.bottom, item.kind == .originalPost ? 12 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let excerpt = configuration.row.excerptText, item.kind == .originalPost {
            Text(excerpt)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let depth = placeholderDepth {
            FireTopicPostPlaceholder(depth: depth)
                .padding(.horizontal, 16)
        } else {
            Color.clear.frame(height: 0)
        }
    }

    private var placeholderDepth: Int? {
        guard item.kind == .reply,
              let index = item.replyIndex,
              index >= 0,
              index < configuration.replyRows.count else {
            return nil
        }
        return Int(configuration.replyRows[index].entry.depth)
    }

    private var statsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            HStack(spacing: 20) {
                statLabel(value: "\(configuration.displayedReplyCount)", label: "回复")
                statLabel(value: "\(configuration.displayedViewsCount)", label: "浏览")
                statLabel(value: configuration.displayedInteractionCount.map(String.init) ?? "…", label: "互动")
            }
            .padding(.vertical, 4)
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

    @ViewBuilder
    private var topicVoteRow: some View {
        if let detail = configuration.detail, configuration.showsTopicVote {
            topicVotePanel(detail)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    Task { await configuration.onToggleTopicVote() }
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
                .disabled(!configuration.canWriteInteractions)

                Button {
                    Task { await configuration.onShowTopicVoters() }
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

    private var repliesHeaderRow: some View {
        HStack {
            Text("回复")
                .font(.headline)
            Spacer()
            if configuration.detail != nil {
                if configuration.loadedReplyCount < configuration.totalReplyCount {
                    Text("已加载 \(configuration.loadedReplyCount) / \(configuration.totalReplyCount) 条")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(configuration.totalReplyCount) 条 · \(configuration.displayedFloorCount) 楼")
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
        if configuration.isLoadingTopic {
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
        } else if let detailError = configuration.detailError {
            VStack(spacing: 8) {
                Text(detailError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("重试") {
                    Task {
                        await configuration.onLoadTopicDetail()
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
                    await configuration.onLoadTopicDetail()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private var replyFooterRow: some View {
        switch configuration.replyFooterState {
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
                .padding(.vertical, configuration.replyRows.isEmpty ? 16 : 12)
                .task(id: configuration.topic.id) {
                    guard configuration.replyRows.isEmpty else { return }
                    let seedVisiblePostNumbers = configuration.originalPost.map { Set([$0.postNumber]) } ?? []
                    configuration.onPreloadTopicPosts(seedVisiblePostNumbers)
                }
        }
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
}
