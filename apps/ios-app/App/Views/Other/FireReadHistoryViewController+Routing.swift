import Combine
import SwiftUI
import UIKit

@MainActor
extension FireReadHistoryViewController {
    func updateTopicRoutePresenter(_ presenter: FireTopicRoutePresenter) {
        topicRoutePresenter = presenter
    }

    func canSelect(_ item: FireReadHistoryCollectionItem) -> Bool {
        if case .topic = item {
            return true
        }
        return false
    }

    func handleSelection(_ item: FireReadHistoryCollectionItem) {
        guard case let .topic(topicID) = item,
              let row = historyViewModel.row(for: topicID) else { return }
        presentRoute(.topic(row: row, postNumber: row.topic.lastReadPostNumber))
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
