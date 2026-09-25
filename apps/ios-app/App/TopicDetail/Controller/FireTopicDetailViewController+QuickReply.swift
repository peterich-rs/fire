import PhotosUI
import UIKit

@MainActor
extension FireTopicDetailViewController {
    func configureQuickReplyBar() {
        // Layer above Texture feed so cells never show through the bar.
        quickReplyBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(quickReplyBar)

        let bottom = quickReplyBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        let height = quickReplyBar.heightAnchor.constraint(equalToConstant: 0)
        quickReplyBottomConstraint = bottom
        quickReplyHeightConstraint = height

        NSLayoutConstraint.activate([
            quickReplyBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            quickReplyBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom,
            height,
        ])
        view.bringSubviewToFront(quickReplyBar)
    }

    func handleQuickReplyFocusChanged(_ focused: Bool) {
        if focused {
            topicDetailStore.beginReplyTyping(topicId: topic.id)
        } else {
            Task {
                topicDetailStore.endReplyTyping(topicId: topic.id)
            }
        }
    }

    func openComposer(replyToPost: TopicPostState?) {
        composerContext = FireReplyComposerContext(
            topicId: topic.id,
            postId: replyToPost?.id,
            replyToPostNumber: replyToPost?.postNumber,
            replyToUsername: replyToPost?.username,
            kind: .reply
        )
        presentQuickReplyInput()
    }

    func openBoostComposer(for post: TopicPostState) {
        guard post.canBoost else {
            modalRouter.presentNotice(message: "当前帖子暂时不能 Boost。")
            return
        }
        guard canWriteInteractions else {
            modalRouter.presentNotice(message: "登录后才能 Boost。")
            return
        }
        // Share the bottom quick-reply chrome with comments instead of a separate sheet.
        composerContext = FireReplyComposerContext(
            topicId: topic.id,
            postId: post.id,
            replyToPostNumber: post.postNumber,
            replyToUsername: post.username,
            kind: .boost
        )
        if !replyDraft.isEmpty, composerContext?.isBoost == true {
            // Keep draft if user was already drafting a boost; otherwise clear reply draft noise.
        }
        presentQuickReplyInput()
    }

    /// Apply chrome first, commit bar geometry, then focus so the keyboard and
    /// input strip rise together (especially for swipe-to-reply).
    func presentQuickReplyInput() {
        buildAndApplyChromeState()
        // Target row / height must be in the hierarchy before first-responder
        // kicks off the keyboard animation; otherwise the bar catches up late.
        view.layoutIfNeeded()
        quickReplyBar.focusInput()
    }

    func clearComposerTarget() {
        // Cancel target is a full dismiss of the current compose session: drop the
        // reply/Boost target, wipe draft text, and leave the keyboard down.
        composerContext = nil
        replyDraft = ""
        quickReplyError = nil
        buildAndApplyChromeState()
        view.layoutIfNeeded()
        quickReplyBar.resignInputFocus()
    }

    func openAdvancedComposer() {
        let context = composerContext
            ?? FireReplyComposerContext(
                topicId: topic.id,
                postId: nil,
                replyToPostNumber: nil,
                replyToUsername: nil
            )
        quickReplyBar.resignInputFocus()
        modalRouter.presentAdvancedComposer(
            route: FireComposerRoute(
                kind: .advancedReply(
                    topicID: topic.id,
                    topicTitle: displayedTopicTitle,
                    categoryID: displayedCategoryId,
                    replyToPostNumber: context.replyToPostNumber,
                    replyToUsername: context.replyToUsername,
                    isPrivateMessage: isPrivateMessageThread
                )
            ),
            initialBody: replyDraft,
            onReplySubmitted: { [weak self] in
                guard let self else { return }
                self.replyDraft = ""
                self.composerContext = nil
                self.quickReplyError = nil
                self.buildAndApplyChromeState()
            },
            onSubmissionNotice: { [weak self] message in
                self?.modalRouter.presentNotice(message: message)
            }
        )
    }

    func openQuoteComposer(for post: TopicPostState) {
        guard let quote = FireQuoteMarkdown.build(
            username: post.username,
            postNumber: post.postNumber,
            topicID: topic.id,
            plainText: post.presentation?.plainText() ?? ""
        ) else {
            modalRouter.presentNotice(message: "该帖子暂无可引用内容。")
            return
        }

        let quickReplyDraft = replyDraft
        let initialBody = FireComposerInitialBody.merge(
            initialBody: quote,
            currentBody: quickReplyDraft
        ).text
        let quoteSelectionLocation = (quote as NSString).length
        composerContext = FireReplyComposerContext(
            topicId: topic.id,
            postId: post.id,
            replyToPostNumber: post.postNumber,
            replyToUsername: post.username
        )
        quickReplyBar.resignInputFocus()
        buildAndApplyChromeState()
        modalRouter.presentAdvancedComposer(
            route: FireComposerRoute(
                kind: .advancedReply(
                    topicID: topic.id,
                    topicTitle: displayedTopicTitle,
                    categoryID: displayedCategoryId,
                    replyToPostNumber: post.postNumber,
                    replyToUsername: post.username,
                    isPrivateMessage: isPrivateMessageThread
                )
            ),
            initialBody: initialBody,
            initialBodySelectionLocation: quoteSelectionLocation,
            onReplySubmitted: { [weak self] in
                guard let self else { return }
                self.replyDraft = ""
                self.composerContext = nil
                self.quickReplyError = nil
                self.buildAndApplyChromeState()
            },
            onSubmissionNotice: { [weak self] message in
                self?.modalRouter.presentNotice(message: message)
            },
            scrollToCreatedReply: true
        )
    }

    func submitQuickReply(_ payload: FireBottomInputPayload) {
        Task { @MainActor in
            let raw: String
            do {
                raw = try await composeQuickReplyRaw(from: payload)
            } catch {
                quickReplyError = error.localizedDescription
                buildAndApplyChromeState()
                return
            }

            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                quickReplyError = composerContext?.isBoost == true
                    ? "Boost 内容不能为空。"
                    : "回复内容不能为空。"
                buildAndApplyChromeState()
                return
            }

            if composerContext?.isBoost == true {
                submitBoostFromQuickReply(raw: trimmed)
                return
            }

            guard trimmed.count >= minimumReplyLength else {
                quickReplyError = "回复至少需要 \(minimumReplyLength) 个字。"
                buildAndApplyChromeState()
                return
            }

            let topicId = composerContext?.topicId ?? topic.id
            let replyToPostNumber = composerContext?.replyToPostNumber
            quickReplyError = nil
            buildAndApplyChromeState()

            do {
                try await topicDetailStore.submitReply(
                    topicId: topicId,
                    raw: trimmed,
                    replyToPostNumber: replyToPostNumber,
                    scrollToCreated: false
                )
                finishQuickReplySuccess()
            } catch {
                let message = error.localizedDescription
                if message.localizedCaseInsensitiveContains("pending review") {
                    finishQuickReplySuccess()
                    modalRouter.presentNotice(message: "回复已提交，等待审核。")
                    return
                }
                quickReplyError = message
                buildAndApplyChromeState()
            }
        }
    }

    func composeQuickReplyRaw(from payload: FireBottomInputPayload) async throws -> String {
        var parts: [String] = []
        let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }
        for image in payload.images {
            guard let data = image.fireJPEGDataForUpload() else { continue }
            let upload = try await viewModel.uploadImage(
                fileName: "reply-\(UUID().uuidString).jpg",
                mimeType: "image/jpeg",
                bytes: data
            )
            let alt = upload.originalFilename?.isEmpty == false
                ? upload.originalFilename!
                : "image"
            parts.append("![\(alt)](\(upload.shortUrl))")
        }
        return parts.joined(separator: "\n\n")
    }

    func finishQuickReplySuccess() {
        replyDraft = ""
        composerContext = nil
        quickReplyBar.resetAfterSend()
        quickReplyBar.resignInputFocus()
        buildAndApplyChromeState()
    }

    func searchQuickReplyMentions(term: String) async -> [FireBottomInputMention] {
        do {
            let result = try await viewModel.searchService.searchUsers(
                term: term,
                includeGroups: true,
                limit: 8,
                topicID: topic.id,
                categoryID: displayedCategoryId
            )
            let users = result.users.map { user in
                FireBottomInputMention(
                    handle: user.username,
                    displayName: user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? user.username
                )
            }
            let groups = result.groups.map { group in
                FireBottomInputMention(
                    handle: group.name,
                    displayName: group.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? group.name
                )
            }
            return users + groups
        } catch {
            return []
        }
    }

    func presentQuickReplyImagePicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 4
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func submitBoostFromQuickReply(raw: String) {
        guard let postId = composerContext?.postId else {
            quickReplyError = "找不到要 Boost 的帖子。"
            buildAndApplyChromeState()
            return
        }
        quickReplyError = nil
        buildAndApplyChromeState()
        Task { @MainActor in
            do {
                try await topicDetailStore.createBoost(
                    topicId: topic.id,
                    postId: postId,
                    raw: raw
                )
                finishQuickReplySuccess()
                FireMotionHaptics.success()
            } catch is CancellationError {
                // ignore
            } catch {
                FireMotionHaptics.error()
                quickReplyError = error.localizedDescription
                buildAndApplyChromeState()
            }
        }
    }
}

extension FireTopicDetailViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        for result in results {
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }
                Task { @MainActor in
                    self?.quickReplyBar.insertImage(image)
                }
            }
        }
    }
}
