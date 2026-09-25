import Combine
import UIKit

@MainActor
extension FireNotificationsViewController {
    func updateToolbar() {
        guard notificationStore.unreadCount > 0 else {
            navigationItem.rightBarButtonItem = nil
            return
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "全部已读",
            style: .plain,
            target: self,
            action: #selector(markAllRead)
        )
    }

    @objc func markAllRead() {
        notificationStore.markAllRead()
    }

    func contextMenuConfiguration(
        for item: FireNotificationsCollectionItem
    ) -> UIContextMenuConfiguration? {
        guard case let .notification(id) = item,
              let notification = notification(id: id)
        else {
            return nil
        }
        let shareURL = notification.fireShareURL(baseURL: baseURLString)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: self?.notificationMenuActions(item: notification, shareURL: shareURL) ?? [])
        }
    }

    func notificationMenuActions(
        item: NotificationItemState,
        shareURL: URL?
    ) -> [UIAction] {
        var actions: [UIAction] = [
            UIAction(title: "跳转到通知", image: UIImage(systemName: "arrow.up.right")) { [weak self] _ in
                self?.open(item)
            },
        ]

        if !item.read {
            actions.append(
                UIAction(title: "标记为已读", image: UIImage(systemName: "envelope.open")) { [weak self] _ in
                    self?.notificationStore.markRead(id: item.id)
                }
            )
        }

        actions.append(
            UIAction(title: "复制通知内容", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                UIPasteboard.general.string = item.displayDescription
                self?.showToast("已复制通知内容", style: .success)
            }
        )

        if let shareURL {
            actions.append(
                UIAction(title: "分享链接", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                    self?.presentShareSheet(url: shareURL)
                }
            )
            actions.append(
                UIAction(title: "复制链接", image: UIImage(systemName: "link")) { [weak self] _ in
                    UIPasteboard.general.string = shareURL.absoluteString
                    self?.showToast("已复制链接", style: .success)
                }
            )
        }

        return actions
    }

    func showToast(_ message: String, style: FireTopicListToastView.Style) {
        toastDismissTask?.cancel()
        toastView?.removeFromSuperview()
        toastView = nil
        FireUIKitToast.show(message, style: FireUIKitToast.Style(style), in: view)
    }
}
