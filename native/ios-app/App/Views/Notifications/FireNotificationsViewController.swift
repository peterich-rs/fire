import Combine
import UIKit

enum FireNotificationsCollectionSection: Hashable {
    case content
}

enum FireNotificationsCollectionItem: Hashable {
    case blockingError(String)
    case loading
    case empty
    case offlineBanner
    case inlineErrorBanner(String)
    case notification(UInt64)
    case historyLink
}

enum FireNotificationHistoryCollectionSection: Hashable {
    case content
}

enum FireNotificationHistoryCollectionItem: Hashable {
    case blockingError(String)
    case loading
    case empty
    case offlineBanner
    case inlineErrorBanner(String)
    case notification(UInt64)
    case retryFooter
    case loadingMore
}

@MainActor
final class FireNotificationsViewController: UIViewController {
    private struct ContentVersion: Hashable {
        let unreadCount: Int
        let notifications: [FireNotificationItemContentToken]
        let isLoading: Bool
        let hasLoadedOnce: Bool
        let errorMessage: String?
        let isOffline: Bool
    }

    private let appViewModel: FireAppViewModel
    private let navigationState: FireNavigationState
    private let notificationStore: FireNotificationStore
    private let topicDetailStore: FireTopicDetailStore
    private let controllerReference: FireNotificationsControllerReference
    private let listController: FireListViewController<FireNotificationsCollectionSection, FireNotificationsCollectionItem>
    private var cancellables: Set<AnyCancellable> = []
    private var loadTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private weak var toastView: UIView?

    private lazy var stateCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var bannerCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var offlineCellRegistration = UICollectionView.CellRegistration<
        FireNotificationInfoBannerCell,
        FireNotificationsCollectionItem
    > { cell, _, _ in
        cell.configure(
            message: "正在显示离线通知缓存",
            systemImage: "wifi.slash",
            tintColor: .systemOrange
        )
    }

    private lazy var notificationCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var historyLinkCellRegistration = UICollectionView.CellRegistration<
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
            backgroundColor: .systemBackground,
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
        view.backgroundColor = .systemBackground

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

    private func configureListController() {
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

    private func installListController() {
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

    private func bindStore() {
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

    private var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    private var contentVersion: ContentVersion {
        ContentVersion(
            unreadCount: notificationStore.unreadCount,
            notifications: notificationStore.recentNotifications.map(FireNotificationItemContentToken.init),
            isLoading: notificationStore.isLoadingRecent,
            hasLoadedOnce: notificationStore.hasLoadedRecentOnce,
            errorMessage: notificationStore.recentErrorMessage,
            isOffline: notificationStore.isRecentOffline
        )
    }

    private func loadRecentIfNeeded() {
        guard !notificationStore.hasLoadedRecentOnce,
              !notificationStore.isLoadingRecent else { return }
        loadTask = Task { [weak self] in
            await self?.notificationStore.loadRecent(force: false)
        }
    }

    private func updateToolbar() {
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

    @objc private func markAllRead() {
        notificationStore.markAllRead()
    }

    private func render() {
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

    private func makeSections()
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

    private func cell(
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

    private func canSelect(_ item: FireNotificationsCollectionItem) -> Bool {
        switch item {
        case .notification, .historyLink:
            return true
        case .blockingError, .loading, .empty, .offlineBanner, .inlineErrorBanner:
            return false
        }
    }

    private func handleSelection(_ item: FireNotificationsCollectionItem) {
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
            navigationController?.pushViewController(controller, animated: true)
        case .blockingError, .loading, .empty, .offlineBanner, .inlineErrorBanner:
            break
        }
    }

    private func notification(id: UInt64) -> NotificationItemState? {
        notificationStore.recentNotifications.first { $0.id == id }
    }

    private func itemContentToken(for item: FireNotificationsCollectionItem) -> AnyHashable {
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

    private func contextMenuConfiguration(
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

    private func notificationMenuActions(
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

    private func open(_ item: NotificationItemState) {
        if !item.read {
            notificationStore.markRead(id: item.id)
        }
        guard let route = item.appRoute else { return }
        presentRoute(route)
    }

    private func presentRoute(_ route: FireAppRoute) {
        if route.isTopicRoute {
            appViewModel.topicRouteLogger()?.info("notifications tab presenting topic route \(route.diagnosticsSummary)")
            navigationState.presentTopicRoute(route)
            return
        }

        guard let navigationController else { return }
        let presenter = FireAppRouteControllerFactory.makeTopicRoutePresenter(
            viewModel: appViewModel,
            topicDetailStore: topicDetailStore,
            navigationControllerProvider: { [weak navigationController] in navigationController }
        )
        let controller = FireAppRouteControllerFactory.makeViewController(
            viewModel: appViewModel,
            topicDetailStore: topicDetailStore,
            route: route,
            topicRoutePresenter: presenter
        )
        navigationController.pushViewController(controller, animated: true)
    }

    private func presentShareSheet(url: URL) {
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

    private func showToast(_ message: String, style: FireTopicListToastView.Style) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        toastDismissTask?.cancel()
        toastView?.removeFromSuperview()

        let toast = FireTopicListToastView(message: message, style: style)
        view.addSubview(toast)
        toast.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toast.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            toast.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            toast.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
        ])
        toastView = toast
        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: -8)
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            toast.alpha = 1
            toast.transform = .identity
        }

        toastDismissTask = Task { [weak self, weak toast] in
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                guard let self, self.toastView === toast else { return }
                self.hideToast()
            }
        }
    }

    private func hideToast() {
        guard let toast = toastView else { return }
        toastView = nil
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn]) {
            toast.alpha = 0
            toast.transform = CGAffineTransform(translationX: 0, y: -8)
        } completion: { _ in
            toast.removeFromSuperview()
        }
    }
}

@MainActor
final class FireNotificationHistoryViewController: UIViewController {
    private struct ContentVersion: Hashable {
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

    private let appViewModel: FireAppViewModel
    private let navigationState: FireNavigationState
    private let notificationStore: FireNotificationStore
    private let topicDetailStore: FireTopicDetailStore
    private let controllerReference: FireNotificationHistoryControllerReference
    private let listController: FireListViewController<FireNotificationHistoryCollectionSection, FireNotificationHistoryCollectionItem>
    private var cancellables: Set<AnyCancellable> = []
    private var loadTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private weak var toastView: UIView?

    private lazy var stateCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var bannerCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var offlineCellRegistration = UICollectionView.CellRegistration<
        FireNotificationInfoBannerCell,
        FireNotificationHistoryCollectionItem
    > { cell, _, _ in
        cell.configure(
            message: "正在显示离线通知缓存",
            systemImage: "wifi.slash",
            tintColor: .systemOrange
        )
    }

    private lazy var notificationCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var retryCellRegistration = UICollectionView.CellRegistration<
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
            backgroundColor: .systemBackground,
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
        view.backgroundColor = .systemBackground

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

    private func configureListController() {
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

    private func installListController() {
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

    private func bindStore() {
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

    private var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    private var contentVersion: ContentVersion {
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

    private func updateToolbar() {
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

    @objc private func markAllRead() {
        notificationStore.markAllRead()
    }

    private func render() {
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

    private func makeSections()
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

    private func cell(
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

    private func canSelect(_ item: FireNotificationHistoryCollectionItem) -> Bool {
        switch item {
        case .notification, .retryFooter:
            return true
        case .blockingError, .loading, .empty, .offlineBanner, .inlineErrorBanner, .loadingMore:
            return false
        }
    }

    private func handleSelection(_ item: FireNotificationHistoryCollectionItem) {
        switch item {
        case let .notification(id):
            guard let notification = notification(id: id) else { return }
            open(notification)
        case .retryFooter:
            loadTask = Task { [weak self] in
                await self?.notificationStore.retryFullLoad()
            }
        case .blockingError, .loading, .empty, .offlineBanner, .inlineErrorBanner, .loadingMore:
            break
        }
    }

    private func notification(id: UInt64) -> NotificationItemState? {
        notificationStore.fullNotifications.first { $0.id == id }
    }

    private func loadMoreIfNeeded(from items: [FireNotificationHistoryCollectionItem]) {
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

    private func itemContentToken(for item: FireNotificationHistoryCollectionItem) -> AnyHashable {
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

    private func contextMenuConfiguration(
        for item: FireNotificationHistoryCollectionItem
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

    private func notificationMenuActions(
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

    private func open(_ item: NotificationItemState) {
        if !item.read {
            notificationStore.markRead(id: item.id)
        }
        guard let route = item.appRoute else { return }
        presentRoute(route)
    }

    private func presentRoute(_ route: FireAppRoute) {
        if route.isTopicRoute {
            appViewModel.topicRouteLogger()?.info("notification history presenting topic route \(route.diagnosticsSummary)")
            navigationState.presentTopicRoute(route)
            return
        }

        guard let navigationController else { return }
        let presenter = FireAppRouteControllerFactory.makeTopicRoutePresenter(
            viewModel: appViewModel,
            topicDetailStore: topicDetailStore,
            navigationControllerProvider: { [weak navigationController] in navigationController }
        )
        let controller = FireAppRouteControllerFactory.makeViewController(
            viewModel: appViewModel,
            topicDetailStore: topicDetailStore,
            route: route,
            topicRoutePresenter: presenter
        )
        navigationController.pushViewController(controller, animated: true)
    }

    private func presentShareSheet(url: URL) {
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

    private func showToast(_ message: String, style: FireTopicListToastView.Style) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        toastDismissTask?.cancel()
        toastView?.removeFromSuperview()

        let toast = FireTopicListToastView(message: message, style: style)
        view.addSubview(toast)
        toast.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toast.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            toast.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            toast.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
        ])
        toastView = toast
        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: -8)
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            toast.alpha = 1
            toast.transform = .identity
        }

        toastDismissTask = Task { [weak self, weak toast] in
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                guard let self, self.toastView === toast else { return }
                self.hideToast()
            }
        }
    }

    private func hideToast() {
        guard let toast = toastView else { return }
        toastView = nil
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn]) {
            toast.alpha = 0
            toast.transform = CGAffineTransform(translationX: 0, y: -8)
        } completion: { _ in
            toast.removeFromSuperview()
        }
    }
}

final class FireNotificationListCell: UICollectionViewCell {
    private let unreadDot = UIView()
    private let avatarContainer = UIView()
    private let avatarView = FireTopicListAvatarView()
    private let iconView = UIImageView()
    private let descriptionLabel = UILabel()
    private let timestampLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
        iconView.image = nil
        timestampLabel.text = nil
        backgroundConfiguration = .clear()
    }

    func configureMissing() {
        avatarView.prepareForReuse()
        descriptionLabel.text = nil
        timestampLabel.text = nil
        iconView.image = nil
        unreadDot.backgroundColor = .clear
        isAccessibilityElement = false
    }

    func configure(item: NotificationItemState, baseURLString: String) {
        let timestamp = FireTopicPresentation.compactTimestamp(item.createdAt)
            ?? FireTopicPresentation.compactTimestamp(unixMs: item.createdTimestampUnixMs)
        let avatarTemplate = item.actingUserAvatarTemplate ?? item.data.avatarTemplate
        let username = item.resolvedUsername ?? "?"

        unreadDot.backgroundColor = item.read ? .clear : FireTopicListPalette.accent
        descriptionLabel.text = item.displayDescription
        descriptionLabel.font = Self.descriptionFont(isRead: item.read)
        descriptionLabel.textColor = item.read ? .secondaryLabel : .label
        timestampLabel.text = timestamp

        if let avatarTemplate, !avatarTemplate.isEmpty {
            avatarContainer.backgroundColor = .clear
            iconView.isHidden = true
            avatarView.isHidden = false
            avatarView.configure(
                username: username,
                avatarTemplate: avatarTemplate,
                baseURLString: baseURLString
            )
        } else {
            avatarView.prepareForReuse()
            avatarView.isHidden = true
            iconView.isHidden = false
            avatarContainer.backgroundColor = item.typeIconUIColor.withAlphaComponent(0.12)
            iconView.image = UIImage(systemName: item.typeSystemImage)
            iconView.tintColor = item.typeIconUIColor
        }

        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = item.read
            ? .clear
            : FireTopicListPalette.accent.withAlphaComponent(0.03)
        backgroundConfiguration = background

        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = Self.accessibilitySummary(item: item, timestamp: timestamp)
        accessibilityHint = "双击打开通知"
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 10,
            leading: 16,
            bottom: 10,
            trailing: 16
        )

        unreadDot.layer.cornerRadius = 3.5
        unreadDot.translatesAutoresizingMaskIntoConstraints = false
        unreadDot.setContentHuggingPriority(.required, for: .horizontal)

        avatarContainer.clipsToBounds = true
        avatarContainer.layer.cornerRadius = 17
        avatarContainer.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.setContentHuggingPriority(.required, for: .horizontal)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        descriptionLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.numberOfLines = 3
        descriptionLabel.lineBreakMode = .byTruncatingTail

        timestampLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        timestampLabel.adjustsFontForContentSizeCategory = true
        timestampLabel.textColor = .tertiaryLabel
        timestampLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [descriptionLabel, timestampLabel])
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = UIStackView(arrangedSubviews: [unreadDot, avatarContainer, textStack])
        rowStack.axis = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        avatarContainer.addSubview(avatarView)
        avatarContainer.addSubview(iconView)
        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            unreadDot.widthAnchor.constraint(equalToConstant: 7),
            unreadDot.heightAnchor.constraint(equalToConstant: 7),
            avatarContainer.widthAnchor.constraint(equalToConstant: 34),
            avatarContainer.heightAnchor.constraint(equalToConstant: 34),
            avatarView.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
            avatarView.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor),
            avatarView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            avatarView.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),
            iconView.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            rowStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    private static func descriptionFont(isRead: Bool) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: .subheadline)
        let weight: UIFont.Weight = isRead ? .regular : .semibold
        return UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont.systemFont(ofSize: base.pointSize, weight: weight)
        )
    }

    private static func accessibilitySummary(
        item: NotificationItemState,
        timestamp: String?
    ) -> String {
        var parts = [item.displayDescription]
        if let timestamp {
            parts.append(timestamp)
        }
        parts.append(item.read ? "已读" : "未读")
        return parts.joined(separator: "，")
    }
}

final class FireNotificationInfoBannerCell: UICollectionViewCell {
    private let containerView = UIView()
    private let iconView = UIImageView()
    private let messageLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        message: String,
        systemImage: String,
        tintColor: UIColor
    ) {
        messageLabel.text = message
        iconView.image = UIImage(systemName: systemImage)
        iconView.tintColor = tintColor
        containerView.backgroundColor = tintColor.withAlphaComponent(0.10)
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 8,
            trailing: 16
        )

        containerView.layer.cornerRadius = 8
        containerView.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        messageLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .label
        messageLabel.numberOfLines = 2

        let stackView = UIStackView(arrangedSubviews: [iconView, messageLabel])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(containerView)
        containerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            containerView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
        ])
    }
}

final class FireNotificationLinkCell: UICollectionViewCell {
    private let label = UILabel()
    private let iconView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, systemImage: String) {
        label.text = title
        iconView.image = UIImage(systemName: systemImage)
        accessibilityLabel = title
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 8,
            trailing: 16
        )

        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = FireTopicListPalette.accent
        label.numberOfLines = 1

        iconView.tintColor = FireTopicListPalette.accent
        iconView.contentMode = .scaleAspectFit

        let stackView = UIStackView(arrangedSubviews: [label, iconView])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let centeredStack = UIStackView(arrangedSubviews: [UIView(), stackView, UIView()])
        centeredStack.axis = .horizontal
        centeredStack.alignment = .center
        centeredStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(centeredStack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            centeredStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            centeredStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            centeredStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            centeredStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])

        isAccessibilityElement = true
        accessibilityTraits = [.button]
    }
}

private struct FireNotificationItemContentToken: Hashable {
    let id: UInt64
    let read: Bool
    let highPriority: Bool
    let description: String
    let timestamp: String?
    let avatarTemplate: String?
    let typeSystemImage: String
    let routeID: String?

    init(_ item: NotificationItemState) {
        id = item.id
        read = item.read
        highPriority = item.highPriority
        description = item.displayDescription
        timestamp = FireTopicPresentation.compactTimestamp(item.createdAt)
            ?? FireTopicPresentation.compactTimestamp(unixMs: item.createdTimestampUnixMs)
        avatarTemplate = item.actingUserAvatarTemplate ?? item.data.avatarTemplate
        typeSystemImage = item.typeSystemImage
        routeID = item.appRoute?.id
    }
}

private final class FireNotificationsControllerReference {
    weak var controller: FireNotificationsViewController?
}

private final class FireNotificationHistoryControllerReference {
    weak var controller: FireNotificationHistoryViewController?
}
