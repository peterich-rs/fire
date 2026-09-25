import UIKit

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

