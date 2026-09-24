import PhotosUI
import UIKit

extension FireChatChannelViewController {
    func presentImagePicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 4
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func searchChatMentions(term: String) async -> [FireBottomInputMention] {
        do {
            let result = try await viewModel.searchService.searchUsers(
                term: term,
                includeGroups: true,
                limit: 8
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

    func send(payload: FireBottomInputPayload) async {
        let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !payload.images.isEmpty, !isSending else { return }
        isSending = true
        inputBar.apply(
            text: payload.text,
            placeholder: "发消息…",
            isSending: true,
            isEnabled: false
        )
        defer {
            isSending = false
            inputBar.apply(
                text: inputBar.currentText,
                placeholder: "发消息…",
                isSending: false,
                isEnabled: true
            )
        }
        do {
            var message = trimmed
            var uploadIDs: [UInt64] = []
            for image in payload.images {
                guard let data = image.fireJPEGDataForUpload() else { continue }
                let upload = try await viewModel.uploadImage(
                    fileName: "chat-\(UUID().uuidString).jpg",
                    mimeType: "image/jpeg",
                    bytes: data
                )
                if let uploadID = upload.id, uploadID > 0 {
                    uploadIDs.append(uploadID)
                } else {
                    let alt = upload.originalFilename?.isEmpty == false
                        ? upload.originalFilename!
                        : "image"
                    let markdown = "![\(alt)](\(upload.shortUrl))"
                    message = message.isEmpty ? markdown : message + "\n\n" + markdown
                }
            }
            await send(message: message, uploadIDs: uploadIDs)
            inputBar.resetAfterSend()
        } catch {
            presentError(error)
        }
    }

    func send(message: String, uploadIDs: [UInt64]) async {
        do {
            _ = try await viewModel.sendChatMessage(
                request: SendChatMessageRequestState(
                    channelId: channel.id,
                    message: message,
                    stagedId: UUID().uuidString,
                    inReplyToId: nil,
                    threadId: threadID,
                    uploadIds: uploadIDs
                )
            )
            await softRefreshLatest()
        } catch {
            presentError(error)
        }
    }

    func presentMessageActions(for message: ChatMessageState) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for emoji in ["heart", "tada", "laughing", "+1", "eyes"] {
            let title = message.reactions.first(where: { $0.emoji == emoji })?.reacted == true
                ? "取消 :\(emoji):"
                : ":\(emoji):"
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                Task { await self?.toggleReaction(message: message, emoji: emoji) }
            })
        }
        if channel.threadingEnabled, !isThread {
            sheet.addAction(UIAlertAction(title: "打开消息串", style: .default) { [weak self] _ in
                Task { await self?.openThread(for: message) }
            })
        }
        if channel.canManagePins || channel.canModerate {
            if message.pinned {
                sheet.addAction(UIAlertAction(title: "取消置顶", style: .default) { [weak self] _ in
                    Task {
                        try? await self?.viewModel.unpinChatMessage(
                            channelID: message.channelId,
                            messageID: message.id
                        )
                    }
                })
            } else {
                sheet.addAction(UIAlertAction(title: "置顶", style: .default) { [weak self] _ in
                    Task {
                        try? await self?.viewModel.pinChatMessage(
                            channelID: message.channelId,
                            messageID: message.id
                        )
                    }
                })
            }
        }
        if message.user?.id == viewModel.currentUserID || channel.canDeleteOthers || channel.canDeleteSelf {
            sheet.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
                Task {
                    try? await self?.viewModel.deleteChatMessage(
                        channelID: message.channelId,
                        messageID: message.id
                    )
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    func toggleReaction(message: ChatMessageState, emoji: String) async {
        let reacted = message.reactions.first(where: { $0.emoji == emoji })?.reacted == true
        do {
            try await viewModel.reactChatMessage(
                channelID: message.channelId,
                messageID: message.id,
                emoji: emoji,
                reactAction: reacted ? "remove" : "add"
            )
        } catch {
            presentError(error)
        }
    }

    func openThread(for message: ChatMessageState) async {
        do {
            let threadID: UInt64
            if let existing = message.threadId ?? message.thread?.id {
                threadID = existing
            } else {
                threadID = try await viewModel.createChatThread(
                    channelID: channel.id,
                    originalMessageID: message.id
                )
            }
            let controller = FireChatChannelViewController(
                channel: channel,
                viewModel: viewModel,
                threadID: threadID,
                onRead: onRead
            )
            navigationController?.pushViewController(controller, animated: true)
        } catch {
            presentError(error)
        }
    }
}

extension FireChatChannelViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        for result in results {
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }
                Task { @MainActor in
                    self?.inputBar.insertImage(image)
                }
            }
        }
    }
}
