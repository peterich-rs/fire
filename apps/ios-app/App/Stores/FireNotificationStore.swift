import Foundation
import Combine

@MainActor
final class FireNotificationStore: ObservableObject {
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var recentNotifications: [NotificationItemState] = []
    @Published private(set) var isLoadingRecent = false
    @Published private(set) var hasLoadedRecentOnce = false
    @Published private(set) var recentErrorMessage: String?
    @Published private(set) var isRecentOffline = false

    private let appViewModel: FireAppViewModel
    private let fullPagination = FireNotificationFullPaginationStore()
    private var pendingStateRefreshTask: Task<Void, Never>?
    private var lastFailedFullOffset: UInt32?
    private var cancellables: Set<AnyCancellable> = []

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
        fullPagination.configure(appViewModel: appViewModel)
        fullPagination.onPageLoaded = { [weak self] in
            self?.lastFailedFullOffset = nil
        }
        fullPagination.onPageFailed = { [weak self] offset in
            self?.lastFailedFullOffset = offset
        }
        fullPagination.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var fullNotifications: [NotificationItemState] {
        fullPagination.items
    }

    var fullNextOffset: UInt32? {
        fullPagination.currentNextOffset
    }

    var isLoadingFullPage: Bool {
        fullPagination.isLoading || fullPagination.isLoadingMore
    }

    var isFullOffline: Bool {
        fullPagination.isOffline
    }

    var hasLoadedFullOnce: Bool {
        fullPagination.hasLoadedOnce
    }

    var hasMoreFull: Bool {
        fullPagination.hasMore
    }

    var fullErrorMessage: String? {
        fullPagination.blockingErrorMessage ?? fullPagination.nonBlockingErrorMessage
    }

    var blockingRecentErrorMessage: String? {
        hasLoadedRecentOnce ? nil : recentErrorMessage
    }

    var recentNonBlockingErrorMessage: String? {
        hasLoadedRecentOnce ? recentErrorMessage : nil
    }

    var blockingFullErrorMessage: String? {
        fullPagination.blockingErrorMessage
    }

    var fullNonBlockingErrorMessage: String? {
        fullPagination.nonBlockingErrorMessage
    }

    var shouldShowFullPaginationRetry: Bool {
        lastFailedFullOffset != nil
    }

    func reset() {
        pendingStateRefreshTask?.cancel()
        pendingStateRefreshTask = nil
        unreadCount = 0
        recentNotifications = []
        isLoadingRecent = false
        hasLoadedRecentOnce = false
        recentErrorMessage = nil
        isRecentOffline = false
        fullPagination.reset()
        lastFailedFullOffset = nil
    }

    func cancelScheduledRefresh() {
        pendingStateRefreshTask?.cancel()
        pendingStateRefreshTask = nil
    }

    func clearRecentError() {
        recentErrorMessage = nil
    }

    func clearFullError() {
        fullPagination.clearErrors()
        lastFailedFullOffset = nil
    }

    func recordRecentLoadFailure(_ message: String) {
        recentErrorMessage = message
    }

    func recordFullLoadFailure(_ message: String, offset: UInt32? = nil) {
        fullPagination.recordFailure(message, isBlocking: !fullPagination.hasLoadedOnce)
        lastFailedFullOffset = offset
    }

    func retryFullLoad() async {
        await loadFullPage(offset: lastFailedFullOffset ?? fullPagination.currentNextOffset)
    }

    func syncStateFromRuntimeIfAvailable() async {
        guard appViewModel.session.readiness.canReadAuthenticatedApi else {
            reset()
            return
        }

        do {
            let state = try await appViewModel.notificationService.notificationCenterState()
            apply(centerState: state, updateRecent: state.hasLoadedRecent, updateFull: state.hasLoadedFull)
        } catch {
            _ = await appViewModel.handleRecoverableSessionErrorIfNeeded(error)
        }
    }

    func loadRecent(force: Bool = true) async {
        guard appViewModel.session.readiness.canReadAuthenticatedApi else { return }
        guard !isLoadingRecent || force else { return }

        isLoadingRecent = true
        recentErrorMessage = nil
        defer { isLoadingRecent = false }

        do {
            try await FireAPMManager.shared.withSpan(.notificationsRefresh) {
                let list = try await appViewModel.notificationService.fetchRecentNotifications()
                recentNotifications = list.notifications
                isRecentOffline = list.isCached
                hasLoadedRecentOnce = true
                recentErrorMessage = nil
                if let state = try? await appViewModel.notificationService.notificationCenterState() {
                    apply(centerState: state, updateRecent: true, updateFull: state.hasLoadedFull)
                }
            }
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            recordRecentLoadFailure(error.localizedDescription)
        }
    }

    func markRead(id: UInt64) {
        Task {
            do {
                let state = try await appViewModel.notificationService.markNotificationRead(id: id)
                apply(centerState: state, updateRecent: true, updateFull: state.hasLoadedFull)
            } catch {
                _ = await appViewModel.handleRecoverableSessionErrorIfNeeded(error)
            }
        }
    }

    func markAllRead() {
        Task {
            do {
                let state = try await appViewModel.notificationService.markAllNotificationsRead()
                apply(centerState: state, updateRecent: true, updateFull: state.hasLoadedFull)
            } catch {
                _ = await appViewModel.handleRecoverableSessionErrorIfNeeded(error)
            }
        }
    }

    func loadFullPage(offset: UInt32?) async {
        guard appViewModel.session.readiness.canReadAuthenticatedApi else { return }
        lastFailedFullOffset = nil
        if let offset {
            await fullPagination.loadPage(offset: offset)
        } else {
            await fullPagination.loadAsync(forceRefresh: true)
        }
    }

    func scheduleStateRefresh() {
        pendingStateRefreshTask?.cancel()
        pendingStateRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            guard let self else { return }

            do {
                let state = try await self.appViewModel.notificationService.notificationCenterState()
                self.apply(
                    centerState: state,
                    updateRecent: true,
                    updateFull: state.hasLoadedFull
                )
            } catch {
                _ = await self.appViewModel.handleRecoverableSessionErrorIfNeeded(error)
            }

            self.pendingStateRefreshTask = nil
        }
    }

    func apply(
        centerState: NotificationCenterState,
        updateRecent: Bool,
        updateFull: Bool
    ) {
        unreadCount = Int(centerState.counters.allUnread)
        if updateRecent {
            recentNotifications = centerState.recent
            hasLoadedRecentOnce = true
            isRecentOffline = centerState.recentIsCached
            recentErrorMessage = nil
        }
        if updateFull {
            fullPagination.applyPage(
                FirePaginatedStore<NotificationItemState>.PageResult(
                    items: centerState.full,
                    nextOffset: centerState.fullNextOffset,
                    isCached: centerState.fullIsCached
                ),
                reset: true
            )
            lastFailedFullOffset = nil
        }
        appViewModel.updateWidgetData()
    }
}

@MainActor
private final class FireNotificationFullPaginationStore: FirePaginatedStore<NotificationItemState> {
    private weak var appViewModel: FireAppViewModel?
    private var requestedOffset: UInt32?
    private(set) var isOffline = false
    var onPageLoaded: (() -> Void)?
    var onPageFailed: ((UInt32?) -> Void)?

    func configure(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    func loadPage(offset: UInt32) async {
        requestedOffset = offset
        await loadMoreAsync()
    }

    override func fetchPage(offset: UInt32?) async throws -> PageResult {
        guard let appViewModel else {
            throw FireNotificationPaginationError.missingAppViewModel
        }

        let pageOffset = offset ?? requestedOffset
        let list = try await appViewModel.notificationService.fetchNotifications(offset: pageOffset)
        requestedOffset = nil
        return PageResult(
            items: list.notifications,
            nextOffset: list.nextOffset,
            loadedOffset: pageOffset,
            isCached: list.isCached
        )
    }

    override func applyPage(_ result: PageResult, reset: Bool) {
        super.applyPage(result, reset: reset)
        isOffline = result.isCached
        onPageLoaded?()
    }

    override func reset() {
        super.reset()
        isOffline = false
    }

    override func mergeItems(
        existing: [NotificationItemState],
        incoming: [NotificationItemState]
    ) -> [NotificationItemState] {
        var merged = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var orderedIDs = existing.map(\.id)

        for item in incoming {
            if merged[item.id] == nil {
                orderedIDs.append(item.id)
            }
            merged[item.id] = item
        }

        return orderedIDs.compactMap { merged[$0] }
    }

    override func handlePageLoadError(_ error: Error, offset: UInt32?) async -> Bool {
        guard let appViewModel else { return false }
        requestedOffset = offset ?? requestedOffset
        let handled = await appViewModel.handleRecoverableSessionErrorIfNeeded(error)
        if !handled {
            onPageFailed?(requestedOffset)
        }
        return handled
    }
}

private enum FireNotificationPaginationError: LocalizedError {
    case missingAppViewModel

    var errorDescription: String? {
        switch self {
        case .missingAppViewModel:
            return "Notification pagination store is not configured."
        }
    }
}
