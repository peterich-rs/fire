import UIKit

extension FireComposerViewController {
    @objc func clearDraftButtonTapped() {
        Task { [weak self] in
            guard let self else { return }
            try? await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
            draftSequence = 0
            noticeMessage = "草稿已清除"
            render()
        }
    }

    func loadInitialComposerState() async {
        guard !didLoadDraft else { return }
        didLoadDraft = true
        if case .createTopic = route.kind {
            selectedCategoryID = initialCategoryID
            if selectedTags.isEmpty {
                selectedTags = initialTags
            }
            applyDefaultCategoryIfNeeded()
        } else if case .privateMessage(let recipients, let initialTitle) = route.kind {
            selectedRecipients = recipients
            titleText = initialTitle ?? titleText
            if let initialBody, bodyText.isEmpty {
                bodyText = initialBody
            }
        } else if let initialBody, bodyText.isEmpty {
            bodyText = initialBody
        }

        isLoadingDraft = true
        render()
        defer {
            isLoadingDraft = false
            bodyTextView.becomeFirstResponder()
            render()
        }

        do {
            if let draft = try await viewModel.fetchDraft(draftKey: route.draftKey) {
                if case .createTopic = route.kind {
                    draftSequence = draft.sequence
                    titleText = draft.data.title ?? titleText
                    bodyText = draft.data.reply ?? bodyText
                    selectedCategoryID = draft.data.categoryId ?? selectedCategoryID
                    selectedTags = draft.data.tags
                } else if case .privateMessage = route.kind {
                    if shouldRestorePrivateMessageDraft(
                        explicitRecipients: route.recipients,
                        draftRecipients: draft.data.recipients
                    ) {
                        draftSequence = draft.sequence
                        titleText = draft.data.title ?? titleText
                        bodyText = draft.data.reply ?? bodyText
                        if !draft.data.recipients.isEmpty {
                            selectedRecipients = draft.data.recipients
                        }
                    }
                } else {
                    draftSequence = draft.sequence
                    bodyText = draft.data.reply ?? bodyText
                }
                if draftSequence > 0, draft.data.reply != nil || draft.data.title != nil {
                    noticeMessage = "已恢复草稿"
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        applyInitialBodyIfNeeded()

        if case .createTopic = route.kind {
            applyDefaultCategoryIfNeeded()
            applyCategoryTemplateIfNeeded()
        }
        resolveShortUploadsIfNeeded()
        render()
    }

    func applyDefaultCategoryIfNeeded() {
        guard case .createTopic = route.kind else { return }
        guard selectedCategoryID == nil else { return }
        if let defaultID = viewModel.session.bootstrap.defaultComposerCategory,
           availableCategories.contains(where: { $0.id == defaultID }) {
            selectedCategoryID = defaultID
            return
        }
        selectedCategoryID = availableCategories.first?.id
    }

    func applyCategoryTemplateIfNeeded() {
        guard case .createTopic = route.kind else { return }
        let template = selectedCategory?.topicTemplate?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let template, !template.isEmpty else {
            lastInjectedTemplate = nil
            return
        }

        if trimmedBody.isEmpty || bodyText == lastInjectedTemplate {
            bodyText = template
            lastInjectedTemplate = template
            bodySelection = NSRange(location: (template as NSString).length, length: 0)
        }
    }

    func applyInitialBodyIfNeeded() {
        guard let initialBody else { return }
        let result = FireComposerInitialBody.merge(
            initialBody: initialBody,
            currentBody: bodyText,
            preferredSelectionLocation: initialBodySelectionLocation
        )
        bodyText = result.text
        bodySelection = result.selectedRange
    }

    func scheduleAutosave() {
        guard didLoadDraft else { return }
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await persistDraftIfNeeded()
        }
    }

    func persistDraftIfNeeded() async {
        guard !isSubmitting else { return }
        guard !didCompleteSubmission else { return }

        if !hasDraftContent {
            guard draftSequence > 0 else { return }
            do {
                try await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                draftSequence = 0
                render()
            } catch {
                errorMessage = error.localizedDescription
                render()
            }
            return
        }

        let draftData = DraftDataState(
            reply: bodyText,
            title: {
                switch route.kind {
                case .createTopic, .privateMessage:
                    return titleText
                case .advancedReply:
                    return nil
                }
            }(),
            categoryId: {
                if case .createTopic = route.kind {
                    return selectedCategoryID
                }
                return nil
            }(),
            tags: {
                if case .createTopic = route.kind {
                    return selectedTags
                }
                return []
            }(),
            replyToPostNumber: route.replyToPostNumber,
            action: {
                switch route.kind {
                case .createTopic:
                    return "create_topic"
                case .privateMessage:
                    return "private_message"
                case .advancedReply:
                    return "reply"
                }
            }(),
            recipients: route.isPrivateMessage ? selectedRecipients : [],
            archetypeId: route.isPrivateMessage ? "private_message" : "regular",
            composerTime: nil,
            typingTime: nil
        )

        do {
            draftSequence = try await viewModel.saveDraft(
                draftKey: route.draftKey,
                data: draftData,
                sequence: draftSequence
            )
            render()
        } catch {
            errorMessage = error.localizedDescription
            render()
        }
    }

}
