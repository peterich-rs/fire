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
    private struct ContentVersion: Hashable {
        let drafts: [FireDraftContentToken]
        let hasMore: Bool
        let isLoading: Bool
        let isLoadingMore: Bool
        let hasLoadedOnce: Bool
        let errorMessage: String?
    }

    private let appViewModel: FireAppViewModel
    private let draftsViewModel: FireDraftsViewModel
    private let controllerReference: FireDraftsControllerReference
    private let listController: FireListViewController<FireDraftsCollectionSection, FireDraftsCollectionItem>
    private var cancellables: Set<AnyCancellable> = []
    private var loadTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private weak var toastView: UIView?

    private lazy var stateCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var bannerCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var draftCellRegistration = UICollectionView.CellRegistration<
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
        _ = stateCellRegistration
        _ = bannerCellRegistration
        _ = draftCellRegistration
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
        draftsViewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.render()
                }
            }
            .store(in: &cancellables)
    }

    private var contentVersion: ContentVersion {
        ContentVersion(
            drafts: draftsViewModel.drafts.map(FireDraftContentToken.init),
            hasMore: draftsViewModel.hasMore,
            isLoading: draftsViewModel.isLoading,
            isLoadingMore: draftsViewModel.isLoadingMore,
            hasLoadedOnce: draftsViewModel.hasLoadedOnce,
            errorMessage: draftsViewModel.errorMessage
        )
    }

    private func render() {
        let sections = makeSections()
        var tokens: [FireDraftsCollectionItem: AnyHashable] = [:]
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

    private func makeSections() -> [FireListSectionModel<FireDraftsCollectionSection, FireDraftsCollectionItem>] {
        var items: [FireDraftsCollectionItem] = []

        if !draftsViewModel.hasLoadedOnce {
            if let errorMessage = draftsViewModel.errorMessage {
                items.append(.blockingError(errorMessage))
            } else {
                items.append(.loading)
            }
            return [.init(id: .content, items: items)]
        }

        if let errorMessage = draftsViewModel.errorMessage {
            items.append(.inlineErrorBanner(errorMessage))
        }

        if draftsViewModel.drafts.isEmpty {
            items.append(.empty)
        } else {
            items.append(contentsOf: draftsViewModel.drafts.map { .draft($0.draftKey) })
            if draftsViewModel.isLoadingMore {
                items.append(.loadingMore)
            }
        }

        return [.init(id: .content, items: items)]
    }

    private func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireDraftsCollectionItem
    ) -> UICollectionViewCell {
        switch item {
        case .blockingError, .loading, .empty, .loadingMore:
            return collectionView.dequeueConfiguredReusableCell(
                using: stateCellRegistration,
                for: indexPath,
                item: item
            )
        case .inlineErrorBanner:
            return collectionView.dequeueConfiguredReusableCell(
                using: bannerCellRegistration,
                for: indexPath,
                item: item
            )
        case .draft:
            return collectionView.dequeueConfiguredReusableCell(
                using: draftCellRegistration,
                for: indexPath,
                item: item
            )
        }
    }

    private func canSelect(_ item: FireDraftsCollectionItem) -> Bool {
        guard case let .draft(key) = item,
              let draft = draft(key: key)
        else {
            return false
        }
        return draft.fireComposerRoute() != nil
    }

    private func handleSelection(_ item: FireDraftsCollectionItem) {
        guard case let .draft(key) = item,
              let draft = draft(key: key)
        else {
            return
        }
        open(draft)
    }

    private func loadMoreIfNeeded(from items: [FireDraftsCollectionItem]) {
        guard let lastDraftKey = draftsViewModel.drafts.last?.draftKey else { return }
        guard items.contains(.draft(lastDraftKey)) || items.contains(.loadingMore) else { return }
        loadTask = Task { [weak self] in
            await self?.draftsViewModel.loadMoreIfNeeded(currentDraftKey: lastDraftKey)
        }
    }

    private func draft(key: String) -> DraftState? {
        draftsViewModel.drafts.first { $0.draftKey == key }
    }

    private func itemContentToken(for item: FireDraftsCollectionItem) -> AnyHashable {
        switch item {
        case let .blockingError(message), let .inlineErrorBanner(message):
            return AnyHashable(message)
        case .loading:
            return AnyHashable(draftsViewModel.isLoading)
        case .empty:
            return AnyHashable(draftsViewModel.hasLoadedOnce)
        case let .draft(key):
            guard let draft = draft(key: key) else {
                return AnyHashable("missing|\(key)")
            }
            return AnyHashable(FireDraftContentToken(draft))
        case .loadingMore:
            return AnyHashable(draftsViewModel.isLoadingMore)
        }
    }

    private func contextMenuConfiguration(for item: FireDraftsCollectionItem) -> UIContextMenuConfiguration? {
        guard case let .draft(key) = item,
              let draft = draft(key: key)
        else {
            return nil
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: self?.draftMenuActions(draft) ?? [])
        }
    }

    private func draftMenuActions(_ draft: DraftState) -> [UIAction] {
        var actions: [UIAction] = []
        if draft.fireComposerRoute() != nil {
            actions.append(
                UIAction(title: "继续编辑", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
                    self?.open(draft)
                }
            )
        }
        actions.append(
            UIAction(
                title: "删除",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.delete(draft)
            }
        )
        return actions
    }

    private func open(_ draft: DraftState) {
        guard let route = draft.fireComposerRoute() else {
            showToast("当前草稿类型暂不支持继续编辑", style: .error)
            return
        }

        let composer = FireComposerViewController(
            viewModel: appViewModel,
            route: route,
            onTopicCreated: { [weak self] _ in
                self?.refreshAfterComposerMutation()
            },
            onReplySubmitted: { [weak self] in
                self?.refreshAfterComposerMutation()
            },
            onPrivateMessageCreated: { [weak self] _, _ in
                self?.refreshAfterComposerMutation()
            },
            onSubmissionNotice: { [weak self] message in
                self?.showToast(message, style: .success)
            }
        )
        let navigationController = UINavigationController(rootViewController: composer)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }

    private func refreshAfterComposerMutation() {
        loadTask = Task { [weak self] in
            await self?.draftsViewModel.refresh()
        }
    }

    private func delete(_ draft: DraftState) {
        loadTask = Task { [weak self] in
            await self?.draftsViewModel.deleteDraft(draft)
        }
    }

    private func showToast(_ message: String, style: FireTopicListToastView.Style) {
        toastDismissTask?.cancel()
        toastView?.removeFromSuperview()
        toastView = nil
        FireUIKitToast.show(message, style: FireUIKitToast.Style(style), in: view)
    }

}

struct FireDraftContentToken: Hashable {
    let key: String
    let title: String
    let excerpt: String?
    let kind: String
    let updatedAt: String?
    let routeID: String?

    init(_ draft: DraftState) {
        key = draft.draftKey
        title = draft.fireDraftTitle
        excerpt = draft.fireDraftExcerpt
        kind = draft.fireDraftKindLabel
        updatedAt = FireTopicPresentation.compactTimestamp(draft.updatedAt)
        routeID = draft.fireComposerRoute()?.id
    }
}

final class FireDraftsControllerReference {
    weak var controller: FireDraftsViewController?
}

extension DraftState {
    func fireComposerRoute() -> FireComposerRoute? {
        let key = draftKey
        if key == "new_topic" {
            return FireComposerRoute(kind: .createTopic)
        }
        if key == "new_private_message" {
            return FireComposerRoute(
                kind: .privateMessage(
                    recipients: data.recipients,
                    title: data.title
                )
            )
        }
        guard let topicID = self.topicId else {
            return nil
        }
        let title = title?.ifEmpty("话题 #\(topicID)") ?? "话题 #\(topicID)"
        return FireComposerRoute(
            kind: .advancedReply(
                topicID: topicID,
                topicTitle: title,
                categoryID: data.categoryId,
                replyToPostNumber: data.replyToPostNumber,
                replyToUsername: nil,
                isPrivateMessage: data.archetypeId == "private_message"
            )
        )
    }

    var fireDraftTitle: String {
        if draftKey == "new_topic" {
            return title?.ifEmpty("未命名新话题") ?? "未命名新话题"
        }
        if draftKey == "new_private_message" {
            return title?.ifEmpty("未命名私信") ?? "未命名私信"
        }
        return title?.ifEmpty("回复草稿") ?? "回复草稿"
    }

    var fireDraftExcerpt: String? {
        let excerpt = excerpt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !excerpt.isEmpty {
            return excerpt
        }
        let reply = data.reply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reply.isEmpty ? nil : reply
    }

    var fireDraftKindLabel: String {
        if draftKey == "new_topic" {
            return "新话题"
        }
        if draftKey == "new_private_message" || data.archetypeId == "private_message" {
            return "私信"
        }
        return "完整回复"
    }

    var fireDraftIcon: String {
        switch fireDraftKindLabel {
        case "新话题":
            return "square.and.pencil"
        case "私信":
            return "paperplane"
        default:
            return "arrowshape.turn.up.left"
        }
    }

    func fireDraftAccessibilityLabel(supported: Bool) -> String {
        var parts = [fireDraftTitle, fireDraftKindLabel]
        if let excerpt = fireDraftExcerpt {
            parts.append(excerpt)
        }
        if let updatedAt = FireTopicPresentation.compactTimestamp(updatedAt) {
            parts.append(updatedAt)
        }
        if !supported {
            parts.append("暂不支持")
        }
        return parts.joined(separator: "，")
    }
}
