import Combine
import UIKit

@MainActor
extension FireNotificationHistoryViewController {
    func loadMoreIfNeeded(from items: [FireNotificationHistoryCollectionItem]) {
        guard notificationStore.hasMoreFull,
              !notificationStore.isLoadingFullPage,
              !notificationStore.shouldShowFullPaginationRetry else { return }
        let lastNotificationID = notificationStore.fullNotifications.last?.id
        guard items.contains(.loadingMore)
            || lastNotificationID.map({ items.contains(.notification($0)) }) == true
        else {
            return
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.notificationStore.loadFullPage(offset: self.notificationStore.fullNextOffset)
        }
    }
}
