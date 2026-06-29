import UIKit

struct FireComposerMetaStepState: Equatable {
    let title: String
    let selectedCategoryName: String?
    let hotCategoryNames: [String]
    let selectedTags: [String]
    let hotTags: [String]
    let minimumRequiredTags: Int
    let selectedTagCount: Int
    let requirementSummaryLines: [String]
    let nextEnabled: Bool

    init(
        title: String,
        selectedCategoryName: String?,
        hotCategoryNames: [String],
        selectedTags: [String],
        hotTags: [String],
        minimumRequiredTags: Int,
        selectedTagCount: Int,
        requirementSummaryLines: [String],
        nextEnabled: Bool
    ) {
        self.title = title
        self.selectedCategoryName = selectedCategoryName
        self.hotCategoryNames = hotCategoryNames
        self.selectedTags = selectedTags
        self.hotTags = hotTags
        self.minimumRequiredTags = minimumRequiredTags
        self.selectedTagCount = selectedTagCount
        self.requirementSummaryLines = requirementSummaryLines
        self.nextEnabled = nextEnabled
    }
}

final class FireComposerMetaStepView: UIView {
    var onTitleChanged: ((String) -> Void)?
    var onCategorySelected: ((Int) -> Void)?
    var onRequestMoreCategories: (() -> Void)?
    var onRequestChangeCategory: (() -> Void)?
    var onTagToggled: ((String) -> Void)?
    var onRequestTagSearch: (() -> Void)?
    var onNext: (() -> Void)?

    private let titleField = UITextField()
    private let categoryInlineStack = UIStackView()
    private let moreCategoriesButton = UIButton(type: .system)
    private let categorySummaryCard = FireComposerCardView()
    private let summaryStack = UIStackView()
    private let changeCategoryButton = UIButton(type: .system)
    private let requirementsCard = FireComposerCardView()
    private let requirementsStack = UIStackView()
    private let selectedTagsScroll = UIScrollView()
    private let selectedTagsContent = UIStackView()
    private let hotTagsScroll = UIScrollView()
    private let hotTagsContent = UIStackView()
    private let tagSearchEntry = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)

    private var appliedHotCategoryNames: [String] = []

    init() {
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(state: FireComposerMetaStepState) {
        if titleField.text != state.title, !titleField.isFirstResponder {
            titleField.text = state.title
        }

        let hasSelection = state.selectedCategoryName != nil
        categoryInlineStack.isHidden = hasSelection
        categorySummaryCard.isHidden = !hasSelection

        if let name = state.selectedCategoryName {
            configureSummaryCard(name: name)
        } else {
            configureInlineCategories(names: state.hotCategoryNames)
        }

        requirementsStack.removeAllArrangedSubviews()
        requirementsCard.isHidden = state.requirementSummaryLines.isEmpty
        for line in state.requirementSummaryLines {
            requirementsStack.addArrangedSubview(makeLabel(line, style: .caption1, color: .secondaryLabel))
        }

        rebuildChipScroll(selectedTagsScroll, content: selectedTagsContent, items: state.selectedTags, isRemovable: true)
        selectedTagsScroll.isHidden = state.selectedTags.isEmpty

        rebuildChipScroll(hotTagsScroll, content: hotTagsContent, items: state.hotTags, isRemovable: false)
        hotTagsScroll.isHidden = state.hotTags.isEmpty

        var nextConfig = nextButton.configuration
        nextConfig?.title = "下一步"
        nextButton.configuration = nextConfig
        nextButton.isEnabled = state.nextEnabled
        nextButton.alpha = state.nextEnabled ? 1.0 : 0.5
    }

    private func configure() {
        backgroundColor = .clear

        let root = UIStackView(arrangedSubviews: [
            titleField,
            categoryInlineStack,
            categorySummaryCard,
            requirementsCard,
            selectedTagsScroll,
            hotTagsScroll,
            tagSearchEntry,
            nextButton,
        ])
        root.axis = .vertical
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        configureTitleField()
        configureCategoryInline()
        configureSummaryCard()
        configureRequirementsCard()
        configureChipScroll(selectedTagsScroll, content: selectedTagsContent)
        configureChipScroll(hotTagsScroll, content: hotTagsContent)
        configureTagSearchEntry()
        configureNextButton()
    }

    private func configureTitleField() {
        titleField.borderStyle = .roundedRect
        titleField.placeholder = "标题"
        titleField.font = .preferredFont(forTextStyle: .title3)
        titleField.adjustsFontForContentSizeCategory = true
        titleField.returnKeyType = .next
        titleField.clearButtonMode = .whileEditing
        titleField.addTarget(self, action: #selector(handleTitleChanged(_:)), for: .editingChanged)
    }

    private func configureCategoryInline() {
        categoryInlineStack.axis = .vertical
        categoryInlineStack.spacing = 8

        let header = makeLabel("选择分类", style: .subheadline, color: .label, weight: .semibold)
        categoryInlineStack.addArrangedSubview(header)

        moreCategoriesButton.configuration = makePlainConfig(title: "更多分类…", systemImage: "chevron.right")
        moreCategoriesButton.contentHorizontalAlignment = .leading
        moreCategoriesButton.addAction(UIAction { [weak self] _ in
            self?.onRequestMoreCategories?()
        }, for: .touchUpInside)
        categoryInlineStack.addArrangedSubview(moreCategoriesButton)
    }

    private func configureSummaryCard() {
        summaryStack.axis = .horizontal
        summaryStack.alignment = .center
        summaryStack.spacing = 8
        summaryStack.translatesAutoresizingMaskIntoConstraints = false

        let name = makeLabel("", style: .subheadline, color: .label, weight: .semibold)
        name.accessibilityIdentifier = "meta.category.name"
        summaryStack.addArrangedSubview(name)
        summaryStack.addArrangedSubview(UIView())

        changeCategoryButton.configuration = makePlainConfig(title: "更换", systemImage: "arrow.triangle.2.circlepath")
        changeCategoryButton.contentHorizontalAlignment = .trailing
        changeCategoryButton.addAction(UIAction { [weak self] _ in
            self?.onRequestChangeCategory?()
        }, for: .touchUpInside)
        summaryStack.addArrangedSubview(changeCategoryButton)

        categorySummaryCard.embed(summaryStack, insets: UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
    }

    private func configureRequirementsCard() {
        requirementsStack.axis = .vertical
        requirementsStack.spacing = 6
        requirementsStack.translatesAutoresizingMaskIntoConstraints = false
        requirementsCard.embed(requirementsStack, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
    }

    private func configureChipScroll(_ scroll: UIScrollView, content: UIStackView) {
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        content.axis = .horizontal
        content.alignment = .center
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        scroll.heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    private func configureTagSearchEntry() {
        tagSearchEntry.configuration = makePlainConfig(title: "搜索标签", systemImage: "magnifyingglass")
        tagSearchEntry.contentHorizontalAlignment = .leading
        tagSearchEntry.addAction(UIAction { [weak self] _ in
            self?.onRequestTagSearch?()
        }, for: .touchUpInside)
    }

    private func configureNextButton() {
        var config = UIButton.Configuration.filled()
        config.title = "下一步"
        config.cornerStyle = .medium
        config.baseBackgroundColor = FireTopicListPalette.accent
        config.baseForegroundColor = .white
        nextButton.configuration = config
        nextButton.addAction(UIAction { [weak self] _ in
            self?.onNext?()
        }, for: .touchUpInside)
    }

    private func configureInlineCategories(names: [String]) {
        let first = categoryInlineStack.arrangedSubviews.first
        let keepHeader = first
        for view in categoryInlineStack.arrangedSubviews where view !== keepHeader && view !== moreCategoriesButton {
            categoryInlineStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard appliedHotCategoryNames != names || categoryInlineStack.arrangedSubviews.count <= 2 else { return }
        appliedHotCategoryNames = names

        let insertIndex = categoryInlineStack.arrangedSubviews.firstIndex(of: moreCategoriesButton) ?? 1
        for (index, name) in names.enumerated() {
            let button = makeHotCategoryButton(title: name, index: index)
            categoryInlineStack.insertArrangedSubview(button, at: insertIndex + index)
        }
    }

    private func configureSummaryCard(name: String) {
        for view in summaryStack.arrangedSubviews {
            if let label = view as? UILabel, label.accessibilityIdentifier == "meta.category.name" {
                label.text = name
            }
        }
    }

    private func rebuildChipScroll(_ scroll: UIScrollView, content: UIStackView, items: [String], isRemovable: Bool) {
        content.removeAllArrangedSubviews()
        for item in items {
            let button = makeChipButton(title: "#\(item)", isRemovable: isRemovable)
            button.addAction(UIAction { [weak self] _ in
                self?.onTagToggled?(item)
            }, for: .touchUpInside)
            content.addArrangedSubview(button)
        }
        content.addArrangedSubview(UIView())
    }

    private func makeHotCategoryButton(title: String, index: Int) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: "folder")
        config.imagePadding = 6
        config.baseForegroundColor = FireTopicListPalette.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
        let button = UIButton(type: .system)
        button.configuration = config
        button.tag = index
        button.addAction(UIAction { [weak self] _ in
            self?.onCategorySelected?(index)
        }, for: .touchUpInside)
        return button
    }

    private func makeChipButton(title: String, isRemovable: Bool) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: isRemovable ? "xmark" : "plus")
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.cornerStyle = .capsule
        config.baseBackgroundColor = isRemovable
            ? FireTopicListPalette.accent.withAlphaComponent(0.12)
            : UIColor.tertiarySystemFill
        config.baseForegroundColor = isRemovable ? FireTopicListPalette.accent : .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        let button = UIButton(type: .system)
        button.configuration = config
        button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        return button
    }

    private func makePlainConfig(title: String, systemImage: String) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: systemImage)
        config.imagePadding = 8
        config.baseForegroundColor = FireTopicListPalette.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
        return config
    }

    private func makeLabel(_ text: String, style: UIFont.TextStyle, color: UIColor, weight: UIFont.Weight? = nil) -> UILabel {
        let label = UILabel()
        label.text = text
        if let weight {
            let descriptor = UIFont.preferredFont(forTextStyle: style).fontDescriptor.addingAttributes([
                .traits: [UIFontDescriptor.TraitKey.weight: weight],
            ])
            label.font = UIFont(descriptor: descriptor, size: 0)
        } else {
            label.font = .preferredFont(forTextStyle: style)
        }
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    @objc private func handleTitleChanged(_ sender: UITextField) {
        onTitleChanged?(sender.text ?? "")
    }
}

private extension UIStackView {
    func removeAllArrangedSubviews() {
        for view in arrangedSubviews {
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}
