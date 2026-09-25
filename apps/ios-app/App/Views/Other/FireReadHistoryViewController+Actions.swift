import Combine
import SwiftUI
import UIKit

@MainActor
extension FireReadHistoryViewController {
    func contextMenuConfiguration(
        for item: FireReadHistoryCollectionItem
    ) -> UIContextMenuConfiguration? {
        guard case let .topic(topicID) = item,
              let row = historyViewModel.row(for: topicID)
        else {
            return nil
        }
        let shareURL = row.fireTopicURL(baseURL: baseURLString)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: self?.topicMenuActions(row: row, shareURL: shareURL) ?? [])
        }
    }

    func topicMenuActions(
        row: FireTopicRowPresentation,
        shareURL: URL
    ) -> [UIAction] {
        [
            UIAction(title: "打开话题", image: UIImage(systemName: "arrow.up.right")) { [weak self] _ in
                self?.presentRoute(.topic(row: row, postNumber: row.topic.lastReadPostNumber))
            },
            UIAction(
                title: row.topic.bookmarkId == nil ? "添加书签" : "编辑书签",
                image: UIImage(systemName: row.topic.bookmarkId == nil ? "bookmark" : "bookmark.fill")
            ) { [weak self] _ in
                self?.presentBookmarkEditor(for: row)
            },
            UIAction(title: "分享话题", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                self?.presentShareSheet(url: shareURL)
            },
            UIAction(title: "复制链接", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                UIPasteboard.general.string = shareURL.absoluteString
                self?.showToast("已复制链接", style: .success)
            },
            UIAction(title: "静音话题", image: UIImage(systemName: "bell.slash")) { [weak self] _ in
                self?.muteTopicFromAction(row)
            },
        ]
    }

    func presentBookmarkEditor(for row: FireTopicRowPresentation) {
        let context = row.fireBookmarkEditorContext()
        let recoveryOriginURL = row.fireTopicURL(baseURL: baseURLString)
        let rootView = FireBookmarkEditorSheet(
            context: context,
            onSave: { [weak self] name, reminderAt in
                try await self?.saveBookmark(
                    context: context,
                    name: name,
                    reminderAt: reminderAt,
                    recoveryOriginURL: recoveryOriginURL
                )
            },
            onDelete: context.bookmarkID.map { bookmarkID in
                { [weak self] in
                    try await self?.deleteBookmark(
                        bookmarkID: bookmarkID,
                        recoveryOriginURL: recoveryOriginURL,
                        showSuccessToast: false
                    )
                }
            }
        )
        let controller = UIHostingController(rootView: rootView)
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(controller, animated: true)
    }

    func saveBookmark(
        context: FireBookmarkEditorContext,
        name: String?,
        reminderAt: String?,
        recoveryOriginURL: URL
    ) async throws {
        if let bookmarkID = context.bookmarkID {
            try await appViewModel.topicInteraction.updateBookmark(
                bookmarkID: bookmarkID,
                name: name,
                reminderAt: reminderAt,
                recoveryOriginURL: recoveryOriginURL
            )
        } else {
            _ = try await appViewModel.topicInteraction.createBookmark(
                bookmarkableID: context.bookmarkableID,
                bookmarkableType: context.bookmarkableType,
                name: name,
                reminderAt: reminderAt,
                recoveryOriginURL: recoveryOriginURL
            )
        }
        await historyViewModel.refresh()
    }

    func deleteBookmarkFromAction(for row: FireTopicRowPresentation) {
        guard let bookmarkID = row.topic.bookmarkId else { return }
        let recoveryOriginURL = row.fireTopicURL(baseURL: baseURLString)
        loadTask = Task { [weak self] in
            do {
                try await self?.deleteBookmark(
                    bookmarkID: bookmarkID,
                    recoveryOriginURL: recoveryOriginURL,
                    showSuccessToast: true
                )
            } catch {
                self?.historyViewModel.reportError(error.localizedDescription)
                self?.showToast(error.localizedDescription, style: .error)
            }
        }
    }

    func deleteBookmark(
        bookmarkID: UInt64,
        recoveryOriginURL: URL,
        showSuccessToast: Bool
    ) async throws {
        try await appViewModel.topicInteraction.deleteBookmark(
            bookmarkID: bookmarkID,
            recoveryOriginURL: recoveryOriginURL
        )
        await historyViewModel.refresh()
        if showSuccessToast {
            showToast("已删除书签", style: .success)
        }
    }

    func muteTopicFromAction(_ row: FireTopicRowPresentation) {
        loadTask = Task { [weak self] in
            do {
                try await self?.appViewModel.topicInteraction.setTopicNotificationLevel(
                    topicID: row.topic.id,
                    notificationLevel: FireTopicNotificationLevelOption.muted.rawValue,
                    recoveryOriginURL: row.fireTopicURL(baseURL: self?.baseURLString ?? "https://linux.do")
                )
                self?.showToast("已静音话题", style: .success)
            } catch {
                self?.showToast(error.localizedDescription, style: .error)
            }
        }
    }

    func showToast(_ message: String, style: FireTopicListToastView.Style) {
        toastDismissTask?.cancel()
        toastView?.removeFromSuperview()
        toastView = nil
        FireUIKitToast.show(message, style: FireUIKitToast.Style(style), in: view)
    }
}
