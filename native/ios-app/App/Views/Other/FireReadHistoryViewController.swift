import Combine
import SwiftUI
import UIKit

struct FireReadHistoryControllerHost: UIViewControllerRepresentable {
    @Environment(\.fireTopicRoutePresenter) private var topicRoutePresenter
    @EnvironmentObject private var topicDetailStore: FireTopicDetailStore

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
    private struct ContentVersion: Hashable {
        let rows: [FireTopicRowPresentation]
        let nextPage: UInt32?
        let isLoading: Bool
        let isLoadingMore: Bool
        let hasLoadedOnce: Bool
        let errorMessage: String?
    }

    private let appViewModel: FireAppViewModel
    private let topicDetailStore: FireTopicDetailStore
    private let historyViewModel: FireReadHistoryViewModel
    private let controllerReference: FireReadHistoryControllerReference
    private let listController: FireListViewController<FireReadHistoryCollectionSection, FireReadHistoryCollectionItem>
    private var topicRoutePresenter: FireTopicRoutePresenter
    private var cancellables: Set<AnyCancellable> = []
    private var loadTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private weak var toastView: UIView?

    private lazy var stateCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var bannerCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var topicCellRegistration = UICollectionView.CellRegistration<
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
                controllerReference.controller?.loadMoreIfNeeded(from: items)
            },
            onRefresh: { [historyViewModel] in
                await historyViewModel.refresh()
            },
            cellProvider: { _, _, _ in UICollectionViewCell() }
        )
        super.init(nibName: nil, bundle: nil)
        controllerReference.controller = self
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
        view.backgroundColor = .systemBackground

        installListController()
        bindViewModel()
        render()
        loadTask = Task { [weak self] in
            await self?.historyViewModel.loadIfNeeded()
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
        listController.updateContextMenuConfigurationProvider { [weak self] item in
            self?.contextMenuConfiguration(for: item)
        }
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
        historyViewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.render()
                }
            }
            .store(in: &cancellables)
    }

    private var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    private var contentVersion: ContentVersion {
        ContentVersion(
            rows: historyViewModel.rows,
            nextPage: historyViewModel.nextPage,
            isLoading: historyViewModel.isLoading,
            isLoadingMore: historyViewModel.isLoadingMore,
            hasLoadedOnce: historyViewModel.hasLoadedOnce,
            errorMessage: historyViewModel.errorMessage
        )
    }

    private func render() {
        let sections = makeSections()
        var tokens: [FireReadHistoryCollectionItem: AnyHashable] = [:]
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
        -> [FireListSectionModel<FireReadHistoryCollectionSection, FireReadHistoryCollectionItem>]
    {
        var items: [FireReadHistoryCollectionItem] = []

        if let errorMessage = historyViewModel.errorMessage,
           historyViewModel.hasLoadedOnce {
            items.append(.inlineErrorBanner(errorMessage))
        }

        if !historyViewModel.hasLoadedOnce {
            if let errorMessage = historyViewModel.errorMessage {
                items.append(.blockingError(errorMessage))
            } else {
                items.append(.loading)
            }
        } else if historyViewModel.rows.isEmpty {
            items.append(.empty)
        } else {
            items.append(contentsOf: historyViewModel.rows.map {
                .topic($0.topic.id)
            })

            if historyViewModel.isLoadingMore {
                items.append(.loadingMore)
            }
        }

        return [.init(id: .content, items: items)]
    }

    private func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireReadHistoryCollectionItem
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
        case .topic:
            return collectionView.dequeueConfiguredReusableCell(
                using: topicCellRegistration,
                for: indexPath,
                item: item
            )
        }
    }

    private func canSelect(_ item: FireReadHistoryCollectionItem) -> Bool {
        if case .topic = item {
            return true
        }
        return false
    }

    private func handleSelection(_ item: FireReadHistoryCollectionItem) {
        guard case let .topic(topicID) = item,
              let row = historyViewModel.row(for: topicID) else { return }
        presentRoute(.topic(row: row, postNumber: row.topic.lastReadPostNumber))
    }

    private func handleVisibleItemsChanged(_ items: [FireReadHistoryCollectionItem]) {
        loadMoreIfNeeded(from: items)
    }

    private func loadMoreIfNeeded(from items: [FireReadHistoryCollectionItem]) {
        guard let lastTopicID = historyViewModel.lastTopicID else { return }
        guard items.contains(.topic(lastTopicID)) || items.contains(.loadingMore) else { return }
        loadTask = Task { [weak self] in
            await self?.historyViewModel.loadMoreIfNeeded(currentTopicID: lastTopicID)
        }
    }

    private func contextMenuConfiguration(
        for item: FireReadHistoryCollectionItem
    ) -> UIContextMenuConfiguration? {
        guard case let .topic(topicID) = item,
              let row = historyViewModel.row(for: topicID)
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
                self?.presentRoute(.topic(row: row, postNumber: row.topic.lastReadPostNumber))
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
                self?.muteTopicFromAction(row)
            },
        ]
    }

    private func itemContentToken(for item: FireReadHistoryCollectionItem) -> AnyHashable {
        switch item {
        case let .blockingError(message), let .inlineErrorBanner(message):
            return AnyHashable(message)
        case .loading:
            return AnyHashable(historyViewModel.isLoading)
        case .empty:
            return AnyHashable(historyViewModel.hasLoadedOnce)
        case let .topic(topicID):
            guard let row = historyViewModel.row(for: topicID) else {
                return AnyHashable("missing|\(topicID)")
            }
            return AnyHashable(topicRowContentToken(row))
        case .loadingMore:
            return AnyHashable(historyViewModel.isLoadingMore)
        }
    }

    private func topicRowContentToken(_ row: FireTopicRowPresentation) -> String {
        let topic = row.topic
        let category = appViewModel.categoryPresentation(for: topic.categoryId)
        var parts: [String] = []
        parts.reserveCapacity(31)
        parts.append(String(topic.id))
        parts.append(topic.title)
        parts.append(topic.slug)
        parts.append(String(topic.postsCount))
        parts.append(String(topic.replyCount))
        parts.append(String(topic.views))
        parts.append(String(topic.likeCount))
        parts.append(topic.excerpt ?? "")
        parts.append(topic.createdAt ?? "")
        parts.append(topic.lastPostedAt ?? "")
        parts.append(topic.lastPosterUsername ?? "")
        parts.append(topic.categoryId.map(String.init) ?? "")
        parts.append(String(topic.pinned))
        parts.append(String(topic.closed))
        parts.append(String(topic.archived))
        parts.append(String(topic.unseen))
        parts.append(String(topic.unreadPosts))
        parts.append(String(topic.newPosts))
        parts.append(topic.lastReadPostNumber.map(String.init) ?? "")
        parts.append(String(topic.highestPostNumber))
        parts.append(topic.bookmarkedPostNumber.map(String.init) ?? "")
        parts.append(topic.bookmarkId.map(String.init) ?? "")
        parts.append(topic.bookmarkName ?? "")
        parts.append(topic.bookmarkReminderAt ?? "")
        parts.append(topic.bookmarkableType ?? "")
        parts.append(row.excerptText ?? "")
        parts.append(row.originalPosterUsername ?? "")
        parts.append(row.originalPosterAvatarTemplate ?? "")
        parts.append(row.tagNames.joined(separator: ","))
        parts.append(row.statusLabels.joined(separator: ","))
        parts.append(category.map { "\($0.id)|\($0.displayName)|\($0.colorHex ?? "")" } ?? "")
        return parts.joined(separator: "\u{1F}")
    }

    private func presentRoute(_ route: FireAppRoute) {
        if topicRoutePresenter.present(route) {
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
        await historyViewModel.refresh()
    }

    private func deleteBookmarkFromAction(for row: FireTopicRowPresentation) {
        guard let bookmarkID = row.topic.bookmarkId else { return }
        let recoveryOriginURL = row.fireTopicURL(baseURL: baseURLString)
        loadTask = Task { [weak self] in
            do {
                try await self?.deleteBookmark(
                    bookmarkID: bookmarkID,
                    recoveryOriginURL: recoveryOriginURL,
                    showSuccessToast: true
                )
            } catch {
                self?.historyViewModel.reportError(error.localizedDescription)
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
        await historyViewModel.refresh()
        if showSuccessToast {
            showToast("已删除书签", style: .success)
        }
    }

    private func muteTopicFromAction(_ row: FireTopicRowPresentation) {
        loadTask = Task { [weak self] in
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
}

private final class FireReadHistoryControllerReference {
    weak var controller: FireReadHistoryViewController?
}
