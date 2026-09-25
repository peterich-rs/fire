import UIKit

final class FireFilteredFeedSelectorCell: UICollectionViewCell {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    func configure(
        selectedKind: TopicListKindState,
        onSelectKind: @escaping (TopicListKindState) -> Void
    ) {
        prepareForReuse()
        for kind in TopicListKindState.orderedCases {
            var configuration = UIButton.Configuration.filled()
            configuration.title = kind.title
            configuration.cornerStyle = .capsule
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            let selected = selectedKind == kind
            configuration.baseBackgroundColor = selected ? FireTheme.uiAccent : .tertiarySystemFill
            configuration.baseForegroundColor = selected ? .white : .label
            let button = UIButton(configuration: configuration)
            button.addAction(UIAction { _ in
                FireMotionHaptics.selection()
                onSelectKind(kind)
            }, for: .touchUpInside)
            button.fireBindPressBounce(.compact)
            stackView.addArrangedSubview(button)
        }
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }
}
