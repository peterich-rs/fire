import SnapKit
import UIKit

/// Inline non-blocking error banner used above list content.
final class FireUIKitErrorBannerView: UIView {
    private let iconView = UIImageView()
    private let messageLabel = UILabel()
    private let dismissButton = UIButton(type: .system)
    private var onDismiss: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(message: String, onDismiss: (() -> Void)? = nil) {
        messageLabel.text = message
        self.onDismiss = onDismiss
        dismissButton.isHidden = onDismiss == nil
        accessibilityLabel = message
    }

    private func configureHierarchy() {
        backgroundColor = FireTheme.uiError.withAlphaComponent(0.12)
        layer.cornerRadius = FireTheme.smallCornerRadius
        layer.cornerCurve = .continuous

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: symbolConfig)
        iconView.tintColor = FireTheme.uiError
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        messageLabel.font = .preferredFont(forTextStyle: .footnote)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = FireTheme.uiInk
        messageLabel.numberOfLines = 0

        dismissButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        dismissButton.tintColor = FireTheme.uiSubtleInk
        dismissButton.addTarget(self, action: #selector(handleDismiss), for: .touchUpInside)
        dismissButton.accessibilityLabel = "关闭"

        let stack = UIStackView(arrangedSubviews: [iconView, messageLabel, dismissButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10

        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12))
        }

        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    @objc
    private func handleDismiss() {
        FireMotionHaptics.selection()
        onDismiss?()
    }
}
