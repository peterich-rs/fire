import SnapKit
import UIKit

/// Shared empty-state chrome for UIKit lists (Home, filtered lists, bookmarks, …).
final class FireUIKitEmptyStateView: UIView {
    struct Configuration {
        var systemImage: String
        var title: String
        var message: String?
        var actionTitle: String?
        var onAction: (() -> Void)?
    }

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let stack = UIStackView()
    private var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ configuration: Configuration) {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 34, weight: .medium)
        iconView.image = UIImage(systemName: configuration.systemImage, withConfiguration: symbolConfig)
        titleLabel.text = configuration.title

        let message = configuration.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        messageLabel.text = message
        messageLabel.isHidden = message.isEmpty

        onAction = configuration.onAction
        if let actionTitle = configuration.actionTitle, !actionTitle.isEmpty, configuration.onAction != nil {
            actionButton.setTitle(actionTitle, for: .normal)
            actionButton.isHidden = false
        } else {
            actionButton.isHidden = true
        }

        isAccessibilityElement = false
        titleLabel.accessibilityTraits = .header
    }

    private func configureHierarchy() {
        backgroundColor = .clear

        iconView.tintColor = FireTheme.uiTertiaryInk
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .vertical)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = FireTheme.uiInk
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = FireTheme.uiSubtleInk
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        actionButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        actionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        actionButton.tintColor = FireTheme.uiAccent
        actionButton.addTarget(self, action: #selector(handleAction), for: .touchUpInside)
        actionButton.fireBindPressBounce(.button)

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(messageLabel)
        stack.addArrangedSubview(actionButton)
        stack.setCustomSpacing(16, after: messageLabel)

        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(24)
            make.trailing.lessThanOrEqualToSuperview().offset(-24)
            make.top.greaterThanOrEqualToSuperview().offset(24)
            make.bottom.lessThanOrEqualToSuperview().offset(-24)
        }
    }

    @objc
    private func handleAction() {
        FireMotionHaptics.selection()
        onAction?()
    }
}
