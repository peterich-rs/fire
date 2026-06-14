import Combine
import SwiftUI
import UIKit

func fireHomeShouldRequestNextPage(
    nextTopicsPage: UInt32?,
    lastTriggeredTopicsPage: UInt32?,
    isLoadingTopics: Bool,
    metrics: FireCollectionScrollMetrics,
    paginationPrefetchDistance: CGFloat,
    didPrefetchToFillViewport: Bool
) -> Bool {
    guard let nextTopicsPage else {
        return false
    }
    guard !isLoadingTopics else {
        return false
    }

    let contentFitsViewport = metrics.contentHeight <= metrics.visibleHeight + 1
    if contentFitsViewport {
        guard !didPrefetchToFillViewport else {
            return false
        }
    } else {
        let isNearBottom = metrics.remainingDistanceToBottom <= paginationPrefetchDistance
        guard isNearBottom else {
            return false
        }
    }

    return lastTriggeredTopicsPage != nextTopicsPage
}

private enum FireHomeCollectionSection: Int, Hashable {
    case categoryTabs
    case feedSelector
    case tagChips
    case content
}

private enum FireHomeCollectionItem: Hashable {
    case categoryTabs
    case feedSelector
    case tagChips
    case blockingError(String)
    case inlineErrorBanner(String)
    case topic(UInt64)
    case loadingSkeleton(Int)
    case emptyState
    case appendingFooter
}

@MainActor
final class FireHomeViewController: UIViewController {
    private struct ContentVersion: Hashable {
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

    private static let paginationPrefetchDistance: CGFloat = 480

    private let appViewModel: FireAppViewModel
    private let navigationState: FireNavigationState
    private let homeFeedStore: FireHomeFeedStore
    private let searchStore: FireSearchStore
    private let topicDetailStore: FireTopicDetailStore
    private let controllerReference: FireHomeControllerReference
    private let listController: FireListViewController<FireHomeCollectionSection, FireHomeCollectionItem>
    private var topicRoutePresenter: FireTopicRoutePresenter
    private var cancellables: Set<AnyCancellable> = []
    private var refreshTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private weak var toastView: UIView?
    private weak var composerController: UIViewController?
    private let offlineBannerView = FireHomeOfflineBannerView()
    private var didPrefetchToFillViewport = false
    private var lastTriggeredTopicsPage: UInt32?

    private lazy var categoryTabsCellRegistration = UICollectionView.CellRegistration<
        FireHomeCategoryTabsCell,
        FireHomeCollectionItem
    > { [weak self] cell, _, item in
        guard let self, item == .categoryTabs else { return }
        cell.configure(
            parentCategories: self.parentCategories,
            selectedCategoryID: self.homeFeedStore.selectedHomeCategoryId,
            onSelectCategory: { [weak self] categoryID in
                self?.homeFeedStore.selectHomeCategory(categoryID)
            },
            onShowCategoryBrowser: { [weak self] in
                self?.presentCategoryBrowser()
            }
        )
    }

    private lazy var feedSelectorCellRegistration = UICollectionView.CellRegistration<
        FireHomeFeedSelectorCell,
        FireHomeCollectionItem
    > { [weak self] cell, _, item in
        guard let self, item == .feedSelector else { return }
        cell.configure(
            selectedKind: self.homeFeedStore.selectedTopicKind,
            onSelectKind: { [weak self] kind in
                self?.homeFeedStore.selectTopicKind(kind)
            }
        )
    }

    private lazy var tagChipsCellRegistration = UICollectionView.CellRegistration<
        FireHomeTagChipsCell,
        FireHomeCollectionItem
    > { [weak self] cell, _, item in
        guard let self, item == .tagChips else { return }
        cell.configure(
            selectedTags: self.homeFeedStore.selectedHomeTags,
            onShowTagPicker: { [weak self] in
                self?.presentTagPicker()
            },
            onRemoveTag: { [weak self] tag in
                self?.homeFeedStore.removeHomeTag(tag)
            }
        )
    }

    private lazy var stateCellRegistration = UICollectionView.CellRegistration<
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
                title: "当前 feed 暂无话题",
                message: "下拉刷新，或切换分类、排序、标签后再试。",
                systemImage: "tray"
            )
        case .appendingFooter:
            cell.configureLoadingMore()
        case .categoryTabs, .feedSelector, .tagChips, .inlineErrorBanner, .topic, .loadingSkeleton:
            cell.configureEmpty()
        }
    }

    private lazy var loadingSkeletonCellRegistration = UICollectionView.CellRegistration<
        FireHomeLoadingSkeletonCell,
        FireHomeCollectionItem
    > { cell, _, item in
        guard case .loadingSkeleton = item else { return }
        cell.configure()
    }

    private lazy var bannerCellRegistration = UICollectionView.CellRegistration<
        FireTopicListErrorBannerCell,
        FireHomeCollectionItem
    > { [weak self] cell, _, item in
        guard case let .inlineErrorBanner(message) = item else { return }
        cell.configure(
            message: message,
            onCopy: {
                UIPasteboard.general.string = message
            },
            onDismiss: { [weak self] in
                self?.homeFeedStore.clearTopicLoadError()
            }
        )
    }

    private lazy var topicCellRegistration = UICollectionView.CellRegistration<
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
            backgroundColor: .systemBackground,
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
        view.backgroundColor = .systemBackground
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

    private func configureToolbar() {
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

        navigationItem.rightBarButtonItems = [searchButton, createButton]
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

    private func prepareCellRegistrations() {
        _ = categoryTabsCellRegistration
        _ = feedSelectorCellRegistration
        _ = tagChipsCellRegistration
        _ = stateCellRegistration
        _ = loadingSkeletonCellRegistration
        _ = bannerCellRegistration
        _ = topicCellRegistration
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

    private func installOfflineBanner() {
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

    private func bindState() {
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

    private var parentCategories: [FireTopicCategoryPresentation] {
        homeFeedStore.allCategories.filter { $0.parentCategoryId == nil }
    }

    private var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    private var contentVersion: ContentVersion {
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

    private func render() {
        let sections = makeSections()
        var tokens: [FireHomeCollectionItem: AnyHashable] = [:]
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

    private func makeSections() -> [FireListSectionModel<FireHomeCollectionSection, FireHomeCollectionItem>] {
        var sections: [FireListSectionModel<FireHomeCollectionSection, FireHomeCollectionItem>] = [
            .init(id: .categoryTabs, items: [.categoryTabs]),
            .init(id: .feedSelector, items: [.feedSelector]),
        ]

        if !homeFeedStore.selectedHomeTags.isEmpty || !homeFeedStore.topTags.isEmpty {
            sections.append(.init(id: .tagChips, items: [.tagChips]))
        }

        let contentItems: [FireHomeCollectionItem]
        switch homeFeedStore.topicListDisplayState {
        case .loading:
            contentItems = (0..<6).map(FireHomeCollectionItem.loadingSkeleton)
        case let .blockingError(message):
            contentItems = [.blockingError(message)]
        case let .empty(nonBlockingErrorMessage):
            contentItems =
                (nonBlockingErrorMessage.map { [.inlineErrorBanner($0)] } ?? [])
                + [.emptyState]
        case let .content(nonBlockingErrorMessage):
            contentItems =
                (nonBlockingErrorMessage.map { [.inlineErrorBanner($0)] } ?? [])
                + homeFeedStore.topicRows.map { .topic($0.topic.id) }
                + (homeFeedStore.currentScopeNextTopicsPage != nil && homeFeedStore.isAppendingTopics
                    ? [.appendingFooter]
                    : [])
        }

        sections.append(.init(id: .content, items: contentItems))
        return sections
    }

    private func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireHomeCollectionItem
    ) -> UICollectionViewCell {
        switch item {
        case .categoryTabs:
            return collectionView.dequeueConfiguredReusableCell(
                using: categoryTabsCellRegistration,
                for: indexPath,
                item: item
            )
        case .feedSelector:
            return collectionView.dequeueConfiguredReusableCell(
                using: feedSelectorCellRegistration,
                for: indexPath,
                item: item
            )
        case .tagChips:
            return collectionView.dequeueConfiguredReusableCell(
                using: tagChipsCellRegistration,
                for: indexPath,
                item: item
            )
        case .blockingError, .emptyState, .appendingFooter:
            return collectionView.dequeueConfiguredReusableCell(
                using: stateCellRegistration,
                for: indexPath,
                item: item
            )
        case .loadingSkeleton:
            return collectionView.dequeueConfiguredReusableCell(
                using: loadingSkeletonCellRegistration,
                for: indexPath,
                item: item
            )
        case .inlineErrorBanner:
            return collectionView.dequeueConfiguredReusableCell(
                using: bannerCellRegistration,
                for: indexPath,
                item: item
            )
        case .topic:
            return collectionView.dequeueConfiguredReusableCell(
                using: topicCellRegistration,
                for: indexPath,
                item: item
            )
        }
    }

    private func canSelect(_ item: FireHomeCollectionItem) -> Bool {
        if case .topic = item {
            return true
        }
        return false
    }

    private func handleSelection(_ item: FireHomeCollectionItem) {
        guard case let .topic(topicID) = item else {
            appViewModel.topicRouteLogger()?.debug("home controller ignored selection item=\(String(describing: item))")
            return
        }
        guard let row = homeFeedStore.topicRow(for: topicID) else {
            appViewModel.topicRouteLogger()?.warning(
                "home controller selected missing topic row topic_id=\(topicID) visible_topic_count=\(homeFeedStore.visibleTopicIDs.count) row_count=\(homeFeedStore.topicRows.count)"
            )
            return
        }
        appViewModel.topicRouteLogger()?.info(
            "home controller selected topic topic_id=\(topicID) selected_kind=\(String(describing: homeFeedStore.selectedTopicKind)) selected_category_id=\(homeFeedStore.selectedHomeCategoryId.map(String.init) ?? "nil") selected_tag_count=\(homeFeedStore.selectedHomeTags.count) row_count=\(homeFeedStore.topicRows.count)"
        )
        presentRoute(.topic(row: row))
    }

    private func handleVisibleItemsChanged(_ items: [FireHomeCollectionItem]) {
        let visibleTopicIDs: Set<UInt64> = Set(items.compactMap { item in
            guard case let .topic(topicID) = item else { return nil }
            return topicID
        })
        homeFeedStore.updateVisibleTopicIDs(visibleTopicIDs)
    }

    private func handlePrefetchItems(_ items: [FireHomeCollectionItem]) {
        guard homeFeedStore.currentScopeNextTopicsPage != nil else { return }
        guard !homeFeedStore.isLoadingTopics else { return }

        if items.contains(.appendingFooter) {
            homeFeedStore.loadMoreTopics()
            return
        }

        let prefetchedTopicIDs = Set(items.compactMap { item -> UInt64? in
            guard case let .topic(topicID) = item else { return nil }
            return topicID
        })
        guard !prefetchedTopicIDs.isEmpty else { return }

        let rows = homeFeedStore.topicRows
        let prefetchThreshold = 5
        if let furthestIndex = rows.lastIndex(where: { prefetchedTopicIDs.contains($0.topic.id) }),
           rows.count - furthestIndex <= prefetchThreshold {
            homeFeedStore.loadMoreTopics()
        }
    }

    private func handleTopicListScrollMetricsChange(_ newMetrics: FireCollectionScrollMetrics) {
        guard fireHomeShouldRequestNextPage(
            nextTopicsPage: homeFeedStore.currentScopeNextTopicsPage,
            lastTriggeredTopicsPage: lastTriggeredTopicsPage,
            isLoadingTopics: homeFeedStore.isLoadingTopics,
            metrics: newMetrics,
            paginationPrefetchDistance: Self.paginationPrefetchDistance,
            didPrefetchToFillViewport: didPrefetchToFillViewport
        ) else {
            return
        }
        guard let nextTopicsPage = homeFeedStore.currentScopeNextTopicsPage else { return }

        if newMetrics.contentHeight <= newMetrics.visibleHeight + 1 {
            didPrefetchToFillViewport = true
        }
        lastTriggeredTopicsPage = nextTopicsPage
        homeFeedStore.loadMoreTopics()
    }

    private func contextMenuConfiguration(
        for item: FireHomeCollectionItem
    ) -> UIContextMenuConfiguration? {
        guard case let .topic(topicID) = item,
              let row = homeFeedStore.topicRow(for: topicID)
        else {
            return nil
        }
        let shareURL = row.fireTopicURL(baseURL: baseURLString)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: self?.topicMenuActions(row: row, shareURL: shareURL) ?? [])
        }
    }

    private func topicMenuActions(
        row: FireTopicRowPresentation,
        shareURL: URL
    ) -> [UIAction] {
        [
            UIAction(title: "打开话题", image: UIImage(systemName: "arrow.up.right")) { [weak self] _ in
                self?.presentRoute(.topic(row: row))
            },
            UIAction(
                title: row.topic.bookmarkId == nil ? "添加书签" : "编辑书签",
                image: UIImage(systemName: row.topic.bookmarkId == nil ? "bookmark" : "bookmark.fill")
            ) { [weak self] _ in
                self?.presentBookmarkEditor(for: row)
            },
            UIAction(title: "分享话题", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                self?.presentShareSheet(url: shareURL)
            },
            UIAction(title: "复制链接", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                UIPasteboard.general.string = shareURL.absoluteString
                self?.showToast("已复制链接", style: .success)
            },
            UIAction(title: "静音话题", image: UIImage(systemName: "bell.slash")) { [weak self] _ in
                self?.muteTopic(row)
            },
        ]
    }

    private func itemContentToken(for item: FireHomeCollectionItem) -> AnyHashable {
        switch item {
        case .categoryTabs:
            return AnyHashable(
                parentCategories.map { "\($0.id)|\($0.displayName)|\($0.colorHex ?? "")" }
                    .joined(separator: "\u{1F}")
                    + "|selected:\(homeFeedStore.selectedHomeCategoryId.map(String.init) ?? "all")"
            )
        case .feedSelector:
            return AnyHashable(homeFeedStore.selectedTopicKind)
        case .tagChips:
            return AnyHashable(
                (homeFeedStore.selectedHomeTags + homeFeedStore.topTags).joined(separator: "\u{1F}")
            )
        case let .blockingError(message), let .inlineErrorBanner(message):
            return AnyHashable(message)
        case let .topic(topicID):
            return AnyHashable(
                homeFeedStore.topicRowContentToken(for: topicID) ?? "missing|\(topicID)"
            )
        case let .loadingSkeleton(index):
            return AnyHashable(index)
        case .emptyState:
            return AnyHashable(homeFeedStore.topicListDisplayState)
        case .appendingFooter:
            return AnyHashable(homeFeedStore.isAppendingTopics)
        }
    }

    private func resetPaginationTracking() {
        didPrefetchToFillViewport = false
        lastTriggeredTopicsPage = nil
    }

    private func syncNextPageTracking() {
        guard let nextPage = homeFeedStore.currentScopeNextTopicsPage else {
            lastTriggeredTopicsPage = nil
            return
        }
        if let lastTriggeredTopicsPage,
           nextPage <= lastTriggeredTopicsPage {
            self.lastTriggeredTopicsPage = nil
        }
    }

    private func consumePendingRouteIfVisible(_ route: FireAppRoute?) {
        guard navigationState.selectedTab == 0, let route else {
            return
        }
        switch route {
        case .topic, .profile, .badge, .search:
            break
        case .notifications, .profileTab:
            return
        }
        presentRoute(route)
        navigationState.pendingRoute = nil
    }

    private func consumePendingSearchQuery(_ query: String?) {
        guard navigationState.selectedTab == 0,
              let query = query?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }
        presentSearch(initialQuery: query.isEmpty ? nil : query)
        navigationState.pendingSearchQuery = nil
    }

    private func presentRoute(_ route: FireAppRoute) {
        let logger = appViewModel.topicRouteLogger()
        logger?.debug("home controller present route requested \(route.diagnosticsSummary)")
        if case .search(let query) = route {
            logger?.debug("home controller routing search query_present=\(query != nil)")
            let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedQuery, !trimmedQuery.isEmpty {
                presentSearch(initialQuery: trimmedQuery)
            } else {
                presentSearch(initialQuery: nil)
            }
            navigationState.pendingSearchQuery = nil
            return
        }
        if topicRoutePresenter.present(route) {
            logger?.debug("home controller route handled by topic presenter \(route.diagnosticsSummary)")
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

    private func presentSearch(initialQuery: String?) {
        let presenter = FireAppRouteControllerFactory.makeTopicRoutePresenter(
            viewModel: appViewModel,
            topicDetailStore: topicDetailStore,
            navigationControllerProvider: { [weak navigationController] in navigationController }
        )
        let controller = FireSearchViewController(
            viewModel: appViewModel,
            searchStore: searchStore,
            topicDetailStore: topicDetailStore,
            initialQuery: initialQuery,
            topicRoutePresenter: presenter,
            fallbackRoutePresenter: { [weak self] route in
                self?.presentRoute(route)
            }
        )
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func createTopicButtonTapped() {
        presentCreateTopicComposer()
    }

    @objc private func searchButtonTapped() {
        presentSearch(initialQuery: nil)
    }

    private func presentCreateTopicComposer() {
        let composer = FireComposerViewController(
            viewModel: appViewModel,
            route: FireComposerRoute(kind: .createTopic),
            initialCategoryID: homeFeedStore.selectedHomeCategoryId,
            initialTags: homeFeedStore.selectedHomeTags,
            onSubmissionNotice: { [weak self] message in
                self?.showToast(message, style: .info)
            }
        )
        let navigationController = UINavigationController(rootViewController: composer)
        navigationController.modalPresentationStyle = .fullScreen
        composerController = navigationController
        present(navigationController, animated: true)
    }

    private func presentCategoryBrowser() {
        let rootView = FireCategoryBrowserSheet(viewModel: appViewModel)
            .environmentObject(homeFeedStore)
        let controller = UIHostingController(rootView: rootView)
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(controller, animated: true)
    }

    private func presentTagPicker() {
        let rootView = FireTagPickerSheet(viewModel: appViewModel)
            .environmentObject(homeFeedStore)
        let controller = UIHostingController(rootView: rootView)
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(controller, animated: true)
    }

    private func presentBookmarkEditor(for row: FireTopicRowPresentation) {
        let context = row.fireBookmarkEditorContext()
        let recoveryOriginURL = row.fireTopicURL(baseURL: baseURLString)
        let rootView = FireBookmarkEditorSheet(
            context: context,
            onSave: { [weak self] name, reminderAt in
                try await self?.saveBookmark(
                    context: context,
                    name: name,
                    reminderAt: reminderAt,
                    recoveryOriginURL: recoveryOriginURL
                )
            },
            onDelete: context.bookmarkID.map { bookmarkID in
                { [weak self] in
                    try await self?.deleteBookmark(
                        bookmarkID: bookmarkID,
                        recoveryOriginURL: recoveryOriginURL,
                        showSuccessToast: false
                    )
                }
            }
        )
        let controller = UIHostingController(rootView: rootView)
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(controller, animated: true)
    }

    private func saveBookmark(
        context: FireBookmarkEditorContext,
        name: String?,
        reminderAt: String?,
        recoveryOriginURL: URL
    ) async throws {
        if let bookmarkID = context.bookmarkID {
            try await appViewModel.topicInteraction.updateBookmark(
                bookmarkID: bookmarkID,
                name: name,
                reminderAt: reminderAt,
                recoveryOriginURL: recoveryOriginURL
            )
        } else {
            _ = try await appViewModel.topicInteraction.createBookmark(
                bookmarkableID: context.bookmarkableID,
                bookmarkableType: context.bookmarkableType,
                name: name,
                reminderAt: reminderAt,
                recoveryOriginURL: recoveryOriginURL
            )
        }
        await homeFeedStore.refreshTopicsAsync()
    }

    private func deleteBookmarkFromAction(for row: FireTopicRowPresentation) {
        guard let bookmarkID = row.topic.bookmarkId else { return }
        let recoveryOriginURL = row.fireTopicURL(baseURL: baseURLString)
        refreshTask = Task { [weak self] in
            do {
                try await self?.deleteBookmark(
                    bookmarkID: bookmarkID,
                    recoveryOriginURL: recoveryOriginURL,
                    showSuccessToast: true
                )
            } catch {
                self?.showToast(error.localizedDescription, style: .error)
            }
        }
    }

    private func deleteBookmark(
        bookmarkID: UInt64,
        recoveryOriginURL: URL,
        showSuccessToast: Bool
    ) async throws {
        try await appViewModel.topicInteraction.deleteBookmark(
            bookmarkID: bookmarkID,
            recoveryOriginURL: recoveryOriginURL
        )
        await homeFeedStore.refreshTopicsAsync()
        if showSuccessToast {
            showToast("已删除书签", style: .success)
        }
    }

    private func muteTopic(_ row: FireTopicRowPresentation) {
        refreshTask = Task { [weak self] in
            do {
                try await self?.appViewModel.topicInteraction.setTopicNotificationLevel(
                    topicID: row.topic.id,
                    notificationLevel: FireTopicNotificationLevelOption.muted.rawValue,
                    recoveryOriginURL: row.fireTopicURL(baseURL: self?.baseURLString ?? "https://linux.do")
                )
                self?.showToast("已静音话题", style: .success)
            } catch {
                self?.showToast(error.localizedDescription, style: .error)
            }
        }
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

    private func syncOfflineBanner(animated: Bool) {
        let shouldShow = homeFeedStore.isOffline
        let changes = {
            self.offlineBannerView.alpha = shouldShow ? 1 : 0
            self.offlineBannerView.transform = shouldShow
                ? .identity
                : CGAffineTransform(translationX: 0, y: -8)
        }

        if shouldShow {
            offlineBannerView.isHidden = false
        }

        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            if !shouldShow {
                self.offlineBannerView.isHidden = true
            }
        }

        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.curveEaseOut],
                animations: changes,
                completion: completion
            )
        } else {
            changes()
            completion(true)
        }
    }
}

private final class FireHomeCategoryTabsCell: UICollectionViewCell {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

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
        removeArrangedSubviews()
    }

    func configure(
        parentCategories: [FireTopicCategoryPresentation],
        selectedCategoryID: UInt64?,
        onSelectCategory: @escaping (UInt64?) -> Void,
        onShowCategoryBrowser: @escaping () -> Void
    ) {
        removeArrangedSubviews()
        stackView.addArrangedSubview(
            makeChipButton(
                title: "全部",
                imageName: nil,
                isSelected: selectedCategoryID == nil,
                tintColor: FireTopicListPalette.accent
            ) {
                onSelectCategory(nil)
            }
        )

        for category in parentCategories {
            let tintColor = UIColor(fireHomeHex: category.colorHex) ?? FireTopicListPalette.accent
            stackView.addArrangedSubview(
                makeChipButton(
                    title: category.displayName,
                    imageName: nil,
                    isSelected: selectedCategoryID == category.id,
                    tintColor: tintColor
                ) {
                    onSelectCategory(category.id)
                }
            )
        }

        let browserButton = makeChipButton(
            title: nil,
            imageName: "square.grid.2x2",
            isSelected: false,
            tintColor: .secondaryLabel,
            action: onShowCategoryBrowser
        )
        browserButton.accessibilityLabel = "浏览全部分类"
        stackView.addArrangedSubview(browserButton)
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 4,
            trailing: 16
        )

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 2),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -2),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -4),
        ])
    }
}

private final class FireHomeFeedSelectorCell: UICollectionViewCell {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

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
        removeArrangedSubviews()
    }

    func configure(
        selectedKind: TopicListKindState,
        onSelectKind: @escaping (TopicListKindState) -> Void
    ) {
        removeArrangedSubviews()
        for kind in TopicListKindState.orderedCases {
            stackView.addArrangedSubview(
                makeChipButton(
                    title: kind.title,
                    imageName: nil,
                    isSelected: selectedKind == kind,
                    tintColor: FireTopicListPalette.accent,
                    contentInsets: NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
                ) {
                    onSelectKind(kind)
                }
            )
        }
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 2,
            leading: 16,
            bottom: 4,
            trailing: 16
        )

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 2),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -2),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -4),
        ])
    }
}

private final class FireHomeTagChipsCell: UICollectionViewCell {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

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
        removeArrangedSubviews()
    }

    func configure(
        selectedTags: [String],
        onShowTagPicker: @escaping () -> Void,
        onRemoveTag: @escaping (String) -> Void
    ) {
        removeArrangedSubviews()
        let pickerButton = makeChipButton(
            title: "标签",
            imageName: "plus",
            isSelected: false,
            tintColor: FireTopicListPalette.accent,
            action: onShowTagPicker
        )
        pickerButton.accessibilityLabel = "添加标签"
        stackView.addArrangedSubview(pickerButton)

        for tag in selectedTags {
            stackView.addArrangedSubview(
                makeChipButton(
                    title: "#\(tag)",
                    imageName: "xmark",
                    imagePlacement: .trailing,
                    isSelected: true,
                    tintColor: FireTopicListPalette.accent
                ) {
                    onRemoveTag(tag)
                }
            )
        }
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 2,
            leading: 16,
            bottom: 6,
            trailing: 16
        )

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 2),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -2),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -4),
        ])
    }
}

private final class FireHomeLoadingSkeletonCell: UICollectionViewCell {
    private let avatarView = FireHomeSkeletonShapeView(cornerRadius: 19, fillColor: .tertiarySystemFill)
    private let titleBar = FireHomeSkeletonShapeView(cornerRadius: 4, fillColor: .tertiarySystemFill)
    private let subtitleBar = FireHomeSkeletonShapeView(cornerRadius: 4, fillColor: .quaternarySystemFill)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        isAccessibilityElement = false
        contentView.isAccessibilityElement = false
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 6,
            leading: 16,
            bottom: 6,
            trailing: 16
        )

        let bodyStack = UIStackView(arrangedSubviews: [titleBar, subtitleBar])
        bodyStack.axis = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 6
        bodyStack.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = UIStackView(arrangedSubviews: [avatarView, bodyStack])
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 38),
            avatarView.heightAnchor.constraint(equalToConstant: 38),
            titleBar.heightAnchor.constraint(equalToConstant: 14),
            titleBar.widthAnchor.constraint(equalTo: bodyStack.widthAnchor),
            subtitleBar.widthAnchor.constraint(equalToConstant: 100),
            subtitleBar.heightAnchor.constraint(equalToConstant: 10),
            rowStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }
}

private final class FireHomeSkeletonShapeView: UIView {
    private let shimmerLayer = CAGradientLayer()
    private var animatedWidth: CGFloat = 0

    init(cornerRadius: CGFloat, fillColor: UIColor) {
        super.init(frame: .zero)
        backgroundColor = fillColor
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true
        configureShimmerLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shimmerLayer.frame = bounds.insetBy(dx: -bounds.width, dy: 0)
        if window != nil,
           !UIAccessibility.isReduceMotionEnabled,
           abs(animatedWidth - bounds.width) > 0.5 {
            shimmerLayer.removeAnimation(forKey: "fire.home.skeleton.shimmer")
            startShimmering()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil || UIAccessibility.isReduceMotionEnabled {
            animatedWidth = 0
            shimmerLayer.removeAnimation(forKey: "fire.home.skeleton.shimmer")
        } else {
            startShimmering()
        }
    }

    private func configureShimmerLayer() {
        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmerLayer.locations = [0.35, 0.5, 0.65]
        shimmerLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(0.22).cgColor,
            UIColor.clear.cgColor,
        ]
        layer.addSublayer(shimmerLayer)
    }

    private func startShimmering() {
        guard bounds.width > 0 else {
            return
        }
        guard shimmerLayer.animation(forKey: "fire.home.skeleton.shimmer") == nil else {
            return
        }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = -bounds.width
        animation.toValue = bounds.width
        animation.duration = 1.15
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shimmerLayer.add(animation, forKey: "fire.home.skeleton.shimmer")
        animatedWidth = bounds.width
    }
}

private final class FireHomeOfflineBannerView: UIView {
    private let iconView = UIImageView(image: UIImage(systemName: "wifi.slash"))
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureSubviews() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 3)

        iconView.tintColor = .systemOrange
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        label.text = "当前网络不可用，显示已缓存内容"
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 2

        let stackView = UIStackView(arrangedSubviews: [iconView, label])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }
}

private final class FireHomeControllerReference {
    weak var controller: FireHomeViewController?
}

private extension UICollectionViewCell {
    func removeArrangedSubviews() {
        guard let stackView = contentView.subviews
            .compactMap({ view -> UIStackView? in
                if let stackView = view as? UIStackView {
                    return stackView
                }
                if let scrollView = view as? UIScrollView {
                    return scrollView.subviews.compactMap { $0 as? UIStackView }.first
                }
                return nil
            })
            .first
        else {
            return
        }

        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    func makeChipButton(
        title: String?,
        imageName: String?,
        imagePlacement: NSDirectionalRectEdge = .leading,
        isSelected: Bool,
        tintColor: UIColor,
        contentInsets: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(
            top: 7,
            leading: 14,
            bottom: 7,
            trailing: 14
        ),
        action: @escaping () -> Void
    ) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = imageName.flatMap { UIImage(systemName: $0) }
        configuration.imagePlacement = imagePlacement
        configuration.imagePadding = title == nil || imageName == nil ? 0 : 4
        configuration.contentInsets = contentInsets
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = isSelected
            ? tintColor
            : UIColor.tertiarySystemFill
        configuration.baseForegroundColor = isSelected
            ? .white
            : (imageName == nil ? .label : tintColor)

        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .caption1).withHomeWeight(.medium)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
}

private extension UIFont {
    func withHomeWeight(_ weight: Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

private extension UIColor {
    convenience init?(fireHomeHex hex: String?) {
        guard let hex else {
            return nil
        }
        let cleaned = hex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .uppercased()
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1
        )
    }
}
