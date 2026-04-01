import Foundation
import XCTest
@testable import Fire

final class FireSessionSecurityTests: XCTestCase {
    func testRestoreColdStartReappliesSecureStoreCookiesToRedactedSession() async throws {
        let sessionFileURL = try makeSessionFileURL(name: "restore-cold-start-redacted")
        try redactedSessionJSON().write(to: sessionFileURL, atomically: true, encoding: .utf8)
        let secureStore = InMemoryAuthCookieSecureStore(
            secrets: FireAuthCookieSecrets(
                tToken: "token",
                forumSession: "forum",
                cfClearance: "clearance"
            )
        )
        let store = try FireSessionStore(
            workspacePath: try FireSessionStore.defaultWorkspacePath(),
            sessionFilePath: sessionFileURL.path,
            authCookieStore: secureStore
        )

        let session = try await store.restoreColdStartSession()
        let persisted = try String(contentsOf: sessionFileURL, encoding: .utf8)

        XCTAssertTrue(session.readiness.canReadAuthenticatedApi)
        XCTAssertTrue(session.readiness.hasCurrentUser)
        XCTAssertTrue(session.readiness.hasSharedSessionKey)
        XCTAssertTrue(session.readiness.canOpenMessageBus)
        XCTAssertEqual(session.loginPhase, .bootstrapCaptured)
        XCTAssertFalse(persisted.contains("\"token\""))
        XCTAssertFalse(persisted.contains("\"forum\""))
        XCTAssertFalse(persisted.contains("\"clearance\""))
    }

    func testRestoreColdStartClearsStaleBootstrapWhenSecureStoreIsMissing() async throws {
        let sessionFileURL = try makeSessionFileURL(name: "restore-cold-start-clears-bootstrap")
        try redactedSessionJSON().write(to: sessionFileURL, atomically: true, encoding: .utf8)
        let secureStore = InMemoryAuthCookieSecureStore()
        let store = try FireSessionStore(
            workspacePath: try FireSessionStore.defaultWorkspacePath(),
            sessionFilePath: sessionFileURL.path,
            authCookieStore: secureStore
        )

        let session = try await store.restoreColdStartSession()

        XCTAssertFalse(session.readiness.canReadAuthenticatedApi)
        XCTAssertFalse(session.readiness.hasCurrentUser)
        XCTAssertFalse(session.readiness.hasSharedSessionKey)
        XCTAssertNil(session.bootstrap.currentUsername)
        XCTAssertEqual(session.profileDisplayName, "未登录")
    }

    func testSyncLoginContextStoresCookiesInSecureStoreAndPersistsRedactedSession() async throws {
        let sessionFileURL = try makeSessionFileURL(name: "sync-login-context-stores-secure-cookies")
        let secureStore = InMemoryAuthCookieSecureStore()
        let store = try FireSessionStore(
            workspacePath: try FireSessionStore.defaultWorkspacePath(),
            sessionFilePath: sessionFileURL.path,
            authCookieStore: secureStore
        )

        _ = try await store.syncLoginContext(
            FireCapturedLoginState(
                currentURL: "https://linux.do",
                username: "alice",
                csrfToken: "csrf-token",
                homeHTML: nil,
                cookies: [
                    makePlatformCookie(name: "_t", value: "token"),
                    makePlatformCookie(name: "_forum_session", value: "forum"),
                    makePlatformCookie(name: "cf_clearance", value: "clearance"),
                ]
            )
        )

        let persisted = try String(contentsOf: sessionFileURL, encoding: .utf8)
        let secrets = try secureStore.load()

        XCTAssertEqual(secrets.tToken, "token")
        XCTAssertEqual(secrets.forumSession, "forum")
        XCTAssertEqual(secrets.cfClearance, "clearance")
        XCTAssertFalse(persisted.contains("\"token\""))
        XCTAssertFalse(persisted.contains("\"forum\""))
        XCTAssertFalse(persisted.contains("\"clearance\""))
        XCTAssertFalse(persisted.contains("\"csrf-token\""))
    }

    private func makeSessionFileURL(name: String) throws -> URL {
        let workspacePath = try FireSessionStore.defaultWorkspacePath()
        let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
        let testsURL = workspaceURL.appendingPathComponent("Tests", isDirectory: true)
        try FileManager.default.createDirectory(at: testsURL, withIntermediateDirectories: true)
        return testsURL.appendingPathComponent("\(name)-\(UUID().uuidString).json", isDirectory: false)
    }

    private func makePlatformCookie(name: String, value: String) -> PlatformCookieState {
        PlatformCookieState(name: name, value: value, domain: "linux.do", path: "/")
    }

    private func redactedSessionJSON() -> String {
        """
        {
          "version": 2,
          "saved_at_unix_ms": 1,
          "auth_cookies_redacted": true,
          "snapshot": {
            "cookies": {
              "t_token": null,
              "forum_session": null,
              "cf_clearance": null,
              "csrf_token": null
            },
            "bootstrap": {
              "base_url": "https://linux.do/",
              "discourse_base_uri": "/",
              "shared_session_key": "shared",
              "current_username": "alice",
              "current_user_id": 1,
              "notification_channel_position": 42,
              "long_polling_base_url": "https://linux.do",
              "turnstile_sitekey": "sitekey",
              "topic_tracking_state_meta": "{\\"message_bus_last_id\\":42}",
              "preloaded_json": "{\\"currentUser\\":{\\"id\\":1,\\"username\\":\\"alice\\",\\"notification_channel_position\\":42}}",
              "has_preloaded_data": true,
              "categories": [],
              "enabled_reaction_ids": ["heart"],
              "min_post_length": 1
            }
          }
        }
        """
    }
}

private final class InMemoryAuthCookieSecureStore: FireAuthCookieSecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: FireAuthCookieSecrets

    init(secrets: FireAuthCookieSecrets = FireAuthCookieSecrets()) {
        self.secrets = secrets
    }

    func load() throws -> FireAuthCookieSecrets {
        lock.lock()
        defer { lock.unlock() }
        return secrets
    }

    func save(_ secrets: FireAuthCookieSecrets) throws {
        lock.lock()
        self.secrets = secrets
        lock.unlock()
    }

    func clear(preserveCfClearance: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        secrets = preserveCfClearance ? secrets.preservingCfClearanceOnly() : FireAuthCookieSecrets()
    }
}
