import UIKit

extension FireComposerViewController {
    func configureChrome() {
        title = route.navigationTitle
        view.backgroundColor = FireComposerPalette.canvas
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "关闭",
            style: .plain,
            target: self,
            action: #selector(closeButtonTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: route.submitLabel,
            style: .done,
            target: self,
            action: #selector(submitButtonTapped)
        )
    }

    func configureLayout() {
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(noticeBanner)
        contentStack.addArrangedSubview(errorBanner)
        contentStack.addArrangedSubview(replyTargetCard)
        contentStack.addArrangedSubview(topicHeaderStack)
        contentStack.addArrangedSubview(privateHeaderStack)
        contentStack.addArrangedSubview(toolbarStack)
        contentStack.addArrangedSubview(markdownToolbarScroll)
        contentStack.addArrangedSubview(editorContainer)
        contentStack.addArrangedSubview(mentionResultsStack)
        contentStack.addArrangedSubview(bodyRequirementLabel)
        contentStack.addArrangedSubview(previewContainer)

        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    func configureTopicHeader() {
        topicHeaderStack.axis = .vertical
        topicHeaderStack.spacing = 14

        configureTitleField(topicTitleField, placeholder: "标题")
        topicTitleField.addTarget(self, action: #selector(titleFieldChanged(_:)), for: .editingChanged)

        categoryButton.contentHorizontalAlignment = .leading
        categoryButton.configuration = makePlainButtonConfiguration(title: "选择分类", systemImage: "folder")
        categoryButton.addTarget(self, action: #selector(categoryButtonTapped), for: .touchUpInside)
        categoryButton.fireBindPressBounce(.compact)

        requirementsStack.axis = .vertical
        requirementsStack.spacing = 8
        requirementsCard.embed(requirementsStack, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))

        configureHorizontalStack(selectedTagsStack)
        configureHorizontalStack(suggestedTagsStack)
        configureVerticalResultsStack(tagResultsStack)

        configureSearchField(tagField, placeholder: "添加标签")
        tagField.addTarget(self, action: #selector(tagFieldChanged(_:)), for: .editingChanged)

        topicHeaderStack.addArrangedSubview(topicTitleField)
        topicHeaderStack.addArrangedSubview(categoryButton)
        topicHeaderStack.addArrangedSubview(requirementsCard)
        topicHeaderStack.addArrangedSubview(selectedTagsStack)
        topicHeaderStack.addArrangedSubview(tagField)
        topicHeaderStack.addArrangedSubview(suggestedTagsStack)
        topicHeaderStack.addArrangedSubview(tagResultsStack)
    }

    func configurePrivateHeader() {
        privateHeaderStack.axis = .vertical
        privateHeaderStack.spacing = 14

        configureHorizontalStack(recipientChipsStack)
        configureSearchField(recipientField, placeholder: "添加收件人")
        recipientField.textContentType = .username
        recipientField.addTarget(self, action: #selector(recipientFieldChanged(_:)), for: .editingChanged)
        configureVerticalResultsStack(recipientResultsStack)
        configureTitleField(privateTitleField, placeholder: "标题")
        privateTitleField.addTarget(self, action: #selector(titleFieldChanged(_:)), for: .editingChanged)

        privateHeaderStack.addArrangedSubview(recipientChipsStack)
        privateHeaderStack.addArrangedSubview(recipientField)
        privateHeaderStack.addArrangedSubview(recipientResultsStack)
        privateHeaderStack.addArrangedSubview(privateTitleField)
    }

    func configureReplyTargetCard() {
        replyTargetStack.axis = .vertical
        replyTargetStack.spacing = 6
        replyTargetCard.embed(replyTargetStack, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
    }

    func configureComposerToolbar() {
        toolbarStack.axis = .horizontal
        toolbarStack.alignment = .center
        toolbarStack.spacing = 12

        imageButton.configuration = makePlainButtonConfiguration(title: "图片", systemImage: "photo")
        imageButton.addTarget(self, action: #selector(imageButtonTapped), for: .touchUpInside)
        imageButton.fireBindPressBounce(.compact)
        previewButton.configuration = makePlainButtonConfiguration(title: "预览", systemImage: "eye")
        previewButton.addTarget(self, action: #selector(previewButtonTapped), for: .touchUpInside)
        previewButton.fireBindPressBounce(.compact)

        countLabel.font = .preferredFont(forTextStyle: .caption1)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .right

        toolbarStack.addArrangedSubview(imageButton)
        toolbarStack.addArrangedSubview(previewButton)
        toolbarStack.addArrangedSubview(UIView())
        toolbarStack.addArrangedSubview(countLabel)

        markdownToolbarScroll.showsHorizontalScrollIndicator = false
        markdownToolbarScroll.backgroundColor = FireComposerPalette.chrome
        markdownToolbarScroll.layer.cornerRadius = FireTheme.smallCornerRadius
        markdownToolbarScroll.layer.borderColor = FireComposerPalette.divider.cgColor
        markdownToolbarScroll.layer.borderWidth = 1
        markdownToolbarScroll.heightAnchor.constraint(equalToConstant: 42).isActive = true

        markdownToolbarStack.axis = .horizontal
        markdownToolbarStack.alignment = .center
        markdownToolbarStack.spacing = 4
        markdownToolbarStack.translatesAutoresizingMaskIntoConstraints = false
        markdownToolbarScroll.addSubview(markdownToolbarStack)

        NSLayoutConstraint.activate([
            markdownToolbarStack.leadingAnchor.constraint(equalTo: markdownToolbarScroll.contentLayoutGuide.leadingAnchor, constant: 6),
            markdownToolbarStack.trailingAnchor.constraint(equalTo: markdownToolbarScroll.contentLayoutGuide.trailingAnchor, constant: -6),
            markdownToolbarStack.topAnchor.constraint(equalTo: markdownToolbarScroll.contentLayoutGuide.topAnchor),
            markdownToolbarStack.bottomAnchor.constraint(equalTo: markdownToolbarScroll.contentLayoutGuide.bottomAnchor),
            markdownToolbarStack.heightAnchor.constraint(equalTo: markdownToolbarScroll.frameLayoutGuide.heightAnchor),
        ])

        for action in FireMarkdownFormatAction.allCases {
            let button = UIButton(type: .system)
            button.tag = action.rawTag
            button.accessibilityLabel = action.accessibilityLabel
            button.configuration = makeToolbarButtonConfiguration(for: action)
            button.addTarget(self, action: #selector(markdownButtonTapped(_:)), for: .touchUpInside)
            button.fireBindPressBounce(.compact)
            markdownToolbarStack.addArrangedSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 36),
                button.heightAnchor.constraint(equalToConstant: 34),
            ])
        }
    }

    func configureEditor() {
        bodyTextView.delegate = self
        bodyTextView.font = .preferredFont(forTextStyle: .body)
        bodyTextView.adjustsFontForContentSizeCategory = true
        bodyTextView.backgroundColor = .clear
        bodyTextView.autocorrectionType = .yes
        bodyTextView.autocapitalizationType = .sentences
        bodyTextView.smartDashesType = .yes
        bodyTextView.smartQuotesType = .yes
        bodyTextView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        editorContainer.embed(bodyTextView, insets: .zero)
        bodyTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        configureVerticalResultsStack(mentionResultsStack)

        bodyRequirementLabel.font = .preferredFont(forTextStyle: .caption1)
        bodyRequirementLabel.adjustsFontForContentSizeCategory = true
        bodyRequirementLabel.textColor = .secondaryLabel
        bodyRequirementLabel.numberOfLines = 0
    }

    func configurePreview() {
        previewStack.axis = .vertical
        previewStack.spacing = 14
        previewContainer.embed(previewStack, insets: UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18))
    }

    func configureBottomBar() {
        bottomStack.axis = .vertical
        bottomStack.spacing = 10
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.contentView.addSubview(bottomStack)

        validationLabel.font = .preferredFont(forTextStyle: .caption1)
        validationLabel.adjustsFontForContentSizeCategory = true
        validationLabel.textColor = .secondaryLabel
        validationLabel.numberOfLines = 0

        clearDraftButton.setTitle("清除草稿", for: .normal)
        clearDraftButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        clearDraftButton.addTarget(self, action: #selector(clearDraftButtonTapped), for: .touchUpInside)
        clearDraftButton.fireBindPressBounce(.compact)

        submitButtonConfiguration.cornerStyle = .capsule
        submitButtonConfiguration.baseBackgroundColor = FireTopicListPalette.accent
        submitButtonConfiguration.baseForegroundColor = .white
        submitButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        submitButton.configuration = submitButtonConfiguration
        submitButton.addTarget(self, action: #selector(submitButtonTapped), for: .touchUpInside)
        submitButton.fireBindPressBounce(.button)

        let buttonRow = UIStackView(arrangedSubviews: [clearDraftButton, UIView(), submitButton])
        buttonRow.axis = .horizontal
        buttonRow.alignment = .center
        buttonRow.spacing = 12

        bottomStack.addArrangedSubview(validationLabel)
        bottomStack.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            bottomStack.leadingAnchor.constraint(equalTo: bottomBar.contentView.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            bottomStack.trailingAnchor.constraint(equalTo: bottomBar.contentView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            bottomStack.topAnchor.constraint(equalTo: bottomBar.contentView.topAnchor, constant: 10),
            bottomStack.bottomAnchor.constraint(equalTo: bottomBar.contentView.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            submitButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
    }

}
