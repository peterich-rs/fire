import XCTest
@testable import Fire

@MainActor
final class FireStartupPreloadCoordinatorTests: XCTestCase {
    func testRunPreloadInvokesProfileAndNotificationsOnFreshSession() async {
        let profile = MockProfileLoader()
        let notifications = MockNotificationsLoader(hasLoadedRecentOnce: false)
        let coordinator = FireStartupPreloadCoordinator(
            profile: profile,
            notifications: notifications
        )

        await coordinator.runPreload()

        XCTAssertEqual(profile.loadProfileInvocations, [false])
        XCTAssertEqual(notifications.loadRecentInvocations, [false])
    }

    func testRunPreloadSkipsNotificationsFetchWhenAlreadyLoadedOnce() async {
        let profile = MockProfileLoader()
        let notifications = MockNotificationsLoader(hasLoadedRecentOnce: true)
        let coordinator = FireStartupPreloadCoordinator(
            profile: profile,
            notifications: notifications
        )

        await coordinator.runPreload()

        XCTAssertEqual(profile.loadProfileInvocations, [false])
        XCTAssertEqual(notifications.loadRecentInvocations, [])
    }

    func testRunPreloadInvokesMethodsOnceEachCall() async {
        let profile = MockProfileLoader()
        let notifications = MockNotificationsLoader(hasLoadedRecentOnce: false)
        let coordinator = FireStartupPreloadCoordinator(
            profile: profile,
            notifications: notifications
        )

        await coordinator.runPreload()
        notifications.hasLoadedRecentOnce = true
        await coordinator.runPreload()
        notifications.hasLoadedRecentOnce = false
        await coordinator.runPreload()

        XCTAssertEqual(profile.loadProfileInvocations, [false, false, false])
        XCTAssertEqual(notifications.loadRecentInvocations, [false, false])
    }

    func testRunPreloadDoesNotSurfaceNotificationsLoadFailure() async {
        struct PreloadStubError: Error {}

        let profile = MockProfileLoader()
        let notifications = MockNotificationsLoader(hasLoadedRecentOnce: false)
        notifications.loadRecentError = PreloadStubError()
        let coordinator = FireStartupPreloadCoordinator(
            profile: profile,
            notifications: notifications
        )

        await coordinator.runPreload()
        await coordinator.runPreload()

        XCTAssertEqual(notifications.loadRecentInvocations, [false, false])
    }
}

@MainActor
private final class MockProfileLoader: FireStartupPreloadProfileLoader {
    private(set) var loadProfileInvocations: [Bool] = []

    func loadProfile(force: Bool) {
        loadProfileInvocations.append(force)
    }
}

@MainActor
private final class MockNotificationsLoader: FireStartupPreloadNotificationsLoader {
    var hasLoadedRecentOnce: Bool
    private(set) var loadRecentInvocations: [Bool] = []
    var loadRecentError: Error?

    init(hasLoadedRecentOnce: Bool) {
        self.hasLoadedRecentOnce = hasLoadedRecentOnce
    }

    func loadRecent(force: Bool) async {
        loadRecentInvocations.append(force)
        // Simulate the production store's "swallow errors via existing
        // pathways" contract: never throw out.
        _ = loadRecentError
    }
}
