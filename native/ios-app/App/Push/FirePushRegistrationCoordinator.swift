import Combine
import Foundation
import UIKit
import UserNotifications

struct FirePushRegistrationDiagnostics: Equatable {
    enum RegistrationState: String {
        case idle
        case requestingAuthorization
        case denied
        case registering
        case registered
        case failed
    }

    var authorizationStatusRawValue: Int
    var registrationStateRawValue: String
    var deviceTokenHex: String?
    var lastErrorMessage: String?
    var lastUpdatedAtUnixMs: UInt64?

    var authorizationStatus: UNAuthorizationStatus {
        UNAuthorizationStatus(rawValue: authorizationStatusRawValue) ?? .notDetermined
    }

    var registrationState: RegistrationState {
        RegistrationState(rawValue: registrationStateRawValue) ?? .idle
    }

    var authorizationStatusTitle: String {
        switch authorizationStatus {
        case .notDetermined:
            return "未请求"
        case .denied:
            return "已拒绝"
        case .authorized:
            return "已授权"
        case .provisional:
            return "临时授权"
        case .ephemeral:
            return "临时会话"
        @unknown default:
            return "未知"
        }
    }

    var registrationStateTitle: String {
        switch registrationState {
        case .idle:
            return "未开始"
        case .requestingAuthorization:
            return "请求权限中"
        case .denied:
            return "权限被拒"
        case .registering:
            return "注册中"
        case .registered:
            return "已注册"
        case .failed:
            return "注册失败"
        }
    }

    static let initial = FirePushRegistrationDiagnostics(
        authorizationStatusRawValue: UNAuthorizationStatus.notDetermined.rawValue,
        registrationStateRawValue: RegistrationState.idle.rawValue,
        deviceTokenHex: nil,
        lastErrorMessage: nil,
        lastUpdatedAtUnixMs: nil
    )
}

@MainActor
final class FirePushRegistrationCoordinator: ObservableObject {
    static let shared = FirePushRegistrationCoordinator()

    @Published private(set) var diagnostics: FirePushRegistrationDiagnostics

    private enum Keys {
        static let authorizationStatus = "fire.push.authorization-status"
        static let registrationState = "fire.push.registration-state"
        static let deviceToken = "fire.push.device-token"
        static let lastErrorMessage = "fire.push.last-error-message"
        static let lastUpdatedAtUnixMs = "fire.push.last-updated-at-unix-ms"
    }

    private let defaults: UserDefaults
    private let loadAuthorizationStatus: () async -> UNAuthorizationStatus
    private let requestAuthorization: () async throws -> Bool
    private let registerForRemoteNotifications: @MainActor () -> Void
    private var isRegistrationInFlight = false

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard,
        loadAuthorizationStatus: (() async -> UNAuthorizationStatus)? = nil,
        requestAuthorization: (() async throws -> Bool)? = nil,
        registerForRemoteNotifications: @escaping @MainActor () -> Void = {
            UIApplication.shared.registerForRemoteNotifications()
        }
    ) {
        self.defaults = defaults
        self.loadAuthorizationStatus = loadAuthorizationStatus ?? {
            await center.notificationSettings().authorizationStatus
        }
        self.requestAuthorization = requestAuthorization ?? {
            try await center.requestAuthorization(options: [.alert, .badge, .sound])
        }
        self.registerForRemoteNotifications = registerForRemoteNotifications
        self.diagnostics = Self.loadDiagnostics(from: defaults)
    }

    func refreshAuthorizationStatus() async {
        let authorizationStatus = await loadAuthorizationStatus()
        await sync(
            authorizationStatus: authorizationStatus,
            requestAuthorizationIfNeeded: false
        )
    }

    func ensurePushRegistration() async {
        let authorizationStatus = await loadAuthorizationStatus()
        await sync(
            authorizationStatus: authorizationStatus,
            requestAuthorizationIfNeeded: true
        )
    }

    func handleRegisteredDeviceToken(_ deviceToken: Data) {
        isRegistrationInFlight = false
        diagnostics.deviceTokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
        diagnostics.lastErrorMessage = nil
        diagnostics.registrationStateRawValue = FirePushRegistrationDiagnostics.RegistrationState.registered.rawValue
        diagnostics.lastUpdatedAtUnixMs = Self.currentTimestampUnixMs()
        persistDiagnostics()
    }

    func handleRegistrationFailure(_ error: Error) {
        isRegistrationInFlight = false
        diagnostics.lastErrorMessage = error.localizedDescription
        diagnostics.registrationStateRawValue = FirePushRegistrationDiagnostics.RegistrationState.failed.rawValue
        diagnostics.lastUpdatedAtUnixMs = Self.currentTimestampUnixMs()
        persistDiagnostics()
    }

    private func sync(
        authorizationStatus: UNAuthorizationStatus,
        requestAuthorizationIfNeeded: Bool
    ) async {
        diagnostics.authorizationStatusRawValue = authorizationStatus.rawValue
        diagnostics.lastUpdatedAtUnixMs = Self.currentTimestampUnixMs()

        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            if diagnostics.deviceTokenHex != nil {
                diagnostics.registrationStateRawValue = FirePushRegistrationDiagnostics.RegistrationState.registered.rawValue
            }
            persistDiagnostics()
            registerForRemoteNotificationsIfNeeded()
        case .notDetermined:
            persistDiagnostics()
            guard requestAuthorizationIfNeeded else {
                return
            }

            diagnostics.registrationStateRawValue = FirePushRegistrationDiagnostics.RegistrationState.requestingAuthorization.rawValue
            diagnostics.lastErrorMessage = nil
            persistDiagnostics()

            do {
                _ = try await requestAuthorization()
                let refreshedAuthorizationStatus = await loadAuthorizationStatus()
                await sync(
                    authorizationStatus: refreshedAuthorizationStatus,
                    requestAuthorizationIfNeeded: false
                )
            } catch {
                diagnostics.lastErrorMessage = error.localizedDescription
                diagnostics.registrationStateRawValue = FirePushRegistrationDiagnostics.RegistrationState.failed.rawValue
                diagnostics.lastUpdatedAtUnixMs = Self.currentTimestampUnixMs()
                persistDiagnostics()
            }
        case .denied:
            diagnostics.registrationStateRawValue = FirePushRegistrationDiagnostics.RegistrationState.denied.rawValue
            diagnostics.lastUpdatedAtUnixMs = Self.currentTimestampUnixMs()
            persistDiagnostics()
        @unknown default:
            persistDiagnostics()
        }
    }

    private func registerForRemoteNotificationsIfNeeded() {
        guard !isRegistrationInFlight else {
            return
        }

        isRegistrationInFlight = true
        diagnostics.registrationStateRawValue = FirePushRegistrationDiagnostics.RegistrationState.registering.rawValue
        diagnostics.lastErrorMessage = nil
        diagnostics.lastUpdatedAtUnixMs = Self.currentTimestampUnixMs()
        persistDiagnostics()
        registerForRemoteNotifications()
    }

    private func persistDiagnostics() {
        defaults.set(diagnostics.authorizationStatusRawValue, forKey: Keys.authorizationStatus)
        defaults.set(diagnostics.registrationStateRawValue, forKey: Keys.registrationState)
        defaults.set(diagnostics.deviceTokenHex, forKey: Keys.deviceToken)
        defaults.set(diagnostics.lastErrorMessage, forKey: Keys.lastErrorMessage)
        defaults.set(diagnostics.lastUpdatedAtUnixMs, forKey: Keys.lastUpdatedAtUnixMs)
    }

    private static func loadDiagnostics(from defaults: UserDefaults) -> FirePushRegistrationDiagnostics {
        FirePushRegistrationDiagnostics(
            authorizationStatusRawValue: defaults.object(forKey: Keys.authorizationStatus) as? Int
                ?? FirePushRegistrationDiagnostics.initial.authorizationStatusRawValue,
            registrationStateRawValue: defaults.string(forKey: Keys.registrationState)
                ?? FirePushRegistrationDiagnostics.initial.registrationStateRawValue,
            deviceTokenHex: defaults.string(forKey: Keys.deviceToken),
            lastErrorMessage: defaults.string(forKey: Keys.lastErrorMessage),
            lastUpdatedAtUnixMs: (defaults.object(forKey: Keys.lastUpdatedAtUnixMs) as? NSNumber)?.uint64Value
        )
    }

    private static func currentTimestampUnixMs() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }
}
