import Combine
import SwiftUI
import UIKit

@MainActor
extension FireFilteredTopicListViewController {
    func contextMenuConfiguration(
        for item: FireFilteredTopicItem
    ) -> UIContextMenuConfiguration? {
        guard case let .topic(id) = item,
              let row = listViewModel.displayedRows.first(where: { $0.topic.id == id })
        else { return nil }
        let shareURL = row.fireTopicURL(baseURL: baseURLString)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "打开话题", image: UIImage(systemName: "arrow.up.right")) { _ in
                    self?.presentRoute(.topic(row: row))
                },
                UIAction(
                    title: row.topic.bookmarkId == nil ? "添加书签" : "编辑书签",
                    image: UIImage(systemName: row.topic.bookmarkId == nil ? "bookmark" : "bookmark.fill")
                ) { _ in
                    self?.presentBookmarkEditor(for: row)
                },
                UIAction(title: "分享话题", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    self?.presentShareSheet(url: shareURL)
                },
                UIAction(title: "复制链接", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = shareURL.absoluteString
                    self?.showToast("已复制链接", style: .success)
                },
                UIAction(title: "静音话题", image: UIImage(systemName: "bell.slash")) { _ in
                    self?.muteTopic(row)
                },
            ])
        }
    }

    func presentBookmarkEditor(for row: FireTopicRowPresentation) {
        let context = row.fireBookmarkEditorContext()
        let sheet = FireBookmarkEditorSheet(
            context: context,
            onSave: { [weak self] name, reminderAt in
                guard let self else { return }
                if let bookmarkID = context.bookmarkID {
                    try await self.appViewModel.topicInteraction.updateBookmark(
                        bookmarkID: bookmarkID,
                        name: name,
                        reminderAt: reminderAt
                    )
                } else {
                    _ = try await self.appViewModel.topicInteraction.createBookmark(
                        bookmarkableID: context.bookmarkableID,
                        bookmarkableType: context.bookmarkableType,
                        name: name,
                        reminderAt: reminderAt
                    )
                }
                await self.listViewModel.refresh()
            },
            onDelete: context.bookmarkID.map { bookmarkID in
                { [weak self] in
                    try await self?.appViewModel.topicInteraction.deleteBookmark(bookmarkID: bookmarkID)
                    await self?.listViewModel.refresh()
                }
            }
        )
        let host = UIHostingController(rootView: sheet)
        if let sheetController = host.sheetPresentationController {
            sheetController.detents = [.medium(), .large()]
            sheetController.prefersGrabberVisible = true
        }
        present(host, animated: true)
    }

    func deleteBookmark(for row: FireTopicRowPresentation) {
        guard let bookmarkID = row.topic.bookmarkId else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await appViewModel.topicInteraction.deleteBookmark(bookmarkID: bookmarkID)
                await listViewModel.refresh()
                showToast("已删除书签", style: .success)
            } catch {
                showToast(error.localizedDescription, style: .error)
            }
        }
    }

    func muteTopic(_ row: FireTopicRowPresentation) {
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await appViewModel.topicInteraction.setTopicNotificationLevel(
                    topicID: row.topic.id,
                    notificationLevel: FireTopicNotificationLevelOption.muted.rawValue
                )
                showToast("已静音话题", style: .success)
            } catch {
                showToast(error.localizedDescription, style: .error)
            }
        }
    }

    func showToast(_ message: String, style: FireUIKitToast.Style) {
        FireUIKitToast.show(message, style: style, in: view)
    }
}
