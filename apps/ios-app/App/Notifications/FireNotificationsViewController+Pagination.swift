import Combine
import UIKit

@MainActor
extension FireNotificationsViewController {
    func loadRecentIfNeeded() {
        guard !notificationStore.hasLoadedRecentOnce,
              !notificationStore.isLoadingRecent else { return }
        loadTask = Task { [weak self] in
            await self?.notificationStore.loadRecent(force: false)
        }
    }
}
