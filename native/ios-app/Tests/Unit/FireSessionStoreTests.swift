import XCTest
@testable import Fire

final class FireSessionStoreTests: XCTestCase {
    func testRestoreColdStartSessionDefersNativeBootstrapRefresh() async throws {
        let fileManager = FileManager.default
        let workspaceURL = URL(
            fileURLWithPath: try FireSessionStore.defaultWorkspacePath(fileManager: fileManager),
            isDirectory: true
        )
        let sessionFileURL = workspaceURL.appendingPathComponent("session.json", isDirectory: false)
        try? fileManager.removeItem(at: sessionFileURL)
        defer {
            try? fileManager.removeItem(at: sessionFileURL)
        }

        let store = try FireSessionStore(
            workspacePath: workspaceURL.path,
            authCookieStore: MockAuthCookieSecureStore(
                secrets: FireAuthCookieSecrets(
                    tToken: "token",
                    forumSession: "forum",
                    cfClearance: "clearance"
                )
            )
        )

        var bootstrapCalls = 0

        let restored = try await store.restoreColdStartSession(
            refreshBootstrapIfNeeded: {
                bootstrapCalls += 1
                return Self.makeSessionState(csrfToken: nil)
            }
        )

        XCTAssertEqual(bootstrapCalls, 0)
        XCTAssertNil(restored.cookies.csrfToken)
        XCTAssertTrue(restored.readiness.canReadAuthenticatedApi)
        XCTAssertFalse(restored.readiness.canWriteAuthenticatedApi)
        XCTAssertFalse(restored.readiness.hasCurrentUser)
    }

    func testRestoreColdStartSessionCanStillRefreshBootstrapWhenExplicitlyRequested() async throws {
        let fileManager = FileManager.default
        let workspaceURL = URL(
            fileURLWithPath: try FireSessionStore.defaultWorkspacePath(fileManager: fileManager),
            isDirectory: true
        )
        let sessionFileURL = workspaceURL.appendingPathComponent("session.json", isDirectory: false)
        try? fileManager.removeItem(at: sessionFileURL)
        defer {
            try? fileManager.removeItem(at: sessionFileURL)
        }

        let store = try FireSessionStore(
            workspacePath: workspaceURL.path,
            authCookieStore: MockAuthCookieSecureStore()
        )

        var bootstrapCalls = 0

        let restored = try await store.restoreColdStartSession(
            refreshBootstrapIfNeeded: {
                bootstrapCalls += 1
                return Self.makeSessionState(csrfToken: nil)
            },
            refreshBootstrapDuringRestore: true
        )

        XCTAssertEqual(bootstrapCalls, 1)
        XCTAssertNil(restored.cookies.csrfToken)
        XCTAssertTrue(restored.readiness.canReadAuthenticatedApi)
        XCTAssertFalse(restored.readiness.canWriteAuthenticatedApi)
        XCTAssertTrue(restored.readiness.hasCurrentUser)
    }

    func testCfClearanceAutoRefreshRequiresConfirmedLoginState() {
        let session = Self.makeSessionState(
            csrfToken: "csrf-token",
            turnstileSitekey: "sitekey"
        )

        XCTAssertFalse(
            FireCfClearanceRefreshService.shouldAutoRefresh(
                session: session,
                sceneActive: true,
                loginStateConfirmed: false
            )
        )
        XCTAssertTrue(
            FireCfClearanceRefreshService.shouldAutoRefresh(
                session: session,
                sceneActive: true,
                loginStateConfirmed: true
            )
        )
    }

    func testCfClearanceAutoRefreshStillRequiresReadyAuthenticatedSession() {
        var session = Self.makeSessionState(
            csrfToken: "csrf-token",
            turnstileSitekey: "sitekey"
        )
        session.readiness.hasCurrentUser = false

        XCTAssertFalse(
            FireCfClearanceRefreshService.shouldAutoRefresh(
                session: session,
                sceneActive: true,
                loginStateConfirmed: true
            )
        )
    }

    private static func makeSessionState(
        csrfToken: String?,
        turnstileSitekey: String? = nil
    ) -> SessionState {
        SessionState(
            cookies: CookieState(
                tToken: "token",
                forumSession: "forum",
                cfClearance: "clearance",
                csrfToken: csrfToken,
                platformCookies: [],
                canonicalCookies: []
            ),
            bootstrap: BootstrapState(
                baseUrl: "https://linux.do",
                discourseBaseUri: "/",
                sharedSessionKey: "shared-session",
                currentUsername: "alice",
                currentUserId: 1,
                notificationChannelPosition: nil,
                longPollingBaseUrl: "https://linux.do",
                turnstileSitekey: turnstileSitekey,
                topicTrackingStateMeta: nil,
                preloadedJson: "{\"site\":{}}",
                hasPreloadedData: true,
                hasSiteMetadata: true,
                topTags: [],
                canTagTopics: false,
                categories: [],
                hasSiteSettings: true,
                enabledReactionIds: ["heart"],
                minPostLength: 1,
                minTopicTitleLength: 15,
                minFirstPostLength: 20,
                minPersonalMessageTitleLength: 2,
                minPersonalMessagePostLength: 10,
                defaultComposerCategory: nil
            ),
            readiness: SessionReadinessState(
                hasLoginCookie: true,
                hasForumSession: true,
                hasCloudflareClearance: true,
                hasCsrfToken: csrfToken != nil,
                hasCurrentUser: true,
                hasPreloadedData: true,
                hasSharedSessionKey: true,
                canReadAuthenticatedApi: true,
                canWriteAuthenticatedApi: csrfToken != nil,
                canOpenMessageBus: true
            ),
            loginPhase: .ready,
            hasLoginSession: true,
            browserUserAgent: nil,
            profileDisplayName: "alice",
            loginPhaseLabel: csrfToken == nil ? "账号信息同步中" : "已就绪"
        )
    }
}

private struct MockAuthCookieSecureStore: FireAuthCookieSecureStore {
    var secrets = FireAuthCookieSecrets()

    func load() throws -> FireAuthCookieSecrets {
        secrets
    }

    func save(_ secrets: FireAuthCookieSecrets) throws {
    }

    func clear(preserveCfClearance: Bool) throws {
    }
}
