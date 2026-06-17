import UIKit

@MainActor
final class FireOnboardingLoggingInView: UIView {
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let label = UILabel()
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureSubviews() {
        backgroundColor = UIColor.black.withAlphaComponent(0.3)

        label.text = "正在登录…"
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.numberOfLines = 1

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(activityIndicator)
        stackView.addArrangedSubview(label)

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
        ])

        activityIndicator.startAnimating()
    }
}
