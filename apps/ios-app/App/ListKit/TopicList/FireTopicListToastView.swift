import UIKit

final class FireTopicListToastView: UIView {
    enum Style {
        case success
        case error
        case info
    }

    init(message: String, style: Style) {
        super.init(frame: .zero)
        configure(message: message, style: style)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(message: String, style: Style) {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.10
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)

        let iconView = UIImageView(image: UIImage(systemName: style.systemImage))
        iconView.tintColor = style.tintColor
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = message
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 3

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        accessibilityLabel = message
    }
}

private extension FireTopicListToastView.Style {
    var systemImage: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    var tintColor: UIColor {
        switch self {
        case .success:
            return .systemGreen
        case .error:
            return .systemRed
        case .info:
            return .systemBlue
        }
    }
}
