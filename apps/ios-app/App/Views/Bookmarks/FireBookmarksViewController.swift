import Combine
import SwiftUI
import UIKit

struct FireBookmarksControllerHost: UIViewControllerRepresentable {
    @Environment(\.fireTopicRoutePresenter) var topicRoutePresenter
    @EnvironmentObject var topicDetailStore: FireTopicDetailStore

    let viewModel: FireAppViewModel
    let username: String

    func makeUIViewController(context: Context) -> FireBookmarksViewController {
        FireBookmarksViewController(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            username: username,
            topicRoutePresenter: topicRoutePresenter
        )
    }

    func updateUIViewController(
        _ uiViewController: FireBookmarksViewController,
        context: Context
    ) {
        uiViewController.updateTopicRoutePresenter(topicRoutePresenter)
    }
}

@MainActor
final class FireBookmarksViewController: UIViewController {
    struct ContentVersion: Hashable {
        let rows: [FireTopicRowPresentation]
        let nextPage: UInt32?
        let isLoading: Bool
        let isLoadingMore: Bool
        let hasLoadedOnce: Bool
        let errorMessage: String?
    }

    let appViewModel: FireAppViewModel
    let topicDetailStore: FireTopicDetailStore
    let bookmarksViewModel: FireBookmarksViewModel
    let controllerReference: FireBookmarksControllerReference
    let listController: FireListViewController<FireBookmarksCollectionSection, FireBookmarksCollectionItem>
    var topicRoutePresenter: FireTopicRoutePresenter
    var cancellables: Set<AnyCancellable> = []
    var loadTask: Task<Void, Never>?
    var toastDismissTask: Task<Void, Never>?
    weak var toastView: UIView?

    lazy var stateCellRegistration = UICollectionView.CellRegistration<
        FireTopicListStateCell,
        FireBookmarksCollectionItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        switch item {
        case let .blockingError(message):
            cell.configureBlockingError(message: message) { [weak self] in
                self?.loadTask = Task { [weak self] in
                    await self?.bookmarksViewModel.refresh()
                }
            }
        case .loading:
            cell.configureLoading()
        case .empty:
            cell.configureEmpty()
        case .loadingMore:
            cell.configureLoadingMore()
        case .inlineErrorBanner, .bookmark:
            cell.configureEmpty()
        }
    }

    lazy var bannerCellRegistration = UICollectionView.CellRegistration<
        FireTopicListErrorBannerCell,
        FireBookmarksCollectionItem
    > { [weak self] cell, _, item in
        guard case let .inlineErrorBanner(message) = item else { return }
        cell.configure(
            message: message,
            onCopy: {
                UIPasteboard.general.string = message
            },
            onDismiss: { [weak self] in
                self?.bookmarksViewModel.clearErrorMessage()
            }
        )
    }

    lazy var topicCellRegistration = UICollectionView.CellRegistration<
        FireTopicListTopicCell,
        FireBookmarksCollectionItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        guard case let .bookmark(rowID) = item,
              let row = self.bookmarksViewModel.row(for: rowID)
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
                self?.deleteBookmarkFromAction(for: row)
            }
        )
    }

    init(
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore,
        username: String,
        topicRoutePresenter: FireTopicRoutePresenter
    ) {
        self.appViewModel = viewModel
        self.topicDetailStore = topicDetailStore
        self.bookmarksViewModel = FireBookmarksViewModel(appViewModel: viewModel, username: username)
        let controllerReference = FireBookmarksControllerReference()
        self.controllerReference = controllerReference
        self.topicRoutePresenter = topicRoutePresenter
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
                controllerReference.controller?.loadMoreIfNeeded(from: items)
            },
            onScrollActivityChanged: { scrolling in
                FireTopicListMetricEffectCoordinator.shared.setScrolling(scrolling)
            },
            onRefresh: { [bookmarksViewModel] in
                await bookmarksViewModel.refresh()
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

        title = "我的书签"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = FireTheme.uiCanvas

        installListController()
        bindViewModel()
        render()
        loadTask = Task { [weak self] in
            await self?.bookmarksViewModel.loadIfNeeded()
        }
    }

}

final class FireBookmarksControllerReference {
    weak var controller: FireBookmarksViewController?
}
