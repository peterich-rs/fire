import UIKit

final class FireNotificationListCell: UICollectionViewCell {
    private let unreadDot = UIView()
    private let avatarContainer = UIView()
    private let avatarView = FireTopicListAvatarView()
    private let iconView = UIImageView()
    private let descriptionLabel = UILabel()
    private let timestampLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
        iconView.image = nil
        timestampLabel.text = nil
        backgroundConfiguration = .clear()
    }

    func configureMissing() {
        avatarView.prepareForReuse()
        descriptionLabel.text = nil
        timestampLabel.text = nil
        iconView.image = nil
        unreadDot.backgroundColor = .clear
        isAccessibilityElement = false
    }

    func configure(item: NotificationItemState, baseURLString: String) {
        let timestamp = FireTopicPresentation.compactTimestamp(item.createdAt)
            ?? FireTopicPresentation.compactTimestamp(unixMs: item.createdTimestampUnixMs)
        let avatarTemplate = item.actingUserAvatarTemplate ?? item.data.avatarTemplate
        let username = item.resolvedUsername ?? "?"

        unreadDot.backgroundColor = item.read ? .clear : FireTopicListPalette.accent
        descriptionLabel.text = item.displayDescription
        descriptionLabel.font = Self.descriptionFont(isRead: item.read)
        descriptionLabel.textColor = item.read ? .secondaryLabel : .label
        timestampLabel.text = timestamp

        if let avatarTemplate, !avatarTemplate.isEmpty {
            avatarContainer.backgroundColor = .clear
            iconView.isHidden = true
            avatarView.isHidden = false
            avatarView.configure(
                username: username,
                avatarTemplate: avatarTemplate,
                baseURLString: baseURLString
            )
        } else {
            avatarView.prepareForReuse()
            avatarView.isHidden = true
            iconView.isHidden = false
            avatarContainer.backgroundColor = item.typeIconUIColor.withAlphaComponent(0.12)
            iconView.image = UIImage(systemName: item.typeSystemImage)
            iconView.tintColor = item.typeIconUIColor
        }

        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = item.read
            ? .clear
            : FireTopicListPalette.accent.withAlphaComponent(0.03)
        backgroundConfiguration = background

        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = Self.accessibilitySummary(item: item, timestamp: timestamp)
        accessibilityHint = "双击打开通知"
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 10,
            leading: 16,
            bottom: 10,
            trailing: 16
        )

        unreadDot.layer.cornerRadius = 3.5
        unreadDot.translatesAutoresizingMaskIntoConstraints = false
        unreadDot.setContentHuggingPriority(.required, for: .horizontal)

        avatarContainer.clipsToBounds = true
        avatarContainer.layer.cornerRadius = 17
        avatarContainer.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.setContentHuggingPriority(.required, for: .horizontal)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        descriptionLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.numberOfLines = 3
        descriptionLabel.lineBreakMode = .byTruncatingTail

        timestampLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        timestampLabel.adjustsFontForContentSizeCategory = true
        timestampLabel.textColor = .tertiaryLabel
        timestampLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [descriptionLabel, timestampLabel])
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = UIStackView(arrangedSubviews: [unreadDot, avatarContainer, textStack])
        rowStack.axis = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        avatarContainer.addSubview(avatarView)
        avatarContainer.addSubview(iconView)
        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            unreadDot.widthAnchor.constraint(equalToConstant: 7),
            unreadDot.heightAnchor.constraint(equalToConstant: 7),
            avatarContainer.widthAnchor.constraint(equalToConstant: 34),
            avatarContainer.heightAnchor.constraint(equalToConstant: 34),
            avatarView.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
            avatarView.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor),
            avatarView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            avatarView.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),
            iconView.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            rowStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    private static func descriptionFont(isRead: Bool) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: .subheadline)
        let weight: UIFont.Weight = isRead ? .regular : .semibold
        return UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont.systemFont(ofSize: base.pointSize, weight: weight)
        )
    }

    private static func accessibilitySummary(
        item: NotificationItemState,
        timestamp: String?
    ) -> String {
        var parts = [item.displayDescription]
        if let timestamp {
            parts.append(timestamp)
        }
        parts.append(item.read ? "已读" : "未读")
        return parts.joined(separator: "，")
    }
}
