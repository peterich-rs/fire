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
                browserUserAgent: nil,
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

    @MainActor
    func testCompleteLoginRollsBackPartialSessionWhenBootstrapRefreshIsChallenged() async {
        let store = MockLoginSessionStore(
            syncResult: partialAuthenticatedSession(),
            refreshResult: .failure(FireUniFfiError.CloudflareChallenge),
            logoutLocalResult: SessionState.placeholder()
        )
        let coordinator = FireWebViewLoginCoordinator(loginSessionStore: store)

        do {
            _ = try await coordinator.completeLogin(sampleCapturedLoginState())
            XCTFail("expected completeLogin to surface CloudflareChallenge")
        } catch let error as FireUniFfiError {
            XCTAssertEqual(error, .CloudflareChallenge)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let calls = await store.calls()
        XCTAssertEqual(calls.syncLoginContextCount, 1)
        XCTAssertEqual(calls.refreshBootstrapIfNeededCount, 1)
        XCTAssertEqual(calls.logoutLocalArguments, [true])
    }

    @MainActor
    func testCompleteLoginReturnsRefreshedSessionWhenBootstrapRefreshSucceeds() async throws {
        let refreshed = readySession(username: "alice")
        let store = MockLoginSessionStore(
            syncResult: partialAuthenticatedSession(),
            refreshResult: .success(refreshed),
            logoutLocalResult: SessionState.placeholder()
        )
        let coordinator = FireWebViewLoginCoordinator(loginSessionStore: store)

        let result = try await coordinator.completeLogin(sampleCapturedLoginState())

        XCTAssertEqual(result, refreshed)
        let calls = await store.calls()
        XCTAssertEqual(calls.syncLoginContextCount, 1)
        XCTAssertEqual(calls.refreshBootstrapIfNeededCount, 1)
        XCTAssertTrue(calls.logoutLocalArguments.isEmpty)
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
              "preloaded_json": "{\\"currentUser\\":{\\"id\\":1,\\"username\\":\\"alice\\",\\"notification_channel_position\\":42},\\"siteSettings\\":{\\"min_post_length\\":18,\\"discourse_reactions_enabled_reactions\\":\\"heart|clap\\"},\\"site\\":{\\"categories\\":[{\\"id\\":2,\\"name\\":\\"Rust\\",\\"slug\\":\\"rust\\"}],\\"top_tags\\":[\\"rust\\"],\\"can_tag_topics\\":true}}",
              "has_preloaded_data": true,
              "categories": [],
              "enabled_reaction_ids": ["heart"],
              "min_post_length": 1
            }
          }
        }
        """
    }

    private func sampleCapturedLoginState() -> FireCapturedLoginState {
        FireCapturedLoginState(
            currentURL: "https://linux.do",
            username: nil,
            csrfToken: nil,
            homeHTML: nil,
            browserUserAgent: "Mozilla/5.0 Test Browser",
            cookies: [
                makePlatformCookie(name: "_t", value: "token"),
                makePlatformCookie(name: "_forum_session", value: "forum"),
            ]
        )
    }

    private func partialAuthenticatedSession() -> SessionState {
        SessionState(
            cookies: CookieState(
                tToken: "token",
                forumSession: "forum",
                cfClearance: "clearance",
                csrfToken: nil,
                platformCookies: []
            ),
            bootstrap: BootstrapState(
                baseUrl: "https://linux.do",
                discourseBaseUri: "/",
                sharedSessionKey: nil,
                currentUsername: nil,
                currentUserId: nil,
                notificationChannelPosition: nil,
                longPollingBaseUrl: nil,
                turnstileSitekey: nil,
                topicTrackingStateMeta: nil,
                preloadedJson: nil,
                hasPreloadedData: false,
                hasSiteMetadata: false,
                topTags: [],
                canTagTopics: false,
                categories: [],
                hasSiteSettings: false,
                enabledReactionIds: ["heart"],
                minPostLength: 1
            ),
            readiness: SessionReadinessState(
                hasLoginCookie: true,
                hasForumSession: true,
                hasCloudflareClearance: true,
                hasCsrfToken: false,
                hasCurrentUser: false,
                hasPreloadedData: false,
                hasSharedSessionKey: false,
                canReadAuthenticatedApi: true,
                canWriteAuthenticatedApi: false,
                canOpenMessageBus: false
            ),
            loginPhase: .cookiesCaptured,
            hasLoginSession: true,
            profileDisplayName: "会话已连接",
            loginPhaseLabel: "账号信息同步中"
        )
    }

    private func readySession(username: String) -> SessionState {
        SessionState(
            cookies: CookieState(
                tToken: "token",
                forumSession: "forum",
                cfClearance: "clearance",
                csrfToken: "csrf-token",
                platformCookies: []
            ),
            bootstrap: BootstrapState(
                baseUrl: "https://linux.do",
                discourseBaseUri: "/",
                sharedSessionKey: nil,
                currentUsername: username,
                currentUserId: 1,
                notificationChannelPosition: 42,
                longPollingBaseUrl: "https://linux.do",
                turnstileSitekey: nil,
                topicTrackingStateMeta: "{\"message_bus_last_id\":42}",
                preloadedJson: "{\"currentUser\":{\"id\":1,\"username\":\"alice\"},\"siteSettings\":{\"min_post_length\":18,\"discourse_reactions_enabled_reactions\":\"heart|clap\"},\"site\":{\"categories\":[{\"id\":2,\"name\":\"Rust\",\"slug\":\"rust\"}],\"top_tags\":[\"rust\"],\"can_tag_topics\":true}}",
                hasPreloadedData: true,
                hasSiteMetadata: true,
                topTags: ["rust"],
                canTagTopics: true,
                categories: [],
                hasSiteSettings: true,
                enabledReactionIds: ["heart"],
                minPostLength: 1
            ),
            readiness: SessionReadinessState(
                hasLoginCookie: true,
                hasForumSession: true,
                hasCloudflareClearance: true,
                hasCsrfToken: true,
                hasCurrentUser: true,
                hasPreloadedData: true,
                hasSharedSessionKey: false,
                canReadAuthenticatedApi: true,
                canWriteAuthenticatedApi: true,
                canOpenMessageBus: true
            ),
            loginPhase: .ready,
            hasLoginSession: true,
            profileDisplayName: username,
            loginPhaseLabel: "已就绪"
        )
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

private actor MockLoginSessionStore: FireLoginSessionStoring {
    struct Calls {
        var syncLoginContextCount = 0
        var refreshBootstrapIfNeededCount = 0
        var logoutLocalArguments: [Bool] = []
    }

    private var recordedCalls = Calls()
    private let syncResult: Result<SessionState, Error>
    private let refreshResult: Result<SessionState, Error>
    private let logoutLocalResult: Result<SessionState, Error>

    init(
        syncResult: SessionState,
        refreshResult: Result<SessionState, Error>,
        logoutLocalResult: SessionState
    ) {
        self.syncResult = .success(syncResult)
        self.refreshResult = refreshResult
        self.logoutLocalResult = .success(logoutLocalResult)
    }

    func calls() -> Calls {
        recordedCalls
    }

    func restorePersistedSessionIfAvailable() async throws -> SessionState? {
        nil
    }

    func syncLoginContext(_ captured: FireCapturedLoginState) async throws -> SessionState {
        recordedCalls.syncLoginContextCount += 1
        return try syncResult.get()
    }

    func refreshBootstrapIfNeeded() async throws -> SessionState {
        recordedCalls.refreshBootstrapIfNeededCount += 1
        return try refreshResult.get()
    }

    func logout() async throws -> SessionState {
        SessionState.placeholder()
    }

    func logoutLocal(preserveCfClearance: Bool) async throws -> SessionState {
        recordedCalls.logoutLocalArguments.append(preserveCfClearance)
        return try logoutLocalResult.get()
    }

    func applyPlatformCookies(_ cookies: [PlatformCookieState]) async throws -> SessionState {
        SessionState.placeholder()
    }
}
