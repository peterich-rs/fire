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
    private struct ContentVersion: Hashable {
        let selectedKind: String
        let renderedKind: String?
        let rowIDs: [UInt64]
        let userIDs: [UInt64]
        let isLoading: Bool
        let isLoadingMore: Bool
        let hasLoadedOnce: Bool
        let errorMessage: String?
    }

    private struct ParticipantToken: Hashable {
        let userID: UInt64
        let username: String?
        let name: String?
        let avatarTemplate: String?
    }

    private struct MessageContentToken: Hashable {
        let topicID: UInt64
        let title: String
        let replyCount: UInt32
        let excerptText: String?
        let activityTimestampUnixMs: UInt64?
        let participants: [ParticipantToken]
    }

    private let appViewModel: FireAppViewModel
    private let topicDetailStore: FireTopicDetailStore
    private let mailboxViewModel: FirePrivateMessagesViewModel
    private let controllerReference: FirePrivateMessagesControllerReference
    private let listController: FireListViewController<
        FirePrivateMessagesCollectionSection,
        FirePrivateMessagesCollectionItem
    >
    private var topicRoutePresenter: FireTopicRoutePresenter
    private var cancellables: Set<AnyCancellable> = []
    private var loadTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private weak var toastView: UIView?

    private lazy var pickerCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var stateCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var bannerCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var messageCellRegistration = UICollectionView.CellRegistration<
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

    func updateTopicRoutePresenter(_ presenter: FireTopicRoutePresenter) {
        topicRoutePresenter = presenter
    }

    private func configureListController() {
        listController.updateCellProvider { [weak self] collectionView, indexPath, item in
            guard let self else {
                return UICollectionViewCell()
            }
            return self.cell(collectionView: collectionView, indexPath: indexPath, item: item)
        }
    }

    private func prepareCellRegistrations() {
        _ = pickerCellRegistration
        _ = stateCellRegistration
        _ = bannerCellRegistration
        _ = messageCellRegistration
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

    private func bindViewModel() {
        mailboxViewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.render()
                }
            }
            .store(in: &cancellables)
    }

    private var currentUsername: String? {
        appViewModel.session.bootstrap.currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    private var usersByID: [UInt64: TopicUserState] {
        mailboxViewModel.displayedUsers.reduce(into: [:]) { partialResult, user in
            partialResult[user.id] = user
        }
    }

    private var contentVersion: ContentVersion {
        ContentVersion(
            selectedKind: Self.kindIdentifier(mailboxViewModel.selectedKind),
            renderedKind: mailboxViewModel.renderedKind.map(Self.kindIdentifier(_:)),
            rowIDs: mailboxViewModel.displayedRows.map(\.topic.id),
            userIDs: mailboxViewModel.displayedUsers.map(\.id),
            isLoading: mailboxViewModel.isLoading,
            isLoadingMore: mailboxViewModel.isLoadingMore,
            hasLoadedOnce: mailboxViewModel.hasLoadedOnce,
            errorMessage: mailboxViewModel.errorMessage
        )
    }

    private var nonBlockingErrorMessage: String? {
        switch mailboxViewModel.currentKindDisplayState {
        case .empty(let message), .content(let message):
            return message
        case .loading, .blockingError:
            return nil
        }
    }

    private func render() {
        let sections = makeSections()
        var tokens: [FirePrivateMessagesCollectionItem: AnyHashable] = [:]
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
        -> [FireListSectionModel<FirePrivateMessagesCollectionSection, FirePrivateMessagesCollectionItem>]
    {
        var sections: [FireListSectionModel<FirePrivateMessagesCollectionSection, FirePrivateMessagesCollectionItem>] = [
            .init(id: .controls, items: [.mailboxPicker]),
        ]

        var contentItems: [FirePrivateMessagesCollectionItem] = []
        if let errorMessage = nonBlockingErrorMessage {
            contentItems.append(.inlineErrorBanner(errorMessage))
        }

        switch mailboxViewModel.currentKindDisplayState {
        case .loading:
            contentItems.append(.loading)
        case let .blockingError(message):
            contentItems.append(.blockingError(message))
        case .empty:
            contentItems.append(.empty)
        case .content:
            contentItems.append(contentsOf: mailboxViewModel.displayedRows.map { .message($0.topic.id) })
            if mailboxViewModel.isLoadingMore {
                contentItems.append(.loadingMore)
            }
        }

        sections.append(.init(id: .content, items: contentItems))
        return sections
    }

    private func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FirePrivateMessagesCollectionItem
    ) -> UICollectionViewCell {
        switch item {
        case .mailboxPicker:
            return collectionView.dequeueConfiguredReusableCell(
                using: pickerCellRegistration,
                for: indexPath,
                item: item
            )
        case .inlineErrorBanner:
            return collectionView.dequeueConfiguredReusableCell(
                using: bannerCellRegistration,
                for: indexPath,
                item: item
            )
        case .loading, .blockingError, .empty, .loadingMore:
            return collectionView.dequeueConfiguredReusableCell(
                using: stateCellRegistration,
                for: indexPath,
                item: item
            )
        case .message:
            return collectionView.dequeueConfiguredReusableCell(
                using: messageCellRegistration,
                for: indexPath,
                item: item
            )
        }
    }

    private func itemContentToken(for item: FirePrivateMessagesCollectionItem) -> AnyHashable {
        switch item {
        case .mailboxPicker:
            return AnyHashable(mailboxViewModel.selectedKind)
        case let .inlineErrorBanner(message), let .blockingError(message):
            return AnyHashable(message)
        case .loading:
            return AnyHashable(mailboxViewModel.isLoading)
        case .empty:
            return AnyHashable("\(Self.kindIdentifier(mailboxViewModel.selectedKind))|\(mailboxViewModel.hasLoadedOnce)")
        case let .message(topicID):
            guard let row = row(topicID: topicID) else {
                return AnyHashable("missing|\(topicID)")
            }
            return AnyHashable(MessageContentToken(
                topicID: topicID,
                title: row.topic.title,
                replyCount: row.topic.replyCount,
                excerptText: row.excerptText,
                activityTimestampUnixMs: row.activityTimestampUnixMs,
                participants: resolvedParticipants(for: row.topic).map {
                    ParticipantToken(
                        userID: $0.userId,
                        username: $0.username,
                        name: $0.name,
                        avatarTemplate: $0.avatarTemplate
                    )
                }
            ))
        case .loadingMore:
            return AnyHashable(mailboxViewModel.isLoadingMore)
        }
    }

    private static func kindIdentifier(_ kind: TopicListKindState) -> String {
        String(describing: kind)
    }

    private func row(topicID: UInt64) -> TopicRowState? {
        mailboxViewModel.displayedRows.first { $0.topic.id == topicID }
    }

    private func canSelect(_ item: FirePrivateMessagesCollectionItem) -> Bool {
        if case .message = item {
            return true
        }
        return false
    }

    private func handleSelection(_ item: FirePrivateMessagesCollectionItem) {
        guard case let .message(topicID) = item,
              let row = row(topicID: topicID)
        else {
            return
        }
        presentRoute(.topic(row: row))
    }

    private func loadMoreIfNeeded(from items: [FirePrivateMessagesCollectionItem]) {
        guard let lastTopicID = mailboxViewModel.displayedRows.last?.topic.id else { return }
        guard items.contains(.message(lastTopicID)) || items.contains(.loadingMore) else { return }
        loadTask = Task { [weak self] in
            await self?.mailboxViewModel.loadMoreIfNeeded(currentTopicID: lastTopicID)
        }
    }

    private func resolvedParticipants(for topic: TopicSummaryState) -> [TopicParticipantState] {
        var merged: [TopicParticipantState] = []
        for participant in topic.participants {
            let resolvedUser = usersByID[participant.userId]
            let resolved = TopicParticipantState(
                userId: participant.userId,
                username: participant.username ?? resolvedUser?.username,
                name: participant.name,
                avatarTemplate: participant.avatarTemplate ?? resolvedUser?.avatarTemplate
            )
            let stableName = resolved.username?.lowercased() ?? "id:\(resolved.userId)"
            if merged.contains(where: {
                ($0.username?.lowercased() ?? "id:\($0.userId)") == stableName
            }) {
                continue
            }
            if let currentUsername, resolved.username?.caseInsensitiveCompare(currentUsername) == .orderedSame {
                continue
            }
            merged.append(resolved)
        }
        return merged
    }

    private func presentRoute(_ route: FireAppRoute) {
        if topicRoutePresenter.present(route) {
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
        // Already inside secondary stack: push local drill-down.
        if let navigationController {
            let controller = FireAppRouteControllerFactory.makeViewController(
                viewModel: appViewModel,
                topicDetailStore: topicDetailStore,
                route: route,
                topicRoutePresenter: topicRoutePresenter
            )
            navigationController.pushViewController(controller, animated: true)
        }
    }

    @objc private func openComposer() {
        let composer = FireComposerViewController(
            viewModel: appViewModel,
            route: FireComposerRoute(kind: .privateMessage(recipients: [], title: nil)),
            onPrivateMessageCreated: { [weak self] topicID, title in
                guard let self else { return }
                let route = FireAppRoute.topic(
                    topicId: topicID,
                    postNumber: nil,
                    preview: FireTopicRoutePreview.fromMetadata(title: title, slug: nil)
                )
                self.presentRoute(route)
                self.loadTask = Task { [weak self] in
                    await self?.mailboxViewModel.refresh()
                }
            },
            onSubmissionNotice: { [weak self] message in
                guard message.contains("等待审核") else { return }
                self?.showToast(message, style: .info)
            }
        )
        let navigationController = UINavigationController(rootViewController: composer)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }

    private func showToast(_ message: String, style: FireTopicListToastView.Style) {
        toastDismissTask?.cancel()
        toastView?.removeFromSuperview()
        toastView = nil
        FireUIKitToast.show(message, style: FireUIKitToast.Style(style), in: view)
    }
}

final class FirePrivateMessagesControllerReference {
    weak var controller: FirePrivateMessagesViewController?
}
