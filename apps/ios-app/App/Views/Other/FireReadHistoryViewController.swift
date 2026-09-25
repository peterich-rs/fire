import Combine
import SwiftUI
import UIKit

struct FireReadHistoryControllerHost: UIViewControllerRepresentable {
    @Environment(\.fireTopicRoutePresenter) var topicRoutePresenter
    @EnvironmentObject var topicDetailStore: FireTopicDetailStore

    let viewModel: FireAppViewModel

    func makeUIViewController(context: Context) -> FireReadHistoryViewController {
        FireReadHistoryViewController(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            topicRoutePresenter: topicRoutePresenter
        )
    }

    func updateUIViewController(
        _ uiViewController: FireReadHistoryViewController,
        context: Context
    ) {
        uiViewController.updateTopicRoutePresenter(topicRoutePresenter)
    }
}

@MainActor
final class FireReadHistoryViewController: UIViewController {
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
    let historyViewModel: FireReadHistoryViewModel
    let controllerReference: FireReadHistoryControllerReference
    let listController: FireListViewController<FireReadHistoryCollectionSection, FireReadHistoryCollectionItem>
    var topicRoutePresenter: FireTopicRoutePresenter
    var cancellables: Set<AnyCancellable> = []
    var loadTask: Task<Void, Never>?
    var toastDismissTask: Task<Void, Never>?
    weak var toastView: UIView?

    lazy var stateCellRegistration = UICollectionView.CellRegistration<
        FireTopicListStateCell,
        FireReadHistoryCollectionItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        switch item {
        case let .blockingError(message):
            cell.configureBlockingError(title: "浏览历史加载失败", message: message) { [weak self] in
                self?.loadTask = Task { [weak self] in
                    await self?.historyViewModel.refresh()
                }
            }
        case .loading:
            cell.configureLoading(title: "正在加载浏览历史")
        case .empty:
            cell.configureEmpty(
                title: "还没有浏览历史",
                message: "看过的话题会在这里继续接上次读到的位置。",
                systemImage: "clock.arrow.circlepath"
            )
        case .loadingMore:
            cell.configureLoadingMore()
        case .inlineErrorBanner, .topic:
            cell.configureEmpty()
        }
    }

    lazy var bannerCellRegistration = UICollectionView.CellRegistration<
        FireTopicListErrorBannerCell,
        FireReadHistoryCollectionItem
    > { [weak self] cell, _, item in
        guard case let .inlineErrorBanner(message) = item else { return }
        cell.configure(
            message: message,
            onCopy: {
                UIPasteboard.general.string = message
            },
            onDismiss: { [weak self] in
                self?.historyViewModel.clearErrorMessage()
            }
        )
    }

    lazy var topicCellRegistration = UICollectionView.CellRegistration<
        FireTopicListTopicCell,
        FireReadHistoryCollectionItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        guard case let .topic(topicID) = item,
              let row = self.historyViewModel.row(for: topicID)
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
        topicRoutePresenter: FireTopicRoutePresenter
    ) {
        self.appViewModel = viewModel
        self.topicDetailStore = topicDetailStore
        self.historyViewModel = FireReadHistoryViewModel(appViewModel: viewModel)
        let controllerReference = FireReadHistoryControllerReference()
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
            onRefresh: { [historyViewModel] in
                await historyViewModel.refresh()
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

        title = "浏览历史"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = FireTheme.uiCanvas

        installListController()
        bindViewModel()
        render()
        loadTask = Task { [weak self] in
            await self?.historyViewModel.loadIfNeeded()
        }
    }

}

final class FireReadHistoryControllerReference {
    weak var controller: FireReadHistoryViewController?
}
