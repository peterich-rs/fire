import Combine
import SwiftUI
import UIKit

@MainActor
final class FirePrivateMessagesViewModel: ObservableObject {
    typealias FetchPrivateMessages = @MainActor (
        TopicListKindState,
        UInt32?
    ) async throws -> TopicListState

    @Published var selectedKind: TopicListKindState = .privateMessagesInbox
    @Published private(set) var rows: [TopicRowState] = []
    @Published private(set) var users: [TopicUserState] = []
    @Published private(set) var renderedKind: TopicListKindState?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?

    private let fetchPrivateMessages: FetchPrivateMessages
    private var nextPage: UInt32?
    private var hasMore = true
    private var loadGeneration: UInt64 = 0

    init(appViewModel: FireAppViewModel) {
        self.fetchPrivateMessages = { kind, page in
            try await appViewModel.fetchPrivateMessages(kind: kind, page: page)
        }
    }

    init(fetchPrivateMessages: @escaping FetchPrivateMessages) {
        self.fetchPrivateMessages = fetchPrivateMessages
    }

    var hasResolvedCurrentKind: Bool {
        renderedKind == selectedKind
    }

    var displayedRows: [TopicRowState] {
        hasResolvedCurrentKind ? rows : []
    }

    var displayedUsers: [TopicUserState] {
        hasResolvedCurrentKind ? users : []
    }

    var currentKindDisplayState: FireScopedTopicListDisplayState {
        FireScopedTopicListDisplayState.resolve(
            hasResolvedCurrentScope: hasResolvedCurrentKind,
            hasRows: !displayedRows.isEmpty,
            errorMessage: errorMessage
        )
    }

    private func deduplicatedRows(_ rows: [TopicRowState]) -> [TopicRowState] {
        var seenTopicIDs = Set<UInt64>()
        return rows.filter { row in
            seenTopicIDs.insert(row.topic.id).inserted
        }
    }

    private func deduplicatedUsers(_ users: [TopicUserState]) -> [TopicUserState] {
        var seenUserIDs = Set<UInt64>()
        return users.filter { user in
            seenUserIDs.insert(user.id).inserted
        }
    }

    func loadIfNeeded() async {
        guard (!hasResolvedCurrentKind || rows.isEmpty), !isLoading else { return }
        await load(reset: true)
    }

    func refresh() async {
        await load(reset: true)
    }

    func selectKind(_ kind: TopicListKindState) async {
        guard selectedKind != kind else { return }
        selectedKind = kind
        await load(reset: true)
    }

    func loadMoreIfNeeded(currentTopicID: UInt64) async {
        guard hasResolvedCurrentKind else { return }
        guard hasMore, !isLoading, !isLoadingMore else { return }
        guard displayedRows.last?.topic.id == currentTopicID else { return }
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        let requestKind = selectedKind
        let requestPage = reset ? nil : nextPage
        loadGeneration &+= 1
        let generation = loadGeneration

        if reset {
            isLoading = true
            isLoadingMore = false
            nextPage = nil
            hasMore = false
        } else {
            isLoadingMore = true
        }
        errorMessage = nil

        defer {
            if generation == loadGeneration {
                isLoading = false
                isLoadingMore = false
            }
        }

        do {
            let response = try await fetchPrivateMessages(requestKind, requestPage)
            guard generation == loadGeneration, requestKind == selectedKind else {
                return
            }

            let uniqueRows = deduplicatedRows(response.rows)
            let uniqueUsers = deduplicatedUsers(response.users)
            let freshRows: [TopicRowState]
            let freshUsers: [TopicUserState]

            if reset {
                rows = uniqueRows
                users = uniqueUsers
                freshRows = uniqueRows
                freshUsers = uniqueUsers
            } else {
                let existingIDs = Set(rows.map(\.topic.id))
                freshRows = uniqueRows.filter { !existingIDs.contains($0.topic.id) }
                rows.append(contentsOf: freshRows)
                let existingUserIDs = Set(users.map(\.id))
                freshUsers = uniqueUsers.filter { !existingUserIDs.contains($0.id) }
                users.append(contentsOf: freshUsers)
            }

            let resolvedNextPage: UInt32? = {
                guard let candidate = response.nextPage else {
                    return nil
                }
                guard let requestPage else {
                    return candidate
                }
                return candidate > requestPage ? candidate : nil
            }()

            let receivedFreshContent = !freshRows.isEmpty || !freshUsers.isEmpty
            nextPage = resolvedNextPage
            hasMore = resolvedNextPage != nil && (reset || receivedFreshContent)
            renderedKind = requestKind
            hasLoadedOnce = true
            errorMessage = nil
        } catch {
            guard generation == loadGeneration, requestKind == selectedKind else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}

struct FirePrivateMessagesControllerHost: UIViewControllerRepresentable {
    @Environment(\.fireTopicRoutePresenter) private var topicRoutePresenter
    @EnvironmentObject private var topicDetailStore: FireTopicDetailStore

    let viewModel: FireAppViewModel

    func makeUIViewController(context: Context) -> FirePrivateMessagesViewController {
        FirePrivateMessagesViewController(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            topicRoutePresenter: topicRoutePresenter
        )
    }

    func updateUIViewController(
        _ uiViewController: FirePrivateMessagesViewController,
        context: Context
    ) {
        uiViewController.updateTopicRoutePresenter(topicRoutePresenter)
    }
}

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
            layout: FireCollectionLayouts.plainList(backgroundColor: .systemGroupedBackground),
            backgroundColor: .systemGroupedBackground,
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
        view.backgroundColor = .systemGroupedBackground

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
        let controller = FireAppRouteControllerFactory.makeViewController(
            viewModel: appViewModel,
            topicDetailStore: topicDetailStore,
            route: route,
            topicRoutePresenter: topicRoutePresenter
        )
        if let navigationController {
            navigationController.pushViewController(controller, animated: true)
        } else {
            let navigationController = UINavigationController(rootViewController: controller)
            present(navigationController, animated: true)
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
        UIView.animate(withDuration: 0.18) {
            toast.alpha = 1
            toast.transform = .identity
        }
        toastDismissTask = Task { [weak self, weak toast] in
            try? await Task.sleep(for: .seconds(2.0))
            await MainActor.run {
                guard let self, self.toastView === toast else { return }
                self.dismissToast()
            }
        }
    }

    private func dismissToast() {
        guard let toast = toastView else { return }
        toastView = nil
        UIView.animate(withDuration: 0.18, animations: {
            toast.alpha = 0
            toast.transform = CGAffineTransform(translationX: 0, y: -8)
        }, completion: { _ in
            toast.removeFromSuperview()
        })
    }
}

final class FirePrivateMessagesPickerCell: UICollectionViewCell {
    private let segmentedControl = UISegmentedControl(items: ["收件箱", "已发送"])
    private var onSelectKind: ((TopicListKindState) -> Void)?
    private var isConfiguring = false

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
        onSelectKind = nil
    }

    func configure(
        selectedKind: TopicListKindState,
        onSelectKind: @escaping (TopicListKindState) -> Void
    ) {
        isConfiguring = true
        segmentedControl.selectedSegmentIndex = selectedKind == .privateMessagesInbox ? 0 : 1
        isConfiguring = false
        self.onSelectKind = onSelectKind
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 12,
            leading: 16,
            bottom: 8,
            trailing: 16
        )

        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addAction(UIAction { [weak self] _ in
            guard let self, !self.isConfiguring else { return }
            let kind: TopicListKindState =
                self.segmentedControl.selectedSegmentIndex == 0
                    ? .privateMessagesInbox
                    : .privateMessagesSent
            self.onSelectKind?(kind)
        }, for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(segmentedControl)
        NSLayoutConstraint.activate([
            segmentedControl.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            segmentedControl.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            segmentedControl.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            segmentedControl.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }
}

final class FirePrivateMessageListCell: UICollectionViewCell {
    private let avatarView = FireTopicListAvatarView()
    private let titleLabel = UILabel()
    private let chipLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let excerptLabel = UILabel()
    private let metricsLabel = UILabel()

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
        titleLabel.text = nil
        subtitleLabel.text = nil
        excerptLabel.text = nil
        metricsLabel.text = nil
    }

    func configureMissing() {
        titleLabel.text = nil
        subtitleLabel.text = nil
        excerptLabel.text = nil
        metricsLabel.text = nil
        avatarView.prepareForReuse()
    }

    func configure(
        row: TopicRowState,
        participants: [TopicParticipantState],
        currentUsername: String?,
        baseURLString: String
    ) {
        let displayParticipants = Self.filteredParticipants(
            participants,
            currentUsername: currentUsername
        )
        let firstParticipant = displayParticipants.first
        let username = firstParticipant?.username ?? firstParticipant?.name ?? "pm"
        let subtitle = Self.participantSubtitle(for: displayParticipants)
        let excerpt = row.excerptText?.trimmingCharacters(in: .whitespacesAndNewlines)

        titleLabel.text = row.topic.title.ifEmpty("私信会话")
        subtitleLabel.text = subtitle
        excerptLabel.text = excerpt?.isEmpty == false ? excerpt : nil
        excerptLabel.isHidden = excerptLabel.text == nil
        metricsLabel.text = Self.metricsText(row: row)
        avatarView.configure(
            username: username,
            avatarTemplate: firstParticipant?.avatarTemplate,
            baseURLString: baseURLString
        )

        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = [
            titleLabel.text,
            subtitleLabel.text,
            excerptLabel.text,
            metricsLabel.text,
        ]
        .compactMap { $0 }
        .joined(separator: "，")
        accessibilityHint = "双击查看私信话题"
    }

    private static func filteredParticipants(
        _ participants: [TopicParticipantState],
        currentUsername: String?
    ) -> [TopicParticipantState] {
        let current = currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current, !current.isEmpty else {
            return participants
        }
        return participants.filter {
            $0.username?.caseInsensitiveCompare(current) != .orderedSame
        }
    }

    private static func participantSubtitle(for participants: [TopicParticipantState]) -> String {
        let labels = participants.compactMap { participant in
            let preferred = (participant.name ?? "").ifEmpty(
                participant.username ?? "用户 \(participant.userId)"
            )
            let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !labels.isEmpty else {
            return "私信会话"
        }
        return labels.joined(separator: "、")
    }

    private static func metricsText(row: TopicRowState) -> String {
        var parts = ["\(row.topic.replyCount) 回复"]
        if let timestamp = FireTopicPresentation.compactTimestamp(unixMs: row.activityTimestampUnixMs) {
            parts.append(timestamp)
        }
        return parts.joined(separator: " · ")
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 10,
            leading: 16,
            bottom: 10,
            trailing: 16
        )

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.widthAnchor.constraint(equalToConstant: 34).isActive = true
        avatarView.heightAnchor.constraint(equalToConstant: 34).isActive = true

        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        chipLabel.text = "私信"
        chipLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        chipLabel.adjustsFontForContentSizeCategory = true
        chipLabel.textColor = FireTopicListPalette.accent
        chipLabel.backgroundColor = FireTopicListPalette.accent.withAlphaComponent(0.13)
        chipLabel.textAlignment = .center
        chipLabel.layer.cornerRadius = 5
        chipLabel.layer.masksToBounds = true
        chipLabel.setContentHuggingPriority(.required, for: .horizontal)

        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1

        excerptLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        excerptLabel.adjustsFontForContentSizeCategory = true
        excerptLabel.textColor = .secondaryLabel
        excerptLabel.numberOfLines = 3

        metricsLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        metricsLabel.adjustsFontForContentSizeCategory = true
        metricsLabel.textColor = .tertiaryLabel
        metricsLabel.numberOfLines = 1

        let metaStack = UIStackView(arrangedSubviews: [chipLabel, subtitleLabel])
        metaStack.axis = .horizontal
        metaStack.alignment = .center
        metaStack.spacing = 6

        let textStack = UIStackView(arrangedSubviews: [
            titleLabel,
            metaStack,
            excerptLabel,
            metricsLabel,
        ])
        textStack.axis = .vertical
        textStack.spacing = 6

        let rootStack = UIStackView(arrangedSubviews: [avatarView, textStack])
        rootStack.axis = .horizontal
        rootStack.alignment = .top
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            chipLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
            chipLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 34),
        ])
    }
}

private final class FirePrivateMessagesControllerReference {
    weak var controller: FirePrivateMessagesViewController?
}
