import UIKit

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

