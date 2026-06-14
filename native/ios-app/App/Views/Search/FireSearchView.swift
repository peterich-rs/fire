import Combine
import SwiftUI
import UIKit

private enum FireSearchCollectionSection: Int, Hashable {
    case content
}

private enum FireSearchCollectionItem: Hashable {
    case placeholder
    case loading(Int)
    case blockingError(String)
    case inlineErrorBanner(String)
    case sectionHeader(String)
    case topic(UInt64)
    case post(UInt64)
    case user(UInt64)
    case loadMore
    case empty
}

@MainActor
final class FireSearchViewController: UIViewController {
    private struct ContentVersion: Hashable {
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

    private let appViewModel: FireAppViewModel
    private let searchStore: FireSearchStore
    private let topicDetailStore: FireTopicDetailStore
    private let initialQuery: String?
    private let controllerReference: FireSearchControllerReference
    private let headerView = FireSearchHeaderView()
    private let listController: FireListViewController<FireSearchCollectionSection, FireSearchCollectionItem>
    private var topicRoutePresenter: FireTopicRoutePresenter
    private var fallbackRoutePresenter: ((FireAppRoute) -> Void)?
    private var cancellables: Set<AnyCancellable> = []
    private var actionTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private weak var toastView: UIView?

    private lazy var stateCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var bannerCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var sectionHeaderCellRegistration = UICollectionView.CellRegistration<
        FireSearchSectionHeaderCell,
        FireSearchCollectionItem
    > { cell, _, item in
        guard case let .sectionHeader(title) = item else { return }
        cell.configure(title: title)
    }

    private lazy var topicCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var postCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var userCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var loadMoreCellRegistration = UICollectionView.CellRegistration<
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
            backgroundColor: .systemBackground,
            onSelectItem: { [controllerReference] item in
                controllerReference.controller?.handleSelection(item)
            },
            canSelectItem: { [controllerReference] item in
                controllerReference.controller?.canSelect(item) ?? false
            },
            onPrefetchItems: { [controllerReference] items in
                controllerReference.controller?.handlePrefetchItems(items)
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

        title = "搜索"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground
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

    func updateTopicRoutePresenter(_ presenter: FireTopicRoutePresenter) {
        topicRoutePresenter = presenter
    }

    func updateFallbackRoutePresenter(_ presenter: ((FireAppRoute) -> Void)?) {
        fallbackRoutePresenter = presenter
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
        _ = sectionHeaderCellRegistration
        _ = topicCellRegistration
        _ = postCellRegistration
        _ = userCellRegistration
        _ = loadMoreCellRegistration
    }

    private func installHeaderView() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
        ])
    }

    private func installListController() {
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

    private func configureHeader() {
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

    private func bindState() {
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

    private var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    private var topicIndex: [UInt64: SearchTopicState] {
        guard let result = searchStore.result else { return [:] }
        return Dictionary(
            result.topics.map { ($0.id, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
    }

    private var contentVersion: ContentVersion {
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

    private func render() {
        let sections = makeSections()
        var tokens: [FireSearchCollectionItem: AnyHashable] = [:]
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
        -> [FireListSectionModel<FireSearchCollectionSection, FireSearchCollectionItem>]
    {
        var items: [FireSearchCollectionItem] = []

        if searchStore.isSearching && searchStore.result == nil {
            items.append(.sectionHeader("话题"))
            items.append(contentsOf: (0..<3).map(FireSearchCollectionItem.loading))
            items.append(.sectionHeader("帖子"))
            items.append(contentsOf: (3..<6).map(FireSearchCollectionItem.loading))
            return [.init(id: .content, items: items)]
        }

        if let result = searchStore.result {
            if let errorMessage = searchStore.errorMessage {
                items.append(.inlineErrorBanner(errorMessage))
            }

            if !result.topics.isEmpty {
                items.append(.sectionHeader("话题"))
                items.append(contentsOf: result.topics.map { .topic($0.id) })
            }

            if !result.posts.isEmpty {
                items.append(.sectionHeader("帖子"))
                items.append(contentsOf: result.posts.map { .post($0.id) })
            }

            if !result.users.isEmpty {
                items.append(.sectionHeader("用户"))
                items.append(contentsOf: result.users.map { .user($0.id) })
            }

            if searchStore.canLoadMoreResults {
                items.append(.loadMore)
            }

            if result.posts.isEmpty && result.topics.isEmpty && result.users.isEmpty {
                items.append(.empty)
            }

            return [.init(id: .content, items: items)]
        }

        if let errorMessage = searchStore.errorMessage {
            items.append(.blockingError(errorMessage))
        } else {
            items.append(.placeholder)
        }

        return [.init(id: .content, items: items)]
    }

    private func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireSearchCollectionItem
    ) -> UICollectionViewCell {
        switch item {
        case .placeholder, .loading, .blockingError, .empty:
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
        case .sectionHeader:
            return collectionView.dequeueConfiguredReusableCell(
                using: sectionHeaderCellRegistration,
                for: indexPath,
                item: item
            )
        case .topic:
            return collectionView.dequeueConfiguredReusableCell(
                using: topicCellRegistration,
                for: indexPath,
                item: item
            )
        case .post:
            return collectionView.dequeueConfiguredReusableCell(
                using: postCellRegistration,
                for: indexPath,
                item: item
            )
        case .user:
            return collectionView.dequeueConfiguredReusableCell(
                using: userCellRegistration,
                for: indexPath,
                item: item
            )
        case .loadMore:
            return collectionView.dequeueConfiguredReusableCell(
                using: loadMoreCellRegistration,
                for: indexPath,
                item: item
            )
        }
    }

    private func canSelect(_ item: FireSearchCollectionItem) -> Bool {
        switch item {
        case .topic, .post, .user:
            return true
        case .placeholder, .loading, .blockingError, .inlineErrorBanner, .sectionHeader, .loadMore, .empty:
            return false
        }
    }

    private func handleSelection(_ item: FireSearchCollectionItem) {
        switch item {
        case let .topic(topicID):
            guard let topic = topic(for: topicID) else { return }
            let row = topicRow(for: topic)
            presentRoute(.topic(
                topicId: topic.id,
                postNumber: nil,
                preview: FireTopicRoutePreview(row: row)
            ))
        case let .post(postID):
            guard let post = post(for: postID),
                  let row = postRow(for: post, topicIndex: topicIndex)
            else {
                return
            }
            presentRoute(.topic(
                topicId: row.topic.id,
                postNumber: post.postNumber,
                preview: FireTopicRoutePreview(row: row)
            ))
        case let .user(userID):
            guard let user = user(for: userID) else { return }
            presentRoute(.profile(username: user.username))
        case .placeholder, .loading, .blockingError, .inlineErrorBanner, .sectionHeader, .loadMore, .empty:
            break
        }
    }

    private func handlePrefetchItems(_ items: [FireSearchCollectionItem]) {
        guard items.contains(.loadMore),
              searchStore.canLoadMoreResults,
              !searchStore.isSearching,
              !searchStore.isAppending
        else {
            return
        }
        searchStore.submit(reset: false)
    }

    private func contextMenuConfiguration(
        for item: FireSearchCollectionItem
    ) -> UIContextMenuConfiguration? {
        guard case let .topic(topicID) = item,
              let topic = topic(for: topicID)
        else {
            return nil
        }
        let row = topicRow(for: topic)
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
            UIAction(title: "添加书签", image: UIImage(systemName: "bookmark")) { [weak self] _ in
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

    private func itemContentToken(for item: FireSearchCollectionItem) -> AnyHashable {
        switch item {
        case .placeholder:
            return AnyHashable("placeholder|\(searchStore.query)")
        case let .loading(index):
            return AnyHashable(index)
        case let .blockingError(message), let .inlineErrorBanner(message):
            return AnyHashable(message)
        case let .sectionHeader(title):
            return AnyHashable(title)
        case let .topic(topicID):
            guard let topic = topic(for: topicID) else {
                return AnyHashable("missing-topic|\(topicID)")
            }
            return AnyHashable(topicContentToken(topic))
        case let .post(postID):
            guard let post = post(for: postID) else {
                return AnyHashable("missing-post|\(postID)")
            }
            return AnyHashable(postContentToken(post))
        case let .user(userID):
            guard let user = user(for: userID) else {
                return AnyHashable("missing-user|\(userID)")
            }
            return AnyHashable(userContentToken(user))
        case .loadMore:
            return AnyHashable("\(searchStore.isAppending)|\(searchStore.canLoadMoreResults)")
        case .empty:
            return AnyHashable("empty|\(searchStore.query)|\(searchStore.scope.rawValue)")
        }
    }

    private func topic(for topicID: UInt64) -> SearchTopicState? {
        searchStore.result?.topics.first { $0.id == topicID }
    }

    private func post(for postID: UInt64) -> SearchPostState? {
        searchStore.result?.posts.first { $0.id == postID }
    }

    private func user(for userID: UInt64) -> SearchUserState? {
        searchStore.result?.users.first { $0.id == userID }
    }

    private func presentRoute(_ route: FireAppRoute) {
        if topicRoutePresenter.present(route) {
            return
        }
        if let fallbackRoutePresenter {
            fallbackRoutePresenter(route)
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
                        recoveryOriginURL: recoveryOriginURL
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
        searchStore.submit(reset: true)
    }

    private func deleteBookmark(
        bookmarkID: UInt64,
        recoveryOriginURL: URL
    ) async throws {
        try await appViewModel.topicInteraction.deleteBookmark(
            bookmarkID: bookmarkID,
            recoveryOriginURL: recoveryOriginURL
        )
        searchStore.submit(reset: true)
    }

    private func muteTopic(_ row: FireTopicRowPresentation) {
        actionTask = Task { [weak self] in
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

    private func postRow(
        for post: SearchPostState,
        topicIndex: [UInt64: SearchTopicState]
    ) -> FireTopicRowPresentation? {
        guard let topicID = post.topicId else {
            return nil
        }
        let topic = topicIndex[topicID]
            ?? SearchTopicState(
                id: topicID,
                title: post.topicTitleHeadline ?? "话题 \(topicID)",
                slug: "",
                categoryId: nil,
                tags: [],
                postsCount: max(post.postNumber, 1),
                views: 0,
                closed: false,
                archived: false
            )
        let excerpt = previewTextFromHtml(rawHtml: post.blurb)
        return topicRow(for: topic, excerptText: excerpt)
    }

    private func topicRow(
        for topic: SearchTopicState,
        excerptText: String? = nil
    ) -> FireTopicRowPresentation {
        let statusLabels = {
            var labels: [String] = []
            if topic.closed {
                labels.append("已关闭")
            }
            if topic.archived {
                labels.append("已归档")
            }
            return labels
        }()

        return TopicRowState(
            topic: TopicSummaryState(
                id: topic.id,
                title: topic.title,
                slug: topic.slug,
                postsCount: topic.postsCount,
                replyCount: topic.postsCount > 0 ? topic.postsCount - 1 : 0,
                views: topic.views,
                likeCount: 0,
                excerpt: excerptText,
                createdAt: nil,
                lastPostedAt: nil,
                lastPosterUsername: nil,
                categoryId: topic.categoryId,
                pinned: false,
                visible: true,
                closed: topic.closed,
                archived: topic.archived,
                tags: topic.tags.map { TopicTagState(id: nil, name: $0, slug: nil) },
                posters: [],
                participants: [],
                unseen: false,
                unreadPosts: 0,
                newPosts: 0,
                lastReadPostNumber: nil,
                highestPostNumber: max(topic.postsCount, 1),
                bookmarkedPostNumber: nil,
                bookmarkId: nil,
                bookmarkName: nil,
                bookmarkReminderAt: nil,
                bookmarkableType: nil,
                hasAcceptedAnswer: false,
                canHaveAnswer: false
            ),
            excerptText: excerptText,
            originalPosterUsername: nil,
            originalPosterAvatarTemplate: nil,
            tagNames: topic.tags,
            statusLabels: statusLabels,
            isPinned: false,
            isClosed: topic.closed,
            isArchived: topic.archived,
            hasAcceptedAnswer: false,
            hasUnreadPosts: false,
            createdTimestampUnixMs: nil,
            activityTimestampUnixMs: nil,
            lastPosterUsername: nil
        )
    }

    private func topicContentToken(_ topic: SearchTopicState) -> String {
        var components: [String] = []
        components.reserveCapacity(9)
        components.append(String(topic.id))
        components.append(topic.title)
        components.append(topic.slug)
        components.append(topic.categoryId.map(String.init) ?? "")
        components.append(topic.tags.joined(separator: ","))
        components.append(String(topic.postsCount))
        components.append(String(topic.views))
        components.append(String(topic.closed))
        components.append(String(topic.archived))
        return components.joined(separator: "\u{1F}")
    }

    private func postContentToken(_ post: SearchPostState) -> String {
        var components: [String] = []
        components.reserveCapacity(10)
        components.append(String(post.id))
        components.append(post.topicId.map(String.init) ?? "")
        components.append(post.username)
        components.append(post.avatarTemplate ?? "")
        components.append(post.createdAt ?? "")
        components.append(post.createdTimestampUnixMs.map(String.init) ?? "")
        components.append(String(post.likeCount))
        components.append(post.blurb)
        components.append(String(post.postNumber))
        components.append(post.topicTitleHeadline ?? "")
        return components.joined(separator: "\u{1F}")
    }

    private func userContentToken(_ user: SearchUserState) -> String {
        var components: [String] = []
        components.reserveCapacity(4)
        components.append(String(user.id))
        components.append(user.username)
        components.append(user.name ?? "")
        components.append(user.avatarTemplate ?? "")
        return components.joined(separator: "\u{1F}")
    }
}

private final class FireSearchHeaderView: UIView, UITextFieldDelegate {
    private let stackView = UIStackView()
    private let searchTextField = UISearchTextField()
    private let scopeControl = UISegmentedControl(items: FireSearchScope.allCases.map(\.title))
    private var onQueryChanged: ((String) -> Void)?
    private var onSubmit: (() -> Void)?
    private var onClear: (() -> Void)?
    private var onScopeChanged: ((FireSearchScope) -> Void)?
    private var isProgrammaticUpdate = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        query: String,
        scope: FireSearchScope,
        onQueryChanged: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onScopeChanged: @escaping (FireSearchScope) -> Void
    ) {
        self.onQueryChanged = onQueryChanged
        self.onSubmit = onSubmit
        self.onClear = onClear
        self.onScopeChanged = onScopeChanged
        update(query: query, scope: scope)
    }

    func update(query: String, scope: FireSearchScope) {
        isProgrammaticUpdate = true
        if searchTextField.text != query {
            searchTextField.text = query
        }
        if let index = FireSearchScope.allCases.firstIndex(of: scope),
           scopeControl.selectedSegmentIndex != index {
            scopeControl.selectedSegmentIndex = index
        }
        isProgrammaticUpdate = false
    }

    func focusSearchField() {
        searchTextField.becomeFirstResponder()
    }

    private func configureSubviews() {
        backgroundColor = .systemBackground
        directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 10,
            trailing: 16
        )

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false

        searchTextField.placeholder = "搜索话题、帖子、用户..."
        searchTextField.returnKeyType = .search
        searchTextField.autocorrectionType = .no
        searchTextField.autocapitalizationType = .none
        searchTextField.clearButtonMode = .whileEditing
        searchTextField.delegate = self
        searchTextField.addTarget(self, action: #selector(queryDidChange), for: .editingChanged)

        scopeControl.selectedSegmentIndex = 0
        scopeControl.addTarget(self, action: #selector(scopeDidChange), for: .valueChanged)

        stackView.addArrangedSubview(searchTextField)
        stackView.addArrangedSubview(scopeControl)

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])
    }

    @objc private func queryDidChange() {
        guard !isProgrammaticUpdate else { return }
        let query = searchTextField.text ?? ""
        onQueryChanged?(query)
        if query.isEmpty {
            onClear?()
        }
    }

    @objc private func scopeDidChange() {
        guard !isProgrammaticUpdate else { return }
        let index = scopeControl.selectedSegmentIndex
        guard FireSearchScope.allCases.indices.contains(index) else { return }
        onScopeChanged?(FireSearchScope.allCases[index])
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onSubmit?()
        textField.resignFirstResponder()
        return true
    }
}

private final class FireSearchSectionHeaderCell: UICollectionViewCell {
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        titleLabel.text = title
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 14,
            leading: 16,
            bottom: 4,
            trailing: 16
        )

        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline).withSearchWeight(.semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }
}

private final class FireSearchPostResultCell: UICollectionViewCell {
    private let titleLabel = UILabel()
    private let excerptLabel = UILabel()
    private let metaStack = UIStackView()

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
        metaStack.arrangedSubviews.forEach { view in
            metaStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    func configureMissing() {
        titleLabel.text = "帖子结果"
        excerptLabel.text = nil
        metaStack.arrangedSubviews.forEach { view in
            metaStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    func configure(post: SearchPostState, row: FireTopicRowPresentation?) {
        titleLabel.text = post.topicTitleHeadline ?? row?.topic.title ?? "帖子结果"
        excerptLabel.text = previewTextFromHtml(rawHtml: post.blurb) ?? post.blurb
        configureMeta(post: post)

        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = [
            titleLabel.text,
            excerptLabel.text,
            "@\(post.username)",
            "第 \(post.postNumber) 楼",
        ].compactMap { $0 }.joined(separator: "，")
    }

    private func configureMeta(post: SearchPostState) {
        metaStack.arrangedSubviews.forEach { view in
            metaStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        metaStack.addArrangedSubview(makeMetaLabel(systemImage: "person", text: post.username))
        metaStack.addArrangedSubview(makeMetaLabel(systemImage: "number", text: "\(post.postNumber)"))
        if post.likeCount > 0 {
            metaStack.addArrangedSubview(makeMetaLabel(systemImage: "heart", text: "\(post.likeCount)"))
        }
        if let timestampText = FireTopicPresentation.compactTimestamp(
            unixMs: post.createdTimestampUnixMs
        ) {
            metaStack.addArrangedSubview(makeMetaLabel(systemImage: "clock", text: timestampText))
        }
        metaStack.addArrangedSubview(UIView())
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 8,
            trailing: 16
        )

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        excerptLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        excerptLabel.adjustsFontForContentSizeCategory = true
        excerptLabel.textColor = .secondaryLabel
        excerptLabel.numberOfLines = 3

        metaStack.axis = .horizontal
        metaStack.alignment = .center
        metaStack.spacing = 10

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(excerptLabel)
        stackView.addArrangedSubview(metaStack)

        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    private func makeMetaLabel(systemImage: String, text: String) -> UIView {
        let imageView = UIImageView(image: UIImage(systemName: systemImage))
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = text
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 1

        let stackView = UIStackView(arrangedSubviews: [imageView, label])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 4
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 12),
            imageView.heightAnchor.constraint(equalToConstant: 12),
        ])
        return stackView
    }
}

private final class FireSearchUserResultCell: UICollectionViewCell {
    private let avatarView = FireTopicListAvatarView()
    private let nameLabel = UILabel()
    private let usernameLabel = UILabel()

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
        avatarView.prepareForReuse()
    }

    func configureMissing() {
        nameLabel.text = "用户"
        usernameLabel.text = nil
        avatarView.prepareForReuse()
    }

    func configure(user: SearchUserState, baseURLString: String) {
        nameLabel.text = user.name ?? user.username
        usernameLabel.text = "@\(user.username)"
        avatarView.configure(
            username: user.username,
            avatarTemplate: user.avatarTemplate,
            baseURLString: baseURLString
        )

        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = "用户搜索结果：\(user.name ?? user.username)，@\(user.username)"
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 8,
            trailing: 16
        )

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 4

        nameLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 1

        usernameLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        usernameLabel.adjustsFontForContentSizeCategory = true
        usernameLabel.textColor = .secondaryLabel
        usernameLabel.numberOfLines = 1

        textStack.addArrangedSubview(nameLabel)
        textStack.addArrangedSubview(usernameLabel)

        let rowStack = UIStackView(arrangedSubviews: [avatarView, textStack])
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 42),
            avatarView.heightAnchor.constraint(equalToConstant: 42),
            rowStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }
}

private final class FireSearchLoadMoreCell: UICollectionViewCell {
    private let button = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var onTap: (() -> Void)?

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
        onTap = nil
        activityIndicator.stopAnimating()
    }

    func configure(
        isLoading: Bool,
        isEnabled: Bool,
        onTap: @escaping () -> Void
    ) {
        self.onTap = onTap
        button.isHidden = isLoading
        button.isEnabled = isEnabled
        activityIndicator.isHidden = !isLoading
        if isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 10,
            leading: 16,
            bottom: 10,
            trailing: 16
        )

        button.configuration = {
            var configuration = UIButton.Configuration.plain()
            configuration.title = "加载更多"
            configuration.image = UIImage(systemName: "arrow.down.circle")
            configuration.imagePadding = 6
            return configuration
        }()
        button.addAction(UIAction { [weak self] _ in
            self?.onTap?()
        }, for: .touchUpInside)

        let stackView = UIStackView(arrangedSubviews: [button, activityIndicator])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }
}

private final class FireSearchControllerReference {
    weak var controller: FireSearchViewController?
}

private extension UIFont {
    func withSearchWeight(_ weight: Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
