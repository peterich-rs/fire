import UIKit

final class FireHomeLoadingSkeletonCell: UICollectionViewCell {
    let avatarView = UIView()
    let titleBar = UIView()
    let subtitleBar = UIView()

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
        FireUIKitSkeleton.hide(contentView)
    }

    func configure() {
        isAccessibilityElement = false
        contentView.isAccessibilityElement = false
        FireUIKitSkeleton.show(contentView)
    }

    func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 6,
            leading: 16,
            bottom: 6,
            trailing: 16
        )

        avatarView.layer.cornerRadius = 19
        avatarView.layer.cornerCurve = .continuous
        titleBar.layer.cornerRadius = 4
        titleBar.layer.cornerCurve = .continuous
        subtitleBar.layer.cornerRadius = 4
        subtitleBar.layer.cornerCurve = .continuous

        let bodyStack = UIStackView(arrangedSubviews: [titleBar, subtitleBar])
        bodyStack.axis = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 6
        bodyStack.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = UIStackView(arrangedSubviews: [avatarView, bodyStack])
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 38),
            avatarView.heightAnchor.constraint(equalToConstant: 38),
            titleBar.heightAnchor.constraint(equalToConstant: 14),
            titleBar.widthAnchor.constraint(equalTo: bodyStack.widthAnchor),
            subtitleBar.widthAnchor.constraint(equalToConstant: 100),
            subtitleBar.heightAnchor.constraint(equalToConstant: 10),
            rowStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])

        FireUIKitSkeleton.prepareHierarchy(in: contentView)
    }
}

final class FireHomeOfflineBannerView: UIView {
    let iconView = UIImageView(image: UIImage(systemName: "wifi.slash"))
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureSubviews() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 3)

        iconView.tintColor = .systemOrange
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        label.text = "当前网络不可用，显示已缓存内容"
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 2

        let stackView = UIStackView(arrangedSubviews: [iconView, label])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }
}
