import UIKit

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

