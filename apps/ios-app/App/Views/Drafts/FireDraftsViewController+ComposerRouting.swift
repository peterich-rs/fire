import Combine
import SwiftUI
import UIKit

@MainActor
extension FireDraftsViewController {
    func canSelect(_ item: FireDraftsCollectionItem) -> Bool {
        guard case let .draft(key) = item,
              let draft = draft(key: key)
        else {
            return false
        }
        return draft.fireComposerRoute() != nil
    }

    func handleSelection(_ item: FireDraftsCollectionItem) {
        guard case let .draft(key) = item,
              let draft = draft(key: key)
        else {
            return
        }
        open(draft)
    }

    func contextMenuConfiguration(for item: FireDraftsCollectionItem) -> UIContextMenuConfiguration? {
        guard case let .draft(key) = item,
              let draft = draft(key: key)
        else {
            return nil
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: self?.draftMenuActions(draft) ?? [])
        }
    }

    func draftMenuActions(_ draft: DraftState) -> [UIAction] {
        var actions: [UIAction] = []
        if draft.fireComposerRoute() != nil {
            actions.append(
                UIAction(title: "继续编辑", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
                    self?.open(draft)
                }
            )
        }
        actions.append(
            UIAction(
                title: "删除",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.delete(draft)
            }
        )
        return actions
    }

    func open(_ draft: DraftState) {
        guard let route = draft.fireComposerRoute() else {
            showToast("当前草稿类型暂不支持继续编辑", style: .error)
            return
        }

        let composer = FireComposerViewController(
            viewModel: appViewModel,
            route: route,
            onTopicCreated: { [weak self] _ in
                self?.refreshAfterComposerMutation()
            },
            onReplySubmitted: { [weak self] in
                self?.refreshAfterComposerMutation()
            },
            onPrivateMessageCreated: { [weak self] _, _ in
                self?.refreshAfterComposerMutation()
            },
            onSubmissionNotice: { [weak self] message in
                self?.showToast(message, style: .success)
            }
        )
        let navigationController = UINavigationController(rootViewController: composer)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }

    func refreshAfterComposerMutation() {
        loadTask = Task { [weak self] in
            await self?.draftsViewModel.refresh()
        }
    }

    func delete(_ draft: DraftState) {
        loadTask = Task { [weak self] in
            await self?.draftsViewModel.deleteDraft(draft)
        }
    }

    func showToast(_ message: String, style: FireTopicListToastView.Style) {
        toastDismissTask?.cancel()
        toastView?.removeFromSuperview()
        toastView = nil
        FireUIKitToast.show(message, style: FireUIKitToast.Style(style), in: view)
    }
}
