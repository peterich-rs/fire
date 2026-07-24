import Combine
import SwiftUI
import UIKit

// MARK: - SwiftUI host (category browser NavigationLink)

struct FireFilteredTopicListControllerHost: UIViewControllerRepresentable {
    @Environment(\.fireTopicRoutePresenter) private var topicRoutePresenter
    @EnvironmentObject private var topicDetailStore: FireTopicDetailStore

    let viewModel: FireAppViewModel
    let title: String
    let categorySlug: String?
    let categoryId: UInt64?
    let parentCategorySlug: String?
    let tag: String?

    func makeUIViewController(context: Context) -> FireFilteredTopicListViewController {
        FireFilteredTopicListViewController(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            title: title,
            categorySlug: categorySlug,
            categoryId: categoryId,
            parentCategorySlug: parentCategorySlug,
            tag: tag,
            topicRoutePresenter: topicRoutePresenter
        )
    }

    func updateUIViewController(
        _ uiViewController: FireFilteredTopicListViewController,
        context: Context
    ) {
        uiViewController.updateTopicRoutePresenter(topicRoutePresenter)
    }
}

// MARK: - Collection model

private enum FireFilteredTopicSection: Int, Hashable {
    case feedSelector
    case content
}

private enum FireFilteredTopicItem: Hashable {
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
    private struct ContentVersion: Hashable {
        let selectedKind: TopicListKindState
        let rows: [UInt64]
        let nextPage: UInt32?
        let isLoading: Bool
        let isLoadingMore: Bool
        let hasResolved: Bool
        let errorMessage: String?
        let displayState: FireScopedTopicListDisplayState
    }

    private let appViewModel: FireAppViewModel
    private let topicDetailStore: FireTopicDetailStore
    private let listViewModel: FireFilteredTopicListViewModel
    private let listTitle: String
    private let controllerReference = FireFilteredTopicListControllerReference()
    private let listController: FireListViewController<FireFilteredTopicSection, FireFilteredTopicItem>
    private var topicRoutePresenter: FireTopicRoutePresenter
    private var cancellables: Set<AnyCancellable> = []
    private var loadTask: Task<Void, Never>?

    private lazy var feedSelectorCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var stateCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var skeletonCellRegistration = UICollectionView.CellRegistration<
        FireHomeStyleSkeletonCell,
        FireFilteredTopicItem
    > { cell, _, _ in
        cell.configure()
    }

    private lazy var bannerCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var topicCellRegistration = UICollectionView.CellRegistration<
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

    func updateTopicRoutePresenter(_ presenter: FireTopicRoutePresenter) {
        topicRoutePresenter = presenter
    }

    private func configureListController() {
        listController.updateCellProvider { [weak self] collectionView, indexPath, item in
            guard let self else { return UICollectionViewCell() }
            return self.cell(collectionView: collectionView, indexPath: indexPath, item: item)
        }
        listController.updateContextMenuConfigurationProvider { [weak self] item in
            self?.contextMenuConfiguration(for: item)
        }
    }

    private func prepareCellRegistrations() {
        _ = feedSelectorCellRegistration
        _ = stateCellRegistration
        _ = skeletonCellRegistration
        _ = bannerCellRegistration
        _ = topicCellRegistration
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
        listViewModel.objectWillChange
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
            selectedKind: listViewModel.selectedKind,
            rows: listViewModel.displayedRows.map(\.topic.id),
            nextPage: listViewModel.currentKindNextPage,
            isLoading: listViewModel.isLoading,
            isLoadingMore: listViewModel.isLoadingMore,
            hasResolved: listViewModel.hasResolvedCurrentKind,
            errorMessage: listViewModel.errorMessage,
            displayState: listViewModel.currentKindDisplayState
        )
    }

    private func render() {
        let sections = makeSections()
        var tokens: [FireFilteredTopicItem: AnyHashable] = [:]
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
        -> [FireListSectionModel<FireFilteredTopicSection, FireFilteredTopicItem>]
    {
        var sections: [FireListSectionModel<FireFilteredTopicSection, FireFilteredTopicItem>] = [
            .init(id: .feedSelector, items: [.feedSelector]),
        ]

        var items: [FireFilteredTopicItem] = []
        switch listViewModel.currentKindDisplayState {
        case .loading:
            items.append(contentsOf: (0..<6).map { .loadingSkeleton($0) })
        case let .blockingError(message):
            items.append(.blockingError(message))
        case let .empty(nonBlocking):
            if let nonBlocking {
                items.append(.inlineErrorBanner(nonBlocking))
            }
            items.append(.empty)
        case let .content(nonBlocking):
            if let nonBlocking {
                items.append(.inlineErrorBanner(nonBlocking))
            }
            items.append(contentsOf: listViewModel.displayedRows.map { .topic($0.topic.id) })
            if listViewModel.currentKindNextPage != nil {
                items.append(.loadingMore)
            }
        }
        sections.append(.init(id: .content, items: items))
        return sections
    }

    private func itemContentToken(for item: FireFilteredTopicItem) -> AnyHashable {
        switch item {
        case .feedSelector:
            return listViewModel.selectedKind
        case let .blockingError(message), let .inlineErrorBanner(message):
            return message
        case let .loadingSkeleton(index):
            return index
        case .empty:
            return "empty"
        case let .topic(id):
            if let row = listViewModel.displayedRows.first(where: { $0.topic.id == id }) {
                return "\(id)-\(row.topic.likeCount)-\(row.topic.replyCount)-\(row.topic.bookmarkId ?? 0)"
            }
            return id
        case .loadingMore:
            return listViewModel.isLoadingMore
        }
    }

    private func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireFilteredTopicItem
    ) -> UICollectionViewCell {
        switch item {
        case .feedSelector:
            return collectionView.dequeueConfiguredReusableCell(
                using: feedSelectorCellRegistration,
                for: indexPath,
                item: item
            )
        case .blockingError, .empty, .loadingMore:
            return collectionView.dequeueConfiguredReusableCell(
                using: stateCellRegistration,
                for: indexPath,
                item: item
            )
        case .loadingSkeleton:
            return collectionView.dequeueConfiguredReusableCell(
                using: skeletonCellRegistration,
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

    private func canSelect(_ item: FireFilteredTopicItem) -> Bool {
        if case .topic = item { return true }
        return false
    }

    private func handleSelection(_ item: FireFilteredTopicItem) {
        guard case let .topic(id) = item,
              let row = listViewModel.displayedRows.first(where: { $0.topic.id == id })
        else { return }
        presentRoute(.topic(row: row))
    }

    private func handleVisibleItemsChanged(_ items: [FireFilteredTopicItem]) {
        let nearEnd = items.contains {
            if case .loadingMore = $0 { return true }
            if case let .topic(id) = $0 {
                return id == listViewModel.displayedRows.last?.topic.id
            }
            return false
        }
        guard nearEnd else { return }
        loadTask = Task { [weak self] in
            await self?.listViewModel.loadMore()
        }
    }

    private func contextMenuConfiguration(
        for item: FireFilteredTopicItem
    ) -> UIContextMenuConfiguration? {
        guard case let .topic(id) = item,
              let row = listViewModel.displayedRows.first(where: { $0.topic.id == id })
        else { return nil }
        let shareURL = row.fireTopicURL(baseURL: baseURLString)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "打开话题", image: UIImage(systemName: "arrow.up.right")) { _ in
                    self?.presentRoute(.topic(row: row))
                },
                UIAction(
                    title: row.topic.bookmarkId == nil ? "添加书签" : "编辑书签",
                    image: UIImage(systemName: row.topic.bookmarkId == nil ? "bookmark" : "bookmark.fill")
                ) { _ in
                    self?.presentBookmarkEditor(for: row)
                },
                UIAction(title: "分享话题", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    self?.presentShareSheet(url: shareURL)
                },
                UIAction(title: "复制链接", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = shareURL.absoluteString
                    self?.showToast("已复制链接", style: .success)
                },
                UIAction(title: "静音话题", image: UIImage(systemName: "bell.slash")) { _ in
                    self?.muteTopic(row)
                },
            ])
        }
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
        }
    }

    private func presentShareSheet(url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(controller, animated: true)
    }

    private func presentBookmarkEditor(for row: FireTopicRowPresentation) {
        let context = row.fireBookmarkEditorContext()
        let sheet = FireBookmarkEditorSheet(
            context: context,
            onSave: { [weak self] name, reminderAt in
                guard let self else { return }
                if let bookmarkID = context.bookmarkID {
                    try await self.appViewModel.topicInteraction.updateBookmark(
                        bookmarkID: bookmarkID,
                        name: name,
                        reminderAt: reminderAt
                    )
                } else {
                    _ = try await self.appViewModel.topicInteraction.createBookmark(
                        bookmarkableID: context.bookmarkableID,
                        bookmarkableType: context.bookmarkableType,
                        name: name,
                        reminderAt: reminderAt
                    )
                }
                await self.listViewModel.refresh()
            },
            onDelete: context.bookmarkID.map { bookmarkID in
                { [weak self] in
                    try await self?.appViewModel.topicInteraction.deleteBookmark(bookmarkID: bookmarkID)
                    await self?.listViewModel.refresh()
                }
            }
        )
        let host = UIHostingController(rootView: sheet)
        if let sheetController = host.sheetPresentationController {
            sheetController.detents = [.medium(), .large()]
            sheetController.prefersGrabberVisible = true
        }
        present(host, animated: true)
    }

    private func deleteBookmark(for row: FireTopicRowPresentation) {
        guard let bookmarkID = row.topic.bookmarkId else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await appViewModel.topicInteraction.deleteBookmark(bookmarkID: bookmarkID)
                await listViewModel.refresh()
                showToast("已删除书签", style: .success)
            } catch {
                showToast(error.localizedDescription, style: .error)
            }
        }
    }

    private func muteTopic(_ row: FireTopicRowPresentation) {
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await appViewModel.topicInteraction.setTopicNotificationLevel(
                    topicID: row.topic.id,
                    notificationLevel: FireTopicNotificationLevelOption.muted.rawValue
                )
                showToast("已静音话题", style: .success)
            } catch {
                showToast(error.localizedDescription, style: .error)
            }
        }
    }

    private func showToast(_ message: String, style: FireUIKitToast.Style) {
        FireUIKitToast.show(message, style: style, in: view)
    }
}

// MARK: - Supporting cells

private final class FireFilteredFeedSelectorCell: UICollectionViewCell {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

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
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    func configure(
        selectedKind: TopicListKindState,
        onSelectKind: @escaping (TopicListKindState) -> Void
    ) {
        prepareForReuse()
        for kind in TopicListKindState.orderedCases {
            var configuration = UIButton.Configuration.filled()
            configuration.title = kind.title
            configuration.cornerStyle = .capsule
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            let selected = selectedKind == kind
            configuration.baseBackgroundColor = selected ? FireTheme.uiAccent : .tertiarySystemFill
            configuration.baseForegroundColor = selected ? .white : .label
            let button = UIButton(configuration: configuration)
            button.addAction(UIAction { _ in
                FireMotionHaptics.selection()
                onSelectKind(kind)
            }, for: .touchUpInside)
            stackView.addArrangedSubview(button)
        }
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }
}

/// Shared-style skeleton matching home feed placeholder geometry.
final class FireHomeStyleSkeletonCell: UICollectionViewCell {
    private let avatarView = UIView()
    private let titleBar = UIView()
    private let subtitleBar = UIView()

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
        FireUIKitSkeleton.hide(contentView)
    }

    func configure() {
        isAccessibilityElement = false
        FireUIKitSkeleton.show(contentView)
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        avatarView.layer.cornerRadius = 19
        avatarView.layer.cornerCurve = .continuous
        titleBar.layer.cornerRadius = 4
        subtitleBar.layer.cornerRadius = 4
        let body = UIStackView(arrangedSubviews: [titleBar, subtitleBar])
        body.axis = .vertical
        body.spacing = 6
        let row = UIStackView(arrangedSubviews: [avatarView, body])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 38),
            avatarView.heightAnchor.constraint(equalToConstant: 38),
            titleBar.heightAnchor.constraint(equalToConstant: 14),
            titleBar.widthAnchor.constraint(equalTo: body.widthAnchor),
            subtitleBar.widthAnchor.constraint(equalToConstant: 100),
            subtitleBar.heightAnchor.constraint(equalToConstant: 10),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
        FireUIKitSkeleton.prepareHierarchy(in: contentView)
    }
}

private final class FireFilteredTopicListControllerReference {
    weak var controller: FireFilteredTopicListViewController?
}
