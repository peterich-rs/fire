import Combine
import UIKit

@MainActor
final class FireNotificationHistoryViewController: UIViewController {
    struct ContentVersion: Hashable {
        let unreadCount: Int
        let notifications: [FireNotificationItemContentToken]
        let nextOffset: UInt32?
        let isLoading: Bool
        let hasLoadedOnce: Bool
        let hasMore: Bool
        let shouldShowRetry: Bool
        let errorMessage: String?
        let isOffline: Bool
    }

    let appViewModel: FireAppViewModel
    let navigationState: FireNavigationState
    let notificationStore: FireNotificationStore
    let topicDetailStore: FireTopicDetailStore
    let controllerReference: FireNotificationHistoryControllerReference
    let listController: FireListViewController<FireNotificationHistoryCollectionSection, FireNotificationHistoryCollectionItem>
    var cancellables: Set<AnyCancellable> = []
    var loadTask: Task<Void, Never>?
    var toastDismissTask: Task<Void, Never>?
    weak var toastView: UIView?

    lazy var stateCellRegistration = UICollectionView.CellRegistration<
        FireTopicListStateCell,
        FireNotificationHistoryCollectionItem
    > { [weak self] cell, _, item in
        switch item {
        case let .blockingError(message):
            cell.configureBlockingError(title: "全部通知加载失败", message: message) { [weak self] in
                self?.loadTask = Task { [weak self] in
                    await self?.notificationStore.retryFullLoad()
                }
            }
        case .loading:
            cell.configureLoading(title: "正在加载全部通知")
        case .empty:
            cell.configureEmpty(
                title: "暂无通知",
                message: "完整通知历史为空。",
                systemImage: "bell.slash"
            )
        case .loadingMore:
            cell.configureLoadingMore()
        case .offlineBanner, .inlineErrorBanner, .notification, .retryFooter:
            cell.configureEmpty()
        }
    }

    lazy var bannerCellRegistration = UICollectionView.CellRegistration<
        FireTopicListErrorBannerCell,
        FireNotificationHistoryCollectionItem
    > { [weak self] cell, _, item in
        guard let self, case let .inlineErrorBanner(message) = item else { return }
        cell.configure(
            message: message,
            onCopy: {
                UIPasteboard.general.string = message
            },
            onDismiss: { [weak self] in
                self?.notificationStore.clearFullError()
            }
        )
    }

    lazy var offlineCellRegistration = UICollectionView.CellRegistration<
        FireNotificationInfoBannerCell,
        FireNotificationHistoryCollectionItem
    > { cell, _, _ in
        cell.configure(
            message: "正在显示离线通知缓存",
            systemImage: "wifi.slash",
            tintColor: .systemOrange
        )
    }

    lazy var notificationCellRegistration = UICollectionView.CellRegistration<
        FireNotificationListCell,
        FireNotificationHistoryCollectionItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        guard case let .notification(id) = item,
              let notification = self.notification(id: id)
        else {
            cell.configureMissing()
            return
        }
        cell.configure(item: notification, baseURLString: self.baseURLString)
    }

    lazy var retryCellRegistration = UICollectionView.CellRegistration<
        FireNotificationLinkCell,
        FireNotificationHistoryCollectionItem
    > { cell, _, _ in
        cell.configure(title: "重试加载更多", systemImage: "arrow.clockwise")
    }

    init(
        viewModel: FireAppViewModel,
        navigationState: FireNavigationState,
        notificationStore: FireNotificationStore,
        topicDetailStore: FireTopicDetailStore
    ) {
        self.appViewModel = viewModel
        self.navigationState = navigationState
        self.notificationStore = notificationStore
        self.topicDetailStore = topicDetailStore
        let controllerReference = FireNotificationHistoryControllerReference()
        self.controllerReference = controllerReference
        self.listController = FireListViewController(
            layout: FireCollectionLayouts.plainList(),
            backgroundColor: FireTheme.uiCanvas,
            onSelectItem: { [controllerReference] item in
                controllerReference.controller?.handleSelection(item)
            },
            canSelectItem: { [controllerReference] item in
                controllerReference.controller?.canSelect(item) ?? false
            },
            onVisibleItemsChanged: { [controllerReference] items in
                controllerReference.controller?.loadMoreIfNeeded(from: items)
            },
            onPrefetchItems: { [controllerReference] items in
                controllerReference.controller?.loadMoreIfNeeded(from: items)
            },
            onRefresh: { [notificationStore] in
                await notificationStore.loadFullPage(offset: nil)
            },
            contextMenuConfigurationProvider: { [controllerReference] item in
                controllerReference.controller?.contextMenuConfiguration(for: item)
            },
            cellProvider: { _, _, _ in UICollectionViewCell() }
        )
        super.init(nibName: nil, bundle: nil)
        controllerReference.controller = self
        prepareCellRegistrations()
        configureListController()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        toastDismissTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "全部通知"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = FireTheme.uiCanvas

        installListController()
        bindStore()
        render()
        loadTask = Task { [weak self] in
            await self?.notificationStore.loadFullPage(offset: nil)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateToolbar()
    }

}

final class FireNotificationHistoryControllerReference {
    weak var controller: FireNotificationHistoryViewController?
}
