import UserNotifications
import XCTest
@testable import Fire

@MainActor
final class FirePushRegistrationCoordinatorTests: XCTestCase {
    func testEnsurePushRegistrationReregistersWhenCachedTokenExists() async throws {
        let defaults = try makeDefaults()
        var registerCallCount = 0
        let coordinator = FirePushRegistrationCoordinator(
            defaults: defaults,
            loadAuthorizationStatus: { .authorized },
            requestAuthorization: { true },
            registerForRemoteNotifications: {
                registerCallCount += 1
            }
        )

        coordinator.handleRegisteredDeviceToken(Data([0x0a, 0x0b]))
        await coordinator.ensurePushRegistration()

        XCTAssertEqual(registerCallCount, 1)
        XCTAssertEqual(coordinator.diagnostics.deviceTokenHex, "0a0b")
        XCTAssertEqual(coordinator.diagnostics.registrationState, .registering)
    }

    func testEnsurePushRegistrationSkipsDuplicateRegisterWhileRequestInFlight() async throws {
        let defaults = try makeDefaults()
        var registerCallCount = 0
        let coordinator = FirePushRegistrationCoordinator(
            defaults: defaults,
            loadAuthorizationStatus: { .authorized },
            requestAuthorization: { true },
            registerForRemoteNotifications: {
                registerCallCount += 1
            }
        )

        await coordinator.ensurePushRegistration()
        await coordinator.ensurePushRegistration()

        XCTAssertEqual(registerCallCount, 1)
        XCTAssertEqual(coordinator.diagnostics.registrationState, .registering)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "fire-push-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("failed to create isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
