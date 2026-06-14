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
        FireBookmarksStateCell,
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
        FireBookmarksErrorBannerCell,
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
        FireBookmarksTopicCell,
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
            onRefresh: { [bookmarksViewModel] in
                await bookmarksViewModel.refresh()
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

        title = "我的书签"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground

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

    private func showToast(_ message: String, style: FireBookmarksToastView.Style) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        toastDismissTask?.cancel()
        toastView?.removeFromSuperview()

        let toast = FireBookmarksToastView(message: message, style: style)
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

private final class FireBookmarksStateCell: UICollectionViewCell {
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

    func configureLoading() {
        iconView.isHidden = true
        activityIndicator.isHidden = false
        activityIndicator.startAnimating()
        titleLabel.text = "正在加载书签"
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

    func configureEmpty() {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        iconView.isHidden = false
        iconView.image = UIImage(systemName: "bookmark")
        iconView.tintColor = .tertiaryLabel
        titleLabel.text = "还没有书签"
        messageLabel.text = "把想回看的话题或帖子收进来，后续会统一在这里管理。"
        actionButton.isHidden = true
        setCompact(false)
    }

    func configureBlockingError(message: String, onRetry: @escaping () -> Void) {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        iconView.isHidden = false
        iconView.image = UIImage(systemName: "exclamationmark.triangle.fill")
        iconView.tintColor = .systemRed
        titleLabel.text = "书签加载失败"
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

private final class FireBookmarksErrorBannerCell: UICollectionViewCell {
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

private final class FireBookmarksTopicCell: UICollectionViewCell {
    private let outerStack = UIStackView()
    private let metaStack = UIStackView()
    private let bookmarkNameLabel = UILabel()
    private let reminderLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    private let avatarView = FireBookmarksAvatarView()
    private let titleLabel = UILabel()
    private let chipStack = UIStackView()
    private let usernameLabel = UILabel()
    private let timestampLabel = UILabel()
    private let replyMetric = FireBookmarksMetricView(systemImage: "arrowshape.turn.up.left")
    private let viewsMetric = FireBookmarksMetricView(systemImage: "eye")
    private let likesMetric = FireBookmarksMetricView(systemImage: "heart")
    private var onEditBookmark: (() -> Void)?
    private var onDeleteBookmark: (() -> Void)?

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
        onEditBookmark = nil
        onDeleteBookmark = nil
        moreButton.menu = nil
    }

    func configureMissing() {
        titleLabel.text = nil
        chipStack.arrangedSubviews.forEach { view in
            chipStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        metaStack.isHidden = true
        avatarView.prepareForReuse()
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
        replyMetric.configure(value: row.topic.replyCount)
        viewsMetric.configure(value: row.topic.views)
        likesMetric.configure(value: row.topic.likeCount)
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
            chipStack.addArrangedSubview(
                FireBookmarksChipLabel(
                    text: category.displayName,
                    textColor: UIColor(fireHex: category.colorHex) ?? FireBookmarksPalette.accent,
                    backgroundColor: (UIColor(fireHex: category.colorHex) ?? FireBookmarksPalette.accent)
                        .withAlphaComponent(0.14)
                )
            )
        }

        for tagName in row.tagNames.prefix(3) {
            chipStack.addArrangedSubview(
                FireBookmarksChipLabel(
                    text: "#\(tagName)",
                    textColor: .secondaryLabel,
                    backgroundColor: .tertiarySystemFill
                )
            )
        }

        if row.isPinned {
            chipStack.addArrangedSubview(FireBookmarksIconChip(systemImage: "pin.fill", tintColor: .systemOrange))
        }
        if row.hasAcceptedAnswer {
            chipStack.addArrangedSubview(
                FireBookmarksIconChip(systemImage: "checkmark.circle.fill", tintColor: .systemGreen)
            )
        }
        if row.hasUnreadPosts {
            chipStack.addArrangedSubview(FireBookmarksUnreadDot())
        }
        chipStack.isHidden = chipStack.arrangedSubviews.isEmpty
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 8,
            trailing: 16
        )

        outerStack.axis = .vertical
        outerStack.spacing = 6
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

        let bodyStack = UIStackView()
        bodyStack.axis = .vertical
        bodyStack.alignment = .fill
        bodyStack.spacing = 6

        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.medium)
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

        usernameLabel.font = UIFont.preferredFont(forTextStyle: .caption2).withWeight(.medium)
        usernameLabel.adjustsFontForContentSizeCategory = true
        usernameLabel.textColor = .secondaryLabel
        usernameLabel.numberOfLines = 1

        timestampLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        timestampLabel.adjustsFontForContentSizeCategory = true
        timestampLabel.textColor = .tertiaryLabel
        timestampLabel.numberOfLines = 1

        bylineStack.addArrangedSubview(usernameLabel)
        bylineStack.addArrangedSubview(timestampLabel)
        bylineStack.addArrangedSubview(UIView())

        let metricStack = UIStackView(arrangedSubviews: [replyMetric, viewsMetric, likesMetric])
        metricStack.axis = .horizontal
        metricStack.alignment = .center
        metricStack.distribution = .fillEqually
        metricStack.spacing = 8

        bodyStack.addArrangedSubview(titleLabel)
        bodyStack.addArrangedSubview(chipStack)
        bodyStack.addArrangedSubview(bylineStack)
        bodyStack.addArrangedSubview(metricStack)

        rowStack.addArrangedSubview(avatarView)
        rowStack.addArrangedSubview(bodyStack)

        outerStack.addArrangedSubview(metaStack)
        outerStack.addArrangedSubview(rowStack)

        contentView.addSubview(outerStack)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 34),
            avatarView.heightAnchor.constraint(equalToConstant: 34),
            outerStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            outerStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            outerStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
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

private final class FireBookmarksAvatarView: UIView {
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
            size: 34,
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

    private func configureSubviews() {
        clipsToBounds = true
        layer.cornerRadius = 17
        backgroundColor = FireBookmarksPalette.accent

        monogramLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
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

private final class FireBookmarksMetricView: UIView {
    private let imageView = UIImageView()
    private let valueLabel = UILabel()

    init(systemImage: String) {
        super.init(frame: .zero)
        imageView.image = UIImage(systemName: systemImage)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(value: UInt32) {
        valueLabel.text = FireTopicPresentation.compactCount(value)
    }

    private func configureSubviews() {
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .tertiaryLabel
        valueLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [imageView, valueLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 14),
            imageView.heightAnchor.constraint(equalToConstant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

private final class FireBookmarksChipLabel: UILabel {
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

private final class FireBookmarksIconChip: UIView {
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

private final class FireBookmarksUnreadDot: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = FireBookmarksPalette.accent
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

private final class FireBookmarksToastView: UIView {
    enum Style {
        case success
        case error
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

        let iconView = UIImageView(
            image: UIImage(systemName: style == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
        )
        iconView.tintColor = style == .success ? .systemGreen : .systemRed
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

private enum FireBookmarksPalette {
    static let accent = UIColor(red: 0.91, green: 0.39, blue: 0.18, alpha: 1)
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
