import Combine
import UIKit

@MainActor
extension FireNotificationsViewController {
    func canSelect(_ item: FireNotificationsCollectionItem) -> Bool {
        switch item {
        case .notification, .historyLink:
            return true
        case .blockingError, .loading, .empty, .offlineBanner, .inlineErrorBanner:
            return false
        }
    }

    func handleSelection(_ item: FireNotificationsCollectionItem) {
        switch item {
        case let .notification(id):
            guard let notification = notification(id: id) else { return }
            open(notification)
        case .historyLink:
            let controller = FireNotificationHistoryViewController(
                viewModel: appViewModel,
                navigationState: navigationState,
                notificationStore: notificationStore,
                topicDetailStore: topicDetailStore
            )
            FireRootCoordinator.presentSecondary(controller)
        case .blockingError, .loading, .empty, .offlineBanner, .inlineErrorBanner:
            break
        }
    }

    func open(_ item: NotificationItemState) {
        if !item.read {
            notificationStore.markRead(id: item.id)
        }
        guard let route = item.appRoute else { return }
        presentRoute(route)
    }

    func presentRoute(_ route: FireAppRoute) {
        if route.isTopicRoute {
            appViewModel.topicRouteLogger()?.info("notifications tab presenting topic route \(route.diagnosticsSummary)")
            navigationState.presentTopicRoute(route)
            return
        }
        if route.presentsAsSecondaryPage {
            FireAppRouteControllerFactory.presentSecondaryRoute(
                route,
                viewModel: appViewModel,
                topicDetailStore: topicDetailStore
            )
            return
        }
    }

    func presentShareSheet(url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(
                x: view.bounds.midX,
                y: view.safeAreaInsets.top + 24,
                width: 1,
                height: 1
            )
        }
        present(controller, animated: true)
    }
}
