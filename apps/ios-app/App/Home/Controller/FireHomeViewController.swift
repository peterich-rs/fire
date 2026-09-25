import Combine
import SwiftUI
import UIKit

@MainActor
final class FireHomeViewController: UIViewController {
    struct ContentVersion: Hashable {
        let allCategories: [FireTopicCategoryPresentation]
        let topTags: [String]
        let selectedTopicKind: TopicListKindState
        let selectedHomeCategoryId: UInt64?
        let selectedHomeTags: [String]
        let topicListDisplayState: FireHomeTopicListDisplayState
        let topicRowIDs: [UInt64]
        let currentScopeNextTopicsPage: UInt32?
        let hasAppendingFooter: Bool
    }

    static let paginationPrefetchDistance: CGFloat = 480

    let appViewModel: FireAppViewModel
    let navigationState: FireNavigationState
    let homeFeedStore: FireHomeFeedStore
    let searchStore: FireSearchStore
    let topicDetailStore: FireTopicDetailStore
    let controllerReference: FireHomeControllerReference
    let listController: FireListViewController<FireHomeCollectionSection, FireHomeCollectionItem>
    var topicRoutePresenter: FireTopicRoutePresenter
    var cancellables: Set<AnyCancellable> = []
    var refreshTask: Task<Void, Never>?
    var toastDismissTask: Task<Void, Never>?
    weak var toastView: UIView?
    weak var composerController: UIViewController?
    let offlineBannerView = FireHomeOfflineBannerView()
    var didPrefetchToFillViewport = false
    var lastTriggeredTopicsPage: UInt32?

    lazy var scopeStatusCellRegistration = UICollectionView.CellRegistration<
        FireHomeScopeStatusBarCell,
        FireHomeCollectionItem
    > { [weak self] cell, _, item in
        guard let self, item == .scopeStatus else { return }
        cell.configure(
            presentation: self.homeFeedStore.scopePresentation,
            actions: .init(
                onOpenCategoryDrawer: { [weak self] in
                    self?.presentCategoryDrawer()
                },
                onOpenSubcategoryPanel: { [weak self] in
                    self?.presentSubcategoryPanel()
                },
                onSelectKind: { [weak self] kind in
                    self?.homeFeedStore.selectTopicKind(kind)
                },
                onRemoveTag: { [weak self] tag in
                    self?.homeFeedStore.removeHomeTag(tag)
                },
                onClearFilters: { [weak self] in
                    self?.homeFeedStore.clearHomeScopeFilters()
                    if self?.homeFeedStore.selectedTopicKind != .latest {
                        self?.homeFeedStore.selectTopicKind(.latest)
                    }
                }
            )
        )
    }

    lazy var stateCellRegistration = UICollectionView.CellRegistration<
        FireTopicListStateCell,
        FireHomeCollectionItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        switch item {
        case let .blockingError(message):
            cell.configureBlockingError(
                title: "首页加载失败",
                message: message
            ) { [weak self] in
                self?.homeFeedStore.refreshTopics()
            }
        case .emptyState:
            cell.configureEmpty(
                title: "当前范围暂无话题",
                message: "下拉刷新，或点顶部范围胶囊切换分类 / 排序后再试。",
                systemImage: "tray"
            )
        case .appendingFooter:
            cell.configureLoadingMore()
        case .scopeStatus, .inlineErrorBanner, .topic, .loadingSkeleton:
            cell.configureEmpty()
        }
    }

    lazy var loadingSkeletonCellRegistration = UICollectionView.CellRegistration<
        FireHomeLoadingSkeletonCell,
        FireHomeCollectionItem
    > { cell, _, item in
        guard case .loadingSkeleton = item else { return }
        cell.configure()
    }

    lazy var bannerCellRegistration = UICollectionView.CellRegistration<
        FireTopicListErrorBannerCell,
        FireHomeCollectionItem
    > { [weak self] cell, _, item in
        guard case let .inlineErrorBanner(message) = item else { return }
        let isCloudflare = self?.homeFeedStore.topicLoadErrorIsCloudflare == true
        cell.configure(
            message: message,
            onCopy: { [weak self] in
                guard let self else { return }
                if isCloudflare {
                    Task { @MainActor in
                        do {
                            _ = try await self.appViewModel.performWithCloudflareRecovery(
                                operation: "首页手动 Cloudflare 验证",
                                originURL: URL(string: self.baseURLString)
                            ) {
                                true
                            }
                            self.homeFeedStore.clearTopicLoadError()
                            await self.homeFeedStore.refreshTopicsAsync()
                        } catch {
                            UIPasteboard.general.string = message
                        }
                    }
                } else {
                    UIPasteboard.general.string = message
                }
            },
            onDismiss: { [weak self] in
                self?.homeFeedStore.clearTopicLoadError()
            }
        )
    }

    lazy var topicCellRegistration = UICollectionView.CellRegistration<
        FireTopicListTopicCell,
        FireHomeCollectionItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        guard case let .topic(topicID) = item,
              let row = self.homeFeedStore.topicRow(for: topicID)
        else {
            cell.configureMissing()
            return
        }
        cell.configure(
            row: row,
            category: self.homeFeedStore.categoryPresentation(for: row.topic.categoryId),
            baseURLString: self.baseURLString,
            onEditBookmark: { [weak self] in
                self?.presentBookmarkEditor(for: row)
            },
            onDeleteBookmark: { [weak self] in
                self?.deleteBookmarkFromAction(for: row)
            }
        )
        cell.onAvatarTap = { [weak self] username in
            guard let self else { return }
            FireUserCard.present(from: self, viewModel: self.appViewModel, username: username)
        }
    }

    init(
        viewModel: FireAppViewModel,
        navigationState: FireNavigationState,
        homeFeedStore: FireHomeFeedStore,
        searchStore: FireSearchStore,
        topicDetailStore: FireTopicDetailStore,
        topicRoutePresenter: FireTopicRoutePresenter
    ) {
        self.appViewModel = viewModel
        self.navigationState = navigationState
        self.homeFeedStore = homeFeedStore
        self.searchStore = searchStore
        self.topicDetailStore = topicDetailStore
        self.topicRoutePresenter = topicRoutePresenter

        let controllerReference = FireHomeControllerReference()
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
                controllerReference.controller?.handleVisibleItemsChanged(items)
            },
            onPrefetchItems: { [controllerReference] items in
                controllerReference.controller?.handlePrefetchItems(items)
            },
            onScrollMetricsChanged: { [controllerReference] metrics in
                controllerReference.controller?.handleTopicListScrollMetricsChange(metrics)
            },
            onScrollActivityChanged: { scrolling in
                FireTopicListMetricEffectCoordinator.shared.setScrolling(scrolling)
            },
            onRefresh: { [homeFeedStore] in
                await homeFeedStore.refreshTopicsAsync()
            },
            contextMenuConfigurationProvider: { [controllerReference] item in
                controllerReference.controller?.contextMenuConfiguration(for: item)
            },
            updatePolicy: .deferDuringRefresh,
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
        refreshTask?.cancel()
        toastDismissTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "首页"
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.navigationBar.tintColor = FireTopicListPalette.accent
        view.tintColor = FireTopicListPalette.accent
        view.backgroundColor = FireTheme.uiCanvas
        configureToolbar()
        installListController()
        installOfflineBanner()
        bindState()
        render()
        syncOfflineBanner(animated: false)
        refreshTask = Task { [weak self] in
            await self?.homeFeedStore.refreshTopicsIfPossible(force: false)
        }
        consumePendingRouteIfVisible(navigationState.pendingRoute)
        consumePendingSearchQuery(navigationState.pendingSearchQuery)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.tintColor = FireTopicListPalette.accent
        homeFeedStore.setTopicListVisible(true)
        consumePendingRouteIfVisible(navigationState.pendingRoute)
        consumePendingSearchQuery(navigationState.pendingSearchQuery)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        homeFeedStore.setTopicListVisible(false)
    }

    func updateTopicRoutePresenter(_ presenter: FireTopicRoutePresenter) {
        topicRoutePresenter = presenter
    }

    func configureToolbar() {
        let drawerButton = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal"),
            style: .plain,
            target: self,
            action: #selector(categoryDrawerButtonTapped)
        )
        drawerButton.accessibilityLabel = "打开分类抽屉"
        drawerButton.tintColor = FireTopicListPalette.accent

        let createButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil"),
            style: .plain,
            target: self,
            action: #selector(createTopicButtonTapped)
        )
        createButton.accessibilityLabel = "创建新话题"
        createButton.tintColor = FireTopicListPalette.accent

        let searchButton = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass"),
            style: .plain,
            target: self,
            action: #selector(searchButtonTapped)
        )
        searchButton.accessibilityLabel = "搜索"
        searchButton.tintColor = FireTopicListPalette.accent

        navigationItem.leftBarButtonItem = drawerButton
        navigationItem.rightBarButtonItems = [searchButton, createButton]
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
        _ = scopeStatusCellRegistration
        _ = stateCellRegistration
        _ = loadingSkeletonCellRegistration
        _ = bannerCellRegistration
        _ = topicCellRegistration
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

    func installOfflineBanner() {
        offlineBannerView.alpha = 0
        offlineBannerView.isHidden = true
        offlineBannerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(offlineBannerView)
        NSLayoutConstraint.activate([
            offlineBannerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            offlineBannerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            offlineBannerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])
    }

    func bindState() {
        homeFeedStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.render()
                    self?.syncOfflineBanner(animated: true)
                }
            }
            .store(in: &cancellables)

        homeFeedStore.$selectedTopicKind
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.resetPaginationTracking()
            }
            .store(in: &cancellables)

        homeFeedStore.$selectedHomeCategoryId
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.resetPaginationTracking()
            }
            .store(in: &cancellables)

        homeFeedStore.$selectedHomeTags
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.resetPaginationTracking()
            }
            .store(in: &cancellables)

        homeFeedStore.$nextTopicsPage
            .dropFirst()
            .sink { [weak self] _ in
                self?.syncNextPageTracking()
            }
            .store(in: &cancellables)

        homeFeedStore.$topicLoadErrorMessage
            .dropFirst()
            .sink { [weak self] message in
                if message != nil {
                    self?.lastTriggeredTopicsPage = nil
                }
            }
            .store(in: &cancellables)

        homeFeedStore.$isOffline
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.syncOfflineBanner(animated: true)
            }
            .store(in: &cancellables)

        navigationState.$pendingRoute
            .receive(on: DispatchQueue.main)
            .sink { [weak self] route in
                self?.consumePendingRouteIfVisible(route)
            }
            .store(in: &cancellables)

        navigationState.$pendingSearchQuery
            .receive(on: DispatchQueue.main)
            .sink { [weak self] query in
                self?.consumePendingSearchQuery(query)
            }
            .store(in: &cancellables)

        navigationState.$selectedTab
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedTab in
                guard selectedTab == 0 else { return }
                guard let self else { return }
                self.consumePendingSearchQuery(self.navigationState.pendingSearchQuery)
                self.consumePendingRouteIfVisible(self.navigationState.pendingRoute)
            }
            .store(in: &cancellables)
    }

    var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var contentVersion: ContentVersion {
        ContentVersion(
            allCategories: homeFeedStore.allCategories,
            topTags: homeFeedStore.topTags,
            selectedTopicKind: homeFeedStore.selectedTopicKind,
            selectedHomeCategoryId: homeFeedStore.selectedHomeCategoryId,
            selectedHomeTags: homeFeedStore.selectedHomeTags,
            topicListDisplayState: homeFeedStore.topicListDisplayState,
            topicRowIDs: homeFeedStore.topicRows.map(\.topic.id),
            currentScopeNextTopicsPage: homeFeedStore.currentScopeNextTopicsPage,
            hasAppendingFooter: homeFeedStore.currentScopeNextTopicsPage != nil
                && homeFeedStore.isAppendingTopics
        )
    }
}

final class FireHomeControllerReference {
    weak var controller: FireHomeViewController?
}
