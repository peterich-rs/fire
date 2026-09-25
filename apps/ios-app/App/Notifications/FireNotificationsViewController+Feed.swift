import Combine
import UIKit

@MainActor
extension FireNotificationsViewController {
    var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var contentVersion: ContentVersion {
        ContentVersion(
            unreadCount: notificationStore.unreadCount,
            notifications: notificationStore.recentNotifications.map(FireNotificationItemContentToken.init),
            isLoading: notificationStore.isLoadingRecent,
            hasLoadedOnce: notificationStore.hasLoadedRecentOnce,
            errorMessage: notificationStore.recentErrorMessage,
            isOffline: notificationStore.isRecentOffline
        )
    }

    func render() {
        let sections = makeSections()
        var tokens: [FireNotificationsCollectionItem: AnyHashable] = [:]
        tokens.reserveCapacity(sections.reduce(0) { $0 + $1.items.count })
        for section in sections {
            for item in section.items {
                tokens[item] = itemContentToken(for: item)
            }
        }
        listController.setSections(
            sections,
            contentVersion: contentVersion,
            itemContentTokens: tokens,
            animatingDifferences: true
        )
    }

    func makeSections()
        -> [FireListSectionModel<FireNotificationsCollectionSection, FireNotificationsCollectionItem>]
    {
        var items: [FireNotificationsCollectionItem] = []

        if !notificationStore.hasLoadedRecentOnce {
            if let errorMessage = notificationStore.blockingRecentErrorMessage {
                items.append(.blockingError(errorMessage))
            } else {
                items.append(.loading)
            }
            return [.init(id: .content, items: items)]
        }

        if notificationStore.isRecentOffline {
            items.append(.offlineBanner)
        }

        if let errorMessage = notificationStore.recentNonBlockingErrorMessage {
            items.append(.inlineErrorBanner(errorMessage))
        }

        if notificationStore.recentNotifications.isEmpty {
            items.append(.empty)
        } else {
            items.append(contentsOf: notificationStore.recentNotifications.map { .notification($0.id) })
            items.append(.historyLink)
        }

        return [.init(id: .content, items: items)]
    }

    func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireNotificationsCollectionItem
    ) -> UICollectionViewCell {
        switch item {
        case .blockingError, .loading, .empty:
            return collectionView.dequeueConfiguredReusableCell(
                using: stateCellRegistration,
                for: indexPath,
                item: item
            )
        case .offlineBanner:
            return collectionView.dequeueConfiguredReusableCell(
                using: offlineCellRegistration,
                for: indexPath,
                item: item
            )
        case .inlineErrorBanner:
            return collectionView.dequeueConfiguredReusableCell(
                using: bannerCellRegistration,
                for: indexPath,
                item: item
            )
        case .notification:
            return collectionView.dequeueConfiguredReusableCell(
                using: notificationCellRegistration,
                for: indexPath,
                item: item
            )
        case .historyLink:
            return collectionView.dequeueConfiguredReusableCell(
                using: historyLinkCellRegistration,
                for: indexPath,
                item: item
            )
        }
    }

    func notification(id: UInt64) -> NotificationItemState? {
        notificationStore.recentNotifications.first { $0.id == id }
    }

    func itemContentToken(for item: FireNotificationsCollectionItem) -> AnyHashable {
        switch item {
        case let .blockingError(message), let .inlineErrorBanner(message):
            return AnyHashable(message)
        case .loading:
            return AnyHashable(notificationStore.isLoadingRecent)
        case .empty:
            return AnyHashable(notificationStore.hasLoadedRecentOnce)
        case .offlineBanner:
            return AnyHashable(notificationStore.isRecentOffline)
        case let .notification(id):
            guard let notification = notification(id: id) else {
                return AnyHashable("missing|\(id)")
            }
            return AnyHashable(FireNotificationItemContentToken(notification))
        case .historyLink:
            return AnyHashable(notificationStore.recentNotifications.count)
        }
    }
}
