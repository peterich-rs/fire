import UIKit

enum FireComposerPalette {
    static var canvas: UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return FireTheme.isOledMode ? .black : UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1)
            }
            return UIColor(red: 0.94, green: 0.93, blue: 0.91, alpha: 1)
        }
    }

    static var surface: UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return FireTheme.isOledMode
                    ? UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
                    : .secondarySystemBackground
            }
            return .secondarySystemBackground
        }
    }

    static var chrome: UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return FireTheme.isOledMode
                    ? UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 0.92)
                    : UIColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 0.90)
            }
            return UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.78)
        }
    }

    static var divider: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.08)
                : UIColor(white: 0, alpha: 0.08)
        }
    }
}

final class FireComposerCardView: UIView {
    private var embeddedView: UIView?

    init() {
        super.init(frame: .zero)
        backgroundColor = FireComposerPalette.surface
        layer.cornerRadius = FireTheme.cornerRadius
        layer.borderColor = FireComposerPalette.divider.cgColor
        layer.borderWidth = 1
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func embed(_ view: UIView, insets: UIEdgeInsets) {
        embeddedView?.removeFromSuperview()
        embeddedView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            view.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        backgroundColor = FireComposerPalette.surface
        layer.borderColor = FireComposerPalette.divider.cgColor
    }
}

final class FireComposerBannerView: UIView {
    enum Style {
        case success
        case error
    }

    private let style: Style
    private let iconView = UIImageView()
    private let label = UILabel()

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMessage(_ message: String?) {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        label.text = trimmed
        isHidden = trimmed.isEmpty
        accessibilityLabel = trimmed
    }

    private func configure() {
        isHidden = true
        backgroundColor = tint.withAlphaComponent(0.12)
        layer.cornerRadius = FireTheme.mediumCornerRadius

        iconView.image = UIImage(systemName: style == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        iconView.tintColor = tint
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.alignment = .top
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    private var tint: UIColor {
        switch style {
        case .success:
            return .systemGreen
        case .error:
            return .systemRed
        }
    }
}

enum FireComposerMonogramRenderer {
    static func image(text: String) -> UIImage? {
        let size = CGSize(width: 28, height: 28)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            FireTopicListPalette.accent.setFill()
            context.cgContext.fillEllipse(in: rect)

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.preferredFont(forTextStyle: .caption1).withComposerWeight(.bold),
                .foregroundColor: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
                .paragraphStyle: paragraph,
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let textHeight = attributed.size().height
            attributed.draw(
                in: CGRect(
                    x: 0,
                    y: (size.height - textHeight) / 2,
                    width: size.width,
                    height: textHeight
                )
            )
        }
    }
}

extension UIStackView {
    func removeAllArrangedSubviews() {
        for view in arrangedSubviews {
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}

extension UIFont {
    func withComposerWeight(_ weight: Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
