import Combine
import SwiftUI
import UIKit

@MainActor
extension FireFilteredTopicListViewController {
    func handleVisibleItemsChanged(_ items: [FireFilteredTopicItem]) {
        let nearEnd = items.contains {
            if case .loadingMore = $0 { return true }
            if case let .topic(id) = $0 {
                return id == listViewModel.displayedRows.last?.topic.id
            }
            return false
        }
        guard nearEnd else { return }
        loadTask = Task { [weak self] in
            await self?.listViewModel.loadMore()
        }
    }
}
