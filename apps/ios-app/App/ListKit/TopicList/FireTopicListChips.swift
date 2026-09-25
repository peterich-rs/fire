import UIKit

final class FireTopicListChipLabel: UILabel {
    init(text: String, textColor: UIColor, backgroundColor: UIColor) {
        super.init(frame: .zero)
        self.text = text
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        font = UIFont.preferredFont(forTextStyle: .caption2)
        adjustsFontForContentSizeCategory = true
        numberOfLines = 1
        lineBreakMode = .byTruncatingTail
        layer.cornerRadius = 4
        clipsToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 12, height: size.height + 4)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: 6, dy: 2))
    }
}

final class FireTopicListIconChip: UIView {
    init(systemImage: String, tintColor: UIColor) {
        super.init(frame: .zero)
        let imageView = UIImageView(image: UIImage(systemName: systemImage))
        imageView.tintColor = tintColor
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = tintColor.withAlphaComponent(0.12)
        layer.cornerRadius = 5
        addSubview(imageView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 18),
            heightAnchor.constraint(equalToConstant: 18),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 11),
            imageView.heightAnchor.constraint(equalToConstant: 11),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class FireTopicListUnreadDot: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = FireTopicListPalette.accent
        layer.cornerRadius = 3.5
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 7),
            heightAnchor.constraint(equalToConstant: 7),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
