import SwiftUI
import UIKit

enum FireTopicDetailRuntimeCellColors {
    static let accent = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.96, green: 0.45, blue: 0.22, alpha: 1)
        }
        return UIColor(red: 0.91, green: 0.39, blue: 0.18, alpha: 1)
    }
}

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

final class FireTopicDetailStatsCell: UICollectionViewCell {
    static let reuseID = "FireTopicDetailStatsCell"

    private let dividerView = UIView()
    private let stackView = UIStackView()
    private let replyStat = FireTopicDetailStatView()
    private let viewStat = FireTopicDetailStatView()
    private let interactionStat = FireTopicDetailStatView()

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
        dividerView.backgroundColor = .separator
        dividerView.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fillEqually
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(replyStat)
        stackView.addArrangedSubview(viewStat)
        stackView.addArrangedSubview(interactionStat)

        contentView.addSubview(dividerView)
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            dividerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            dividerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            dividerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            dividerView.heightAnchor.constraint(equalToConstant: 0.5),

            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: dividerView.bottomAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    func configure(replyCount: UInt32, viewCount: UInt32, interactionCount: UInt32?) {
        replyStat.configure(value: "\(replyCount)", label: "回复")
        viewStat.configure(value: "\(viewCount)", label: "浏览")
        interactionStat.configure(value: interactionCount.map(String.init) ?? "...", label: "互动")
        accessibilityLabel = "\(replyCount) 回复，\(viewCount) 浏览"
    }
}

private final class FireTopicDetailStatView: UIView {
    private let valueLabel = UILabel()
    private let titleLabel = UILabel()
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
        valueLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont.monospacedDigitSystemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                weight: .semibold
            )
        )
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = .label
        valueLabel.textAlignment = .center

        titleLabel.font = .preferredFont(forTextStyle: .caption2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(valueLabel)
        stackView.addArrangedSubview(titleLabel)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func configure(value: String, label: String) {
        valueLabel.text = value
        titleLabel.text = label
    }
}

final class FireTopicDetailRepliesHeaderCell: UICollectionViewCell {
    static let reuseID = "FireTopicDetailRepliesHeaderCell"

    private let titleLabel = UILabel()
    private let countLabel = UILabel()
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

        titleLabel.text = "回复"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label

        countLabel.font = .preferredFont(forTextStyle: .subheadline)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .right
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(countLabel)
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])
    }

    func configure(loadedReplyCount: Int, totalReplyCount: Int, displayedFloorCount: Int, hasDetail: Bool) {
        if hasDetail {
            if loadedReplyCount < totalReplyCount {
                countLabel.text = "已加载 \(loadedReplyCount) / \(totalReplyCount) 条"
            } else {
                countLabel.text = "\(totalReplyCount) 条 · \(displayedFloorCount) 楼"
            }
        } else {
            countLabel.text = nil
        }
        accessibilityLabel = [titleLabel.text, countLabel.text]
            .compactMap { $0 }
            .joined(separator: "，")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configure(loadedReplyCount: 0, totalReplyCount: 0, displayedFloorCount: 0, hasDetail: false)
    }
}

final class FireTopicDetailReplyFooterCell: UICollectionViewCell {
    static let reuseID = "FireTopicDetailReplyFooterCell"

    private let label = UILabel()
    private let button = UIButton(type: .system)
    private let loadingStack = UIStackView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()
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

        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.image = UIImage(systemName: "arrow.down.circle")
        buttonConfiguration.imagePadding = 6
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        button.configuration = buttonConfiguration
        button.tintColor = FireTopicDetailRuntimeCellColors.accent
        button.titleLabel?.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                weight: .semibold
            )
        )
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in
            self?.action?()
        }, for: .touchUpInside)

        loadingLabel.text = "正在加载更多回复..."
        loadingLabel.font = .preferredFont(forTextStyle: .subheadline)
        loadingLabel.adjustsFontForContentSizeCategory = true
        loadingLabel.textColor = .secondaryLabel
        loadingStack.axis = .horizontal
        loadingStack.alignment = .center
        loadingStack.spacing = 8
        loadingStack.translatesAutoresizingMaskIntoConstraints = false
        loadingStack.addArrangedSubview(activityIndicator)
        loadingStack.addArrangedSubview(loadingLabel)

        contentView.addSubview(label)
        contentView.addSubview(button)
        contentView.addSubview(loadingStack)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            button.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            button.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            button.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),

            loadingStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            loadingStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            loadingStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            loadingStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        configure(state: .none, action: nil)
    }

    func configure(state: FireTopicDetailRuntimeReplyFooterState, action: (() -> Void)?) {
        self.action = action
        label.isHidden = true
        button.isHidden = true
        loadingStack.isHidden = true
        activityIndicator.stopAnimating()
        accessibilityTraits = []

        switch state {
        case .none:
            accessibilityLabel = nil
        case .empty:
            label.text = "还没有回复"
            label.isHidden = false
            accessibilityLabel = label.text
        case .loadMore:
            var configuration = button.configuration
            configuration?.title = "查看更多回复"
            button.configuration = configuration
            button.isHidden = false
            button.isEnabled = action != nil
            accessibilityLabel = "查看更多回复"
            accessibilityTraits = [.button]
        case .loadingFooter:
            loadingStack.isHidden = false
            activityIndicator.startAnimating()
            accessibilityLabel = loadingLabel.text
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configure(state: .none, action: nil)
    }
}

final class FireTopicDetailBodyStateCell: UICollectionViewCell {
    static let reuseID = "FireTopicDetailBodyStateCell"

    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let messageLabel = UILabel()
    private let button = UIButton(type: .system)
    private let stackView = UIStackView()
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

        messageLabel.font = .preferredFont(forTextStyle: .caption1)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        button.setTitleColor(FireTopicDetailRuntimeCellColors.accent, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.addAction(UIAction { [weak self] _ in
            self?.action?()
        }, for: .touchUpInside)

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(activityIndicator)
        stackView.addArrangedSubview(messageLabel)
        stackView.addArrangedSubview(button)
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        configure(isLoading: false, errorMessage: nil, action: nil)
    }

    func configure(isLoading: Bool, errorMessage: String?, action: (() -> Void)?) {
        self.action = action
        if isLoading {
            activityIndicator.isHidden = false
            activityIndicator.startAnimating()
            messageLabel.text = "加载中..."
            button.isHidden = true
            button.setTitle(nil, for: .normal)
        } else {
            activityIndicator.stopAnimating()
            activityIndicator.isHidden = true
            messageLabel.text = errorMessage ?? "加载帖子"
            button.setTitle(errorMessage == nil ? "加载" : "重试", for: .normal)
            button.isHidden = action == nil
        }
        accessibilityLabel = [messageLabel.text, button.title(for: .normal)]
            .compactMap { $0 }
            .joined(separator: "，")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configure(isLoading: false, errorMessage: nil, action: nil)
    }
}

final class FireTopicDetailTopicVoteCell: UICollectionViewCell {
    static let reuseID = "FireTopicDetailTopicVoteCell"

    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let toggleButton = UIButton(type: .system)
    private let votersButton = UIButton(type: .system)
    private let headerStack = UIStackView()
    private let buttonStack = UIStackView()
    private let rootStack = UIStackView()
    private var toggleAction: (() -> Void)?
    private var votersAction: (() -> Void)?

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

        containerView.backgroundColor = .secondarySystemBackground
        containerView.layer.cornerRadius = 8
        containerView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                weight: .semibold
            )
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = FireTopicDetailRuntimeCellColors.accent

        statusLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
                weight: .semibold
            )
        )
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .systemGreen
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)

        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 10
        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(UIView())
        headerStack.addArrangedSubview(statusLabel)

        configureToggleButtonStyle()
        configureVotersButtonStyle()

        toggleButton.addAction(UIAction { [weak self] _ in
            self?.toggleAction?()
        }, for: .touchUpInside)
        votersButton.addAction(UIAction { [weak self] _ in
            self?.votersAction?()
        }, for: .touchUpInside)

        buttonStack.axis = .horizontal
        buttonStack.alignment = .center
        buttonStack.spacing = 10
        buttonStack.addArrangedSubview(toggleButton)
        buttonStack.addArrangedSubview(votersButton)
        buttonStack.addArrangedSubview(UIView())

        rootStack.axis = .vertical
        rootStack.alignment = .fill
        rootStack.spacing = 10
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(headerStack)
        rootStack.addArrangedSubview(buttonStack)

        contentView.addSubview(containerView)
        containerView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            rootStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 14),
            rootStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -14),
            rootStack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 14),
            rootStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -14),
        ])
    }

    private func configureToggleButtonStyle() {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        toggleButton.configuration = configuration
        toggleButton.titleLabel?.adjustsFontForContentSizeCategory = true
    }

    private func configureVotersButtonStyle() {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "person.3")
        configuration.imagePadding = 6
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        votersButton.configuration = configuration
        votersButton.tintColor = FireTopicDetailRuntimeCellColors.accent
        votersButton.titleLabel?.adjustsFontForContentSizeCategory = true
    }

    func configure(
        detail: TopicDetailState,
        canWriteInteractions: Bool,
        onToggle: (() -> Void)?,
        onShowVoters: (() -> Void)?
    ) {
        titleLabel.text = "\(detail.voteCount) 票"
        statusLabel.text = detail.userVoted ? "你已投票" : nil
        statusLabel.isHidden = !detail.userVoted

        var toggleConfiguration = toggleButton.configuration
        toggleConfiguration?.title = detail.userVoted ? "取消投票" : "投一票"
        toggleConfiguration?.baseBackgroundColor = detail.userVoted
            ? .tertiarySystemFill
            : FireTopicDetailRuntimeCellColors.accent
        toggleConfiguration?.baseForegroundColor = detail.userVoted ? .label : .white
        toggleButton.configuration = toggleConfiguration
        toggleButton.isEnabled = canWriteInteractions

        var votersConfiguration = votersButton.configuration
        votersConfiguration?.title = "查看投票用户"
        votersButton.configuration = votersConfiguration

        toggleAction = onToggle
        votersAction = onShowVoters
        accessibilityLabel = "\(detail.voteCount) 票" + (detail.userVoted ? "，你已投票" : "")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        toggleAction = nil
        votersAction = nil
        statusLabel.text = nil
        statusLabel.isHidden = true
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
        case .originalPost, .stats, .topicVote, .repliesHeader, .bodyState, .reply, .replyFooter, .notice:
            EmptyView()
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
