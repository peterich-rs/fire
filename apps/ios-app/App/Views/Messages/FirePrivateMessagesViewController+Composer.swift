import Combine
import SwiftUI
import UIKit

@MainActor
extension FirePrivateMessagesViewController {
    @objc func openComposer() {
        let composer = FireComposerViewController(
            viewModel: appViewModel,
            route: FireComposerRoute(kind: .privateMessage(recipients: [], title: nil)),
            onPrivateMessageCreated: { [weak self] topicID, title in
                guard let self else { return }
                let route = FireAppRoute.topic(
                    topicId: topicID,
                    postNumber: nil,
                    preview: FireTopicRoutePreview.fromMetadata(title: title, slug: nil)
                )
                self.presentRoute(route)
                self.loadTask = Task { [weak self] in
                    await self?.mailboxViewModel.refresh()
                }
            },
            onSubmissionNotice: { [weak self] message in
                guard message.contains("等待审核") else { return }
                self?.showToast(message, style: .info)
            }
        )
        let navigationController = UINavigationController(rootViewController: composer)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }

    func showToast(_ message: String, style: FireTopicListToastView.Style) {
        toastDismissTask?.cancel()
        toastView?.removeFromSuperview()
        toastView = nil
        FireUIKitToast.show(message, style: FireUIKitToast.Style(style), in: view)
    }
}
