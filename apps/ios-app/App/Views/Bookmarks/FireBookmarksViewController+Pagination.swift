import Combine
import SwiftUI
import UIKit

@MainActor
extension FireBookmarksViewController {
    func handleVisibleItemsChanged(_ items: [FireBookmarksCollectionItem]) {
        loadMoreIfNeeded(from: items)
    }

    func loadMoreIfNeeded(from items: [FireBookmarksCollectionItem]) {
        guard let lastRowID = bookmarksViewModel.lastRowID else { return }
        guard items.contains(.bookmark(lastRowID)) || items.contains(.loadingMore) else { return }
        loadTask = Task { [weak self] in
            await self?.bookmarksViewModel.loadMoreIfNeeded(currentRowID: lastRowID)
        }
    }
}
