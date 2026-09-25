import UIKit

final class FireNotificationInfoBannerCell: UICollectionViewCell {
    private let containerView = UIView()
    private let iconView = UIImageView()
    private let messageLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        message: String,
        systemImage: String,
        tintColor: UIColor
    ) {
        messageLabel.text = message
        iconView.image = UIImage(systemName: systemImage)
        iconView.tintColor = tintColor
        containerView.backgroundColor = tintColor.withAlphaComponent(0.10)
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 8,
            trailing: 16
        )

        containerView.layer.cornerRadius = 8
        containerView.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        messageLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .label
        messageLabel.numberOfLines = 2

        let stackView = UIStackView(arrangedSubviews: [iconView, messageLabel])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(containerView)
        containerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            containerView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
        ])
    }
}

final class FireNotificationLinkCell: UICollectionViewCell {
    private let label = UILabel()
    private let iconView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, systemImage: String) {
        label.text = title
        iconView.image = UIImage(systemName: systemImage)
        accessibilityLabel = title
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 8,
            trailing: 16
        )

        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = FireTopicListPalette.accent
        label.numberOfLines = 1

        iconView.tintColor = FireTopicListPalette.accent
        iconView.contentMode = .scaleAspectFit

        let stackView = UIStackView(arrangedSubviews: [label, iconView])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let centeredStack = UIStackView(arrangedSubviews: [UIView(), stackView, UIView()])
        centeredStack.axis = .horizontal
        centeredStack.alignment = .center
        centeredStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(centeredStack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            centeredStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            centeredStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            centeredStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            centeredStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])

        isAccessibilityElement = true
        accessibilityTraits = [.button]
    }
}
