import Combine
import SwiftUI
import UIKit

enum FirePrivateMessagesCollectionSection: Hashable {
    case controls
    case content
}

enum FirePrivateMessagesCollectionItem: Hashable {
    case mailboxPicker
    case inlineErrorBanner(String)
    case loading
    case blockingError(String)
    case empty
    case message(UInt64)
    case loadingMore
}

@MainActor
final class FirePrivateMessagesViewController: UIViewController {
    struct ContentVersion: Hashable {
        let selectedKind: String
        let renderedKind: String?
        let rowIDs: [UInt64]
        let userIDs: [UInt64]
        let isLoading: Bool
        let isLoadingMore: Bool
        let hasLoadedOnce: Bool
        let errorMessage: String?
    }

    struct ParticipantToken: Hashable {
        let userID: UInt64
        let username: String?
        let name: String?
        let avatarTemplate: String?
    }

    struct MessageContentToken: Hashable {
        let topicID: UInt64
        let title: String
        let replyCount: UInt32
        let excerptText: String?
        let activityTimestampUnixMs: UInt64?
        let participants: [ParticipantToken]
    }

    let appViewModel: FireAppViewModel
    let topicDetailStore: FireTopicDetailStore
    let mailboxViewModel: FirePrivateMessagesViewModel
    let controllerReference: FirePrivateMessagesControllerReference
    let listController: FireListViewController<
        FirePrivateMessagesCollectionSection,
        FirePrivateMessagesCollectionItem
    >
    var topicRoutePresenter: FireTopicRoutePresenter
    var cancellables: Set<AnyCancellable> = []
    var loadTask: Task<Void, Never>?
    var toastDismissTask: Task<Void, Never>?
    weak var toastView: UIView?

    lazy var pickerCellRegistration = UICollectionView.CellRegistration<
        FirePrivateMessagesPickerCell,
        FirePrivateMessagesCollectionItem
    > { [weak self] cell, _, _ in
        guard let self else { return }
        cell.configure(selectedKind: self.mailboxViewModel.selectedKind) { [weak self] kind in
            self?.loadTask = Task { [weak self] in
                await self?.mailboxViewModel.selectKind(kind)
            }
        }
    }

    lazy var stateCellRegistration = UICollectionView.CellRegistration<
        FireTopicListStateCell,
        FirePrivateMessagesCollectionItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        switch item {
        case let .blockingError(message):
            cell.configureBlockingError(title: "私信加载失败", message: message) { [weak self] in
                self?.loadTask = Task { [weak self] in
                    await self?.mailboxViewModel.refresh()
                }
            }
        case .loading:
            cell.configureLoading(title: "正在加载私信")
        case .empty:
            cell.configureEmpty(
                title: self.mailboxViewModel.selectedKind == .privateMessagesInbox ? "私信收件箱为空" : "还没有已发送私信",
                message: self.mailboxViewModel.selectedKind == .privateMessagesInbox
                    ? "新收到的私信会出现在这里。"
                    : "你发出的私信会出现在这里。",
                systemImage: "tray.2"
            )
        case .loadingMore:
            cell.configureLoadingMore()
        case .mailboxPicker, .inlineErrorBanner, .message:
            cell.configureEmpty()
        }
    }

    lazy var bannerCellRegistration = UICollectionView.CellRegistration<
        FireTopicListErrorBannerCell,
        FirePrivateMessagesCollectionItem
    > { [weak self] cell, _, item in
        guard case let .inlineErrorBanner(message) = item else { return }
        cell.configure(
            message: message,
            onCopy: { [weak self] in
                UIPasteboard.general.string = message
                self?.showToast("已复制错误", style: .success)
            },
            onDismiss: { [weak self] in
                self?.mailboxViewModel.errorMessage = nil
            }
        )
    }

    lazy var messageCellRegistration = UICollectionView.CellRegistration<
        FirePrivateMessageListCell,
        FirePrivateMessagesCollectionItem
    > { [weak self] cell, _, item in
        guard let self else { return }
        guard case let .message(topicID) = item,
              let row = self.row(topicID: topicID)
        else {
            cell.configureMissing()
            return
        }
        cell.configure(
            row: row,
            participants: self.resolvedParticipants(for: row.topic),
            currentUsername: self.currentUsername,
            baseURLString: self.baseURLString
        )
    }

    init(
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore,
        topicRoutePresenter: FireTopicRoutePresenter
    ) {
        self.appViewModel = viewModel
        self.topicDetailStore = topicDetailStore
        self.mailboxViewModel = FirePrivateMessagesViewModel(appViewModel: viewModel)
        self.topicRoutePresenter = topicRoutePresenter
        let controllerReference = FirePrivateMessagesControllerReference()
        self.controllerReference = controllerReference
        self.listController = FireListViewController(
            layout: FireCollectionLayouts.plainList(backgroundColor: FireTheme.uiCanvas),
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
            onRefresh: { [mailboxViewModel] in
                await mailboxViewModel.refresh()
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

        title = "私信"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil"),
            style: .plain,
            target: self,
            action: #selector(openComposer)
        )
        view.backgroundColor = FireTheme.uiCanvas

        installListController()
        bindViewModel()
        render()
        loadTask = Task { [weak self] in
            await self?.mailboxViewModel.loadIfNeeded()
        }
    }

}

final class FirePrivateMessagesControllerReference {
    weak var controller: FirePrivateMessagesViewController?
}
