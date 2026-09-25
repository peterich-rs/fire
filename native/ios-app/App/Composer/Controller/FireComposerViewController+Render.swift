import UIKit

extension FireComposerViewController {
    func render() {
        noticeBanner.setMessage(noticeMessage)
        errorBanner.setMessage(errorMessage)

        topicHeaderStack.isHidden = {
            if case .createTopic = route.kind { return false }
            return true
        }()
        privateHeaderStack.isHidden = {
            if case .privateMessage = route.kind { return false }
            return true
        }()
        replyTargetCard.isHidden = {
            if case .advancedReply = route.kind { return false }
            return true
        }()

        renderReplyTarget()
        renderTopicHeader()
        renderPrivateHeader()
        renderToolbar()
        renderEditor()
        renderPreview()
        renderBottomBar()
    }

    func renderReplyTarget() {
        replyTargetStack.removeAllArrangedSubviews()
        guard case .advancedReply = route.kind else { return }
        let titleLabel = makeLabel(route.topicTitle ?? "回复话题", style: .headline, color: .label)
        replyTargetStack.addArrangedSubview(titleLabel)
        if let replyToUsername = route.replyToUsername, !replyToUsername.isEmpty {
            replyTargetStack.addArrangedSubview(makeLabel("回复 @\(replyToUsername)", style: .caption1, color: FireTopicListPalette.accent))
        } else if let replyToPostNumber = route.replyToPostNumber {
            replyTargetStack.addArrangedSubview(makeLabel("回复 #\(replyToPostNumber)", style: .caption1, color: FireTopicListPalette.accent))
        }
    }

    func renderTopicHeader() {
        guard case .createTopic = route.kind else { return }
        setTextField(topicTitleField, text: titleText)
        categoryButton.configuration = makePlainButtonConfiguration(
            title: selectedCategory.map(categoryDisplayName(for:)) ?? "选择分类",
            systemImage: "folder"
        )

        requirementsStack.removeAllArrangedSubviews()
        let headerRow = UIStackView()
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = 8
        let icon = UIImageView(image: UIImage(systemName: selectedCategory == nil ? "info.circle.fill" : "checkmark.circle.fill"))
        icon.tintColor = selectedCategory == nil ? .secondaryLabel : FireTopicListPalette.accent
        icon.setContentHuggingPriority(.required, for: .horizontal)
        headerRow.addArrangedSubview(icon)
        headerRow.addArrangedSubview(makeLabel("发布要求", style: .subheadline, color: .label, weight: .semibold))
        requirementsStack.addArrangedSubview(headerRow)

        if let selectedCategory {
            requirementsStack.addArrangedSubview(makeLabel("当前分类：\(categoryDisplayName(for: selectedCategory))", style: .caption1, color: .label))
            if selectedCategoryMinimumTags > 0 {
                let progressColor = selectedTags.count >= selectedCategoryMinimumTags ? FireTopicListPalette.accent : .secondaryLabel
                requirementsStack.addArrangedSubview(makeLabel("标签进度：\(selectedTags.count)/\(selectedCategoryMinimumTags)", style: .caption1, color: progressColor))
            }
            for group in selectedCategoryRequiredTagGroups {
                requirementsStack.addArrangedSubview(makeLabel(requiredTagGroupRequirementText(group), style: .caption1, color: .secondaryLabel))
            }
            if selectedCategoryHasTemplate {
                requirementsStack.addArrangedSubview(makeLabel("该分类会自动带出发帖模板。", style: .caption1, color: .secondaryLabel))
            }
        } else {
            requirementsStack.addArrangedSubview(makeLabel("先选择分类，系统才会显示该分类的模板和标签要求。", style: .caption1, color: .secondaryLabel))
        }

        renderTagChips()
        renderSuggestedTags()
        renderTagResults()
        setTextField(tagField, text: tagInput)
        let canShowTags = viewModel.canTagTopics || selectedCategoryMinimumTags > 0
        selectedTagsStack.isHidden = selectedTags.isEmpty
        suggestedTagsStack.isHidden = !canShowTags || suggestedTags.isEmpty
        tagField.isHidden = !canShowTags
        tagResultsStack.isHidden = tagResults.isEmpty
    }

    func renderPrivateHeader() {
        guard case .privateMessage = route.kind else { return }
        renderRecipientChips()
        renderRecipientResults()
        setTextField(recipientField, text: recipientQuery)
        setTextField(privateTitleField, text: titleText)
        recipientChipsStack.isHidden = selectedRecipients.isEmpty
        recipientResultsStack.isHidden = recipientResults.isEmpty
    }

    func renderTagChips() {
        selectedTagsStack.removeAllArrangedSubviews()
        for tag in selectedTags {
            let button = makeChipButton(title: "#\(tag)", systemImage: "xmark")
            button.addAction(UIAction { [weak self] _ in
                self?.selectedTags.removeAll { $0 == tag }
                self?.errorMessage = nil
                self?.scheduleAutosave()
                self?.render()
            }, for: .touchUpInside)
            selectedTagsStack.addArrangedSubview(button)
        }
        selectedTagsStack.addArrangedSubview(UIView())
    }

    func renderSuggestedTags() {
        suggestedTagsStack.removeAllArrangedSubviews()
        for tag in suggestedTags {
            let button = makeChipButton(title: "#\(tag)", systemImage: "plus", emphasized: false)
            button.addAction(UIAction { [weak self] _ in
                self?.addTag(tag)
            }, for: .touchUpInside)
            suggestedTagsStack.addArrangedSubview(button)
        }
        suggestedTagsStack.addArrangedSubview(UIView())
    }

    func renderTagResults() {
        tagResultsStack.removeAllArrangedSubviews()
        for item in tagResults {
            let title = item.count > 0 ? "#\(item.name)  \(item.count)" : "#\(item.name)"
            let button = makeResultButton(title: title, subtitle: nil, systemImage: "number")
            button.addAction(UIAction { [weak self] _ in
                self?.addTag(item.name)
            }, for: .touchUpInside)
            tagResultsStack.addArrangedSubview(button)
        }
    }

    func renderRecipientChips() {
        recipientChipsStack.removeAllArrangedSubviews()
        for username in selectedRecipients {
            let button = makeChipButton(title: "@\(username)", systemImage: "xmark")
            button.addAction(UIAction { [weak self] _ in
                self?.removeRecipient(username)
                self?.render()
            }, for: .touchUpInside)
            recipientChipsStack.addArrangedSubview(button)
        }
        recipientChipsStack.addArrangedSubview(UIView())
    }

    func renderRecipientResults() {
        recipientResultsStack.removeAllArrangedSubviews()
        for user in recipientResults {
            let subtitle = user.name?.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("")
            let button = makeResultButton(
                title: "@\(user.username)",
                subtitle: subtitle?.isEmpty == false ? subtitle : nil,
                systemImage: nil,
                monogram: monogramForUsername(username: user.username)
            )
            button.addAction(UIAction { [weak self] _ in
                self?.addRecipient(user)
            }, for: .touchUpInside)
            recipientResultsStack.addArrangedSubview(button)
        }
    }

    func renderToolbar() {
        imageButton.configuration = makePlainButtonConfiguration(
            title: isUploadingImage ? "上传中" : "图片",
            systemImage: "photo"
        )
        imageButton.isEnabled = !isUploadingImage && !isSubmitting
        previewButton.configuration = makePlainButtonConfiguration(
            title: previewMode ? "继续编辑" : "预览",
            systemImage: previewMode ? "pencil" : "eye"
        )
        let countText: String
        switch route.kind {
        case .createTopic, .privateMessage:
            countText = "\(titleText.count)/\(minimumTitleLength)+"
        case .advancedReply:
            countText = "\(trimmedBody.count)/\(minimumBodyLength)+"
        }
        countLabel.text = countText
    }

    func renderEditor() {
        markdownToolbarScroll.isHidden = previewMode
        editorContainer.isHidden = previewMode
        mentionResultsStack.isHidden = previewMode || (mentionUsers.isEmpty && mentionGroups.isEmpty)
        bodyRequirementLabel.isHidden = previewMode || trimmedBody.isEmpty || trimmedBody.count >= minimumBodyLength
        bodyRequirementLabel.text = "正文至少需要 \(minimumBodyLength) 个字"
        if bodyTextView.text != bodyText {
            bodyTextView.text = bodyText
        }
        if bodyTextView.selectedRange != bodySelection {
            bodyTextView.selectedRange = bodySelection
        }
        renderMentionResults()
    }

    func renderMentionResults() {
        mentionResultsStack.removeAllArrangedSubviews()
        for user in mentionUsers {
            let button = makeResultButton(
                title: "@\(user.username)",
                subtitle: user.name?.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty(""),
                systemImage: nil,
                monogram: monogramForUsername(username: user.username)
            )
            button.addAction(UIAction { [weak self] _ in
                self?.insertMention("@\(user.username)")
            }, for: .touchUpInside)
            mentionResultsStack.addArrangedSubview(button)
        }
        for group in mentionGroups {
            let button = makeResultButton(
                title: "@\(group.name)",
                subtitle: group.fullName?.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty(""),
                systemImage: "person.3.fill"
            )
            button.addAction(UIAction { [weak self] _ in
                self?.insertMention("@\(group.name)")
            }, for: .touchUpInside)
            mentionResultsStack.addArrangedSubview(button)
        }
    }

    func renderPreview() {
        previewContainer.isHidden = !previewMode
        previewStack.removeAllArrangedSubviews()
        guard previewMode else { return }

        switch route.kind {
        case .createTopic, .privateMessage:
            previewStack.addArrangedSubview(makeLabel(trimmedTitle.isEmpty ? "（无标题）" : trimmedTitle, style: .title2, color: .label, weight: .bold))
        case .advancedReply:
            break
        }

        if case .privateMessage = route.kind, !selectedRecipients.isEmpty {
            previewStack.addArrangedSubview(makeLabel(selectedRecipients.map { "@\($0)" }.joined(separator: "、"), style: .caption1, color: FireTopicListPalette.accent, weight: .semibold))
        }
        if let selectedCategory, case .createTopic = route.kind {
            previewStack.addArrangedSubview(makeLabel(categoryDisplayName(for: selectedCategory), style: .caption1, color: FireTopicListPalette.accent, weight: .semibold))
        }
        if !selectedTags.isEmpty, case .createTopic = route.kind {
            previewStack.addArrangedSubview(makeLabel(selectedTags.map { "#\($0)" }.joined(separator: "  "), style: .caption1, color: FireTopicListPalette.accent, weight: .medium))
        }

        let bodyLabel = makeLabel(trimmedBody.isEmpty ? "暂无内容" : bodyText, style: .body, color: trimmedBody.isEmpty ? .secondaryLabel : .label)
        bodyLabel.numberOfLines = 0
        previewStack.addArrangedSubview(bodyLabel)

        if !markdownImages.isEmpty {
            previewStack.addArrangedSubview(makeLabel("图片预览", style: .subheadline, color: .label, weight: .semibold))
            for image in markdownImages {
                let label = image.altText ?? image.urlString
                let resolved = resolvedURL(for: image.urlString)?.absoluteString ?? image.urlString
                previewStack.addArrangedSubview(makeLabel("\(label)\n\(resolved)", style: .caption1, color: .secondaryLabel))
            }
        }
    }

    func renderBottomBar() {
        let validation = submitValidation
        validationLabel.text = validation.canSubmit ? nil : validation.message
        validationLabel.isHidden = validation.canSubmit || validation.message?.isEmpty != false
        clearDraftButton.isHidden = draftSequence == 0
        navigationItem.rightBarButtonItem?.isEnabled = validation.canSubmit
        submitButton.isEnabled = validation.canSubmit

        var configuration = submitButtonConfiguration
        configuration.title = isSubmitting ? "提交中" : route.submitLabel
        configuration.showsActivityIndicator = isSubmitting
        configuration.baseBackgroundColor = validation.canSubmit ? FireTopicListPalette.accent : .tertiaryLabel
        submitButton.configuration = configuration
        navigationItem.leftBarButtonItem?.isEnabled = !isSubmitting
    }

}
