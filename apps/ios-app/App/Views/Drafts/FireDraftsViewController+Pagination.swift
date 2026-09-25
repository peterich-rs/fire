import Combine
import SwiftUI
import UIKit

@MainActor
extension FireDraftsViewController {
    func loadMoreIfNeeded(from items: [FireDraftsCollectionItem]) {
        guard let lastDraftKey = draftsViewModel.drafts.last?.draftKey else { return }
        guard items.contains(.draft(lastDraftKey)) || items.contains(.loadingMore) else { return }
        loadTask = Task { [weak self] in
            await self?.draftsViewModel.loadMoreIfNeeded(currentDraftKey: lastDraftKey)
        }
    }
}
