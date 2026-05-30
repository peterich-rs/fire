import Foundation

@MainActor
protocol FireStartupPreloadProfileLoader: AnyObject {
    /// Mirrors `FireProfileViewModel.loadProfile(force:)`: synchronous on
    /// MainActor, fires off internal work, idempotent for the current
    /// session when `force == false`.
    func loadProfile(force: Bool)
}

@MainActor
protocol FireStartupPreloadNotificationsLoader: AnyObject {
    /// Mirrors `FireNotificationStore.hasLoadedRecentOnce`. Used by the
    /// coordinator to skip a redundant recent-fetch when the user
    /// already landed on the Notifications tab in this session.
    var hasLoadedRecentOnce: Bool { get }

    /// Mirrors `FireNotificationStore.loadRecent(force:)`.
    func loadRecent(force: Bool) async
}

/// Opt-in helper for warming the two off-screen tab stores at background
/// priority. The production tab root intentionally does not invoke this during
/// cold launch so Notifications and Profile stay lazy-loaded behind their
/// selected tabs.
///
/// Stateless. The owner is responsible for deciding *when* to invoke
/// `preloadOffScreenTabs`.
@MainActor
final class FireStartupPreloadCoordinator {
    private let profile: FireStartupPreloadProfileLoader
    private let notifications: FireStartupPreloadNotificationsLoader

    init(
        profile: FireStartupPreloadProfileLoader,
        notifications: FireStartupPreloadNotificationsLoader
    ) {
        self.profile = profile
        self.notifications = notifications
    }

    /// Schedules the preload on a background-priority `Task`. Returns
    /// immediately. The OS scheduler may yield to foreground rendering
    /// or higher-priority network calls before the body executes.
    func preloadOffScreenTabs() {
        Task(priority: .background) {
            await self.runPreload()
        }
    }

    /// The actual preload body. Exposed (rather than private) so unit
    /// tests can drive it deterministically without polling for the
    /// background `Task` to settle.
    func runPreload() async {
        profile.loadProfile(force: false)
        if !notifications.hasLoadedRecentOnce {
            await notifications.loadRecent(force: false)
        }
    }
}
