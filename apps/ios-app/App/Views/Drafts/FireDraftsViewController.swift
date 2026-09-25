import Combine
import SwiftUI
import UIKit

enum FireDraftsCollectionSection: Hashable {
    case content
}

enum FireDraftsCollectionItem: Hashable {
    case blockingError(String)
    case loading
    case empty
    case inlineErrorBanner(String)
    case draft(String)
    case loadingMore
}

@MainActor
final class FireDraftsViewController: UIViewController {
    struct ContentVersion: Hashable {
        let drafts: [FireDraftContentToken]
        let hasMore: Bool
        let isLoading: Bool
        let isLoadingMore: Bool
        let hasLoadedOnce: Bool
        let errorMessage: String?
    }

    let appViewModel: FireAppViewModel
    let draftsViewModel: FireDraftsViewModel
    let controllerReference: FireDraftsControllerReference
    let listController: FireListViewController<FireDraftsCollectionSection, FireDraftsCollectionItem>
    var cancellables: Set<AnyCancellable> = []
    var loadTask: Task<Void, Never>?
    var toastDismissTask: Task<Void, Never>?
    weak var toastView: UIView?

    lazy var stateCellRegistration = UICollectionView.CellRegistration<
        FireTopicListStateCell,
        FireDraftsCollectionItem
    > { [weak self] cell, _, item in
        switch item {
        case let .blockingError(message):
            cell.configureBlockingError(title: "草稿加载失败", message: message) { [weak self] in
                self?.loadTask = Task { [weak self] in
                    await self?.draftsViewModel.refresh()
                }
            }
        case .loading:
            cell.configureLoading(title: "正在加载草稿")
        case .empty:
            cell.configureEmpty(
                title: "草稿箱是空的",
                message: "这里会保留未发出的新话题和完整回复。",
                systemImage: "tray.full"
            )
        case .loadingMore:
            cell.configureLoadingMore()
        case .inlineErrorBanner, .draft:
            cell.configureEmpty()
        }
    }

    lazy var bannerCellRegistration = UICollectionView.CellRegistration<
        FireTopicListErrorBannerCell,
        FireDraftsCollectionItem
    > { [weak self] cell, _, item in
        guard case let .inlineErrorBanner(message) = item else { return }
        cell.configure(
            message: message,
            onCopy: {
                UIPasteboard.general.string = message
            },
            onDismiss: { [weak self] in
                self?.draftsViewModel.clearErrorMessage()
            }
        )
    }

    lazy var draftCellRegistration = UICollectionView.CellRegistration<
        FireDraftListCell,
        FireDraftsCollectionItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        guard case let .draft(key) = item,
              let draft = self.draft(key: key)
        else {
            cell.configureMissing()
            return
        }
        cell.configure(
            draft: draft,
            route: draft.fireComposerRoute(),
            onOpen: { [weak self] in
                self?.open(draft)
            },
            onDelete: { [weak self] in
                self?.delete(draft)
            }
        )
    }

    init(viewModel: FireAppViewModel) {
        self.appViewModel = viewModel
        self.draftsViewModel = FireDraftsViewModel(appViewModel: viewModel)
        let controllerReference = FireDraftsControllerReference()
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
            onRefresh: { [draftsViewModel] in
                await draftsViewModel.refresh()
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

        title = "草稿箱"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = FireTheme.uiCanvas

        installListController()
        bindViewModel()
        render()
        loadTask = Task { [weak self] in
            await self?.draftsViewModel.loadIfNeeded()
        }
    }

}

final class FireDraftsControllerReference {
    weak var controller: FireDraftsViewController?
}
