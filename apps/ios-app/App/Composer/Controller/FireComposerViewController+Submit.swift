import UIKit

extension FireComposerViewController {
    @objc func closeButtonTapped() {
        guard !isSubmitting else { return }
        dismiss(animated: true)
    }

    @objc func submitButtonTapped() {
        submitComposer()
    }

    func submitComposer() {
        guard !isSubmitting else { return }
        errorMessage = nil
        noticeMessage = nil

        switch route.kind {
        case .createTopic:
            guard !trimmedTitle.isEmpty else {
                showSubmissionError("标题不能为空。")
                return
            }
            guard trimmedTitle.count >= minimumTitleLength else {
                showSubmissionError("标题至少需要 \(minimumTitleLength) 个字。")
                return
            }
            guard let selectedCategoryID else {
                showSubmissionError("请选择分类。")
                return
            }
            guard !trimmedBody.isEmpty else {
                showSubmissionError("正文不能为空。")
                return
            }
            guard trimmedBody.count >= minimumBodyLength else {
                showSubmissionError("正文至少需要 \(minimumBodyLength) 个字。")
                return
            }
            guard selectedTags.count >= selectedCategoryMinimumTags else {
                showSubmissionError("当前分类至少需要 \(selectedCategoryMinimumTags) 个标签。")
                return
            }

            beginSubmitting()
            Task { [weak self] in
                guard let self else { return }
                defer { endSubmitting() }
                do {
                    let topicID = try await viewModel.createTopic(
                        title: trimmedTitle,
                        raw: trimmedBody,
                        categoryID: selectedCategoryID,
                        tags: selectedTags
                    )
                    try? await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                    draftSequence = 0
                    finishSubmission(message: submissionSuccessMessage) { [weak self] in
                        self?.onTopicCreated?(topicID)
                    }
                } catch {
                    handleSubmissionError(error)
                }
            }

        case .privateMessage:
            guard !trimmedTitle.isEmpty else {
                showSubmissionError("标题不能为空。")
                return
            }
            guard trimmedTitle.count >= minimumTitleLength else {
                showSubmissionError("标题至少需要 \(minimumTitleLength) 个字。")
                return
            }
            guard !trimmedBody.isEmpty else {
                showSubmissionError("正文不能为空。")
                return
            }
            guard trimmedBody.count >= minimumBodyLength else {
                showSubmissionError("正文至少需要 \(minimumBodyLength) 个字。")
                return
            }
            guard !selectedRecipients.isEmpty else {
                showSubmissionError("请至少添加一个收件人。")
                return
            }

            beginSubmitting()
            Task { [weak self] in
                guard let self else { return }
                defer { endSubmitting() }
                do {
                    let topicID = try await viewModel.createPrivateMessage(
                        title: trimmedTitle,
                        raw: trimmedBody,
                        targetRecipients: selectedRecipients
                    )
                    try? await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                    draftSequence = 0
                    let submittedTitle = trimmedTitle
                    finishSubmission(message: submissionSuccessMessage) { [weak self] in
                        self?.onPrivateMessageCreated?(topicID, submittedTitle)
                    }
                } catch {
                    handleSubmissionError(error)
                }
            }

        case .advancedReply(let topicID, _, _, let replyToPostNumber, _, _):
            guard !trimmedBody.isEmpty else {
                showSubmissionError("回复内容不能为空。")
                return
            }
            guard trimmedBody.count >= minimumBodyLength else {
                showSubmissionError("回复至少需要 \(minimumBodyLength) 个字。")
                return
            }

            beginSubmitting()
            Task { [weak self] in
                guard let self else { return }
                defer { endSubmitting() }
                do {
                    try await viewModel.submitReply(
                        topicId: topicID,
                        raw: trimmedBody,
                        replyToPostNumber: replyToPostNumber,
                        scrollToCreated: scrollToCreatedReply
                    )
                    try? await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                    draftSequence = 0
                    finishSubmission(message: submissionSuccessMessage) { [weak self] in
                        self?.onReplySubmitted?()
                    }
                } catch {
                    handleSubmissionError(error) { [weak self] in
                        self?.onReplySubmitted?()
                    }
                }
            }
        }
    }

    func beginSubmitting() {
        isSubmitting = true
        view.endEditing(true)
        render()
    }

    func endSubmitting() {
        isSubmitting = false
        render()
    }

    func handleSubmissionError(_ error: Error, pendingReviewCompletion: (() -> Void)? = nil) {
        let message = error.localizedDescription
        if FireComposerSession.isPendingReview(error) {
            Task { [weak self] in
                guard let self else { return }
                try? await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                draftSequence = 0
                finishSubmission(message: pendingReviewMessage) {
                    pendingReviewCompletion?()
                }
            }
            return
        }
        showSubmissionError(message)
    }

    func finishSubmission(message: String, completion: (() -> Void)? = nil) {
        didCompleteSubmission = true
        autosaveTask?.cancel()
        onSubmissionNotice?(message)
        dismiss(animated: true) {
            completion?()
        }
    }

    func showSubmissionError(_ message: String) {
        errorMessage = message
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        render()
    }

}
