import UIKit

final class FireSearchSectionHeaderCell: UICollectionViewCell {
    let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        titleLabel.text = title
    }

    func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 14,
            leading: 16,
            bottom: 4,
            trailing: 16
        )

        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline).withSearchWeight(.semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }
}

final class FireSearchPostResultCell: UICollectionViewCell {
    let titleLabel = UILabel()
    let excerptLabel = UILabel()
    let metaStack = UIStackView()

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
        metaStack.arrangedSubviews.forEach { view in
            metaStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    func configureMissing() {
        titleLabel.text = "帖子结果"
        excerptLabel.text = nil
        metaStack.arrangedSubviews.forEach { view in
            metaStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    func configure(post: SearchPostState, row: FireTopicRowPresentation?) {
        titleLabel.text = post.topicTitleHeadline ?? row?.topic.title ?? "帖子结果"
        excerptLabel.text = previewTextFromHtml(rawHtml: post.blurb) ?? post.blurb
        configureMeta(post: post)

        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = [
            titleLabel.text,
            excerptLabel.text,
            "@\(post.username)",
            "第 \(post.postNumber) 楼",
        ].compactMap { $0 }.joined(separator: "，")
    }

    func configureMeta(post: SearchPostState) {
        metaStack.arrangedSubviews.forEach { view in
            metaStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        metaStack.addArrangedSubview(makeMetaLabel(systemImage: "person", text: post.username))
        metaStack.addArrangedSubview(makeMetaLabel(systemImage: "number", text: "\(post.postNumber)"))
        if post.likeCount > 0 {
            metaStack.addArrangedSubview(makeMetaLabel(systemImage: "heart", text: "\(post.likeCount)"))
        }
        if let timestampText = FireTopicPresentation.compactTimestamp(
            unixMs: post.createdTimestampUnixMs
        ) {
            metaStack.addArrangedSubview(makeMetaLabel(systemImage: "clock", text: timestampText))
        }
        metaStack.addArrangedSubview(UIView())
    }

    func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 8,
            trailing: 16
        )

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        excerptLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        excerptLabel.adjustsFontForContentSizeCategory = true
        excerptLabel.textColor = .secondaryLabel
        excerptLabel.numberOfLines = 3

        metaStack.axis = .horizontal
        metaStack.alignment = .center
        metaStack.spacing = 10

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(excerptLabel)
        stackView.addArrangedSubview(metaStack)

        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    func makeMetaLabel(systemImage: String, text: String) -> UIView {
        let imageView = UIImageView(image: UIImage(systemName: systemImage))
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = text
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 1

        let stackView = UIStackView(arrangedSubviews: [imageView, label])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 4
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 12),
            imageView.heightAnchor.constraint(equalToConstant: 12),
        ])
        return stackView
    }
}

final class FireSearchUserResultCell: UICollectionViewCell {
    let avatarView = FireTopicListAvatarView()
    let nameLabel = UILabel()
    let usernameLabel = UILabel()

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
    }

    func configureMissing() {
        nameLabel.text = "用户"
        usernameLabel.text = nil
        avatarView.prepareForReuse()
    }

    func configure(user: SearchUserState, baseURLString: String) {
        nameLabel.text = user.name ?? user.username
        usernameLabel.text = "@\(user.username)"
        avatarView.configure(
            username: user.username,
            avatarTemplate: user.avatarTemplate,
            baseURLString: baseURLString
        )

        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = "用户搜索结果：\(user.name ?? user.username)，@\(user.username)"
    }

    func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 8,
            trailing: 16
        )

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 4

        nameLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 1

        usernameLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        usernameLabel.adjustsFontForContentSizeCategory = true
        usernameLabel.textColor = .secondaryLabel
        usernameLabel.numberOfLines = 1

        textStack.addArrangedSubview(nameLabel)
        textStack.addArrangedSubview(usernameLabel)

        let rowStack = UIStackView(arrangedSubviews: [avatarView, textStack])
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 42),
            avatarView.heightAnchor.constraint(equalToConstant: 42),
            rowStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }
}

final class FireSearchLoadMoreCell: UICollectionViewCell {
    let button = UIButton(type: .system)
    let activityIndicator = UIActivityIndicatorView(style: .medium)
    var onTap: (() -> Void)?

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
        onTap = nil
        activityIndicator.stopAnimating()
    }

    func configure(
        isLoading: Bool,
        isEnabled: Bool,
        onTap: @escaping () -> Void
    ) {
        self.onTap = onTap
        button.isHidden = isLoading
        button.isEnabled = isEnabled
        activityIndicator.isHidden = !isLoading
        if isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 10,
            leading: 16,
            bottom: 10,
            trailing: 16
        )

        button.configuration = {
            var configuration = UIButton.Configuration.plain()
            configuration.title = "加载更多"
            configuration.image = UIImage(systemName: "arrow.down.circle")
            configuration.imagePadding = 6
            return configuration
        }()
        button.addAction(UIAction { [weak self] _ in
            self?.onTap?()
        }, for: .touchUpInside)

        let stackView = UIStackView(arrangedSubviews: [button, activityIndicator])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }
}

private extension UIFont {
    func withSearchWeight(_ weight: Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
