import UIKit

// MARK: - Status bar (L0)

final class FireHomeScopeStatusBarCell: UICollectionViewCell {
    struct Actions {
        /// Opens leading parent-category drawer.
        var onOpenCategoryDrawer: () -> Void
        /// Opens subcategory sheet for the current parent (only when children exist).
        var onOpenSubcategoryPanel: () -> Void
        var onSelectKind: (TopicListKindState) -> Void
        var onRemoveTag: (String) -> Void
        var onClearFilters: () -> Void
    }

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var actions = Actions(
        onOpenCategoryDrawer: {},
        onOpenSubcategoryPanel: {},
        onSelectKind: { _ in },
        onRemoveTag: { _ in },
        onClearFilters: {}
    )

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
        clearArrangedSubviews()
    }

    func configure(presentation: FireHomeScopePresentation, actions: Actions) {
        self.actions = actions
        clearArrangedSubviews()

        let accent = UIColor(fireHomeScopeHex: presentation.categoryAccentHex)
            ?? FireTopicListPalette.accent

        // Arrow opens subcategory sheet when the current parent has children;
        // otherwise fall back to the leading parent drawer.
        let categoryAction: () -> Void = { [weak self] in
            guard let self else { return }
            if presentation.showsChildShortcutStrip {
                self.actions.onOpenSubcategoryPanel()
            } else {
                self.actions.onOpenCategoryDrawer()
            }
        }
        let categoryAccessibility: String = {
            if presentation.showsChildShortcutStrip {
                return "分类：\(presentation.categoryPathTitle)，点击选择子类"
            }
            return "分类：\(presentation.categoryPathTitle)，点击打开分类抽屉"
        }()
        stackView.addArrangedSubview(
            FireHomeScopeCapsuleButton.make(
                title: presentation.categoryPathTitle,
                trailingSystemName: presentation.showsChildShortcutStrip ? "chevron.down" : "line.3.horizontal",
                isEmphasized: !presentation.isDefaultCategory,
                tintColor: accent,
                accessibilityLabel: categoryAccessibility,
                action: categoryAction
            )
        )

        let kindButton = FireHomeScopeCapsuleButton.make(
            title: presentation.kindTitle,
            trailingSystemName: "chevron.down",
            isEmphasized: !presentation.isDefaultKind,
            tintColor: FireTopicListPalette.accent,
            accessibilityLabel: "排序：\(presentation.kindTitle)"
        )
        kindButton.showsMenuAsPrimaryAction = true
        kindButton.menu = UIMenu(
            children: TopicListKindState.orderedCases.map { kind in
                UIAction(
                    title: kind.title,
                    state: presentation.kind == kind ? .on : .off
                ) { [weak self] _ in
                    self?.actions.onSelectKind(kind)
                }
            }
        )
        stackView.addArrangedSubview(kindButton)

        for tag in presentation.tags {
            stackView.addArrangedSubview(
                FireHomeScopeCapsuleButton.make(
                    title: "#\(tag)",
                    trailingSystemName: "xmark",
                    isEmphasized: true,
                    tintColor: FireTopicListPalette.accent,
                    accessibilityLabel: "移除标签 \(tag)",
                    action: { [weak self] in
                        self?.actions.onRemoveTag(tag)
                    }
                )
            )
        }

        if !presentation.isDefaultScope {
            stackView.addArrangedSubview(
                FireHomeScopeCapsuleButton.make(
                    title: nil,
                    trailingSystemName: "xmark.circle",
                    isEmphasized: false,
                    tintColor: .secondaryLabel,
                    accessibilityLabel: "清除筛选",
                    action: { [weak self] in
                        self?.actions.onClearFilters()
                    }
                )
            )
        }
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 4,
            trailing: 16
        )

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
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
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 2),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -2),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -4),
        ])
    }

    private func clearArrangedSubviews() {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}

// MARK: - Child shortcut strip (L1)

final class FireHomeChildShortcutBarCell: UICollectionViewCell {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var onSelect: ((FireHomeChildShortcut) -> Void)?

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
        clearArrangedSubviews()
        onSelect = nil
    }

    func configure(
        shortcuts: [FireHomeChildShortcut],
        accentHex: String?,
        onSelect: @escaping (FireHomeChildShortcut) -> Void
    ) {
        self.onSelect = onSelect
        clearArrangedSubviews()
        let accent = UIColor(fireHomeScopeHex: accentHex) ?? FireTopicListPalette.accent
        for shortcut in shortcuts {
            let button = FireHomeScopeCapsuleButton.make(
                title: shortcut.title,
                trailingSystemName: nil,
                isEmphasized: shortcut.isSelected,
                tintColor: accent,
                compact: true,
                accessibilityLabel: shortcut.representsParentAll
                    ? "小类：全部"
                    : "小类：\(shortcut.title)",
                action: { [weak self] in
                    self?.onSelect?(shortcut)
                }
            )
            stackView.addArrangedSubview(button)
        }
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: 16,
            bottom: 6,
            trailing: 16
        )

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .horizontal
        stackView.alignment = .center
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
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 1),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -1),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -2),
        ])
    }

    private func clearArrangedSubviews() {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}

// MARK: - Shared capsule

enum FireHomeScopeCapsuleButton {
    static func make(
        title: String?,
        trailingSystemName: String?,
        isEmphasized: Bool,
        tintColor: UIColor,
        compact: Bool = false,
        accessibilityLabel: String? = nil,
        action: (() -> Void)? = nil
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        if let trailingSystemName {
            configuration.image = UIImage(systemName: trailingSystemName)
            configuration.imagePlacement = .trailing
            configuration.imagePadding = title == nil ? 0 : 5
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: compact ? 9 : 10,
                weight: .semibold
            )
        }
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: compact ? 6 : 8,
            leading: compact ? 12 : 14,
            bottom: compact ? 6 : 8,
            trailing: compact ? 12 : 14
        )
        configuration.cornerStyle = .capsule
        // Quiet resting chrome; only the active scope fills with accent.
        if isEmphasized {
            configuration.baseBackgroundColor = tintColor.withAlphaComponent(0.18)
            configuration.baseForegroundColor = tintColor
            configuration.background.strokeColor = tintColor.withAlphaComponent(0.35)
            configuration.background.strokeWidth = 1
        } else {
            configuration.baseBackgroundColor = FireTheme.uiSurfaceSecondary
            configuration.baseForegroundColor = FireTheme.uiInk
            configuration.background.strokeColor = UIColor.separator.withAlphaComponent(0.35)
            configuration.background.strokeWidth = 1
        }
        let font = UIFont.preferredFont(forTextStyle: compact ? .caption1 : .subheadline)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = font.withHomeScopeWeight(.semibold)
            return outgoing
        }

        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = accessibilityLabel ?? title
        button.fireBindPressBounce(.compact)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        if let action {
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        }
        return button
    }
}

private extension UIFont {
    func withHomeScopeWeight(_ weight: Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

extension UIColor {
    convenience init?(fireHomeScopeHex hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .uppercased()
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1
        )
    }
}
