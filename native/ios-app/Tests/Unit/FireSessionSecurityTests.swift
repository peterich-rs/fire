import Foundation
import WebKit
import XCTest
@testable import Fire

final class FireSessionSecurityTests: XCTestCase {
    @MainActor
    func testMirrorCookiesToNativeStorageSynchronizesWebKitStore() async throws {
        let freshExpiry = Int64(Date().timeIntervalSince1970 * 1000) + 60_000
        let store = InMemoryMirroredCookieStore()
        let session = SessionState(
            cookies: CookieState(
                tToken: "fresh-token",
                forumSession: "fresh-forum",
                cfClearance: "fresh-clearance",
                csrfToken: nil,
                platformCookies: [
                    makePlatformCookie(
                        name: "_t",
                        value: "fresh-token",
                        domain: "linux.do",
                        expiresAtUnixMs: freshExpiry
                    ),
                    makePlatformCookie(
                        name: "_forum_session",
                        value: "fresh-forum",
                        domain: "linux.do"
                    ),
                    makePlatformCookie(
                        name: "cf_clearance",
                        value: "fresh-clearance",
                        domain: ".linux.do",
                        expiresAtUnixMs: freshExpiry
                    ),
                    makePlatformCookie(
                        name: "__cf_bm",
                        value: "browser-context",
                        domain: ".linux.do",
                        path: "/cdn-cgi",
                        expiresAtUnixMs: freshExpiry
                    ),
                ]
            ),
            bootstrap: BootstrapState(
                baseUrl: "https://linux.do",
                discourseBaseUri: nil,
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

        let previousFactory = MirroredCookieStoreFactory.makeWebKitStore
        MirroredCookieStoreFactory.makeWebKitStore = { store }
        defer {
            MirroredCookieStoreFactory.makeWebKitStore = previousFactory
        }

        clearMirroredCookiesFromSharedStorage()
        await clearMirroredCookiesFromWebKitStore(store)

        let staleToken = try XCTUnwrap(
            makeHTTPCookie(name: "_t", value: "stale-token", domain: "linux.do")
        )
        HTTPCookieStorage.shared.setCookie(staleToken)
        await store.setCookie(staleToken)

        await session.mirrorCookiesToNativeStorage()

        let sharedCookies = mirroredSharedCookies()
        XCTAssertEqual(sharedCookies.count, 4)
        XCTAssertEqual(sharedCookies.first(where: { $0.name == "_t" })?.value, "fresh-token")
        XCTAssertEqual(
            sharedCookies.first(where: { $0.name == "cf_clearance" })?.value,
            "fresh-clearance"
        )
        XCTAssertEqual(
            sharedCookies.first(where: { $0.name == "__cf_bm" })?.value,
            "browser-context"
        )

        let webKitCookies = await mirroredWebKitCookies(store)
        XCTAssertEqual(webKitCookies.count, 4)
        XCTAssertEqual(webKitCookies.first(where: { $0.name == "_t" })?.value, "fresh-token")
        XCTAssertEqual(
            webKitCookies.first(where: { $0.name == "cf_clearance" })?.value,
            "fresh-clearance"
        )
        XCTAssertEqual(
            webKitCookies.first(where: { $0.name == "__cf_bm" })?.value,
            "browser-context"
        )
        XCTAssertFalse(webKitCookies.contains(where: { $0.value == "stale-token" }))

        clearMirroredCookiesFromSharedStorage()
        await clearMirroredCookiesFromWebKitStore(store)
    }

    func testRestoreColdStartReappliesSecureStoreCookiesAndRepairsLegacyRedactedCsrf() async throws {
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
        let recorder = ColdStartRefreshRecorder()

        let session = try await store.restoreColdStartSession(
            refreshBootstrapIfNeeded: {
                await recorder.recordBootstrapRefresh()
                return self.bootstrapCapturedSession(username: "alice")
            },
            refreshCsrfTokenIfNeeded: {
                await recorder.recordCsrfRefresh()
                return self.readySession(username: "alice")
            }
        )
        let persisted = try String(contentsOf: sessionFileURL, encoding: .utf8)
        let counts = await recorder.snapshot()
        let debugSession = "\(session)"

        XCTAssertTrue(session.readiness.canReadAuthenticatedApi, debugSession)
        XCTAssertTrue(session.readiness.canWriteAuthenticatedApi, debugSession)
        XCTAssertTrue(session.readiness.hasCurrentUser, debugSession)
        XCTAssertTrue(session.readiness.hasSharedSessionKey, debugSession)
        XCTAssertTrue(session.readiness.canOpenMessageBus, debugSession)
        XCTAssertEqual(session.loginPhase, .ready, debugSession)
        XCTAssertEqual(counts.bootstrapRefreshCount, 1)
        XCTAssertEqual(counts.csrfRefreshCount, 1)
        XCTAssertTrue(persisted.contains("\"token\""))
        XCTAssertTrue(persisted.contains("\"forum\""))
        XCTAssertTrue(persisted.contains("\"clearance\""))
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

    func testRestoreColdStartSkipsCsrfRepairWhenBootstrapStillIncomplete() async throws {
        let sessionFileURL = try makeSessionFileURL(name: "restore-cold-start-no-csrf-repair")
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
        let recorder = ColdStartRefreshRecorder()

        let session = try await store.restoreColdStartSession(
            refreshBootstrapIfNeeded: {
                await recorder.recordBootstrapRefresh()
                return self.partialAuthenticatedSession()
            },
            refreshCsrfTokenIfNeeded: {
                await recorder.recordCsrfRefresh()
                return self.readySession(username: "alice")
            }
        )
        let counts = await recorder.snapshot()

        XCTAssertFalse(session.readiness.canWriteAuthenticatedApi)
        XCTAssertEqual(session.loginPhase, .cookiesCaptured)
        XCTAssertEqual(counts.bootstrapRefreshCount, 1)
        XCTAssertEqual(counts.csrfRefreshCount, 0)
    }

    func testSyncLoginContextStoresCookiesInSecureStoreAndPersistsFullSession() async throws {
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
        XCTAssertTrue(persisted.contains("\"token\""))
        XCTAssertTrue(persisted.contains("\"forum\""))
        XCTAssertTrue(persisted.contains("\"clearance\""))
        XCTAssertTrue(persisted.contains("\"csrf-token\""))
    }

    func testPersistCurrentSessionRewritesSecureStoreFromCurrentSnapshot() async throws {
        let sessionFileURL = try makeSessionFileURL(name: "persist-current-session-rewrites-secure-store")
        let secureStore = InMemoryAuthCookieSecureStore()
        let store = try FireSessionStore(
            workspacePath: try FireSessionStore.defaultWorkspacePath(),
            sessionFilePath: sessionFileURL.path,
            authCookieStore: secureStore
        )
        let freshExpiry = Int64(Date().timeIntervalSince1970 * 1000) + 60_000

        _ = try await store.syncLoginContext(
            FireCapturedLoginState(
                currentURL: "https://linux.do",
                username: "alice",
                csrfToken: "csrf-token",
                homeHTML: nil,
                browserUserAgent: nil,
                cookies: [
                    makePlatformCookie(
                        name: "_t",
                        value: "fresh-token",
                        domain: "linux.do",
                        expiresAtUnixMs: freshExpiry
                    ),
                    makePlatformCookie(
                        name: "_forum_session",
                        value: "fresh-forum",
                        domain: ".linux.do",
                        expiresAtUnixMs: freshExpiry
                    ),
                ]
            )
        )

        try secureStore.save(
            FireAuthCookieSecrets(
                platformCookies: [
                    makePlatformCookie(
                        name: "_t",
                        value: "stale-token",
                        domain: "linux.do"
                    ),
                    makePlatformCookie(
                        name: "_forum_session",
                        value: "stale-forum",
                        domain: ".linux.do"
                    ),
                ]
            )
        )

        try await store.persistCurrentSession()

        let secrets = try secureStore.load()

        XCTAssertEqual(secrets.tToken, "fresh-token")
        XCTAssertEqual(secrets.forumSession, "fresh-forum")
        XCTAssertEqual(secrets.platformCookies.count, 2)
        XCTAssertTrue(
            secrets.platformCookies.contains { cookie in
                cookie.name == "_t"
                    && cookie.value == "fresh-token"
                    && cookie.domain == "linux.do"
                    && cookie.expiresAtUnixMs == freshExpiry
            }
        )
        XCTAssertTrue(
            secrets.platformCookies.contains { cookie in
                cookie.name == "_forum_session"
                    && cookie.value == "fresh-forum"
                    && cookie.domain == ".linux.do"
                    && cookie.expiresAtUnixMs == freshExpiry
            }
        )
    }

    func testAuthCookieSecretsPreserveExpiryAndDistinctDomainVariants() throws {
        let futureExpiry = Int64(Date().timeIntervalSince1970 * 1000) + 60_000
        let secrets = FireAuthCookieSecrets(
            platformCookies: [
                makePlatformCookie(
                    name: "_t",
                    value: "host-cookie",
                    domain: "linux.do",
                    expiresAtUnixMs: futureExpiry
                ),
                makePlatformCookie(
                    name: "_t",
                    value: "domain-cookie",
                    domain: ".linux.do",
                    expiresAtUnixMs: futureExpiry
                ),
            ]
        )

        let restored = secrets.platformCookies(baseURL: URL(string: "https://linux.do")!)

        XCTAssertEqual(restored.count, 2)
        XCTAssertTrue(
            restored.contains { cookie in
                cookie.domain == "linux.do"
                    && cookie.value == "host-cookie"
                    && cookie.expiresAtUnixMs == futureExpiry
            }
        )
        XCTAssertTrue(
            restored.contains { cookie in
                cookie.domain == ".linux.do"
                    && cookie.value == "domain-cookie"
                    && cookie.expiresAtUnixMs == futureExpiry
            }
        )
    }

    func testAuthCookieSecretsFilterExpiredPlatformCookies() throws {
        let futureExpiry = Int64(Date().timeIntervalSince1970 * 1000) + 60_000
        let secrets = FireAuthCookieSecrets(
            platformCookies: [
                makePlatformCookie(
                    name: "_t",
                    value: "expired-token",
                    domain: "linux.do",
                    expiresAtUnixMs: 1
                ),
                makePlatformCookie(
                    name: "_forum_session",
                    value: "fresh-forum",
                    domain: "linux.do",
                    expiresAtUnixMs: futureExpiry
                ),
            ]
        )

        let restored = secrets.platformCookies(baseURL: URL(string: "https://linux.do")!)

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.name, "_forum_session")
        XCTAssertEqual(restored.first?.expiresAtUnixMs, futureExpiry)
    }

    func testAuthCookieSecretsNormalizedRecomputesScalarMirrorsFromActivePlatformCookies() throws {
        let futureExpiry = Int64(Date().timeIntervalSince1970 * 1000) + 60_000
        let normalized = FireAuthCookieSecrets(
            tToken: "stale-token",
            forumSession: "stale-forum",
            cfClearance: "stale-clearance",
            platformCookies: [
                makePlatformCookie(
                    name: "_t",
                    value: "expired-token",
                    domain: "linux.do",
                    expiresAtUnixMs: 1
                ),
                makePlatformCookie(
                    name: "_forum_session",
                    value: "fresh-forum",
                    domain: "linux.do",
                    expiresAtUnixMs: futureExpiry
                ),
                makePlatformCookie(
                    name: "cf_clearance",
                    value: "fresh-clearance",
                    domain: "linux.do",
                    expiresAtUnixMs: futureExpiry
                ),
            ].map(FireStoredPlatformCookie.init)
        ).normalized()

        XCTAssertNil(normalized.tToken)
        XCTAssertEqual(normalized.forumSession, "fresh-forum")
        XCTAssertEqual(normalized.cfClearance, "fresh-clearance")
        XCTAssertEqual(normalized.platformCookies.count, 2)
        XCTAssertEqual(
            normalized.platformCookies.map { $0.name }.sorted(),
            ["_forum_session", "cf_clearance"]
        )
    }

    func testAuthCookieSecretsNormalizedPreservesScalarOnlySecrets() throws {
        let normalized = FireAuthCookieSecrets(
            tToken: "token",
            forumSession: "forum",
            cfClearance: "clearance"
        ).normalized()

        XCTAssertEqual(normalized.tToken, "token")
        XCTAssertEqual(normalized.forumSession, "forum")
        XCTAssertEqual(normalized.cfClearance, "clearance")
        XCTAssertTrue(normalized.platformCookies.isEmpty)
    }

    func testAuthenticatedWritePreflightHostResyncRunsAtMostOncePerEpoch() async throws {
        let store = try makeAuthenticatedWritePreflightStore()
        let harness = AuthenticatedWritePreflightHarness(
            context: authenticatedWritePreflightContext(
                sessionEpoch: 7,
                authRecoveryHint: authRecoveryHint(epoch: 7)
            ),
            hostResyncCookies: [
                makePlatformCookie(name: "_forum_session", value: "forum-2")
            ]
        )

        try await runAuthenticatedWritePreflight(store: store, harness: harness)
        try await runAuthenticatedWritePreflight(store: store, harness: harness)

        let counts = await harness.counts()
        XCTAssertEqual(counts.hostResyncProviderCount, 1)
        XCTAssertEqual(counts.applyPlatformCookiesCount, 1)
    }

    func testAuthenticatedWritePreflightSingleFlightsConcurrentHostResync() async throws {
        let store = try makeAuthenticatedWritePreflightStore()
        let enteredGate = AsyncGate()
        let releaseGate = AsyncGate()
        let harness = AuthenticatedWritePreflightHarness(
            context: authenticatedWritePreflightContext(
                sessionEpoch: 11,
                authRecoveryHint: authRecoveryHint(epoch: 11)
            ),
            hostResyncCookies: [
                makePlatformCookie(name: "_forum_session", value: "forum-2")
            ],
            providerEnteredGate: enteredGate,
            providerReleaseGate: releaseGate
        )

        let firstTask = Task {
            try await self.runAuthenticatedWritePreflight(store: store, harness: harness)
        }

        await enteredGate.wait()

        let secondTask = Task {
            try await self.runAuthenticatedWritePreflight(store: store, harness: harness)
        }

        await releaseGate.open()

        try await firstTask.value
        try await secondTask.value

        let counts = await harness.counts()
        XCTAssertEqual(counts.hostResyncProviderCount, 1)
        XCTAssertEqual(counts.applyPlatformCookiesCount, 1)
    }

    func testAuthenticatedWritePreflightSkipsHostResyncWhenCsrfRefreshRequiresLogin() async throws {
        let store = try makeAuthenticatedWritePreflightStore()
        let harness = AuthenticatedWritePreflightHarness(
            context: authenticatedWritePreflightContext(
                sessionEpoch: 19,
                authRecoveryHint: authRecoveryHint(epoch: 19)
            ),
            refreshOutcomes: [
                .error(FireUniFfiError.LoginRequired(details: "您需要登录才能执行此操作。"))
            ],
            hostResyncCookies: [
                makePlatformCookie(name: "_forum_session", value: "forum-2")
            ]
        )

        do {
            try await runAuthenticatedWritePreflight(store: store, harness: harness)
            XCTFail("expected LoginRequired to bypass host resync")
        } catch let error as FireUniFfiError {
            XCTAssertEqual(error, .LoginRequired(details: "您需要登录才能执行此操作。"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let counts = await harness.counts()
        XCTAssertEqual(counts.hostResyncProviderCount, 0)
        XCTAssertEqual(counts.applyPlatformCookiesCount, 0)
    }

    func testAuthenticatedWritePreflightDropsLateHostResyncResultsFromOldEpoch() async throws {
        let store = try makeAuthenticatedWritePreflightStore()
        let enteredGate = AsyncGate()
        let releaseGate = AsyncGate()
        let harness = AuthenticatedWritePreflightHarness(
            context: authenticatedWritePreflightContext(
                sessionEpoch: 23,
                authRecoveryHint: authRecoveryHint(epoch: 23)
            ),
            hostResyncCookies: [
                makePlatformCookie(name: "_forum_session", value: "forum-2")
            ],
            providerEnteredGate: enteredGate,
            providerReleaseGate: releaseGate
        )

        await harness.setNextAppliedContext(
            authenticatedWritePreflightContext(
                sessionEpoch: 25,
                authRecoveryHint: nil
            )
        )

        let firstTask = Task {
            try await self.runAuthenticatedWritePreflight(store: store, harness: harness)
        }

        await enteredGate.wait()
        await harness.setContext(
            authenticatedWritePreflightContext(
                sessionEpoch: 24,
                authRecoveryHint: authRecoveryHint(epoch: 24)
            )
        )
        await releaseGate.open()

        try await firstTask.value

        var counts = await harness.counts()
        XCTAssertEqual(counts.hostResyncProviderCount, 1)
        XCTAssertEqual(counts.applyPlatformCookiesCount, 0)

        try await runAuthenticatedWritePreflight(store: store, harness: harness)

        counts = await harness.counts()
        XCTAssertEqual(counts.hostResyncProviderCount, 2)
        XCTAssertEqual(counts.applyPlatformCookiesCount, 1)
    }

    @MainActor
    func testCompleteLoginRollsBackPartialSessionWhenBootstrapRefreshIsChallenged() async {
        let store = MockLoginSessionStore(
            syncResult: partialAuthenticatedSession(),
            refreshResult: .failure(FireUniFfiError.CloudflareChallenge),
            logoutLocalResult: SessionState.placeholder()
        )
        let clearedChallengeCookies = expectation(
            description: "challenge recovery cookies cleared"
        )
        let coordinator = FireWebViewLoginCoordinator(
            loginSessionStore: store,
            challengeRecoveryCookieCleaner: {
                clearedChallengeCookies.fulfill()
            }
        )

        do {
            _ = try await coordinator.completeLogin(sampleCapturedLoginState())
            XCTFail("expected completeLogin to surface CloudflareChallenge")
        } catch let error as FireUniFfiError {
            XCTAssertEqual(error, .CloudflareChallenge)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        await fulfillment(of: [clearedChallengeCookies], timeout: 1.0)
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

    func testBootstrapHTMLHeuristicsPreferCurrentPageWhenFetchedHomeHTMLIsPartial() {
        let browserFetchedHomeHTML = """
        <!doctype html>
        <html>
          <head>
            <meta name="current-username" content="alice">
            <meta name="csrf-token" content="csrf-token">
          </head>
          <body>
            <div id="data-discourse-setup" data-preloaded="{&quot;currentUser&quot;:{&quot;username&quot;:&quot;alice&quot;},&quot;siteSettings&quot;:{&quot;min_post_length&quot;:20}}"></div>
          </body>
        </html>
        """
        let currentPageHTML = """
        <!doctype html>
        <html>
          <head>
            <meta name="shared_session_key" content="shared-session">
            <meta name="current-username" content="alice">
            <meta name="csrf-token" content="csrf-token">
          </head>
          <body>
            <div id="data-discourse-setup" data-preloaded="{&quot;currentUser&quot;:{&quot;id&quot;:1,&quot;username&quot;:&quot;alice&quot;,&quot;notification_channel_position&quot;:42},&quot;siteSettings&quot;:{&quot;long_polling_base_url&quot;:&quot;https://ping.linux.do&quot;,&quot;min_post_length&quot;:20},&quot;topicTrackingStateMeta&quot;:{&quot;/notification/1&quot;:42},&quot;site&quot;:{&quot;categories&quot;:[{&quot;id&quot;:2,&quot;name&quot;:&quot;Rust&quot;,&quot;slug&quot;:&quot;rust&quot;}],&quot;top_tags&quot;:[&quot;rust&quot;],&quot;can_tag_topics&quot;:true}}"></div>
          </body>
        </html>
        """

        XCTAssertEqual(
            FireBootstrapHTMLHeuristics.preferredHTML(
                browserFetchedHomeHTML: browserFetchedHomeHTML,
                currentPageHTML: currentPageHTML
            ),
            currentPageHTML
        )
    }

    func testBootstrapHTMLHeuristicsKeepFetchedHomeWhenCurrentPageHasNoBootstrap() {
        let browserFetchedHomeHTML = """
        <!doctype html>
        <html>
          <head>
            <meta name="shared_session_key" content="shared-session">
            <meta name="current-username" content="alice">
            <meta name="csrf-token" content="csrf-token">
          </head>
          <body>
            <div id="data-discourse-setup" data-preloaded="{&quot;currentUser&quot;:{&quot;id&quot;:1,&quot;username&quot;:&quot;alice&quot;,&quot;notification_channel_position&quot;:42},&quot;siteSettings&quot;:{&quot;long_polling_base_url&quot;:&quot;https://ping.linux.do&quot;,&quot;min_post_length&quot;:20},&quot;site&quot;:{&quot;categories&quot;:[{&quot;id&quot;:2,&quot;name&quot;:&quot;Rust&quot;,&quot;slug&quot;:&quot;rust&quot;}],&quot;top_tags&quot;:[&quot;rust&quot;],&quot;can_tag_topics&quot;:true}}"></div>
          </body>
        </html>
        """
        let currentPageHTML = "<html><body>Sync complete</body></html>"

        XCTAssertEqual(
            FireBootstrapHTMLHeuristics.preferredHTML(
                browserFetchedHomeHTML: browserFetchedHomeHTML,
                currentPageHTML: currentPageHTML
            ),
            browserFetchedHomeHTML
        )
    }

    func testBootstrapHTMLMetadataParserReadsMetaFallbackValues() {
        let html = """
        <!doctype html>
        <html>
          <head>
            <meta content="alice" name="current-username">
            <meta name="csrf-token" content="csrf-token">
          </head>
        </html>
        """

        XCTAssertEqual(FireBootstrapHTMLMetadataParser.currentUsername(from: html), "alice")
        XCTAssertEqual(FireBootstrapHTMLMetadataParser.csrfToken(from: html), "csrf-token")
    }

    @MainActor
    func testLoginSyncReadinessRequiresUsernameAuthCookiesAndBootstrapHTML() async {
        let store = MockLoginSessionStore(
            syncResult: partialAuthenticatedSession(),
            refreshResult: .success(readySession(username: "alice")),
            logoutLocalResult: SessionState.placeholder()
        )
        let coordinator = FireWebViewLoginCoordinator(loginSessionStore: store)
        let ready = coordinator.loginSyncReadiness(
            for: FireCapturedLoginState(
                currentURL: "https://linux.do",
                username: "alice",
                csrfToken: "csrf-token",
                homeHTML: """
                <!doctype html>
                <html>
                  <head><meta name="current-username" content="alice"></head>
                  <body>
                    <div id="data-discourse-setup" data-preloaded="{&quot;currentUser&quot;:{&quot;username&quot;:&quot;alice&quot;}}"></div>
                  </body>
                </html>
                """,
                browserUserAgent: "Mozilla/5.0",
                cookies: [
                    makePlatformCookie(name: "_t", value: "token"),
                    makePlatformCookie(name: "_forum_session", value: "forum"),
                ]
            )
        )
        let missingBootstrap = coordinator.loginSyncReadiness(
            for: FireCapturedLoginState(
                currentURL: "https://linux.do",
                username: "alice",
                csrfToken: "csrf-token",
                homeHTML: "<html><body>Done</body></html>",
                browserUserAgent: "Mozilla/5.0",
                cookies: [
                    makePlatformCookie(name: "_t", value: "token"),
                    makePlatformCookie(name: "_forum_session", value: "forum"),
                ]
            )
        )
        let missingCookies = coordinator.loginSyncReadiness(
            for: FireCapturedLoginState(
                currentURL: "https://linux.do",
                username: "alice",
                csrfToken: "csrf-token",
                homeHTML: """
                <!doctype html>
                <html><body><div id="data-discourse-setup" data-preloaded="{}"></div></body></html>
                """,
                browserUserAgent: "Mozilla/5.0",
                cookies: [makePlatformCookie(name: "_t", value: "token")]
            )
        )

        XCTAssertTrue(ready.isReady)
        XCTAssertTrue(ready.hasAuthCookies)
        XCTAssertTrue(ready.hasBootstrapHTML)
        XCTAssertFalse(missingBootstrap.isReady)
        XCTAssertFalse(missingBootstrap.hasBootstrapHTML)
        XCTAssertFalse(missingCookies.isReady)
        XCTAssertFalse(missingCookies.hasAuthCookies)
    }

    func testCfClearanceRefreshServiceRequiresAuthenticatedSessionSceneAndSitekey() {
        XCTAssertFalse(
            FireCfClearanceRefreshService.shouldAutoRefresh(
                session: authenticatedSession(),
                sceneActive: true
            )
        )
        XCTAssertFalse(
            FireCfClearanceRefreshService.shouldAutoRefresh(
                session: authenticatedSession(turnstileSitekey: "sitekey"),
                sceneActive: false
            )
        )
        XCTAssertTrue(
            FireCfClearanceRefreshService.shouldAutoRefresh(
                session: authenticatedSession(turnstileSitekey: "sitekey"),
                sceneActive: true
            )
        )
        XCTAssertFalse(
            FireCfClearanceRefreshService.shouldAutoRefresh(
                session: authenticatedSession(turnstileSitekey: "sitekey"),
                sceneActive: true,
                interactiveRecoveryActive: true
            )
        )
    }

    func testCfClearanceRefreshServiceTurnstileRuntimeIncludesRcBridge() {
        let html = FireCfClearanceRefreshService.turnstileHTML(
            sitekey: "sitekey",
            runtimeToken: "runtime-token"
        )

        XCTAssertTrue(
            FireCfClearanceRefreshService.fetchInterceptionUserScriptSource
                .contains("onRcIntercepted")
        )
        XCTAssertTrue(
            FireCfClearanceRefreshService.fetchInterceptionUserScriptSource
                .contains("window._resolveRc")
        )
        XCTAssertTrue(html.contains("window.__fireCfRuntimeToken = \"runtime-token\""))
        XCTAssertTrue(html.contains("'refresh-expired': 'auto'"))
        XCTAssertTrue(html.contains("onTurnstileError"))
    }

    func testCfClearanceRefreshServiceBuildsRcEndpointURL() {
        let url = FireCfClearanceRefreshService.rcEndpointURL(
            baseURL: URL(string: "https://linux.do")!,
            challengeID: "challenge-id"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://linux.do/cdn-cgi/challenge-platform/h/g/rc/challenge-id"
        )
    }

    @MainActor
    func testOpenLoginPresentsLoginImmediatelyBeforeWarmupCompletes() async {
        let gate = AsyncGate()
        let viewModel = FireAppViewModel(
            loginCoordinatorPreloader: {
                await gate.wait()
            },
            loginNetworkWarmup: {}
        )

        viewModel.openLogin()

        XCTAssertTrue(viewModel.isPresentingLogin)
        XCTAssertTrue(viewModel.isPreparingLogin)

        await gate.open()
        let finishedPreparing = await waitUntil { !viewModel.isPreparingLogin }
        XCTAssertTrue(finishedPreparing)
        XCTAssertFalse(viewModel.isPreparingLogin)
    }

    @MainActor
    func testOpenLoginKeepsPresentedWhenCoordinatorPreloadFails() async {
        struct SampleLoginOpenError: LocalizedError {
            var errorDescription: String? { "login init failed" }
        }

        let viewModel = FireAppViewModel(
            loginCoordinatorPreloader: {
                throw SampleLoginOpenError()
            },
            loginNetworkWarmup: {}
        )

        viewModel.openLogin()

        XCTAssertTrue(viewModel.isPresentingLogin)

        let finishedPreparing = await waitUntil { !viewModel.isPreparingLogin }
        let surfacedError = await waitUntil { viewModel.errorMessage != nil }
        XCTAssertTrue(finishedPreparing)
        XCTAssertTrue(surfacedError)
        XCTAssertFalse(viewModel.isPreparingLogin)
        XCTAssertEqual(viewModel.errorMessage, "login init failed")
    }

    @MainActor
    func testChallengeRecoveryPresentsInteractiveRecoveryWithoutClearingSession() async {
        let viewModel = FireAppViewModel(initialSession: authenticatedSession())

        let recovered = await viewModel.handleCloudflareChallengeIfNeeded(
            FireUniFfiError.CloudflareChallenge
        )

        XCTAssertTrue(recovered)
        XCTAssertTrue(viewModel.isPresentingLogin)
        guard case let .cloudflareRecovery(context)? = viewModel.authPresentationState else {
            return XCTFail("expected interactive Cloudflare recovery presentation")
        }
        XCTAssertEqual(context.preferredURL.absoluteString, "https://linux.do/challenge")
        XCTAssertEqual(
            context.message,
            "需要先完成 Cloudflare 验证。请在验证页完成后重试。"
        )
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.session.hasLoginSession)
        XCTAssertTrue(viewModel.session.readiness.canReadAuthenticatedApi)
        XCTAssertTrue(viewModel.session.readiness.hasCloudflareClearance)
    }

    @MainActor
    func testStaleSessionResponseIsConsumedWithoutPresentingRecovery() async {
        let viewModel = FireAppViewModel(initialSession: authenticatedSession())

        let recovered = await viewModel.handleRecoverableSessionErrorIfNeeded(
            FireUniFfiError.StaleSessionResponse(operation: "fetch topic list")
        )

        XCTAssertTrue(recovered)
        XCTAssertFalse(viewModel.isPresentingLogin)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.session.hasLoginSession)
        XCTAssertTrue(viewModel.session.readiness.canReadAuthenticatedApi)
        XCTAssertTrue(viewModel.session.readiness.hasCloudflareClearance)
    }

    @MainActor
    func testLoginRequiredRecoveryClearsLocalSessionAndPresentsLogin() async {
        let recoveryStore = MockChallengeRecoveryStore(
            result: .success(challengedLoggedOutSession())
        )
        let viewModel = FireAppViewModel(
            initialSession: authenticatedSession(),
            challengeRecoveryStore: recoveryStore
        )

        let recovered = await viewModel.handleLoginRequiredIfNeeded(
            FireUniFfiError.LoginRequired(details: "您需要登录才能执行此操作。")
        )

        XCTAssertTrue(recovered)
        XCTAssertTrue(viewModel.isPresentingLogin)
        XCTAssertEqual(viewModel.errorMessage, "您需要登录才能执行此操作。")
        XCTAssertFalse(viewModel.session.hasLoginSession)
        XCTAssertFalse(viewModel.session.readiness.canReadAuthenticatedApi)
        XCTAssertTrue(viewModel.session.readiness.hasCloudflareClearance)
        let calls = await recoveryStore.recordedCalls()
        XCTAssertEqual(calls, [true])
    }

    @MainActor
    func testLoginRequiredRecoveryDeduplicatesConcurrentReset() async {
        let enteredGate = AsyncGate()
        let releaseGate = AsyncGate()
        let recoveryStore = BlockingChallengeRecoveryStore(
            enteredGate: enteredGate,
            releaseGate: releaseGate,
            result: .success(challengedLoggedOutSession())
        )
        let viewModel = FireAppViewModel(
            initialSession: authenticatedSession(),
            challengeRecoveryStore: recoveryStore
        )

        let firstTask = Task {
            await viewModel.handleLoginRequiredIfNeeded(
                FireUniFfiError.LoginRequired(details: "您需要登录才能执行此操作。")
            )
        }

        await enteredGate.wait()

        let secondTask = Task {
            await viewModel.handleLoginRequiredIfNeeded(
                FireUniFfiError.LoginRequired(details: "您需要登录才能执行此操作。")
            )
        }

        let secondRecovered = await secondTask.value
        let intermediateCalls = await recoveryStore.recordedCalls()
        XCTAssertTrue(secondRecovered)
        XCTAssertEqual(intermediateCalls, [true])

        await releaseGate.open()

        let firstRecovered = await firstTask.value
        let finalCalls = await recoveryStore.recordedCalls()

        XCTAssertTrue(firstRecovered)
        XCTAssertTrue(viewModel.isPresentingLogin)
        XCTAssertEqual(viewModel.errorMessage, "您需要登录才能执行此操作。")
        XCTAssertFalse(viewModel.session.hasLoginSession)
        XCTAssertEqual(finalCalls, [true])
    }

    @MainActor
    func testNonChallengeErrorDoesNotTriggerRecovery() async {
        let recoveryStore = MockChallengeRecoveryStore(
            result: .success(challengedLoggedOutSession())
        )
        let viewModel = FireAppViewModel(
            initialSession: authenticatedSession(),
            challengeRecoveryStore: recoveryStore
        )

        let recovered = await viewModel.handleCloudflareChallengeIfNeeded(
            FireUniFfiError.Network(details: "offline")
        )

        XCTAssertFalse(recovered)
        XCTAssertFalse(viewModel.isPresentingLogin)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.session.hasLoginSession)
        XCTAssertTrue(viewModel.session.readiness.canReadAuthenticatedApi)
        let calls = await recoveryStore.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testPerformWithCloudflareRecoveryWaitsForInteractiveRecoveryAndRetries() async throws {
        let viewModel = FireAppViewModel(
            initialSession: authenticatedSession(),
            cloudflareRecoveryCookieSync: {
                self.authenticatedSession(turnstileSitekey: "sitekey")
            }
        )
        var attempts = 0

        let task = Task {
            try await viewModel.performWithCloudflareRecovery(operation: "刷新首页话题列表") {
                attempts += 1
                if attempts < 3 {
                    throw FireUniFfiError.CloudflareChallenge
                }
                return "ok"
            }
        }

        let presentedRecovery = await waitUntil {
            if case .cloudflareRecovery? = viewModel.authPresentationState {
                return true
            }
            return false
        }

        XCTAssertTrue(presentedRecovery)
        XCTAssertEqual(attempts, 2)

        viewModel.completeCloudflareRecovery()

        let dismissedRecovery = await waitUntil { viewModel.authPresentationState == nil }
        XCTAssertTrue(dismissedRecovery)
        let result = try await task.value
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(attempts, 3)
    }

    @MainActor
    func testPerformWithCloudflareRecoveryCancellationStopsWaitingTaskFromRetrying() async {
        let viewModel = FireAppViewModel(
            initialSession: authenticatedSession(),
            cloudflareRecoveryCookieSync: {
                self.authenticatedSession(turnstileSitekey: "sitekey")
            }
        )
        var attempts = 0

        let task = Task {
            try await viewModel.performWithCloudflareRecovery(operation: "刷新首页话题列表") {
                attempts += 1
                if attempts < 3 {
                    throw FireUniFfiError.CloudflareChallenge
                }
                return "ok"
            }
        }

        let presentedRecovery = await waitUntil {
            if case .cloudflareRecovery? = viewModel.authPresentationState {
                return true
            }
            return false
        }

        XCTAssertTrue(presentedRecovery)
        XCTAssertEqual(attempts, 2)

        task.cancel()

        let finished = expectation(description: "cancelled recovery task finished")
        var completionError: Error?
        Task { @MainActor in
            do {
                _ = try await task.value
                XCTFail("Expected task cancellation while waiting for Cloudflare recovery")
            } catch {
                completionError = error
            }
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)
        XCTAssertTrue(completionError is CancellationError)
        XCTAssertEqual(attempts, 2)

        viewModel.completeCloudflareRecovery()
        let dismissedRecovery = await waitUntil { viewModel.authPresentationState == nil }
        XCTAssertTrue(dismissedRecovery)
        XCTAssertEqual(attempts, 2)
    }

    @MainActor
    func testLoginWebViewProbeBridgeDebouncesCookieTriggeredProbes() {
        let expectation = expectation(description: "probe requested")
        let webView = WKWebView(frame: .zero)
        var probedWebView: WKWebView?
        var probeCount = 0
        let bridge = FireLoginWebViewProbeBridge { webView in
            probeCount += 1
            probedWebView = webView
            expectation.fulfill()
        }

        bridge.attach(to: webView)
        bridge.cookiesDidChange(in: webView.configuration.websiteDataStore.httpCookieStore)
        bridge.cookiesDidChange(in: webView.configuration.websiteDataStore.httpCookieStore)
        bridge.cookiesDidChange(in: webView.configuration.websiteDataStore.httpCookieStore)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(probeCount, 1)
        XCTAssertTrue(probedWebView === webView)
    }

    @MainActor
    func testLoginWebViewProbeBridgeStopsRequestingProbeAfterDetach() {
        let webView = WKWebView(frame: .zero)
        let expectation = expectation(description: "probe should not fire")
        expectation.isInverted = true
        let bridge = FireLoginWebViewProbeBridge { _ in
            expectation.fulfill()
        }

        bridge.attach(to: webView)
        bridge.detach()
        bridge.cookiesDidChange(in: webView.configuration.websiteDataStore.httpCookieStore)

        wait(for: [expectation], timeout: 0.5)
    }

    private func makeSessionFileURL(name: String) throws -> URL {
        let workspacePath = try FireSessionStore.defaultWorkspacePath()
        let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
        let testsURL = workspaceURL.appendingPathComponent("Tests", isDirectory: true)
        try FileManager.default.createDirectory(at: testsURL, withIntermediateDirectories: true)
        return testsURL.appendingPathComponent("\(name)-\(UUID().uuidString).json", isDirectory: false)
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        return condition()
    }

    private func makePlatformCookie(
        name: String,
        value: String,
        domain: String = "linux.do",
        path: String = "/",
        expiresAtUnixMs: Int64? = nil
    ) -> PlatformCookieState {
        PlatformCookieState(
            name: name,
            value: value,
            domain: domain,
            path: path,
            expiresAtUnixMs: expiresAtUnixMs
        )
    }

    private func makeHTTPCookie(
        name: String,
        value: String,
        domain: String,
        path: String = "/"
    ) -> HTTPCookie? {
        HTTPCookie(properties: [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .originURL: URL(string: "https://linux.do")!,
            .secure: true,
        ])
    }

    private func mirroredSharedCookies() -> [HTTPCookie] {
        let host = "linux.do"
        return (HTTPCookieStorage.shared.cookies ?? [])
            .filter {
                let normalizedDomain = normalizeCookieDomain($0.domain)
                return normalizedDomain == host || normalizedDomain.hasSuffix(".\(host)")
            }
            .sorted {
                if $0.name != $1.name {
                    return $0.name < $1.name
                }
                return $0.domain < $1.domain
            }
    }

    private func clearMirroredCookiesFromSharedStorage() {
        for cookie in mirroredSharedCookies() {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private func mirroredWebKitCookies(_ store: any MirroredCookieStore) async -> [HTTPCookie] {
        let host = "linux.do"
        let cookies = await store.getAllCookies()
        return cookies
            .filter {
                let normalizedDomain = normalizeCookieDomain($0.domain)
                return normalizedDomain == host || normalizedDomain.hasSuffix(".\(host)")
            }
            .sorted {
                if $0.name != $1.name {
                    return $0.name < $1.name
                }
                return $0.domain < $1.domain
            }
    }

    private func clearMirroredCookiesFromWebKitStore(_ store: any MirroredCookieStore) async {
        for cookie in await mirroredWebKitCookies(store) {
            await store.deleteCookie(cookie)
        }
    }

    private func normalizeCookieDomain(_ domain: String) -> String {
        let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix(".") {
            return String(normalized.dropFirst())
        }
        return normalized
    }

    @MainActor
    private final class InMemoryMirroredCookieStore: MirroredCookieStore {
        private var cookies: [HTTPCookie] = []

        func getAllCookies() async -> [HTTPCookie] {
            cookies
        }

        func setCookie(_ cookie: HTTPCookie) async {
            cookies.removeAll {
                $0.name == cookie.name
                    && Self.normalizeDomain($0.domain) == Self.normalizeDomain(cookie.domain)
                    && $0.path == cookie.path
            }
            cookies.append(cookie)
        }

        func deleteCookie(_ cookie: HTTPCookie) async {
            cookies.removeAll {
                $0.name == cookie.name
                    && Self.normalizeDomain($0.domain) == Self.normalizeDomain(cookie.domain)
                    && $0.path == cookie.path
            }
        }

        private static func normalizeDomain(_ domain: String) -> String {
            let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.hasPrefix(".") {
                return String(normalized.dropFirst())
            }
            return normalized
        }
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

    private func bootstrapCapturedSession(username: String) -> SessionState {
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
                sharedSessionKey: "shared",
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
                hasCsrfToken: false,
                hasCurrentUser: true,
                hasPreloadedData: true,
                hasSharedSessionKey: true,
                canReadAuthenticatedApi: true,
                canWriteAuthenticatedApi: false,
                canOpenMessageBus: true
            ),
            loginPhase: .bootstrapCaptured,
            hasLoginSession: true,
            profileDisplayName: username,
            loginPhaseLabel: "会话初始化中"
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
                sharedSessionKey: "shared",
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
                hasCsrfToken: true,
                hasCurrentUser: true,
                hasPreloadedData: true,
                hasSharedSessionKey: true,
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

    private func authenticatedSession(turnstileSitekey: String? = nil) -> SessionState {
        SessionState(
            cookies: CookieState(
                tToken: "token",
                forumSession: "forum",
                cfClearance: "clearance",
                csrfToken: "csrf",
                platformCookies: []
            ),
            bootstrap: BootstrapState(
                baseUrl: "https://linux.do",
                discourseBaseUri: "/",
                sharedSessionKey: "shared",
                currentUsername: "alice",
                currentUserId: 1,
                notificationChannelPosition: 42,
                longPollingBaseUrl: "https://linux.do",
                turnstileSitekey: turnstileSitekey,
                topicTrackingStateMeta: nil,
                preloadedJson: "{}",
                hasPreloadedData: true,
                hasSiteMetadata: true,
                topTags: ["rust"],
                canTagTopics: true,
                categories: [],
                hasSiteSettings: true,
                enabledReactionIds: ["heart"],
                minPostLength: 15,
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
                hasCsrfToken: true,
                hasCurrentUser: true,
                hasPreloadedData: true,
                hasSharedSessionKey: true,
                canReadAuthenticatedApi: true,
                canWriteAuthenticatedApi: true,
                canOpenMessageBus: true
            ),
            loginPhase: .bootstrapCaptured,
            hasLoginSession: true,
            profileDisplayName: "alice",
            loginPhaseLabel: "已登录"
        )
    }

    private func challengedLoggedOutSession() -> SessionState {
        SessionState(
            cookies: CookieState(
                tToken: nil,
                forumSession: nil,
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
                minPostLength: 1,
                minTopicTitleLength: 15,
                minFirstPostLength: 20,
                minPersonalMessageTitleLength: 2,
                minPersonalMessagePostLength: 10,
                defaultComposerCategory: nil
            ),
            readiness: SessionReadinessState(
                hasLoginCookie: false,
                hasForumSession: false,
                hasCloudflareClearance: true,
                hasCsrfToken: false,
                hasCurrentUser: false,
                hasPreloadedData: false,
                hasSharedSessionKey: false,
                canReadAuthenticatedApi: false,
                canWriteAuthenticatedApi: false,
                canOpenMessageBus: false
            ),
            loginPhase: .anonymous,
            hasLoginSession: false,
            profileDisplayName: "未登录",
            loginPhaseLabel: "未登录"
        )
    }

    private func makeAuthenticatedWritePreflightStore() throws -> FireSessionStore {
        try FireSessionStore(
            workspacePath: try FireSessionStore.defaultWorkspacePath(),
            sessionFilePath: makeSessionFileURL(name: "authenticated-write-preflight").path,
            authCookieStore: InMemoryAuthCookieSecureStore()
        )
    }

    private func authenticatedWritePreflightContext(
        sessionEpoch: UInt64,
        authRecoveryHint: AuthRecoveryHintState?
    ) -> FireSessionStore.AuthenticatedWritePreflightContext {
        FireSessionStore.AuthenticatedWritePreflightContext(
            sessionEpoch: sessionEpoch,
            authRecoveryHint: authRecoveryHint
        )
    }

    private func authRecoveryHint(epoch: UInt64) -> AuthRecoveryHintState {
        AuthRecoveryHintState(
            observedEpoch: epoch,
            reason: .forumSessionOnlyRotation
        )
    }

    private func runAuthenticatedWritePreflight(
        store: FireSessionStore,
        harness: AuthenticatedWritePreflightHarness
    ) async throws {
        try await store.runAuthenticatedWritePreflight(
            readContext: {
                await harness.readContext()
            },
            refreshCsrfTokenIfNeeded: {
                try await harness.refreshCsrfTokenIfNeeded()
            },
            applyPlatformCookies: { cookies in
                await harness.applyPlatformCookies(cookies)
            },
            hostResyncProvider: {
                await harness.hostResyncProvider()
            }
        )
    }
}

private actor ColdStartRefreshRecorder {
    struct Snapshot {
        let bootstrapRefreshCount: Int
        let csrfRefreshCount: Int
    }

    private var bootstrapRefreshCount = 0
    private var csrfRefreshCount = 0

    func recordBootstrapRefresh() {
        bootstrapRefreshCount += 1
    }

    func recordCsrfRefresh() {
        csrfRefreshCount += 1
    }

    func snapshot() -> Snapshot {
        Snapshot(
            bootstrapRefreshCount: bootstrapRefreshCount,
            csrfRefreshCount: csrfRefreshCount
        )
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else {
            return
        }

        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }
}

private actor AuthenticatedWritePreflightHarness {
    enum RefreshOutcome {
        case context(FireSessionStore.AuthenticatedWritePreflightContext)
        case error(FireUniFfiError)
    }

    struct Counts {
        let readContextCount: Int
        let refreshCsrfCount: Int
        let hostResyncProviderCount: Int
        let applyPlatformCookiesCount: Int
    }

    private var context: FireSessionStore.AuthenticatedWritePreflightContext
    private var refreshOutcomes: [RefreshOutcome]
    private let hostResyncCookies: [PlatformCookieState]
    private let providerEnteredGate: AsyncGate?
    private let providerReleaseGate: AsyncGate?
    private var nextAppliedContext: FireSessionStore.AuthenticatedWritePreflightContext?
    private var readContextCount = 0
    private var refreshCsrfCount = 0
    private var hostResyncProviderCount = 0
    private var applyPlatformCookiesCount = 0

    init(
        context: FireSessionStore.AuthenticatedWritePreflightContext,
        refreshOutcomes: [RefreshOutcome] = [],
        hostResyncCookies: [PlatformCookieState],
        providerEnteredGate: AsyncGate? = nil,
        providerReleaseGate: AsyncGate? = nil
    ) {
        self.context = context
        self.refreshOutcomes = refreshOutcomes
        self.hostResyncCookies = hostResyncCookies
        self.providerEnteredGate = providerEnteredGate
        self.providerReleaseGate = providerReleaseGate
    }

    func readContext() -> FireSessionStore.AuthenticatedWritePreflightContext {
        readContextCount += 1
        return context
    }

    func refreshCsrfTokenIfNeeded() throws -> FireSessionStore.AuthenticatedWritePreflightContext {
        refreshCsrfCount += 1
        guard !refreshOutcomes.isEmpty else {
            return context
        }

        let outcome = refreshOutcomes.removeFirst()
        switch outcome {
        case let .context(nextContext):
            context = nextContext
            return nextContext
        case let .error(error):
            throw error
        }
    }

    func hostResyncProvider() async -> [PlatformCookieState]? {
        hostResyncProviderCount += 1
        if let providerEnteredGate {
            await providerEnteredGate.open()
        }
        if let providerReleaseGate {
            await providerReleaseGate.wait()
        }
        return hostResyncCookies
    }

    func applyPlatformCookies(
        _ cookies: [PlatformCookieState]
    ) -> FireSessionStore.AuthenticatedWritePreflightContext {
        _ = cookies
        applyPlatformCookiesCount += 1
        if let nextAppliedContext {
            context = nextAppliedContext
            self.nextAppliedContext = nil
        }
        return context
    }

    func setContext(_ context: FireSessionStore.AuthenticatedWritePreflightContext) {
        self.context = context
    }

    func setNextAppliedContext(_ context: FireSessionStore.AuthenticatedWritePreflightContext?) {
        nextAppliedContext = context
    }

    func counts() -> Counts {
        Counts(
            readContextCount: readContextCount,
            refreshCsrfCount: refreshCsrfCount,
            hostResyncProviderCount: hostResyncProviderCount,
            applyPlatformCookiesCount: applyPlatformCookiesCount
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

private actor MockChallengeRecoveryStore: FireChallengeSessionRecovering {
    private var calls: [Bool] = []
    private let result: Result<SessionState, Error>

    init(result: Result<SessionState, Error>) {
        self.result = result
    }

    func logoutLocalAndClearPlatformCookies(preserveCfClearance: Bool) async throws -> SessionState {
        calls.append(preserveCfClearance)
        return try result.get()
    }

    func recordedCalls() -> [Bool] {
        calls
    }
}

private actor BlockingChallengeRecoveryStore: FireChallengeSessionRecovering {
    private let enteredGate: AsyncGate
    private let releaseGate: AsyncGate
    private let result: Result<SessionState, Error>
    private var calls: [Bool] = []

    init(
        enteredGate: AsyncGate,
        releaseGate: AsyncGate,
        result: Result<SessionState, Error>
    ) {
        self.enteredGate = enteredGate
        self.releaseGate = releaseGate
        self.result = result
    }

    func logoutLocalAndClearPlatformCookies(preserveCfClearance: Bool) async throws -> SessionState {
        calls.append(preserveCfClearance)
        await enteredGate.open()
        await releaseGate.wait()
        return try result.get()
    }

    func recordedCalls() -> [Bool] {
        calls
    }
}
