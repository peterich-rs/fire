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
        await session.searchMentions(term: term)
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
            let uploads = payload.images.compactMap { image -> FireChatPendingUpload? in
                guard let data = image.fireJPEGDataForUpload() else { return nil }
                return FireChatPendingUpload(
                    fileName: "chat-\(UUID().uuidString).jpg",
                    mimeType: "image/jpeg",
                    bytes: data
                )
            }
            _ = try await session.command(.send(message: trimmed, uploads: uploads))
            inputBar.resetAfterSend()
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
                        _ = try? await self?.session.command(
                            .setPinned(messageID: message.id, pinned: false)
                        )
                    }
                })
            } else {
                sheet.addAction(UIAlertAction(title: "置顶", style: .default) { [weak self] _ in
                    Task {
                        _ = try? await self?.session.command(
                            .setPinned(messageID: message.id, pinned: true)
                        )
                    }
                })
            }
        }
        if message.user?.id == viewModel.currentUserID || channel.canDeleteOthers || channel.canDeleteSelf {
            sheet.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
                Task {
                    _ = try? await self?.session.command(.deleteMessage(messageID: message.id))
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
        do {
            _ = try await session.command(
                .toggleReaction(messageID: message.id, emoji: emoji)
            )
        } catch {
            presentError(error)
        }
    }

    func openThread(for message: ChatMessageState) async {
        do {
            let result = try await session.command(.resolveThread(messageID: message.id))
            guard case let .threadID(threadID) = result else { return }
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
