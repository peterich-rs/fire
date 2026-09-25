import UIKit

@MainActor
final class FireOnboardingValidatingView: UIView {
    var onCancel: (() -> Void)?

    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()
    private let detailLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let rowStack = UIStackView()
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        isAnimating: Bool,
        message: String,
        detail: String? = nil,
        showsCancel: Bool = false
    ) {
        label.text = message
        let trimmedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        detailLabel.text = trimmedDetail
        detailLabel.isHidden = trimmedDetail.isEmpty
        cancelButton.isHidden = !showsCancel
        activityIndicator.isHidden = !isAnimating
        if isAnimating {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    private func configureSubviews() {
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.textAlignment = .center

        detailLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .tertiaryLabel
        detailLabel.numberOfLines = 2
        detailLabel.textAlignment = .center
        detailLabel.isHidden = true

        var cancelConfig = UIButton.Configuration.plain()
        cancelConfig.title = "取消"
        cancelConfig.baseForegroundColor = FireTheme.uiAccent
        cancelConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        cancelButton.configuration = cancelConfig
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.isHidden = true

        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.distribution = .fill
        rowStack.spacing = 8
        rowStack.addArrangedSubview(activityIndicator)
        rowStack.addArrangedSubview(label)

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(rowStack)
        stackView.addArrangedSubview(detailLabel)
        stackView.addArrangedSubview(cancelButton)

        addSubview(stackView)
        // Prefer natural height; avoid being vertically compressed by the centered onboarding column.
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            rowStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 22),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    override var intrinsicContentSize: CGSize {
        let size = stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height + 48)
    }
}
