import Foundation

@MainActor
final class FireNotificationStore: ObservableObject {
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var recentNotifications: [NotificationItemState] = []
    @Published private(set) var isLoadingRecent = false
    @Published private(set) var hasLoadedRecentOnce = false
    @Published private(set) var recentErrorMessage: String?
    @Published private(set) var isRecentOffline = false

    @Published private(set) var fullNotifications: [NotificationItemState] = []
    @Published private(set) var fullNextOffset: UInt32?
    @Published private(set) var isLoadingFull = false
    @Published private(set) var isLoadingMoreFull = false
    @Published private(set) var hasLoadedFullOnce = false
    @Published private(set) var isFullOffline = false
    @Published private(set) var blockingFullErrorMessage: String?
    @Published private(set) var fullNonBlockingErrorMessage: String?

    private let appViewModel: FireAppViewModel
    private var lastFailedFullOffset: UInt32?

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    var isLoadingFullPage: Bool {
        isLoadingFull || isLoadingMoreFull
    }

    var hasMoreFull: Bool {
        fullNextOffset != nil
    }

    var fullErrorMessage: String? {
        blockingFullErrorMessage ?? fullNonBlockingErrorMessage
    }

    var blockingRecentErrorMessage: String? {
        hasLoadedRecentOnce ? nil : recentErrorMessage
    }

    var recentNonBlockingErrorMessage: String? {
        hasLoadedRecentOnce ? recentErrorMessage : nil
    }

    var shouldShowFullPaginationRetry: Bool {
        lastFailedFullOffset != nil
    }

    func reset() {
        unreadCount = 0
        recentNotifications = []
        isLoadingRecent = false
        hasLoadedRecentOnce = false
        recentErrorMessage = nil
        isRecentOffline = false
        fullNotifications = []
        fullNextOffset = nil
        isLoadingFull = false
        isLoadingMoreFull = false
        hasLoadedFullOnce = false
        isFullOffline = false
        blockingFullErrorMessage = nil
        fullNonBlockingErrorMessage = nil
        lastFailedFullOffset = nil
    }

    func cancelScheduledRefresh() {}

    func clearRecentError() {
        recentErrorMessage = nil
    }

    func clearFullError() {
        blockingFullErrorMessage = nil
        fullNonBlockingErrorMessage = nil
        lastFailedFullOffset = nil
    }

    func recordRecentLoadFailure(_ message: String) {
        recentErrorMessage = message
    }

    func recordFullLoadFailure(_ message: String, offset: UInt32? = nil) {
        if hasLoadedFullOnce {
            fullNonBlockingErrorMessage = message
        } else {
            blockingFullErrorMessage = message
        }
        lastFailedFullOffset = offset
    }

    func retryFullLoad() async {
        await loadFullPage(offset: lastFailedFullOffset ?? fullNextOffset)
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
                _ = try await appViewModel.notificationService.fetchRecentNotifications()
                let state = try await appViewModel.notificationService.notificationCenterState()
                apply(centerState: state, updateRecent: true, updateFull: state.hasLoadedFull)
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
        let isMore = offset != nil && hasLoadedFullOnce
        if isMore {
            isLoadingMoreFull = true
        } else {
            isLoadingFull = true
        }
        blockingFullErrorMessage = nil
        fullNonBlockingErrorMessage = nil
        defer {
            isLoadingFull = false
            isLoadingMoreFull = false
        }

        do {
            _ = try await appViewModel.notificationService.fetchNotifications(offset: offset)
            let state = try await appViewModel.notificationService.notificationCenterState()
            apply(centerState: state, updateRecent: state.hasLoadedRecent, updateFull: true)
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            recordFullLoadFailure(error.localizedDescription, offset: offset)
        }
    }

    func scheduleStateRefresh() {
        Task { [weak self] in
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
            fullNotifications = centerState.full
            fullNextOffset = centerState.fullNextOffset
            hasLoadedFullOnce = true
            isFullOffline = centerState.fullIsCached
            blockingFullErrorMessage = nil
            fullNonBlockingErrorMessage = nil
            lastFailedFullOffset = nil
        }
        appViewModel.updateWidgetData()
    }
}
