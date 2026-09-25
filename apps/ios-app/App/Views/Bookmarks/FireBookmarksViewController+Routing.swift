import Combine
import SwiftUI
import UIKit

@MainActor
extension FireBookmarksViewController {
    func updateTopicRoutePresenter(_ presenter: FireTopicRoutePresenter) {
        topicRoutePresenter = presenter
    }

    func canSelect(_ item: FireBookmarksCollectionItem) -> Bool {
        if case .bookmark = item {
            return true
        }
        return false
    }

    func handleSelection(_ item: FireBookmarksCollectionItem) {
        guard case let .bookmark(id) = item,
              let row = bookmarksViewModel.row(for: id) else { return }
        presentRoute(.topic(
            row: row,
            postNumber: row.topic.bookmarkedPostNumber ?? row.topic.lastReadPostNumber
        ))
    }

    func presentRoute(_ route: FireAppRoute) {
        if topicRoutePresenter.present(route) {
            return
        }
        if route.presentsAsSecondaryPage {
            FireAppRouteControllerFactory.presentSecondaryRoute(
                route,
                viewModel: appViewModel,
                topicDetailStore: topicDetailStore
            )
        }
    }

    func presentShareSheet(url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(
                x: view.bounds.midX,
                y: view.safeAreaInsets.top + 24,
                width: 1,
                height: 1
            )
        }
        present(controller, animated: true)
    }
}
