import Combine
import SwiftUI
import UIKit

@MainActor
final class FireSearchViewController: UIViewController {
    struct ContentVersion: Hashable {
        let query: String
        let scope: FireSearchScope
        let resultTopics: [UInt64]
        let resultPosts: [UInt64]
        let resultUsers: [UInt64]
        let isSearching: Bool
        let isAppending: Bool
        let errorMessage: String?
        let canLoadMoreResults: Bool
    }

    let appViewModel: FireAppViewModel
    let searchStore: FireSearchStore
    let topicDetailStore: FireTopicDetailStore
    let initialQuery: String?
    let controllerReference: FireSearchControllerReference
    let headerView = FireSearchHeaderView()
    let listController: FireListViewController<FireSearchCollectionSection, FireSearchCollectionItem>
    var topicRoutePresenter: FireTopicRoutePresenter
    var fallbackRoutePresenter: ((FireAppRoute) -> Void)?
    var cancellables: Set<AnyCancellable> = []
    var actionTask: Task<Void, Never>?
    var toastDismissTask: Task<Void, Never>?
    weak var toastView: UIView?

    lazy var stateCellRegistration = UICollectionView.CellRegistration<
        FireTopicListStateCell,
        FireSearchCollectionItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        switch item {
        case .placeholder:
            cell.configureEmpty(
                title: "搜索 LinuxDo",
                message: "输入关键词搜索话题、帖子或用户。",
                systemImage: "text.magnifyingglass"
            )
        case .loading:
            cell.configureLoading(title: "搜索中")
        case let .blockingError(message):
            cell.configureBlockingError(
                title: "搜索失败",
                message: message
            ) { [weak self] in
                self?.searchStore.submit(reset: true)
            }
        case .empty:
            cell.configureEmpty(
                title: "没有找到相关结果",
                message: "调整关键词或搜索范围后再试。",
                systemImage: "magnifyingglass"
            )
        case .inlineErrorBanner, .sectionHeader, .topic, .post, .user, .loadMore:
            cell.configureEmpty()
        }
    }

    lazy var bannerCellRegistration = UICollectionView.CellRegistration<
        FireTopicListErrorBannerCell,
        FireSearchCollectionItem
    > { [weak self] cell, _, item in
        guard case let .inlineErrorBanner(message) = item else { return }
        cell.configure(
            message: message,
            onCopy: {
                UIPasteboard.general.string = message
            },
            onDismiss: { [weak self] in
                self?.searchStore.clearErrors()
            }
        )
    }

    lazy var sectionHeaderCellRegistration = UICollectionView.CellRegistration<
        FireSearchSectionHeaderCell,
        FireSearchCollectionItem
    > { cell, _, item in
        guard case let .sectionHeader(title) = item else { return }
        cell.configure(title: title)
    }

    lazy var topicCellRegistration = UICollectionView.CellRegistration<
        FireTopicListTopicCell,
        FireSearchCollectionItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        guard case let .topic(topicID) = item,
              let topic = self.topic(for: topicID)
        else {
            cell.configureMissing()
            return
        }
        let row = self.topicRow(for: topic)
        cell.configure(
            row: row,
            category: self.appViewModel.categoryPresentation(for: topic.categoryId),
            baseURLString: self.baseURLString,
            onEditBookmark: { [weak self] in
                self?.presentBookmarkEditor(for: row)
            },
            onDeleteBookmark: {}
        )
    }

    lazy var postCellRegistration = UICollectionView.CellRegistration<
        FireSearchPostResultCell,
        FireSearchCollectionItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        guard case let .post(postID) = item,
              let post = self.post(for: postID)
        else {
            cell.configureMissing()
            return
        }
        let row = self.postRow(for: post, topicIndex: self.topicIndex)
        cell.configure(post: post, row: row)
    }

    lazy var userCellRegistration = UICollectionView.CellRegistration<
        FireSearchUserResultCell,
        FireSearchCollectionItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        guard case let .user(userID) = item,
              let user = self.user(for: userID)
        else {
            cell.configureMissing()
            return
        }
        cell.configure(
            user: user,
            baseURLString: self.baseURLString
        )
    }

    lazy var loadMoreCellRegistration = UICollectionView.CellRegistration<
        FireSearchLoadMoreCell,
        FireSearchCollectionItem
    > { [weak self] cell, _, item in
        guard let self, item == .loadMore else { return }
        cell.configure(
            isLoading: self.searchStore.isAppending,
            isEnabled: !self.searchStore.isSearching && !self.searchStore.isAppending
        ) { [weak self] in
            self?.searchStore.submit(reset: false)
        }
    }

    init(
        viewModel: FireAppViewModel,
        searchStore: FireSearchStore,
        topicDetailStore: FireTopicDetailStore,
        initialQuery: String?,
        topicRoutePresenter: FireTopicRoutePresenter,
        fallbackRoutePresenter: ((FireAppRoute) -> Void)? = nil
    ) {
        self.appViewModel = viewModel
        self.searchStore = searchStore
        self.topicDetailStore = topicDetailStore
        self.initialQuery = initialQuery
        self.topicRoutePresenter = topicRoutePresenter
        self.fallbackRoutePresenter = fallbackRoutePresenter

        let controllerReference = FireSearchControllerReference()
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
            onPrefetchItems: { [controllerReference] items in
                controllerReference.controller?.handlePrefetchItems(items)
            },
            onScrollActivityChanged: { scrolling in
                FireTopicListMetricEffectCoordinator.shared.setScrolling(scrolling)
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
        actionTask?.cancel()
        toastDismissTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Search owns a custom header (field + scope). Hide system title chrome so we don't
        // stack a nav bar strip above the search field (login-style double-top).
        title = nil
        navigationItem.title = nil
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = FireTheme.uiCanvas
        installHeaderView()
        installListController()
        bindState()
        configureHeader()

        searchStore.reset()
        if let initialQuery = initialQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
           !initialQuery.isEmpty {
            searchStore.prepareSearch(query: initialQuery)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.headerView.focusSearchField()
            }
        }
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateSearchChromeForPresentation(animated: animated)
    }

    func updateTopicRoutePresenter(_ presenter: FireTopicRoutePresenter) {
        topicRoutePresenter = presenter
    }

    func updateFallbackRoutePresenter(_ presenter: ((FireAppRoute) -> Void)?) {
        fallbackRoutePresenter = presenter
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
        _ = bannerCellRegistration
        _ = sectionHeaderCellRegistration
        _ = topicCellRegistration
        _ = postCellRegistration
        _ = userCellRegistration
        _ = loadMoreCellRegistration
    }

    func installHeaderView() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
        ])
    }

    func installListController() {
        addChild(listController)
        view.addSubview(listController.view)
        listController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            listController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listController.view.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            listController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        listController.didMove(toParent: self)
    }

    func configureHeader() {
        headerView.configure(
            query: searchStore.query,
            scope: searchStore.scope,
            onQueryChanged: { [weak self] query in
                self?.searchStore.query = query
            },
            onSubmit: { [weak self] in
                self?.searchStore.submit(reset: true)
            },
            onClear: { [weak self] in
                self?.searchStore.reset()
                self?.headerView.focusSearchField()
            },
            onScopeChanged: { [weak self] scope in
                self?.searchStore.setScope(scope)
            }
        )
    }

    func updateSearchChromeForPresentation(animated: Bool) {
        let navigation = navigationController
        let isRoot = navigation?.viewControllers.first === self
        let isSecondaryHost = (navigation as? FireMainNavigationController)?.allowsInteractiveDismissWhenAtRoot == true

        if isSecondaryHost, isRoot {
            navigation?.setNavigationBarHidden(true, animated: animated)
            headerView.setShowsBackButton(true) { [weak self] in
                self?.navigationController?.dismiss(animated: true)
            }
        } else {
            navigation?.setNavigationBarHidden(false, animated: animated)
            headerView.setShowsBackButton(false, onBack: nil)
        }
    }

    func bindState() {
        searchStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.headerView.update(
                        query: self?.searchStore.query ?? "",
                        scope: self?.searchStore.scope ?? .all
                    )
                    self?.render()
                }
            }
            .store(in: &cancellables)
    }

    var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var topicIndex: [UInt64: SearchTopicState] {
        guard let result = searchStore.result else { return [:] }
        return Dictionary(
            result.topics.map { ($0.id, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
    }

    var contentVersion: ContentVersion {
        let result = searchStore.result
        return ContentVersion(
            query: searchStore.query,
            scope: searchStore.scope,
            resultTopics: result?.topics.map(\.id) ?? [],
            resultPosts: result?.posts.map(\.id) ?? [],
            resultUsers: result?.users.map(\.id) ?? [],
            isSearching: searchStore.isSearching,
            isAppending: searchStore.isAppending,
            errorMessage: searchStore.errorMessage,
            canLoadMoreResults: searchStore.canLoadMoreResults
        )
    }
}

final class FireSearchControllerReference {
    weak var controller: FireSearchViewController?
}
