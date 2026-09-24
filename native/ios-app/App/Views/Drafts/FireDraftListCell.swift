import UIKit

final class FireDraftListCell: UICollectionViewCell {
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let unsupportedLabel = UILabel()
    private let excerptLabel = UILabel()
    private let kindLabel = UILabel()
    private let timestampLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    private var onOpen: (() -> Void)?
    private var onDelete: (() -> Void)?

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
        onOpen = nil
        onDelete = nil
        moreButton.menu = nil
        isAccessibilityElement = false
    }

    func configureMissing() {
        titleLabel.text = nil
        excerptLabel.text = nil
        kindLabel.text = nil
        timestampLabel.text = nil
        unsupportedLabel.isHidden = true
        moreButton.menu = nil
    }

    func configure(
        draft: DraftState,
        route: FireComposerRoute?,
        onOpen: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        let supported = route != nil
        self.onOpen = onOpen
        self.onDelete = onDelete

        iconView.image = UIImage(systemName: draft.fireDraftIcon)
        iconView.tintColor = supported ? FireTopicListPalette.accent : .tertiaryLabel
        iconContainer.backgroundColor = (supported ? FireTopicListPalette.accent : UIColor.tertiaryLabel)
            .withAlphaComponent(0.12)
        titleLabel.text = draft.fireDraftTitle
        excerptLabel.text = draft.fireDraftExcerpt
        excerptLabel.isHidden = draft.fireDraftExcerpt == nil
        kindLabel.text = draft.fireDraftKindLabel
        timestampLabel.text = FireTopicPresentation.compactTimestamp(draft.updatedAt)
        timestampLabel.isHidden = timestampLabel.text == nil
        unsupportedLabel.isHidden = supported
        configureMenu(supported: supported)

        isAccessibilityElement = true
        accessibilityTraits = supported ? [.button] : []
        accessibilityLabel = draft.fireDraftAccessibilityLabel(supported: supported)
        accessibilityHint = supported ? "双击继续编辑草稿" : "当前草稿类型暂不支持继续编辑"
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 10,
            leading: 16,
            bottom: 10,
            trailing: 16
        )

        iconContainer.layer.cornerRadius = 8
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.setContentHuggingPriority(.required, for: .horizontal)

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        unsupportedLabel.text = "暂不支持"
        unsupportedLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        unsupportedLabel.adjustsFontForContentSizeCategory = true
        unsupportedLabel.textColor = .systemOrange
        unsupportedLabel.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        unsupportedLabel.layer.cornerRadius = 4
        unsupportedLabel.clipsToBounds = true

        excerptLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        excerptLabel.adjustsFontForContentSizeCategory = true
        excerptLabel.textColor = .secondaryLabel
        excerptLabel.numberOfLines = 3

        kindLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        kindLabel.adjustsFontForContentSizeCategory = true
        kindLabel.textColor = FireTopicListPalette.accent
        kindLabel.numberOfLines = 1

        timestampLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        timestampLabel.adjustsFontForContentSizeCategory = true
        timestampLabel.textColor = .tertiaryLabel
        timestampLabel.numberOfLines = 1

        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.tintColor = .tertiaryLabel
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.accessibilityLabel = "草稿操作"
        moreButton.setContentHuggingPriority(.required, for: .horizontal)

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, unsupportedLabel])
        titleStack.axis = .horizontal
        titleStack.alignment = .firstBaseline
        titleStack.spacing = 8

        let metaStack = UIStackView(arrangedSubviews: [kindLabel, timestampLabel, UIView()])
        metaStack.axis = .horizontal
        metaStack.alignment = .firstBaseline
        metaStack.spacing = 8

        let bodyStack = UIStackView(arrangedSubviews: [titleStack, excerptLabel, metaStack])
        bodyStack.axis = .vertical
        bodyStack.alignment = .fill
        bodyStack.spacing = 6

        let rowStack = UIStackView(arrangedSubviews: [iconContainer, bodyStack, moreButton])
        rowStack.axis = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        iconContainer.addSubview(iconView)
        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 38),
            iconContainer.heightAnchor.constraint(equalToConstant: 38),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            moreButton.widthAnchor.constraint(equalToConstant: 32),
            moreButton.heightAnchor.constraint(equalToConstant: 32),
            rowStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    private func configureMenu(supported: Bool) {
        var actions: [UIAction] = []
        if supported {
            actions.append(
                UIAction(title: "继续编辑", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
                    self?.onOpen?()
                }
            )
        }
        actions.append(
            UIAction(
                title: "删除",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.onDelete?()
            }
        )
        moreButton.menu = UIMenu(children: actions)
    }
}
