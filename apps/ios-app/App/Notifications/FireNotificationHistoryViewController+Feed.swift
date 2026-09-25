import Combine
import UIKit

@MainActor
extension FireNotificationHistoryViewController {
    var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var contentVersion: ContentVersion {
        ContentVersion(
            unreadCount: notificationStore.unreadCount,
            notifications: notificationStore.fullNotifications.map(FireNotificationItemContentToken.init),
            nextOffset: notificationStore.fullNextOffset,
            isLoading: notificationStore.isLoadingFullPage,
            hasLoadedOnce: notificationStore.hasLoadedFullOnce,
            hasMore: notificationStore.hasMoreFull,
            shouldShowRetry: notificationStore.shouldShowFullPaginationRetry,
            errorMessage: notificationStore.fullErrorMessage,
            isOffline: notificationStore.isFullOffline
        )
    }

    func render() {
        let sections = makeSections()
        var tokens: [FireNotificationHistoryCollectionItem: AnyHashable] = [:]
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
        -> [FireListSectionModel<FireNotificationHistoryCollectionSection, FireNotificationHistoryCollectionItem>]
    {
        var items: [FireNotificationHistoryCollectionItem] = []

        if let errorMessage = notificationStore.blockingFullErrorMessage {
            items.append(.blockingError(errorMessage))
            return [.init(id: .content, items: items)]
        }

        if !notificationStore.hasLoadedFullOnce,
           notificationStore.fullNotifications.isEmpty {
            items.append(.loading)
            return [.init(id: .content, items: items)]
        }

        if notificationStore.isFullOffline {
            items.append(.offlineBanner)
        }

        if let errorMessage = notificationStore.fullNonBlockingErrorMessage {
            items.append(.inlineErrorBanner(errorMessage))
        }

        if notificationStore.fullNotifications.isEmpty {
            items.append(.empty)
        } else {
            items.append(contentsOf: notificationStore.fullNotifications.map { .notification($0.id) })

            if notificationStore.shouldShowFullPaginationRetry {
                items.append(.retryFooter)
            } else if notificationStore.hasMoreFull {
                items.append(.loadingMore)
            }
        }

        return [.init(id: .content, items: items)]
    }

    func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireNotificationHistoryCollectionItem
    ) -> UICollectionViewCell {
        switch item {
        case .blockingError, .loading, .empty, .loadingMore:
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
        case .retryFooter:
            return collectionView.dequeueConfiguredReusableCell(
                using: retryCellRegistration,
                for: indexPath,
                item: item
            )
        }
    }

    func notification(id: UInt64) -> NotificationItemState? {
        notificationStore.fullNotifications.first { $0.id == id }
    }

    func itemContentToken(for item: FireNotificationHistoryCollectionItem) -> AnyHashable {
        switch item {
        case let .blockingError(message), let .inlineErrorBanner(message):
            return AnyHashable(message)
        case .loading:
            return AnyHashable(notificationStore.isLoadingFullPage)
        case .empty:
            return AnyHashable(notificationStore.hasLoadedFullOnce)
        case .offlineBanner:
            return AnyHashable(notificationStore.isFullOffline)
        case let .notification(id):
            guard let notification = notification(id: id) else {
                return AnyHashable("missing|\(id)")
            }
            return AnyHashable(FireNotificationItemContentToken(notification))
        case .retryFooter:
            return AnyHashable(notificationStore.shouldShowFullPaginationRetry)
        case .loadingMore:
            return AnyHashable(notificationStore.fullNextOffset)
        }
    }
}
