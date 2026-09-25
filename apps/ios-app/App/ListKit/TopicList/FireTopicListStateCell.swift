import UIKit

final class FireTopicListStateCell: UICollectionViewCell {
    private let stackView = UIStackView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var onAction: (() -> Void)?

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
        onAction = nil
        actionButton.isHidden = true
        activityIndicator.stopAnimating()
    }

    func configureLoading(title: String = "正在加载书签") {
        iconView.isHidden = true
        activityIndicator.isHidden = false
        activityIndicator.startAnimating()
        titleLabel.text = title
        messageLabel.text = nil
        actionButton.isHidden = true
        setCompact(false)
    }

    func configureLoadingMore() {
        iconView.isHidden = true
        activityIndicator.isHidden = false
        activityIndicator.startAnimating()
        titleLabel.text = nil
        messageLabel.text = nil
        actionButton.isHidden = true
        setCompact(true)
    }

    func configureEmpty(
        title: String = "还没有书签",
        message: String = "把想回看的话题或帖子收进来，后续会统一在这里管理。",
        systemImage: String = "bookmark"
    ) {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        iconView.isHidden = false
        iconView.image = UIImage(systemName: systemImage)
        iconView.tintColor = .tertiaryLabel
        titleLabel.text = title
        messageLabel.text = message
        actionButton.isHidden = true
        setCompact(false)
    }

    func configureBlockingError(
        title: String = "书签加载失败",
        message: String,
        onRetry: @escaping () -> Void
    ) {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        iconView.isHidden = false
        iconView.image = UIImage(systemName: "exclamationmark.triangle.fill")
        iconView.tintColor = .systemRed
        titleLabel.text = title
        messageLabel.text = message
        actionButton.isHidden = false
        actionButton.setTitle("重试", for: .normal)
        self.onAction = onRetry
        setCompact(false)
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 24,
            leading: 24,
            bottom: 24,
            trailing: 24
        )

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        messageLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true

        actionButton.addAction(UIAction { [weak self] _ in
            self?.onAction?()
        }, for: .touchUpInside)

        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(activityIndicator)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(messageLabel)
        stackView.addArrangedSubview(actionButton)

        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34),
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    private func setCompact(_ compact: Bool) {
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: compact ? 10 : 24,
            leading: 24,
            bottom: compact ? 10 : 24,
            trailing: 24
        )
    }
}
