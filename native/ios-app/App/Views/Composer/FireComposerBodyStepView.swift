import UIKit

struct FireComposerBodyStepState: Equatable {
    let replyTitle: String?
    let replySubtitle: String?
    let summaryCategoryName: String?
    let summaryTagCount: Int
    let summaryHidden: Bool
    let bodyCount: Int
    let minimumBodyLength: Int
    let bodyRequirementHidden: Bool
}

final class FireComposerBodyStepView: UIView {
    var onRequestChangeCategory: (() -> Void)?
    var onRequestTagSearch: (() -> Void)?

    private let replyCard = FireComposerCardView()
    private let replyStack = UIStackView()
    private let replyTitleLabel = UILabel()
    private let replySubtitleLabel = UILabel()

    private let summaryCard = FireComposerCardView()
    private let summaryStack = UIStackView()
    private let categoryNameLabel = UILabel()
    private let tagSummaryLabel = UILabel()
    private let changeCategoryButton = UIButton(type: .system)
    private let searchTagsButton = UIButton(type: .system)

    let editorContainer = FireComposerCardView()
    let markdownToolbarContainer = UIView()
    let bodyRequirementLabel = UILabel()

    init() {
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(state: FireComposerBodyStepState) {
        if let title = state.replyTitle {
            replyTitleLabel.text = title
        }

        if let subtitle = state.replySubtitle, !subtitle.isEmpty {
            replySubtitleLabel.text = subtitle
            replySubtitleLabel.isHidden = false
        } else {
            replySubtitleLabel.isHidden = true
        }

        replyCard.isHidden = state.replyTitle == nil

        if let categoryName = state.summaryCategoryName {
            categoryNameLabel.text = categoryName
            summaryCard.isHidden = state.summaryHidden
            tagSummaryLabel.text = state.summaryTagCount > 0
                ? "\(state.summaryTagCount) 个标签"
                : "未选标签"
            tagSummaryLabel.isHidden = false
        } else {
            summaryCard.isHidden = true
        }

        if state.bodyRequirementHidden || state.minimumBodyLength == 0 {
            bodyRequirementLabel.isHidden = true
        } else {
            bodyRequirementLabel.isHidden = false
            bodyRequirementLabel.text = "正文至少需要 \(state.minimumBodyLength) 个字（当前 \(state.bodyCount)）"
        }
    }

    private func configure() {
        backgroundColor = .clear

        configureReplyCard()
        configureSummaryCard()
        configureContainers()

        let root = UIStackView(arrangedSubviews: [
            replyCard,
            summaryCard,
            markdownToolbarContainer,
            editorContainer,
            bodyRequirementLabel,
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
    }

    private func configureReplyCard() {
        replyTitleLabel.font = .preferredFont(forTextStyle: .headline)
        replyTitleLabel.adjustsFontForContentSizeCategory = true
        replyTitleLabel.numberOfLines = 0

        replySubtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        replySubtitleLabel.adjustsFontForContentSizeCategory = true
        replySubtitleLabel.textColor = FireTopicListPalette.accent
        replySubtitleLabel.numberOfLines = 0

        replyStack.axis = .vertical
        replyStack.spacing = 6
        replyStack.addArrangedSubview(replyTitleLabel)
        replyStack.addArrangedSubview(replySubtitleLabel)
        replyStack.translatesAutoresizingMaskIntoConstraints = false
        replyCard.embed(replyStack, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
    }

    private func configureSummaryCard() {
        categoryNameLabel.font = .preferredFont(forTextStyle: .subheadline)
        categoryNameLabel.adjustsFontForContentSizeCategory = true
        categoryNameLabel.textColor = .label
        categoryNameLabel.numberOfLines = 1

        tagSummaryLabel.font = .preferredFont(forTextStyle: .caption1)
        tagSummaryLabel.adjustsFontForContentSizeCategory = true
        tagSummaryLabel.textColor = .secondaryLabel

        let textStack = UIStackView(arrangedSubviews: [categoryNameLabel, tagSummaryLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        changeCategoryButton.configuration = makeSummaryButtonConfig(title: "更换分类", systemImage: "arrow.triangle.2.circlepath")
        changeCategoryButton.addAction(UIAction { [weak self] _ in
            self?.onRequestChangeCategory?()
        }, for: .touchUpInside)

        searchTagsButton.configuration = makeSummaryButtonConfig(title: "搜索标签", systemImage: "magnifyingglass")
        searchTagsButton.addAction(UIAction { [weak self] _ in
            self?.onRequestTagSearch?()
        }, for: .touchUpInside)

        let actionStack = UIStackView(arrangedSubviews: [changeCategoryButton, searchTagsButton])
        actionStack.axis = .horizontal
        actionStack.spacing = 6

        summaryStack.axis = .horizontal
        summaryStack.alignment = .center
        summaryStack.spacing = 10
        summaryStack.addArrangedSubview(textStack)
        summaryStack.addArrangedSubview(UIView())
        summaryStack.addArrangedSubview(actionStack)
        summaryStack.translatesAutoresizingMaskIntoConstraints = false
        summaryCard.embed(summaryStack, insets: UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
    }

    private func configureContainers() {
        bodyRequirementLabel.font = .preferredFont(forTextStyle: .caption1)
        bodyRequirementLabel.adjustsFontForContentSizeCategory = true
        bodyRequirementLabel.textColor = .secondaryLabel
        bodyRequirementLabel.numberOfLines = 0
    }

    private func makeSummaryButtonConfig(title: String, systemImage: String) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: systemImage)
        config.imagePadding = 4
        config.baseForegroundColor = FireTopicListPalette.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        return config
    }
}
