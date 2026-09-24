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

    func configureListController() {
        listController.updateCellProvider { [weak self] collectionView, indexPath, item in
            guard let self else {
                return UICollectionViewCell()
            }
            return self.cell(collectionView: collectionView, indexPath: indexPath, item: item)
        }
        listController.updateContextMenuConfigurationProvider { [weak self] item in
            self?.contextMenuConfiguration(for: item)
        }
    }

    func prepareCellRegistrations() {
        _ = stateCellRegistration
        _ = offlineCellRegistration
        _ = bannerCellRegistration
        _ = notificationCellRegistration
        _ = historyLinkCellRegistration
    }

    func installListController() {
        addChild(listController)
        view.addSubview(listController.view)
        listController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            listController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listController.view.topAnchor.constraint(equalTo: view.topAnchor),
            listController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        listController.didMove(toParent: self)
    }

    func bindStore() {
        notificationStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.render()
                    self?.updateToolbar()
                }
            }
            .store(in: &cancellables)
    }

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

    func loadRecentIfNeeded() {
        guard !notificationStore.hasLoadedRecentOnce,
              !notificationStore.isLoadingRecent else { return }
        loadTask = Task { [weak self] in
            await self?.notificationStore.loadRecent(force: false)
        }
    }

    func updateToolbar() {
        guard notificationStore.unreadCount > 0 else {
            navigationItem.rightBarButtonItem = nil
            return
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "全部已读",
            style: .plain,
            target: self,
            action: #selector(markAllRead)
        )
    }

    @objc func markAllRead() {
        notificationStore.markAllRead()
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

    func contextMenuConfiguration(
        for item: FireNotificationsCollectionItem
    ) -> UIContextMenuConfiguration? {
        guard case let .notification(id) = item,
              let notification = notification(id: id)
        else {
            return nil
        }
        let shareURL = notification.fireShareURL(baseURL: baseURLString)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: self?.notificationMenuActions(item: notification, shareURL: shareURL) ?? [])
        }
    }

    func notificationMenuActions(
        item: NotificationItemState,
        shareURL: URL?
    ) -> [UIAction] {
        var actions: [UIAction] = [
            UIAction(title: "跳转到通知", image: UIImage(systemName: "arrow.up.right")) { [weak self] _ in
                self?.open(item)
            },
        ]

        if !item.read {
            actions.append(
                UIAction(title: "标记为已读", image: UIImage(systemName: "envelope.open")) { [weak self] _ in
                    self?.notificationStore.markRead(id: item.id)
                }
            )
        }

        actions.append(
            UIAction(title: "复制通知内容", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                UIPasteboard.general.string = item.displayDescription
                self?.showToast("已复制通知内容", style: .success)
            }
        )

        if let shareURL {
            actions.append(
                UIAction(title: "分享链接", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                    self?.presentShareSheet(url: shareURL)
                }
            )
            actions.append(
                UIAction(title: "复制链接", image: UIImage(systemName: "link")) { [weak self] _ in
                    UIPasteboard.general.string = shareURL.absoluteString
                    self?.showToast("已复制链接", style: .success)
                }
            )
        }

        return actions
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

    func showToast(_ message: String, style: FireTopicListToastView.Style) {
        toastDismissTask?.cancel()
        toastView?.removeFromSuperview()
        toastView = nil
        FireUIKitToast.show(message, style: FireUIKitToast.Style(style), in: view)
    }

}

final class FireNotificationsControllerReference {
    weak var controller: FireNotificationsViewController?
}
