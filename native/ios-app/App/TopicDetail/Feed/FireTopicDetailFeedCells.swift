import AsyncDisplayKit
import UIKit

enum FireTopicDetailCellColors {
    static var accent: UIColor { FireTheme.uiAccent }
    static var warning: UIColor { FireTheme.uiWarning }
    static var tagChipBackground: UIColor { FireTheme.uiTagChipBackground }
    static var tagChipForeground: UIColor { FireTheme.uiTagChipForeground }
    static let privateMessageForeground = UIColor.systemIndigo

    static func categoryChipBackground(accent: UIColor) -> UIColor {
        FireTheme.uiCategoryChipBackground(accent: accent)
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
        contentView.backgroundColor = FireTheme.uiCanvas
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
        contentView.backgroundColor = FireTheme.uiCanvas
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
        contentView.backgroundColor = FireTheme.uiCanvas

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
        contentView.backgroundColor = FireTheme.uiCanvas

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
        button.tintColor = FireTopicDetailCellColors.accent
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
        case .loadMoreAvailable:
            var configuration = button.configuration
            configuration?.image = UIImage(systemName: "arrow.down.circle")
            configuration?.title = "加载更多回复"
            button.configuration = configuration
            button.isHidden = false
            button.isEnabled = action != nil
            accessibilityLabel = "加载更多回复"
            accessibilityTraits = [.button]
        case .emptyPrompt:
            label.text = "还没有回复，发表你的看法吧"
            label.isHidden = false
            accessibilityLabel = label.text
        case .endReached:
            label.text = "---- 到底了 ----"
            label.isHidden = false
            accessibilityLabel = label.text
        case .loadFailed(_):
            var configuration = button.configuration
            configuration?.image = UIImage(systemName: "arrow.clockwise.circle")
            configuration?.title = "加载更多回复失败，点击重试"
            button.configuration = configuration
            button.isHidden = false
            button.isEnabled = action != nil
            accessibilityLabel = "加载更多回复失败，点击重试"
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
        contentView.backgroundColor = FireTheme.uiCanvas

        messageLabel.font = .preferredFont(forTextStyle: .caption1)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        button.setTitleColor(FireTopicDetailCellColors.accent, for: .normal)
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
        contentView.backgroundColor = FireTheme.uiCanvas

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
        titleLabel.textColor = FireTopicDetailCellColors.accent

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
        votersButton.tintColor = FireTopicDetailCellColors.accent
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
            : FireTopicDetailCellColors.accent
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

final class FireTopicDetailHeaderCellNode: ASCellNode {
    private let titleNode = ASTextNode()
    private let chipNodes: [ASButtonNode]

    init(
        configuration: FireTopicDetailRuntimeConfiguration,
        colorTraits: UITraitCollection = .current
    ) {
        var chips: [ASButtonNode] = []
        let titleInk = FireTextureAttributedText.ink(with: colorTraits)

        titleNode.attributedText = NSAttributedString(
            string: configuration.displayedTopicTitle,
            attributes: [
                .font: FireTopicDetailRuntimeTypography.scaledFont(textStyle: .title3, weight: .bold),
                .foregroundColor: titleInk,
            ]
        )
        titleNode.maximumNumberOfLines = 0
        titleNode.style.flexShrink = 1.0

        if configuration.isPrivateMessageThread {
            chips.append(Self.makeChip(
                title: "私信",
                foregroundColor: FireTopicDetailCellColors.accent,
                backgroundColor: FireTopicDetailCellColors.accent.withAlphaComponent(0.12)
            ))

            for participant in configuration.displayedParticipants {
                let label = (participant.name ?? "").ifEmpty(participant.username ?? "用户 \(participant.userId)")
                chips.append(Self.makeChip(
                    title: "@\(label)",
                    foregroundColor: FireTopicDetailCellColors.privateMessageForeground,
                    backgroundColor: FireTopicDetailCellColors.privateMessageForeground.withAlphaComponent(0.12)
                ))
            }
        } else {
            if let category = configuration.displayedCategory {
                let accent = UIColor(fireHex: category.colorHex) ?? FireTopicDetailCellColors.accent
                chips.append(Self.makeChip(
                    title: category.displayName,
                    foregroundColor: accent,
                    backgroundColor: FireTopicDetailCellColors.categoryChipBackground(accent: accent),
                    action: configuration.viewModel == nil ? nil : {
                        configuration.onOpenCategory(category)
                    }
                ))
            }

            for tagName in configuration.displayedTagNames {
                chips.append(Self.makeChip(
                    title: "#\(tagName)",
                    foregroundColor: FireTopicDetailCellColors.tagChipForeground,
                    backgroundColor: FireTopicDetailCellColors.tagChipBackground,
                    horizontalInset: 6,
                    verticalInset: 3,
                    action: configuration.viewModel == nil ? nil : {
                        configuration.onOpenTag(tagName)
                    }
                ))
            }

            for label in configuration.row.statusLabels {
                chips.append(Self.makeChip(
                    title: label,
                    foregroundColor: FireTopicDetailCellColors.accent,
                    backgroundColor: FireTopicDetailCellColors.accent.withAlphaComponent(0.12)
                ))
            }
        }

        chipNodes = chips
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = FireTheme.uiCanvas
        isAccessibilityElement = true
        accessibilityLabel = [configuration.displayedTopicTitle, chips.compactMap(\.accessibilityLabel).joined(separator: ", ")]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        var children: [ASLayoutElement] = [titleNode]
        if !chipNodes.isEmpty {
            let chipStack = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 6,
                justifyContent: .start,
                alignItems: .start,
                children: chipNodes
            )
            chipStack.flexWrap = .wrap
            chipStack.alignContent = .start
            chipStack.lineSpacing = 6
            children.append(chipStack)
        }

        let stack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 8,
            justifyContent: .start,
            alignItems: .stretch,
            children: children
        )
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 16, left: 16, bottom: 0, right: 16),
            child: stack
        )
    }

    private static func makeChip(
        title: String,
        foregroundColor: UIColor,
        backgroundColor: UIColor,
        horizontalInset: CGFloat = 8,
        verticalInset: CGFloat = 4,
        action: (() -> Void)? = nil
    ) -> ASButtonNode {
        let node = FireTopicDetailChipButtonNode(action: action)
        node.setAttributedTitle(
            NSAttributedString(
                string: title,
                attributes: [
                    .font: FireTopicDetailRuntimeTypography.scaledFont(textStyle: .caption2, weight: .medium),
                    .foregroundColor: foregroundColor,
                ]
            ),
            for: .normal
        )
        node.contentEdgeInsets = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
        node.backgroundColor = backgroundColor
        node.cornerRadius = 12
        node.clipsToBounds = true
        node.isEnabled = action != nil
        node.accessibilityLabel = title
        if action != nil {
            node.accessibilityTraits.insert(.button)
        }
        return node
    }
}

final class FireTopicDetailAISummaryCellNode: ASCellNode {
    private let backgroundNode = ASDisplayNode()
    private let headerButtonNode: FireTopicDetailChipButtonNode
    private let iconNode = ASImageNode()
    private let titleNode = ASTextNode()
    private let statusNode = ASTextNode()
    private let chevronNode = ASImageNode()
    private let bodyNode = ASTextNode()
    private let metadataNode = ASTextNode()
    private let isExpanded: Bool

    init(
        configuration: FireTopicDetailRuntimeConfiguration,
        colorTraits: UITraitCollection = .current
    ) {
        let summary = configuration.topicAiSummary
        isExpanded = configuration.isTopicAiSummaryExpanded && summary != nil
        let primaryInk = FireTextureAttributedText.ink(with: colorTraits)
        let secondaryInk = FireTextureAttributedText.subtleInk(with: colorTraits)
        let tertiaryInk = FireTextureAttributedText.tertiaryInk(with: colorTraits)

        backgroundNode.backgroundColor = .secondarySystemBackground
        backgroundNode.cornerRadius = 8
        backgroundNode.clipsToBounds = true

        iconNode.image = UIImage(systemName: "sparkles")?.withTintColor(
            FireTopicDetailCellColors.accent,
            renderingMode: .alwaysOriginal
        )
        iconNode.style.preferredSize = CGSize(width: 17, height: 17)

        titleNode.attributedText = NSAttributedString(
            string: "AI 摘要",
            attributes: [
                .font: FireTopicDetailRuntimeTypography.scaledFont(textStyle: .subheadline, weight: .semibold),
                .foregroundColor: primaryInk,
            ]
        )

        if summary?.outdated == true {
            statusNode.attributedText = NSAttributedString(
                string: "有新回复",
                attributes: [
                    .font: FireTopicDetailRuntimeTypography.scaledFont(textStyle: .caption2, weight: .semibold),
                    .foregroundColor: FireTopicDetailCellColors.warning,
                ]
            )
            statusNode.backgroundColor = FireTopicDetailCellColors.warning.withAlphaComponent(0.12)
            statusNode.cornerRadius = 10
            statusNode.textContainerInset = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        } else {
            statusNode.isHidden = true
        }

        let chevronName = isExpanded ? "chevron.up" : "chevron.down"
        chevronNode.image = UIImage(systemName: chevronName)?.withTintColor(
            tertiaryInk,
            renderingMode: .alwaysOriginal
        )
        chevronNode.style.preferredSize = CGSize(width: 14, height: 14)

        if let summary, isExpanded {
            bodyNode.attributedText = NSAttributedString(
                string: summary.summarizedText,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: primaryInk,
                ]
            )
            bodyNode.maximumNumberOfLines = 0
            bodyNode.style.flexShrink = 1.0

            let metadata = Self.metadata(for: summary)
            if !metadata.isEmpty {
                metadataNode.attributedText = NSAttributedString(
                    string: metadata.joined(separator: " · "),
                    attributes: [
                        .font: UIFont.preferredFont(forTextStyle: .caption2),
                        .foregroundColor: secondaryInk,
                    ]
                )
                metadataNode.maximumNumberOfLines = 0
            } else {
                metadataNode.isHidden = true
            }
        } else {
            bodyNode.isHidden = true
            metadataNode.isHidden = true
        }

        headerButtonNode = FireTopicDetailChipButtonNode(action: configuration.onToggleTopicAiSummaryExpanded)
        headerButtonNode.accessibilityLabel = isExpanded ? "收起 AI 摘要" : "展开 AI 摘要"

        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = FireTheme.uiCanvas
        isAccessibilityElement = false
        accessibilityElements = [headerButtonNode, bodyNode, metadataNode].filter { !$0.isHidden }
        headerButtonNode.accessibilityValue = [
            statusNode.isHidden ? nil : "有新回复",
            isExpanded ? bodyNode.attributedText?.string : "已折叠",
            isExpanded ? metadataNode.attributedText?.string : nil,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "，")
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let headerSpacer = ASLayoutSpec()
        headerSpacer.style.flexGrow = 1.0
        let headerChildren: [ASLayoutElement] = [
            iconNode,
            titleNode,
            headerSpacer,
            statusNode,
            chevronNode,
        ].filter { element in
            guard let node = element as? ASDisplayNode else { return true }
            return !node.isHidden
        }
        let headerContent = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 8,
            justifyContent: .start,
            alignItems: .center,
            children: headerChildren
        )
        let headerButtonSpec = ASBackgroundLayoutSpec(
            child: headerContent,
            background: headerButtonNode
        )
        headerButtonNode.style.flexGrow = 1.0
        headerButtonNode.style.alignSelf = .stretch

        var contentChildren: [ASLayoutElement] = [headerButtonSpec]
        if !bodyNode.isHidden {
            contentChildren.append(bodyNode)
        }
        if !metadataNode.isHidden {
            contentChildren.append(metadataNode)
        }

        let contentStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: isExpanded ? 10 : 0,
            justifyContent: .start,
            alignItems: .stretch,
            children: contentChildren
        )
        let paddedContent = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14),
            child: contentStack
        )
        let card = ASBackgroundLayoutSpec(child: paddedContent, background: backgroundNode)
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 4, left: 16, bottom: 10, right: 16),
            child: card
        )
    }

    private static func metadata(for summary: TopicAiSummaryState) -> [String] {
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

private final class FireTopicDetailChipButtonNode: ASButtonNode {
    private let action: (() -> Void)?

    init(action: (() -> Void)?) {
        self.action = action
        super.init()
        addTarget(self, action: #selector(handleTap), forControlEvents: .touchUpInside)
    }

    @objc private func handleTap() {
        action?()
    }
}

private enum FireTopicDetailRuntimeTypography {
    static func scaledFont(textStyle: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let preferred = UIFont.preferredFont(forTextStyle: textStyle)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: UIFont.systemFont(ofSize: preferred.pointSize, weight: weight)
        )
    }
}

private extension UIColor {
    convenience init?(fireHex hex: String?) {
        guard let hex else {
            return nil
        }

        let cleaned = hex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .uppercased()
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }

        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
