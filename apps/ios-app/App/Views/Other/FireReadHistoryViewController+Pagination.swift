import Combine
import SwiftUI
import UIKit

@MainActor
extension FireReadHistoryViewController {
    func handleVisibleItemsChanged(_ items: [FireReadHistoryCollectionItem]) {
        loadMoreIfNeeded(from: items)
    }

    func loadMoreIfNeeded(from items: [FireReadHistoryCollectionItem]) {
        guard let lastTopicID = historyViewModel.lastTopicID else { return }
        guard items.contains(.topic(lastTopicID)) || items.contains(.loadingMore) else { return }
        loadTask = Task { [weak self] in
            await self?.historyViewModel.loadMoreIfNeeded(currentTopicID: lastTopicID)
        }
    }
}
