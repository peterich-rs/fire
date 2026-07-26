import Combine
import SwiftUI
import UIKit

struct FireBookmarksControllerHost: UIViewControllerRepresentable {
    @Environment(\.fireTopicRoutePresenter) private var topicRoutePresenter
    @EnvironmentObject private var topicDetailStore: FireTopicDetailStore

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
    private let bookmarksViewModel: FireBookmarksViewModel
    private let controllerReference: FireBookmarksControllerReference
    private let listController: FireListViewController<FireBookmarksCollectionSection, FireBookmarksCollectionItem>
    private var topicRoutePresenter: FireTopicRoutePresenter
    private var cancellables: Set<AnyCancellable> = []
    private var loadTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private weak var toastView: UIView?

    private lazy var stateCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var bannerCellRegistration = UICollectionView.CellRegistration<
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

    private lazy var topicCellRegistration = UICollectionView.CellRegistration<
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

    private func prepareCellRegistrations() {
        _ = stateCellRegistration
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
        bookmarksViewModel.objectWillChange
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
            rows: bookmarksViewModel.rows,
            nextPage: bookmarksViewModel.nextPage,
            isLoading: bookmarksViewModel.isLoading,
            isLoadingMore: bookmarksViewModel.isLoadingMore,
            hasLoadedOnce: bookmarksViewModel.hasLoadedOnce,
            errorMessage: bookmarksViewModel.errorMessage
        )
    }

    private func render() {
        let sections = makeSections()
        var tokens: [FireBookmarksCollectionItem: AnyHashable] = [:]
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
        -> [FireListSectionModel<FireBookmarksCollectionSection, FireBookmarksCollectionItem>]
    {
        var items: [FireBookmarksCollectionItem] = []

        if let errorMessage = bookmarksViewModel.errorMessage,
           bookmarksViewModel.hasLoadedOnce {
            items.append(.inlineErrorBanner(errorMessage))
        }

        if !bookmarksViewModel.hasLoadedOnce {
            if let errorMessage = bookmarksViewModel.errorMessage {
                items.append(.blockingError(errorMessage))
            } else {
                items.append(.loading)
            }
        } else if bookmarksViewModel.rows.isEmpty {
            items.append(.empty)
        } else {
            items.append(contentsOf: bookmarksViewModel.rows.map {
                .bookmark(FireBookmarksViewModel.rowID(for: $0))
            })

            if bookmarksViewModel.isLoadingMore {
                items.append(.loadingMore)
            }
        }

        return [.init(id: .content, items: items)]
    }

    private func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireBookmarksCollectionItem
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
        case .bookmark:
            return collectionView.dequeueConfiguredReusableCell(
                using: topicCellRegistration,
                for: indexPath,
                item: item
            )
        }
    }

    private func canSelect(_ item: FireBookmarksCollectionItem) -> Bool {
        if case .bookmark = item {
            return true
        }
        return false
    }

    private func handleSelection(_ item: FireBookmarksCollectionItem) {
        guard case let .bookmark(id) = item,
              let row = bookmarksViewModel.row(for: id) else { return }
        presentRoute(.topic(
            row: row,
            postNumber: row.topic.bookmarkedPostNumber ?? row.topic.lastReadPostNumber
        ))
    }

    private func handleVisibleItemsChanged(_ items: [FireBookmarksCollectionItem]) {
        loadMoreIfNeeded(from: items)
    }

    private func loadMoreIfNeeded(from items: [FireBookmarksCollectionItem]) {
        guard let lastRowID = bookmarksViewModel.lastRowID else { return }
        guard items.contains(.bookmark(lastRowID)) || items.contains(.loadingMore) else { return }
        loadTask = Task { [weak self] in
            await self?.bookmarksViewModel.loadMoreIfNeeded(currentRowID: lastRowID)
        }
    }

    private func contextMenuConfiguration(
        for item: FireBookmarksCollectionItem
    ) -> UIContextMenuConfiguration? {
        guard case let .bookmark(rowID) = item,
              let row = bookmarksViewModel.row(for: rowID)
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
                self?.presentRoute(.topic(
                    row: row,
                    postNumber: row.topic.bookmarkedPostNumber ?? row.topic.lastReadPostNumber
                ))
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

    private func itemContentToken(for item: FireBookmarksCollectionItem) -> AnyHashable {
        switch item {
        case let .blockingError(message), let .inlineErrorBanner(message):
            return AnyHashable(message)
        case .loading:
            return AnyHashable(bookmarksViewModel.isLoading)
        case .empty:
            return AnyHashable(bookmarksViewModel.hasLoadedOnce)
        case let .bookmark(id):
            guard let row = bookmarksViewModel.row(for: id) else {
                return AnyHashable("missing|\(id.value)")
            }
            return AnyHashable(bookmarkRowContentToken(row))
        case .loadingMore:
            return AnyHashable(bookmarksViewModel.isLoadingMore)
        }
    }

    private func bookmarkRowContentToken(_ row: FireTopicRowPresentation) -> String {
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
        if route.presentsAsSecondaryPage {
            FireAppRouteControllerFactory.presentSecondaryRoute(
                route,
                viewModel: appViewModel,
                topicDetailStore: topicDetailStore
            )
        }
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
        await bookmarksViewModel.refresh()
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
                self?.bookmarksViewModel.reportError(error.localizedDescription)
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
        await bookmarksViewModel.refresh()
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
        toastDismissTask?.cancel()
        toastView?.removeFromSuperview()
        toastView = nil
        FireUIKitToast.show(message, style: FireUIKitToast.Style(style), in: view)
    }
}

final class FireTopicListStateCell: UICollectionViewCell {
    private let stackView = UIStackView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var onAction: (() -> Void)?

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
        onAction = nil
        actionButton.isHidden = true
        activityIndicator.stopAnimating()
    }

    func configureLoading(title: String = "正在加载书签") {
        iconView.isHidden = true
        activityIndicator.isHidden = false
        activityIndicator.startAnimating()
        titleLabel.text = title
        messageLabel.text = nil
        actionButton.isHidden = true
        setCompact(false)
    }

    func configureLoadingMore() {
        iconView.isHidden = true
        activityIndicator.isHidden = false
        activityIndicator.startAnimating()
        titleLabel.text = nil
        messageLabel.text = nil
        actionButton.isHidden = true
        setCompact(true)
    }

    func configureEmpty(
        title: String = "还没有书签",
        message: String = "把想回看的话题或帖子收进来，后续会统一在这里管理。",
        systemImage: String = "bookmark"
    ) {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        iconView.isHidden = false
        iconView.image = UIImage(systemName: systemImage)
        iconView.tintColor = .tertiaryLabel
        titleLabel.text = title
        messageLabel.text = message
        actionButton.isHidden = true
        setCompact(false)
    }

    func configureBlockingError(
        title: String = "书签加载失败",
        message: String,
        onRetry: @escaping () -> Void
    ) {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        iconView.isHidden = false
        iconView.image = UIImage(systemName: "exclamationmark.triangle.fill")
        iconView.tintColor = .systemRed
        titleLabel.text = title
        messageLabel.text = message
        actionButton.isHidden = false
        actionButton.setTitle("重试", for: .normal)
        self.onAction = onRetry
        setCompact(false)
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 24,
            leading: 24,
            bottom: 24,
            trailing: 24
        )

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        messageLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true

        actionButton.addAction(UIAction { [weak self] _ in
            self?.onAction?()
        }, for: .touchUpInside)

        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(activityIndicator)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(messageLabel)
        stackView.addArrangedSubview(actionButton)

        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34),
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    private func setCompact(_ compact: Bool) {
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: compact ? 10 : 24,
            leading: 24,
            bottom: compact ? 10 : 24,
            trailing: 24
        )
    }
}

final class FireTopicListErrorBannerCell: UICollectionViewCell {
    private let containerView = UIView()
    private let iconView = UIImageView(image: UIImage(systemName: "exclamationmark.circle.fill"))
    private let messageLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let dismissButton = UIButton(type: .system)
    private var onCopy: (() -> Void)?
    private var onDismiss: (() -> Void)?

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
        onCopy = nil
        onDismiss = nil
    }

    func configure(
        message: String,
        onCopy: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        messageLabel.text = message
        self.onCopy = onCopy
        self.onDismiss = onDismiss
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 8,
            trailing: 16
        )

        containerView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.10)
        containerView.layer.cornerRadius = 8
        containerView.translatesAutoresizingMaskIntoConstraints = false

        iconView.tintColor = .systemRed
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        messageLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .label
        messageLabel.numberOfLines = 3

        copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copyButton.accessibilityLabel = "复制错误"
        copyButton.addAction(UIAction { [weak self] _ in
            self?.onCopy?()
        }, for: .touchUpInside)

        dismissButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        dismissButton.accessibilityLabel = "关闭错误"
        dismissButton.addAction(UIAction { [weak self] _ in
            self?.onDismiss?()
        }, for: .touchUpInside)

        let stackView = UIStackView(arrangedSubviews: [
            iconView,
            messageLabel,
            copyButton,
            dismissButton,
        ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(containerView)
        containerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            containerView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
            copyButton.widthAnchor.constraint(equalToConstant: 32),
            copyButton.heightAnchor.constraint(equalToConstant: 32),
            dismissButton.widthAnchor.constraint(equalToConstant: 32),
            dismissButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }
}

final class FireTopicListTopicCell: UICollectionViewCell {
    private let outerStack = UIStackView()
    private let metaStack = UIStackView()
    private let bookmarkNameLabel = UILabel()
    private let reminderLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    private let avatarView = FireTopicListAvatarView()
    private let titleLabel = UILabel()
    private let chipStack = UIStackView()
    private let usernameLabel = UILabel()
    private let timestampLabel = UILabel()
    private let replyMetric = FireTopicListMetricView(kind: .replies)
    private let viewsMetric = FireTopicListMetricView(kind: .views)
    private let likesMetric = FireTopicListMetricView(kind: .likes)
    private var onEditBookmark: (() -> Void)?
    private var onDeleteBookmark: (() -> Void)?
    private var boundTopicID: UInt64?
    private var pendingViewSurgePulse = false
    private var pendingHeartBalloon = false
    private var pendingHeartTint: UIColor = FireTheme.uiAccent

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
        FireTopicListMetricEffectCoordinator.shared.untrack(self)
        boundTopicID = nil
        pendingViewSurgePulse = false
        pendingHeartBalloon = false
        avatarView.prepareForReuse()
        replyMetric.prepareForReuse()
        viewsMetric.prepareForReuse()
        likesMetric.prepareForReuse()
        onEditBookmark = nil
        onDeleteBookmark = nil
        moreButton.menu = nil
    }

    private func configureMetrics(for row: FireTopicRowPresentation) {
        let created = row.createdTimestampUnixMs
        boundTopicID = row.topic.id

        let replyEmphasis = FireTopicListMetricRanking.emphasis(
            kind: .replies,
            value: row.topic.replyCount,
            createdTimestampUnixMs: created
        )
        let viewsEmphasis = FireTopicListMetricRanking.emphasis(
            kind: .views,
            value: row.topic.views,
            createdTimestampUnixMs: created
        )
        let likesEmphasis = FireTopicListMetricRanking.emphasis(
            kind: .likes,
            value: row.topic.likeCount,
            createdTimestampUnixMs: created
        )

        // Static chrome always updates immediately — only micro-animations wait.
        replyMetric.configure(value: row.topic.replyCount, emphasis: replyEmphasis)
        viewsMetric.configure(
            value: row.topic.views,
            emphasis: viewsEmphasis,
            surgeAccessorySymbol: viewsEmphasis == .surge
                ? FireTopicListMetricRanking.surgeAccessorySymbol(createdTimestampUnixMs: created)
                : nil,
            animateEffects: false
        )
        likesMetric.configure(
            value: row.topic.likeCount,
            emphasis: likesEmphasis,
            animateEffects: false
        )

        pendingViewSurgePulse = viewsEmphasis == .surge
            && !FireTopicListMetricEffectCoordinator.shared.hasPlayed(
                .viewSurgePulse,
                topicID: row.topic.id
            )
        pendingHeartBalloon = likesEmphasis == .high
            && !FireTopicListMetricEffectCoordinator.shared.hasPlayed(
                .heartBalloon,
                topicID: row.topic.id
            )
        pendingHeartTint = FireTopicListMetricView.tint(
            kind: .likes,
            emphasis: likesEmphasis
        )

        FireTopicListMetricEffectCoordinator.shared.track(self)
    }

    /// Invoked by the effect coordinator once the host list is settled.
    func playPendingMetricEffectsIfNeeded() {
        guard let topicID = boundTopicID else { return }
        guard FireTopicListMetricEffectCoordinator.shared.isSettled else { return }
        guard window != nil else { return }

        if pendingViewSurgePulse {
            pendingViewSurgePulse = false
            if FireTopicListMetricEffectCoordinator.shared.claim(.viewSurgePulse, topicID: topicID) {
                viewsMetric.playSurgePulse()
            }
        }

        if pendingHeartBalloon {
            pendingHeartBalloon = false
            if FireTopicListMetricEffectCoordinator.shared.claim(.heartBalloon, topicID: topicID) {
                likesMetric.playHeartBalloons(tint: pendingHeartTint)
            }
        }
    }

    func configureMissing() {
        FireTopicListMetricEffectCoordinator.shared.untrack(self)
        boundTopicID = nil
        pendingViewSurgePulse = false
        pendingHeartBalloon = false
        titleLabel.text = nil
        chipStack.arrangedSubviews.forEach { view in
            chipStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        metaStack.isHidden = true
        avatarView.prepareForReuse()
        replyMetric.prepareForReuse()
        viewsMetric.prepareForReuse()
        likesMetric.prepareForReuse()
    }

    func configure(
        row: FireTopicRowPresentation,
        category: FireTopicCategoryPresentation?,
        baseURLString: String,
        onEditBookmark: @escaping () -> Void,
        onDeleteBookmark: @escaping () -> Void
    ) {
        let username = Self.displayUsername(for: row)
        self.onEditBookmark = onEditBookmark
        self.onDeleteBookmark = onDeleteBookmark

        titleLabel.text = row.topic.title
        usernameLabel.text = username
        timestampLabel.text = FireTopicPresentation.compactTimestamp(unixMs: row.createdTimestampUnixMs)
        configureMetrics(for: row)
        avatarView.configure(
            username: username,
            avatarTemplate: row.originalPosterAvatarTemplate,
            baseURLString: baseURLString
        )
        configureMeta(row: row)
        configureChips(row: row, category: category)
        configureMenu(canDelete: row.topic.bookmarkId != nil)

        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = Self.accessibilitySummary(row: row, category: category, username: username)
        accessibilityHint = "双击查看话题详情"
    }

    private func configureMeta(row: FireTopicRowPresentation) {
        let bookmarkName = row.topic.bookmarkName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reminder = FireTopicPresentation.compactTimestamp(row.topic.bookmarkReminderAt)
        bookmarkNameLabel.text = bookmarkName.isEmpty ? nil : "书签：\(bookmarkName)"
        reminderLabel.text = reminder.map { "提醒：\($0)" }
        bookmarkNameLabel.isHidden = bookmarkNameLabel.text == nil
        reminderLabel.isHidden = reminderLabel.text == nil
        moreButton.isHidden = row.topic.bookmarkId == nil
        metaStack.isHidden = bookmarkNameLabel.isHidden && reminderLabel.isHidden && moreButton.isHidden
    }

    private func configureMenu(canDelete: Bool) {
        guard canDelete else {
            moreButton.menu = nil
            return
        }
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = UIMenu(children: [
            UIAction(title: "编辑", image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.onEditBookmark?()
            },
            UIAction(
                title: "删除",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.onDeleteBookmark?()
            },
        ])
    }

    private func configureChips(
        row: FireTopicRowPresentation,
        category: FireTopicCategoryPresentation?
    ) {
        chipStack.arrangedSubviews.forEach { view in
            chipStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if let category {
            let categoryTint = UIColor(fireHex: category.colorHex) ?? FireTopicListPalette.accent
            chipStack.addArrangedSubview(
                FireTopicListChipLabel(
                    text: category.displayName,
                    textColor: categoryTint,
                    backgroundColor: FireTopicListPalette.categoryChipBackground(accent: categoryTint)
                )
            )
        }

        for tagName in row.tagNames.prefix(3) {
            chipStack.addArrangedSubview(
                FireTopicListChipLabel(
                    text: "#\(tagName)",
                    textColor: FireTopicListPalette.tagChipForeground,
                    backgroundColor: FireTopicListPalette.tagChipBackground
                )
            )
        }

        if row.isPinned {
            chipStack.addArrangedSubview(FireTopicListIconChip(systemImage: "pin.fill", tintColor: .systemOrange))
        }
        if row.hasAcceptedAnswer {
            chipStack.addArrangedSubview(
                FireTopicListIconChip(systemImage: "checkmark.circle.fill", tintColor: .systemGreen)
            )
        }
        if row.hasUnreadPosts {
            chipStack.addArrangedSubview(FireTopicListUnreadDot())
        }

        let chipCount = chipStack.arrangedSubviews.count
        if chipCount > 0 {
            let spacer = UIView()
            spacer.isAccessibilityElement = false
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            chipStack.addArrangedSubview(spacer)
        }
        chipStack.isHidden = chipCount == 0
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        // Allow high-like heart balloons to rise a few points above the metric chip.
        clipsToBounds = false
        contentView.clipsToBounds = false
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 10,
            leading: 16,
            bottom: 10,
            trailing: 16
        )

        outerStack.axis = .vertical
        outerStack.spacing = 8
        outerStack.clipsToBounds = false
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        metaStack.axis = .horizontal
        metaStack.alignment = .center
        metaStack.spacing = 8

        [bookmarkNameLabel, reminderLabel].forEach { label in
            label.font = UIFont.preferredFont(forTextStyle: .caption1)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .secondaryLabel
            label.numberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.tintColor = .tertiaryLabel
        moreButton.accessibilityLabel = "书签操作"
        moreButton.setContentHuggingPriority(.required, for: .horizontal)
        moreButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        moreButton.heightAnchor.constraint(equalToConstant: 32).isActive = true

        metaStack.addArrangedSubview(bookmarkNameLabel)
        metaStack.addArrangedSubview(reminderLabel)
        metaStack.addArrangedSubview(UIView())
        metaStack.addArrangedSubview(moreButton)

        let rowStack = UIStackView()
        rowStack.axis = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = 12
        rowStack.clipsToBounds = false

        let bodyStack = UIStackView()
        bodyStack.axis = .vertical
        bodyStack.alignment = .fill
        bodyStack.spacing = 7
        bodyStack.clipsToBounds = false

        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        chipStack.axis = .horizontal
        chipStack.alignment = .center
        chipStack.spacing = 6

        let bylineStack = UIStackView()
        bylineStack.axis = .horizontal
        bylineStack.alignment = .center
        bylineStack.spacing = 6

        usernameLabel.font = UIFont.preferredFont(forTextStyle: .caption1).withWeight(.medium)
        usernameLabel.adjustsFontForContentSizeCategory = true
        usernameLabel.textColor = FireTopicListPalette.subtleInk
        usernameLabel.numberOfLines = 1

        timestampLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        timestampLabel.adjustsFontForContentSizeCategory = true
        timestampLabel.textColor = FireTopicListPalette.tertiaryInk
        timestampLabel.numberOfLines = 1

        bylineStack.addArrangedSubview(usernameLabel)
        bylineStack.addArrangedSubview(timestampLabel)
        bylineStack.addArrangedSubview(UIView())

        // Reply + views stay left-clustered; likes hug the trailing edge for balance.
        let leadingMetrics = UIStackView(arrangedSubviews: [replyMetric, viewsMetric])
        leadingMetrics.axis = .horizontal
        leadingMetrics.alignment = .center
        leadingMetrics.spacing = 14
        leadingMetrics.clipsToBounds = false

        let metricSpacer = UIView()
        metricSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        metricSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        likesMetric.setContentHuggingPriority(.required, for: .horizontal)
        likesMetric.setContentCompressionResistancePriority(.required, for: .horizontal)

        let metricStack = UIStackView(arrangedSubviews: [leadingMetrics, metricSpacer, likesMetric])
        metricStack.axis = .horizontal
        metricStack.alignment = .center
        metricStack.spacing = 8
        metricStack.clipsToBounds = false

        bodyStack.addArrangedSubview(titleLabel)
        bodyStack.addArrangedSubview(chipStack)
        bodyStack.addArrangedSubview(bylineStack)
        bodyStack.addArrangedSubview(metricStack)

        rowStack.addArrangedSubview(avatarView)
        rowStack.addArrangedSubview(bodyStack)

        outerStack.addArrangedSubview(metaStack)
        outerStack.addArrangedSubview(rowStack)

        contentView.addSubview(outerStack)
        // Self-sizing list cells briefly apply UIView-Encapsulated-Layout-Height (often ~52).
        // Keep the bottom edge one step below required so that temporary height does not fight
        // fixed metric icon sizes and spam unsatisfiable-constraint logs.
        let bottom = outerStack.bottomAnchor.constraint(
            equalTo: contentView.layoutMarginsGuide.bottomAnchor
        )
        bottom.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 36),
            avatarView.heightAnchor.constraint(equalToConstant: 36),
            outerStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            outerStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            bottom,
        ])
    }

    private static func displayUsername(for row: FireTopicRowPresentation) -> String {
        row.originalPosterUsername
            ?? row.topic.lastPosterUsername
            ?? fallbackPresentationUsername(for: row)
            ?? row.topic.posters.first.map { "User \($0.userId)" }
            ?? "?"
    }

    private static func fallbackPresentationUsername(for row: FireTopicRowPresentation) -> String? {
        guard let candidate = row.lastPosterUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty
        else {
            return nil
        }
        return candidate.localizedCaseInsensitiveContains("poster") ? nil : candidate
    }

    private static func accessibilitySummary(
        row: FireTopicRowPresentation,
        category: FireTopicCategoryPresentation?,
        username: String
    ) -> String {
        var parts = [row.topic.title]
        if let category {
            parts.append(category.displayName)
        }
        if !username.isEmpty, username != "?" {
            parts.append(username)
        }
        parts.append("\(row.topic.replyCount) 回复")
        parts.append("\(row.topic.views) 浏览")
        if row.topic.likeCount > 0 {
            parts.append("\(row.topic.likeCount) 赞")
        }
        if row.isPinned {
            parts.append("置顶")
        }
        if row.hasAcceptedAnswer {
            parts.append("已有采纳答案")
        }
        if row.hasUnreadPosts {
            parts.append("有未读回复")
        }
        return parts.joined(separator: "，")
    }
}

final class FireTopicListAvatarView: UIView {
    private let imageView = UIImageView()
    private let monogramLabel = UILabel()
    private var imageTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {
        imageTask?.cancel()
        imageTask = nil
        generation &+= 1
        imageView.image = nil
        imageView.alpha = 0
    }

    func configure(
        username: String,
        avatarTemplate: String?,
        baseURLString: String
    ) {
        prepareForReuse()
        monogramLabel.text = monogramForUsername(username: username.isEmpty ? "?" : username)
        let avatarURL = fireAvatarURL(
            avatarTemplate: avatarTemplate,
            size: 36,
            scale: UIScreen.main.scale,
            baseURLString: baseURLString
        )
        guard let avatarURL else { return }

        let request = FireRemoteImageRequest(url: avatarURL)
        if let cachedImage = FireRemoteImagePipeline.shared.cachedImage(for: request) {
            imageView.image = cachedImage
            imageView.alpha = 1
            return
        }

        let currentGeneration = generation
        imageTask = Task { [weak self] in
            do {
                let image = try await FireRemoteImagePipeline.shared.loadImage(for: request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.apply(image: image, generation: currentGeneration)
                }
            } catch {
                return
            }
        }
    }

    private func apply(image: UIImage, generation: UInt64) {
        guard self.generation == generation else { return }
        imageView.image = image
        imageView.alpha = 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Stay circular at every call-site size (home 36 / profile header 56).
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    private func configureSubviews() {
        clipsToBounds = true
        backgroundColor = FireTopicListPalette.accent

        monogramLabel.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        monogramLabel.textColor = .white
        monogramLabel.textAlignment = .center
        monogramLabel.translatesAutoresizingMaskIntoConstraints = false

        imageView.contentMode = .scaleAspectFill
        imageView.alpha = 0
        imageView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(monogramLabel)
        addSubview(imageView)
        NSLayoutConstraint.activate([
            monogramLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            monogramLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            monogramLabel.topAnchor.constraint(equalTo: topAnchor),
            monogramLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

final class FireTopicListMetricView: UIView {
    private let kind: FireTopicListMetricKind
    private let imageView = UIImageView()
    private let accessoryView = UIImageView()
    private let valueLabel = UILabel()
    private var isPulsing = false
    private var heartBalloonWorkItems: [DispatchWorkItem] = []
    private var activeHeartViews: [UIView] = []

    private static let pulseKey = "fire.metric.surgePulse"
    /// Finite breaths so surge does not loop forever on a parked row.
    private static let surgePulseRepeatCount: Float = 3
    /// Keep balloon bursts rare: only true high-likes, 2 tiny hearts, one shot.
    private static let heartBalloonCount = 2

    init(kind: FireTopicListMetricKind) {
        self.kind = kind
        super.init(frame: .zero)
        // Hearts float slightly above the chip; ancestors must not clip either.
        clipsToBounds = false
        isUserInteractionEnabled = false
        configureSubviews()
        apply(value: 0, emphasis: .normal, surgeAccessorySymbol: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {
        stopPulse()
        cancelHeartBalloons()
        accessoryView.isHidden = true
        accessoryView.image = nil
        apply(value: 0, emphasis: .normal, surgeAccessorySymbol: nil)
    }

    /// Updates static metric chrome. Micro-animations are opt-in via
    /// `playSurgePulse()` / `playHeartBalloons(tint:)` after the list settles.
    func configure(
        value: UInt32,
        emphasis: FireTopicListMetricEmphasis,
        surgeAccessorySymbol: String? = nil,
        animateEffects: Bool = true
    ) {
        apply(value: value, emphasis: emphasis, surgeAccessorySymbol: surgeAccessorySymbol)

        // Legacy path (if any caller still wants immediate play). Prefer the
        // coordinator-driven APIs from the topic cell.
        guard animateEffects else { return }
        if emphasis == .surge {
            playSurgePulse()
        }
        if kind == .likes, emphasis == .high {
            playHeartBalloons(tint: Self.tint(kind: kind, emphasis: emphasis))
        }
    }

    static func tint(kind: FireTopicListMetricKind, emphasis: FireTopicListMetricEmphasis) -> UIColor {
        style(kind: kind, emphasis: emphasis).tint
    }

    func playSurgePulse() {
        guard kind == .views else { return }
        guard !accessoryView.isHidden else { return }
        startPulseIfNeeded()
    }

    func playHeartBalloons(tint: UIColor) {
        guard kind == .likes else { return }
        scheduleHeartBalloons(tint: tint)
    }

    private func apply(
        value: UInt32,
        emphasis: FireTopicListMetricEmphasis,
        surgeAccessorySymbol: String?
    ) {
        // Always clear running effects before restyling — scrolling may rebind the cell.
        stopPulse()
        cancelHeartBalloons()

        let style = Self.style(kind: kind, emphasis: emphasis)
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: style.symbolWeight)
        imageView.image = UIImage(systemName: style.symbol, withConfiguration: symbolConfig)
        imageView.tintColor = style.tint

        valueLabel.text = FireTopicPresentation.compactCount(value)
        valueLabel.textColor = style.tint
        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: style.fontWeight)

        if emphasis == .surge, let accessory = surgeAccessorySymbol {
            let accessoryConfig = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            accessoryView.image = UIImage(systemName: accessory, withConfiguration: accessoryConfig)
            accessoryView.tintColor = style.accessoryTint
            accessoryView.isHidden = false
        } else {
            accessoryView.isHidden = true
            accessoryView.image = nil
        }

        accessibilityLabel = Self.accessibilityLabel(
            kind: kind,
            value: value,
            emphasis: emphasis
        )
    }

    private func configureSubviews() {
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        accessoryView.contentMode = .scaleAspectFit
        accessoryView.setContentHuggingPriority(.required, for: .horizontal)
        accessoryView.isHidden = true

        valueLabel.numberOfLines = 1
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        // Keep icon→number spacing constant. Surge badge sits after the count so
        // flame/rocket never opens a gap between the metric glyph and digits.
        let stack = UIStackView(arrangedSubviews: [imageView, valueLabel, accessoryView])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 3
        stack.clipsToBounds = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Tighter gap between the count and the surge badge than icon→count.
        stack.setCustomSpacing(2, after: valueLabel)

        addSubview(stack)
        let imageWidth = imageView.widthAnchor.constraint(equalToConstant: 13)
        let imageHeight = imageView.heightAnchor.constraint(equalToConstant: 13)
        let accessoryWidth = accessoryView.widthAnchor.constraint(equalToConstant: 10)
        let accessoryHeight = accessoryView.heightAnchor.constraint(equalToConstant: 10)
        // Soften fixed icon sizes so parent self-sizing passes never break required constraints.
        [imageWidth, imageHeight, accessoryWidth, accessoryHeight].forEach {
            $0.priority = UILayoutPriority(999)
        }
        NSLayoutConstraint.activate([
            imageWidth,
            imageHeight,
            accessoryWidth,
            accessoryHeight,
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func startPulseIfNeeded() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            stopPulse()
            return
        }
        guard !isPulsing else { return }
        isPulsing = true

        // Tiny breathe on the surge badge only — finite, never the whole metric row.
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.55
        opacity.toValue = 1.0
        opacity.duration = 1.6
        opacity.autoreverses = true
        opacity.repeatCount = Self.surgePulseRepeatCount
        opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        opacity.isRemovedOnCompletion = false
        opacity.fillMode = .forwards

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.92
        scale.toValue = 1.08
        scale.duration = 1.6
        scale.autoreverses = true
        scale.repeatCount = Self.surgePulseRepeatCount
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        scale.isRemovedOnCompletion = false
        scale.fillMode = .forwards

        accessoryView.layer.add(opacity, forKey: Self.pulseKey + ".opacity")
        accessoryView.layer.add(scale, forKey: Self.pulseKey + ".scale")

        let total = TimeInterval(Self.surgePulseRepeatCount) * 1.6 * 2
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
            self?.stopPulse()
        }
    }

    private func stopPulse() {
        isPulsing = false
        accessoryView.layer.removeAnimation(forKey: Self.pulseKey + ".opacity")
        accessoryView.layer.removeAnimation(forKey: Self.pulseKey + ".scale")
        accessoryView.layer.opacity = 1
        accessoryView.layer.transform = CATransform3DIdentity
    }

    private func scheduleHeartBalloons(tint: UIColor) {
        guard kind == .likes else { return }
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        cancelHeartBalloons()

        // Defer until after Auto Layout so the heart originates on the icon.
        let start = DispatchWorkItem { [weak self] in
            self?.emitHeartBalloons(tint: tint)
        }
        heartBalloonWorkItems.append(start)
        DispatchQueue.main.async(execute: start)
    }

    private func emitHeartBalloons(tint: UIColor) {
        // Stagger two micro hearts so it reads as a soft bubble, not a particle storm.
        for index in 0..<Self.heartBalloonCount {
            let work = DispatchWorkItem { [weak self] in
                self?.spawnHeartBalloon(index: index, tint: tint)
            }
            heartBalloonWorkItems.append(work)
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.08 + Double(index) * 0.28,
                execute: work
            )
        }
    }

    private func spawnHeartBalloon(index: Int, tint: UIColor) {
        guard window != nil, bounds.width > 0 else { return }

        let size: CGFloat = index == 0 ? 8 : 7
        let config = UIImage.SymbolConfiguration(pointSize: size - 1, weight: .bold)
        let heart = UIImageView(image: UIImage(systemName: "heart.fill", withConfiguration: config))
        heart.tintColor = tint.withAlphaComponent(0.82)
        heart.contentMode = .scaleAspectFit
        heart.isUserInteractionEnabled = false
        heart.alpha = 0

        let iconFrame = imageView.convert(imageView.bounds, to: self)
        // Slight horizontal scatter so the two hearts do not stack.
        let driftX: CGFloat = index == 0 ? -3 : 5
        heart.frame = CGRect(
            x: iconFrame.midX - size / 2 + driftX * 0.2,
            y: iconFrame.midY - size / 2,
            width: size,
            height: size
        )
        addSubview(heart)
        activeHeartViews.append(heart)

        let rise: CGFloat = -(16 + CGFloat(index) * 5)
        let endDriftX: CGFloat = driftX

        // Phase 1: soft pop + lift. Phase 2: fade while still drifting up.
        UIView.animate(
            withDuration: 0.55,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
        ) {
            heart.alpha = 0.88
            heart.transform = CGAffineTransform(translationX: endDriftX * 0.45, y: rise * 0.55)
                .scaledBy(x: 1.08, y: 1.08)
        } completion: { [weak self, weak heart] _ in
            guard let heart else { return }
            UIView.animate(
                withDuration: 0.75,
                delay: 0.02,
                options: [.curveEaseIn, .allowUserInteraction, .beginFromCurrentState]
            ) {
                heart.alpha = 0
                heart.transform = CGAffineTransform(translationX: endDriftX, y: rise)
                    .scaledBy(x: 0.72, y: 0.72)
            } completion: { [weak self, weak heart] _ in
                heart?.removeFromSuperview()
                if let heart {
                    self?.activeHeartViews.removeAll { $0 === heart }
                }
            }
        }
    }

    private func cancelHeartBalloons() {
        heartBalloonWorkItems.forEach { $0.cancel() }
        heartBalloonWorkItems.removeAll()
        activeHeartViews.forEach { heart in
            heart.layer.removeAllAnimations()
            heart.removeFromSuperview()
        }
        activeHeartViews.removeAll()
    }

    fileprivate struct Style {
        let symbol: String
        let symbolWeight: UIImage.SymbolWeight
        let tint: UIColor
        let fontWeight: UIFont.Weight
        let accessoryTint: UIColor
    }

    fileprivate static func style(
        kind: FireTopicListMetricKind,
        emphasis: FireTopicListMetricEmphasis
    ) -> Style {
        let muted = FireTheme.uiTertiaryInk
        let soft = FireTheme.uiSubtleInk

        switch (kind, emphasis) {
        case (.replies, .normal):
            return Style(
                symbol: "bubble.left",
                symbolWeight: .regular,
                tint: muted,
                fontWeight: .regular,
                accessoryTint: muted
            )
        case (.replies, .notable):
            return Style(
                symbol: "bubble.left.fill",
                symbolWeight: .medium,
                tint: soft,
                fontWeight: .medium,
                accessoryTint: soft
            )
        case (.replies, .high), (.replies, .surge):
            return Style(
                symbol: "bubble.left.fill",
                symbolWeight: .semibold,
                tint: FireTheme.uiInfo,
                fontWeight: .semibold,
                accessoryTint: FireTheme.uiInfo
            )

        case (.views, .normal):
            return Style(
                symbol: "chart.bar",
                symbolWeight: .regular,
                tint: muted,
                fontWeight: .regular,
                accessoryTint: muted
            )
        case (.views, .notable):
            return Style(
                symbol: "chart.bar.fill",
                symbolWeight: .medium,
                tint: soft,
                fontWeight: .medium,
                accessoryTint: soft
            )
        case (.views, .high):
            return Style(
                symbol: "chart.bar.fill",
                symbolWeight: .semibold,
                tint: UIColor.systemTeal,
                fontWeight: .semibold,
                accessoryTint: UIColor.systemTeal
            )
        case (.views, .surge):
            return Style(
                symbol: "chart.bar.fill",
                symbolWeight: .semibold,
                tint: FireTheme.uiWarning,
                fontWeight: .semibold,
                accessoryTint: FireTheme.uiAccent
            )

        case (.likes, .normal):
            return Style(
                symbol: "heart",
                symbolWeight: .regular,
                tint: muted,
                fontWeight: .regular,
                accessoryTint: muted
            )
        case (.likes, .notable):
            return Style(
                symbol: "heart.fill",
                symbolWeight: .medium,
                tint: UIColor.systemPink.withAlphaComponent(0.85),
                fontWeight: .medium,
                accessoryTint: UIColor.systemPink
            )
        case (.likes, .high), (.likes, .surge):
            return Style(
                symbol: "heart.fill",
                symbolWeight: .semibold,
                tint: FireTheme.uiAccent,
                fontWeight: .semibold,
                accessoryTint: FireTheme.uiAccent
            )
        }
    }

    private static func accessibilityLabel(
        kind: FireTopicListMetricKind,
        value: UInt32,
        emphasis: FireTopicListMetricEmphasis
    ) -> String {
        let base: String
        switch kind {
        case .replies: base = "\(value) 回复"
        case .views: base = "\(value) 浏览"
        case .likes: base = "\(value) 赞"
        }
        switch emphasis {
        case .normal:
            return base
        case .notable:
            return base + "，热度偏高"
        case .high:
            return base + "，热门"
        case .surge:
            return base + "，浏览激增"
        }
    }
}

final class FireTopicListChipLabel: UILabel {
    init(text: String, textColor: UIColor, backgroundColor: UIColor) {
        super.init(frame: .zero)
        self.text = text
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        font = UIFont.preferredFont(forTextStyle: .caption2)
        adjustsFontForContentSizeCategory = true
        numberOfLines = 1
        lineBreakMode = .byTruncatingTail
        layer.cornerRadius = 4
        clipsToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 12, height: size.height + 4)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: 6, dy: 2))
    }
}

final class FireTopicListIconChip: UIView {
    init(systemImage: String, tintColor: UIColor) {
        super.init(frame: .zero)
        let imageView = UIImageView(image: UIImage(systemName: systemImage))
        imageView.tintColor = tintColor
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = tintColor.withAlphaComponent(0.12)
        layer.cornerRadius = 5
        addSubview(imageView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 18),
            heightAnchor.constraint(equalToConstant: 18),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 11),
            imageView.heightAnchor.constraint(equalToConstant: 11),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class FireTopicListUnreadDot: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = FireTopicListPalette.accent
        layer.cornerRadius = 3.5
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 7),
            heightAnchor.constraint(equalToConstant: 7),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class FireTopicListToastView: UIView {
    enum Style {
        case success
        case error
        case info
    }

    init(message: String, style: Style) {
        super.init(frame: .zero)
        configure(message: message, style: style)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(message: String, style: Style) {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.10
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)

        let iconView = UIImageView(image: UIImage(systemName: style.systemImage))
        iconView.tintColor = style.tintColor
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = message
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 3

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        accessibilityLabel = message
    }
}

private extension FireTopicListToastView.Style {
    var systemImage: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    var tintColor: UIColor {
        switch self {
        case .success:
            return .systemGreen
        case .error:
            return .systemRed
        case .info:
            return .systemBlue
        }
    }
}

/// Compatibility alias for existing UIKit list call sites.
/// Prefer `FireTheme.ui*` for new code; this type only forwards to FireTheme.
enum FireTopicListPalette {
    static var accent: UIColor { FireTheme.uiAccent }
    static var subtleInk: UIColor { FireTheme.uiSubtleInk }
    static var tertiaryInk: UIColor { FireTheme.uiTertiaryInk }
    static var tagChipBackground: UIColor { FireTheme.uiTagChipBackground }
    static var tagChipForeground: UIColor { FireTheme.uiTagChipForeground }

    static func categoryChipBackground(accent: UIColor) -> UIColor {
        FireTheme.uiCategoryChipBackground(accent: accent)
    }
}

private final class FireBookmarksControllerReference {
    weak var controller: FireBookmarksViewController?
}

private extension UIFont {
    func withWeight(_ weight: Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

private extension UIColor {
    convenience init?(fireHex hex: String?) {
        guard let hex else {
            return nil
        }
        let cleaned = hex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .uppercased()
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1
        )
    }
}
