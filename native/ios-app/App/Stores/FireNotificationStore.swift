import Foundation

@MainActor
final class FireNotificationStore: ObservableObject {
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var recentNotifications: [NotificationItemState] = []
    @Published private(set) var isLoadingRecent = false
    @Published private(set) var fullNotifications: [NotificationItemState] = []
    @Published private(set) var fullNextOffset: UInt32?
    @Published private(set) var isLoadingFullPage = false
    @Published private(set) var hasMoreFull = false

    private let appViewModel: FireAppViewModel
    private var pendingStateRefreshTask: Task<Void, Never>?

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    func reset() {
        pendingStateRefreshTask?.cancel()
        pendingStateRefreshTask = nil
        unreadCount = 0
        recentNotifications = []
        isLoadingRecent = false
        fullNotifications = []
        fullNextOffset = nil
        isLoadingFullPage = false
        hasMoreFull = false
    }

    func cancelScheduledRefresh() {
        pendingStateRefreshTask?.cancel()
        pendingStateRefreshTask = nil
    }

    func syncStateFromRuntimeIfAvailable() async {
        guard appViewModel.session.readiness.canReadAuthenticatedApi else {
            reset()
            return
        }

        do {
            let state = try await appViewModel.notificationCenterState()
            apply(centerState: state, updateRecent: state.hasLoadedRecent, updateFull: state.hasLoadedFull)
        } catch {
            _ = await appViewModel.handleRecoverableSessionErrorIfNeeded(error)
        }
    }

    func loadRecent(force: Bool = true) async {
        guard appViewModel.session.readiness.canReadAuthenticatedApi else { return }
        guard !isLoadingRecent || force else { return }

        isLoadingRecent = true
        defer { isLoadingRecent = false }

        do {
            try await FireAPMManager.shared.withSpan(.notificationsRefresh) {
                let list = try await appViewModel.fetchRecentNotificationsData()
                recentNotifications = list.notifications
                if let state = try? await appViewModel.notificationCenterState() {
                    apply(centerState: state, updateRecent: true, updateFull: state.hasLoadedFull)
                }
            }
        } catch {
            _ = await appViewModel.handleRecoverableSessionErrorIfNeeded(error)
        }
    }

    func markRead(id: UInt64) {
        Task {
            do {
                let state = try await appViewModel.markNotificationReadState(id: id)
                apply(centerState: state, updateRecent: true, updateFull: state.hasLoadedFull)
            } catch {
                _ = await appViewModel.handleRecoverableSessionErrorIfNeeded(error)
            }
        }
    }

    func markAllRead() {
        Task {
            do {
                let state = try await appViewModel.markAllNotificationsReadState()
                apply(centerState: state, updateRecent: true, updateFull: state.hasLoadedFull)
            } catch {
                _ = await appViewModel.handleRecoverableSessionErrorIfNeeded(error)
            }
        }
    }

    func loadFullPage(offset: UInt32?) async {
        guard appViewModel.session.readiness.canReadAuthenticatedApi else { return }
        guard !isLoadingFullPage else { return }

        isLoadingFullPage = true
        defer { isLoadingFullPage = false }

        do {
            _ = try await appViewModel.fetchNotificationsData(offset: offset)
            let state = try await appViewModel.notificationCenterState()
            apply(centerState: state, updateRecent: state.hasLoadedRecent, updateFull: true)
        } catch {
            _ = await appViewModel.handleRecoverableSessionErrorIfNeeded(error)
        }
    }

    func scheduleStateRefresh() {
        pendingStateRefreshTask?.cancel()
        pendingStateRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            guard let self else { return }

            do {
                let state = try await self.appViewModel.notificationCenterState()
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
        }
        if updateFull {
            fullNotifications = centerState.full
            fullNextOffset = centerState.fullNextOffset
            hasMoreFull = centerState.fullNextOffset != nil
        }
    }
}
