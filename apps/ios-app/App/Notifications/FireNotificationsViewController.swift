import Combine
import UIKit

@MainActor
final class FireNotificationsViewController: UIViewController {
    struct ContentVersion: Hashable {
        let unreadCount: Int
        let notifications: [FireNotificationItemContentToken]
        let isLoading: Bool
        let hasLoadedOnce: Bool
        let errorMessage: String?
        let isOffline: Bool
    }

    let appViewModel: FireAppViewModel
    let navigationState: FireNavigationState
    let notificationStore: FireNotificationStore
    let topicDetailStore: FireTopicDetailStore
    let controllerReference: FireNotificationsControllerReference
    let listController: FireListViewController<FireNotificationsCollectionSection, FireNotificationsCollectionItem>
    var cancellables: Set<AnyCancellable> = []
    var loadTask: Task<Void, Never>?
    var toastDismissTask: Task<Void, Never>?
    weak var toastView: UIView?

    lazy var stateCellRegistration = UICollectionView.CellRegistration<
        FireTopicListStateCell,
        FireNotificationsCollectionItem
    > { [weak self] cell, _, item in
        switch item {
        case let .blockingError(message):
            cell.configureBlockingError(title: "通知加载失败", message: message) { [weak self] in
                self?.loadTask = Task { [weak self] in
                    await self?.notificationStore.loadRecent(force: true)
                }
            }
        case .loading:
            cell.configureLoading(title: "正在加载通知")
        case .empty:
            cell.configureEmpty(
                title: "暂无通知",
                message: "当有人回复、提及或点赞你的帖子时，通知会出现在这里。",
                systemImage: "bell.slash"
            )
        case .offlineBanner, .inlineErrorBanner, .notification, .historyLink:
            cell.configureEmpty()
        }
    }

    lazy var bannerCellRegistration = UICollectionView.CellRegistration<
        FireTopicListErrorBannerCell,
        FireNotificationsCollectionItem
    > { [weak self] cell, _, item in
        guard let self, case let .inlineErrorBanner(message) = item else { return }
        cell.configure(
            message: message,
            onCopy: {
                UIPasteboard.general.string = message
            },
            onDismiss: { [weak self] in
                self?.notificationStore.clearRecentError()
            }
        )
    }

    lazy var offlineCellRegistration = UICollectionView.CellRegistration<
        FireNotificationInfoBannerCell,
        FireNotificationsCollectionItem
    > { cell, _, _ in
        cell.configure(
            message: "正在显示离线通知缓存",
            systemImage: "wifi.slash",
            tintColor: .systemOrange
        )
    }

    lazy var notificationCellRegistration = UICollectionView.CellRegistration<
        FireNotificationListCell,
        FireNotificationsCollectionItem
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

    lazy var historyLinkCellRegistration = UICollectionView.CellRegistration<
        FireNotificationLinkCell,
        FireNotificationsCollectionItem
    > { cell, _, _ in
        cell.configure(title: "查看全部通知", systemImage: "chevron.right")
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
        let controllerReference = FireNotificationsControllerReference()
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
            onRefresh: { [notificationStore] in
                await notificationStore.loadRecent(force: true)
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

        title = "通知"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = FireTheme.uiCanvas

        installListController()
        bindStore()
        render()
        loadRecentIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateToolbar()
        loadRecentIfNeeded()
    }

}

final class FireNotificationsControllerReference {
    weak var controller: FireNotificationsViewController?
}
