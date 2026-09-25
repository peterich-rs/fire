import UIKit

final class FireTopicDetailToolbarTitleLabel: UIView {
    private let label = UILabel()
    private var isTitleVisible = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        // Title must yield horizontal space to trailing actions. Publishing a
        // content-sized width lets long titles compete with (and shove) icons.
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = FireTheme.uiInk
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        label.alpha = 0
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: FireTopicDetailToolbarTitleMetrics.minimumHeight),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTitle(_ text: String, visible: Bool, animated: Bool) {
        isTitleVisible = visible
        let updates = {
            self.label.text = text
            self.label.alpha = visible ? 1 : 0
            self.isAccessibilityElement = visible
            self.accessibilityLabel = visible ? "话题标题：\(text)" : nil
            self.invalidateIntrinsicContentSize()
        }
        if animated {
            UIView.animate(
                withDuration: FireTopicDetailToolbarCoordinator.animationDuration,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
                animations: updates
            )
        } else {
            updates()
        }
    }

    override var intrinsicContentSize: CGSize {
        FireTopicDetailToolbarTitleMetrics.preferredIntrinsicSize(
            isVisible: isTitleVisible,
            labelHeight: label.intrinsicContentSize.height
        )
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        // Accept whatever width the navigation bar assigns after reserving
        // left/right items; height stays compact for the single-line title.
        let intrinsic = intrinsicContentSize
        let width = size.width > 0 ? size.width : intrinsic.width
        return CGSize(width: width, height: intrinsic.height)
    }
}
