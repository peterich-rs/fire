import Combine
import SwiftUI
import UIKit

@MainActor
extension FirePrivateMessagesViewController {
    func loadMoreIfNeeded(from items: [FirePrivateMessagesCollectionItem]) {
        guard let lastTopicID = mailboxViewModel.displayedRows.last?.topic.id else { return }
        guard items.contains(.message(lastTopicID)) || items.contains(.loadingMore) else { return }
        loadTask = Task { [weak self] in
            await self?.mailboxViewModel.loadMoreIfNeeded(currentTopicID: lastTopicID)
        }
    }
}
