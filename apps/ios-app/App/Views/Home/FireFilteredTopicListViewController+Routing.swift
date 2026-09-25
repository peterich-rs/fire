import Combine
import SwiftUI
import UIKit

@MainActor
extension FireFilteredTopicListViewController {
    func updateTopicRoutePresenter(_ presenter: FireTopicRoutePresenter) {
        topicRoutePresenter = presenter
    }

    func canSelect(_ item: FireFilteredTopicItem) -> Bool {
        if case .topic = item { return true }
        return false
    }

    func handleSelection(_ item: FireFilteredTopicItem) {
        guard case let .topic(id) = item,
              let row = listViewModel.displayedRows.first(where: { $0.topic.id == id })
        else { return }
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
        }
    }

    func presentShareSheet(url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(controller, animated: true)
    }
}
