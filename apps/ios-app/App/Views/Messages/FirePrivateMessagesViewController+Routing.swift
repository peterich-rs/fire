import Combine
import SwiftUI
import UIKit

@MainActor
extension FirePrivateMessagesViewController {
    func updateTopicRoutePresenter(_ presenter: FireTopicRoutePresenter) {
        topicRoutePresenter = presenter
    }

    func canSelect(_ item: FirePrivateMessagesCollectionItem) -> Bool {
        if case .message = item {
            return true
        }
        return false
    }

    func handleSelection(_ item: FirePrivateMessagesCollectionItem) {
        guard case let .message(topicID) = item,
              let row = row(topicID: topicID)
        else {
            return
        }
        presentRoute(.topic(row: row))
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
            return
        }
        // Already inside secondary stack: push local drill-down.
        if let navigationController {
            let controller = FireAppRouteControllerFactory.makeViewController(
                viewModel: appViewModel,
                topicDetailStore: topicDetailStore,
                route: route,
                topicRoutePresenter: topicRoutePresenter
            )
            navigationController.pushViewController(controller, animated: true)
        }
    }
}
