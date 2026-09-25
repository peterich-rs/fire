import Combine
import SwiftUI
import UIKit

// MARK: - SwiftUI host (category browser NavigationLink)

// MARK: - Collection model

enum FireFilteredTopicSection: Int, Hashable {
    case feedSelector
    case content
}

enum FireFilteredTopicItem: Hashable {
    case feedSelector
    case blockingError(String)
    case inlineErrorBanner(String)
    case loadingSkeleton(Int)
    case empty
    case topic(UInt64)
    case loadingMore
}

// MARK: - View controller

@MainActor
final class FireFilteredTopicListViewController: UIViewController {
    struct ContentVersion: Hashable {
        let selectedKind: TopicListKindState
        let rows: [UInt64]
        let nextPage: UInt32?
        let isLoading: Bool
        let isLoadingMore: Bool
        let hasResolved: Bool
        let errorMessage: String?
        let displayState: FireScopedTopicListDisplayState
    }

    let appViewModel: FireAppViewModel
    let topicDetailStore: FireTopicDetailStore
    let listViewModel: FireFilteredTopicListViewModel
    let listTitle: String
    let controllerReference = FireFilteredTopicListControllerReference()
    let listController: FireListViewController<FireFilteredTopicSection, FireFilteredTopicItem>
    var topicRoutePresenter: FireTopicRoutePresenter
    var cancellables: Set<AnyCancellable> = []
    var loadTask: Task<Void, Never>?

    lazy var feedSelectorCellRegistration = UICollectionView.CellRegistration<
        FireFilteredFeedSelectorCell,
        FireFilteredTopicItem
    > { [weak self] cell, _, item in
        guard let self, item == .feedSelector else { return }
        cell.configure(
            selectedKind: self.listViewModel.selectedKind,
            onSelectKind: { [weak self] kind in
                self?.loadTask = Task { [weak self] in
                    await self?.listViewModel.selectKind(kind)
                }
            }
        )
    }

    lazy var stateCellRegistration = UICollectionView.CellRegistration<
        FireTopicListStateCell,
        FireFilteredTopicItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        switch item {
        case let .blockingError(message):
            cell.configureBlockingError(
                title: "列表加载失败",
                message: message
            ) { [weak self] in
                self?.loadTask = Task { [weak self] in
                    await self?.listViewModel.refresh()
                }
            }
        case .empty:
            cell.configureEmpty(
                title: "暂无话题",
                message: "当前筛选条件下还没有话题。",
                systemImage: "tray"
            )
        case .loadingMore:
            cell.configureLoadingMore()
        case .loadingSkeleton, .feedSelector, .inlineErrorBanner, .topic:
            cell.configureLoading()
        }
    }

    lazy var skeletonCellRegistration = UICollectionView.CellRegistration<
        FireHomeStyleSkeletonCell,
        FireFilteredTopicItem
    > { cell, _, _ in
        cell.configure()
    }

    lazy var bannerCellRegistration = UICollectionView.CellRegistration<
        FireTopicListErrorBannerCell,
        FireFilteredTopicItem
    > { [weak self] cell, _, item in
        guard case let .inlineErrorBanner(message) = item else { return }
        cell.configure(
            message: message,
            onCopy: { UIPasteboard.general.string = message },
            onDismiss: { [weak self] in
                self?.listViewModel.errorMessage = nil
            }
        )
    }

    lazy var topicCellRegistration = UICollectionView.CellRegistration<
        FireTopicListTopicCell,
        FireFilteredTopicItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        guard case let .topic(topicID) = item,
              let row = self.listViewModel.displayedRows.first(where: { $0.topic.id == topicID })
        else {
            cell.configureMissing()
            return
        }
        cell.configure(
            row: row,
            category: self.appViewModel.categoryPresentation(for: row.topic.categoryId),
            baseURLString: self.baseURLString,
            onEditBookmark: { [weak self] in
                self?.presentBookmarkEditor(for: row)
            },
            onDeleteBookmark: { [weak self] in
                self?.deleteBookmark(for: row)
            }
        )
    }

    init(
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore,
        title: String,
        categorySlug: String?,
        categoryId: UInt64?,
        parentCategorySlug: String?,
        tag: String?,
        topicRoutePresenter: FireTopicRoutePresenter
    ) {
        self.appViewModel = viewModel
        self.topicDetailStore = topicDetailStore
        self.listTitle = title
        self.topicRoutePresenter = topicRoutePresenter
        self.listViewModel = FireFilteredTopicListViewModel(
            appViewModel: viewModel,
            categorySlug: categorySlug,
            categoryId: categoryId,
            parentCategorySlug: parentCategorySlug,
            tag: tag
        )
        let reference = controllerReference
        self.listController = FireListViewController(
            layout: FireCollectionLayouts.plainList(),
            backgroundColor: FireTheme.uiCanvas,
            onSelectItem: { [reference] item in
                reference.controller?.handleSelection(item)
            },
            canSelectItem: { [reference] item in
                reference.controller?.canSelect(item) ?? false
            },
            onVisibleItemsChanged: { [reference] items in
                reference.controller?.handleVisibleItemsChanged(items)
            },
            onPrefetchItems: { [reference] items in
                reference.controller?.handleVisibleItemsChanged(items)
            },
            onScrollActivityChanged: { scrolling in
                FireTopicListMetricEffectCoordinator.shared.setScrolling(scrolling)
            },
            onRefresh: { [listViewModel] in
                await listViewModel.refresh()
            },
            cellProvider: { _, _, _ in UICollectionViewCell() }
        )
        super.init(nibName: nil, bundle: nil)
        reference.controller = self
        prepareCellRegistrations()
        configureListController()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = listTitle
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = FireTheme.uiCanvas
        view.tintColor = FireTheme.uiAccent
        navigationController?.navigationBar.tintColor = FireTheme.uiAccent

        installListController()
        bindViewModel()
        render()
        loadTask = Task { [weak self] in
            await self?.listViewModel.loadIfNeeded()
        }
    }

}

// MARK: - Supporting cells

/// Shared-style skeleton matching home feed placeholder geometry.
final class FireFilteredTopicListControllerReference {
    weak var controller: FireFilteredTopicListViewController?
}
