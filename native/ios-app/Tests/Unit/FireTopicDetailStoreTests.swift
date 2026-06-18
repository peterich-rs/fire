import XCTest
@testable import Fire

final class FireTopicDetailStoreTests: XCTestCase {
    func testWindowStateActiveAnchorPrefersPendingScrollTarget() {
        let window = FireTopicDetailWindowState(
            anchorPostNumber: 72,
            requestedRange: 60..<90,
            loadedIndices: IndexSet(integersIn: 60...70),
            pendingScrollTarget: 88
        )

        XCTAssertEqual(window.activeAnchorPostNumber, 88)
    }

    func testClearingTransientAnchorPreservesWindowShape() {
        let window = FireTopicDetailWindowState(
            anchorPostNumber: 88,
            requestedRange: 40..<70,
            loadedIndices: IndexSet(integersIn: 42...50),
            loadedPostNumbers: Set<UInt32>([41, 42, 43]),
            exhaustedPostIDs: Set<UInt64>([9001]),
            pendingScrollTarget: 88
        )

        let cleared = window.clearingTransientAnchor()

        XCTAssertNil(cleared.anchorPostNumber)
        XCTAssertNil(cleared.pendingScrollTarget)
        XCTAssertNil(cleared.activeAnchorPostNumber)
        XCTAssertEqual(cleared.requestedRange, 40..<70)
        XCTAssertEqual(cleared.loadedIndices, IndexSet(integersIn: 42...50))
        XCTAssertEqual(cleared.loadedPostNumbers, Set<UInt32>([41, 42, 43]))
        XCTAssertEqual(cleared.exhaustedPostIDs, Set<UInt64>([9001]))
    }

    func testInitialRequestedRangeCentersOnAnchorAndIncludesLoadedSpan() {
        let range = FireTopicDetailStore.initialRequestedRange(
            totalCount: 120,
            anchorIndex: 60,
            loadedIndices: IndexSet(integersIn: 58...62)
        )

        XCTAssertTrue(range.contains(60))
        XCTAssertLessThanOrEqual(range.lowerBound, 58)
        XCTAssertGreaterThanOrEqual(range.upperBound, 63)
        XCTAssertGreaterThanOrEqual(range.upperBound - range.lowerBound, 30)
    }

    func testInitialRequestedRangeFallsBackToLeadingPageWithoutAnchor() {
        let range = FireTopicDetailStore.initialRequestedRange(
            totalCount: 120,
            anchorIndex: nil,
            loadedIndices: IndexSet()
        )

        XCTAssertEqual(range, 0..<30)
    }

    func testExpandedRequestedRangeGrowsForwardAroundAnchor() {
        let range = FireTopicDetailStore.expandedRequestedRange(
            current: 45..<75,
            totalCount: 200,
            expandBackward: false,
            expandForward: true,
            anchorIndex: 60
        )

        XCTAssertEqual(range, 45..<135)
    }

    func testBoundedRequestedRangeKeepsAnchorInsideWindowCap() {
        let range = FireTopicDetailStore.boundedRequestedRange(
            lowerBound: 0,
            upperBound: 260,
            totalCount: 400,
            anchorIndex: 180
        )

        XCTAssertEqual(range.upperBound - range.lowerBound, FireTopicDetailWindowState.maxWindowSize)
        XCTAssertTrue(range.contains(180))
    }

    func testActiveScrollTargetIsNotExhaustedUntilWholeStreamHasBeenCovered() {
        let window = FireTopicDetailWindowState(
            anchorPostNumber: 88,
            requestedRange: 40..<70,
            loadedIndices: IndexSet(integersIn: 40..<70),
            loadedPostNumbers: Set((40..<70).map(UInt32.init)),
            pendingScrollTarget: 88
        )
        let orderedPostIDs = Array(1...120).map(UInt64.init)
        let loadedPostIDs = Set(orderedPostIDs[40..<70])

        XCTAssertFalse(FireTopicDetailStore.scrollTargetIsExhausted(
            postNumber: 88,
            window: window,
            orderedPostIDs: orderedPostIDs,
            loadedPostIDs: loadedPostIDs
        ))
    }

    func testScrollTargetIsExhaustedAfterWholeStreamCoveredWithoutTarget() {
        let window = FireTopicDetailWindowState(
            anchorPostNumber: 88,
            requestedRange: 0..<5,
            loadedIndices: IndexSet(integersIn: 0..<5),
            loadedPostNumbers: Set<UInt32>([1, 2, 3, 4, 5]),
            pendingScrollTarget: 88
        )
        let orderedPostIDs = Array(1...5).map(UInt64.init)
        let loadedPostIDs = Set(orderedPostIDs)

        XCTAssertTrue(FireTopicDetailStore.scrollTargetIsExhausted(
            postNumber: 88,
            window: window,
            orderedPostIDs: orderedPostIDs,
            loadedPostIDs: loadedPostIDs
        ))
    }

    func testUnresolvedScrollTargetSearchJumpsNearEstimatedPostNumber() {
        let nextRange = FireTopicDetailStore.nextRequestedRangeForUnresolvedTarget(
            postNumber: 500,
            current: 0..<30,
            totalCount: 1_000,
            loadedPostNumbersInCurrentRange: Array(1...30).map(UInt32.init)
        )

        XCTAssertNotNil(nextRange)
        XCTAssertTrue(nextRange?.contains(499) == true)
    }

    func testUnresolvedScrollTargetSearchMovesBackwardWhenWindowIsPastTarget() {
        let nextRange = FireTopicDetailStore.nextRequestedRangeForUnresolvedTarget(
            postNumber: 500,
            current: 480..<510,
            totalCount: 1_000,
            loadedPostNumbersInCurrentRange: Array(700...729).map(UInt32.init)
        )

        XCTAssertEqual(nextRange, 450..<510)
    }

    func testUnresolvedScrollTargetSearchSlidesForwardAtWindowCap() {
        let nextRange = FireTopicDetailStore.nextRequestedRangeForUnresolvedTarget(
            postNumber: 500,
            current: 400..<600,
            totalCount: 1_000,
            loadedPostNumbersInCurrentRange: Array(300...499).map(UInt32.init)
        )

        XCTAssertEqual(nextRange, 430..<630)
    }

    func testRenderStateCoverageRequiresOriginalRowAndAllRenderedPosts() {
        let original = TopicPostState(
            id: 100,
            username: "alice",
            name: nil,
            avatarTemplate: nil,
            authorMetadata: fireEmptyPostAuthorMetadataState(),
            cooked: "<p>Original</p>",
            renderDocument: renderCookedHtml(rawHtml: "<p>Original</p>", baseUrl: "https://linux.do"),
            raw: "Original",
            postNumber: 1,
            postType: 1,
            createdAt: "2026-03-28T10:00:00Z",
            updatedAt: "2026-03-28T10:00:00Z",
            likeCount: 0,
            replyCount: 0,
            replyToPostNumber: nil,
            replyToUser: nil,
            bookmarked: false,
            bookmarkId: nil,
            bookmarkName: nil,
            bookmarkReminderAt: nil,
            reactions: [],
            currentUserReaction: nil,
            boosts: [],
            canBoost: false,
            polls: [],
            acceptedAnswer: false,
            canAcceptAnswer: false,
            canUnacceptAnswer: false,
            canEdit: false,
            canDelete: false,
            canRecover: false,
            hidden: false
        )
        let reply = TopicPostState(
            id: 200,
            username: "bob",
            name: nil,
            avatarTemplate: nil,
            authorMetadata: fireEmptyPostAuthorMetadataState(),
            cooked: "<p>Reply</p>",
            renderDocument: renderCookedHtml(rawHtml: "<p>Reply</p>", baseUrl: "https://linux.do"),
            raw: "Reply",
            postNumber: 2,
            postType: 1,
            createdAt: "2026-03-28T10:01:00Z",
            updatedAt: "2026-03-28T10:01:00Z",
            likeCount: 0,
            replyCount: 0,
            replyToPostNumber: 1,
            replyToUser: nil,
            bookmarked: false,
            bookmarkId: nil,
            bookmarkName: nil,
            bookmarkReminderAt: nil,
            reactions: [],
            currentUserReaction: nil,
            boosts: [],
            canBoost: false,
            polls: [],
            acceptedAnswer: false,
            canAcceptAnswer: false,
            canUnacceptAnswer: false,
            canEdit: false,
            canDelete: false,
            canRecover: false,
            hidden: false
        )
        let rowInputs = [
            FireTopicTimelineRowInput(postID: original.id, postNumber: 1, replyToPostNumber: nil),
            FireTopicTimelineRowInput(postID: reply.id, postNumber: 2, replyToPostNumber: 1),
        ]
        let renderContent = fireRenderContentFixture("<p>text</p>")
        let validState = FireTopicDetailRenderState(
            originalRow: FirePreparedTopicTimelineRow(
                entry: FireTopicTimelineEntry(
                    postId: original.id,
                    postNumber: 1,
                    parentPostNumber: nil,
                    depth: 0,
                    isOriginalPost: true
                )
            ),
            replyRows: [
                FirePreparedTopicTimelineRow(
                    entry: FireTopicTimelineEntry(
                        postId: reply.id,
                        postNumber: 2,
                        parentPostNumber: 1,
                        depth: 1,
                        isOriginalPost: false
                    )
                )
            ],
            contentByPostID: [
                original.id: renderContent,
                reply.id: renderContent,
            ]
        )
        let missingOriginalContent = FireTopicDetailRenderState(
            originalRow: validState.originalRow,
            replyRows: validState.replyRows,
            contentByPostID: [reply.id: renderContent]
        )

        XCTAssertTrue(
            FireTopicDetailStore.renderStateCoversRowInputs(
                validState,
                rowInputs: rowInputs,
                originalPostID: original.id
            )
        )
        XCTAssertFalse(
            FireTopicDetailStore.renderStateCoversRowInputs(
                missingOriginalContent,
                rowInputs: rowInputs,
                originalPostID: original.id
            )
        )
    }

    func testNextSourcePageLoadGateAllowsLoadedIdleTopic() {
        XCTAssertTrue(FireTopicDetailStore.canStartNextTopicSourcePageLoad(
            hasMoreTopicPosts: true,
            isLoadingMoreTopicPosts: false,
            hasPendingPreloadTask: false,
            hasLoadedDetail: true
        ))
        XCTAssertFalse(FireTopicDetailStore.canStartNextTopicSourcePageLoad(
            hasMoreTopicPosts: true,
            isLoadingMoreTopicPosts: true,
            hasPendingPreloadTask: false,
            hasLoadedDetail: true
        ))
        XCTAssertFalse(FireTopicDetailStore.canStartNextTopicSourcePageLoad(
            hasMoreTopicPosts: true,
            isLoadingMoreTopicPosts: false,
            hasPendingPreloadTask: true,
            hasLoadedDetail: true
        ))
        XCTAssertFalse(FireTopicDetailStore.canStartNextTopicSourcePageLoad(
            hasMoreTopicPosts: false,
            isLoadingMoreTopicPosts: false,
            hasPendingPreloadTask: false,
            hasLoadedDetail: true
        ))
    }

    func testCloudflareRecoveryTopicURLUsesCanonicalTopicHTMLRouteWhenSlugIsKnown() {
        let url = FireAppViewModel.cloudflareRecoveryTopicURL(
            baseURL: "https://linux.do",
            topicId: 42,
            topicSlug: "fire-native"
        )

        XCTAssertEqual(url.absoluteString, "https://linux.do/t/fire-native/42")
    }

    func testCloudflareRecoveryTopicURLFallsBackToTopicIDHTMLRouteWithoutSlug() {
        let url = FireAppViewModel.cloudflareRecoveryTopicURL(
            baseURL: "https://linux.do/",
            topicId: 42,
            topicSlug: "   "
        )

        XCTAssertEqual(url.absoluteString, "https://linux.do/t/42")
    }

    func testCloudflareRecoveryTopicListURLUsesLatestHTMLRoute() {
        let url = FireAppViewModel.cloudflareRecoveryTopicListURL(
            baseURL: "https://linux.do/",
            query: TopicListQueryState(
                kind: .latest,
                page: nil,
                topicIds: [],
                order: nil,
                ascending: nil,
                categorySlug: nil,
                categoryId: nil,
                parentCategorySlug: nil,
                tag: nil,
                additionalTags: [],
                matchAllTags: false
            )
        )

        XCTAssertEqual(url.absoluteString, "https://linux.do/latest")
    }

    func testCloudflareRecoveryTopicListURLUsesCategoryHTMLRouteWithPage() {
        let url = FireAppViewModel.cloudflareRecoveryTopicListURL(
            baseURL: "https://linux.do",
            query: TopicListQueryState(
                kind: .new,
                page: 2,
                topicIds: [],
                order: nil,
                ascending: nil,
                categorySlug: "rust",
                categoryId: 99,
                parentCategorySlug: "dev",
                tag: nil,
                additionalTags: [],
                matchAllTags: false
            )
        )

        XCTAssertEqual(url.absoluteString, "https://linux.do/c/dev/rust/99/l/new?page=2")
    }

    func testCloudflareRecoveryTopicListURLUsesTagHTMLRoute() {
        let url = FireAppViewModel.cloudflareRecoveryTopicListURL(
            baseURL: "https://linux.do",
            query: TopicListQueryState(
                kind: .top,
                page: nil,
                topicIds: [],
                order: nil,
                ascending: nil,
                categorySlug: nil,
                categoryId: nil,
                parentCategorySlug: nil,
                tag: "swift",
                additionalTags: [],
                matchAllTags: false
            )
        )

        XCTAssertEqual(url.absoluteString, "https://linux.do/tag/swift/l/top")
    }

    func testCloudflareRecoveryTopicListURLUsesLatestForIncrementalTopicIDs() {
        let url = FireAppViewModel.cloudflareRecoveryTopicListURL(
            baseURL: "https://linux.do",
            query: TopicListQueryState(
                kind: .new,
                page: nil,
                topicIds: [1, 2, 3],
                order: nil,
                ascending: nil,
                categorySlug: nil,
                categoryId: nil,
                parentCategorySlug: nil,
                tag: nil,
                additionalTags: [],
                matchAllTags: false
            )
        )

        XCTAssertEqual(url.absoluteString, "https://linux.do/latest")
    }

    func testCloudflareRecoveryTopicListURLPreservesCategoryTagQuery() {
        let url = FireAppViewModel.cloudflareRecoveryTopicListURL(
            baseURL: "https://linux.do",
            query: TopicListQueryState(
                kind: .latest,
                page: nil,
                topicIds: [],
                order: nil,
                ascending: nil,
                categorySlug: "dev",
                categoryId: 42,
                parentCategorySlug: nil,
                tag: "swift",
                additionalTags: ["rust"],
                matchAllTags: true
            )
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://linux.do/c/dev/42/l/latest?tags%5B%5D=swift&tags%5B%5D=rust&match_all_tags=true"
        )
    }

    func testCloudflareRecoverySnapshotRequiresNewClearance() {
        let initial = FireCloudflareRecoveryCookieSnapshot(
            hasAuthCookies: true,
            authFingerprint: "auth",
            cfClearanceFingerprint: "old"
        )
        let unchanged = FireCloudflareRecoveryCookieSnapshot(
            hasAuthCookies: true,
            authFingerprint: "auth",
            cfClearanceFingerprint: "old"
        )
        let missing = FireCloudflareRecoveryCookieSnapshot(
            hasAuthCookies: true,
            authFingerprint: "auth",
            cfClearanceFingerprint: nil
        )
        let rotated = FireCloudflareRecoveryCookieSnapshot(
            hasAuthCookies: true,
            authFingerprint: "auth",
            cfClearanceFingerprint: "new"
        )

        XCTAssertTrue(initial.hasCloudflareClearance)
        XCTAssertFalse(unchanged.hasNewCloudflareClearance(comparedTo: initial))
        XCTAssertFalse(missing.hasNewCloudflareClearance(comparedTo: initial))
        XCTAssertTrue(rotated.hasNewCloudflareClearance(comparedTo: initial))
    }

    func testCloudflareRecoverySnapshotAcceptsFirstClearanceWhenBaselineHasNone() {
        let initial = FireCloudflareRecoveryCookieSnapshot(
            hasAuthCookies: true,
            authFingerprint: "auth",
            cfClearanceFingerprint: nil
        )
        let current = FireCloudflareRecoveryCookieSnapshot(
            hasAuthCookies: true,
            authFingerprint: "auth",
            cfClearanceFingerprint: "new"
        )

        XCTAssertFalse(initial.hasCloudflareClearance)
        XCTAssertTrue(current.hasNewCloudflareClearance(comparedTo: initial))
    }

    func testHydrateRequestedRangeFillsAnchorWindowBeforeFirstRender() async throws {
        let initialDetail = makeTopicDetail(
            posts: [
                makePost(postNumber: 3, replyToPostNumber: 2, username: "reply-a"),
                makePost(postNumber: 4, replyToPostNumber: 3, username: "reply-b"),
            ],
            stream: [1, 2, 3, 4, 5, 6]
        )
        let window = FireTopicDetailWindowState(
            anchorPostNumber: 4,
            requestedRange: 1..<5,
            loadedIndices: IndexSet(integersIn: 2..<4),
            loadedPostNumbers: [3, 4],
            pendingScrollTarget: 4
        )
        let requestedBatches = RequestedBatchRecorder()

        let hydrated = try await FireTopicDetailStore.hydrateRequestedRange(
            detail: initialDetail,
            window: window
        ) { postIDs in
            await requestedBatches.append(postIDs)
            return [
                self.makePost(postNumber: 2, replyToPostNumber: 1, username: "reply-root"),
                self.makePost(postNumber: 5, replyToPostNumber: 4, username: "reply-c"),
            ]
        }
        let capturedBatches = await requestedBatches.snapshot()

        XCTAssertEqual(capturedBatches, [[2, 5]])
        XCTAssertEqual(
            hydrated.detail.postStream.posts.map(\.postNumber),
            [2, 3, 4, 5]
        )
        XCTAssertTrue(hydrated.exhaustedPostIDs.isEmpty)
    }

    @MainActor
    func testCompleteLoginUsesAtomicFinalizationWithoutEagerCsrfRefresh() async throws {
        let captured = FireCapturedLoginState(
            currentURL: "https://linux.do/",
            username: "alice",
            csrfToken: nil,
            homeHTML: "<html></html>",
            browserUserAgent: "FireTests/1.0",
            cookies: [
                PlatformCookieState(
                    name: "_t",
                    value: "token",
                    domain: "linux.do",
                    path: "/",
                    expiresAtUnixMs: nil,
                    sameSite: nil
                )
            ]
        )
        let store = MockLoginSessionStore(
            finalizationResult: makeSessionState(csrfToken: nil),
            bootstrapResult: makeSessionState(csrfToken: nil),
        )
        let coordinator = FireWebViewLoginCoordinator(loginSessionStore: store)

        let finalState = try await coordinator.completeLogin(captured)
        let calls = await store.callsSnapshot()
        let finalizedCapture = await store.finalizedCaptureSnapshot()

        XCTAssertEqual(
            calls,
            [.finalizeLoginFromWebView]
        )
        XCTAssertEqual(finalizedCapture, captured)
        XCTAssertNil(finalState.cookies.csrfToken)
        XCTAssertFalse(finalState.readiness.hasCsrfToken)
        XCTAssertFalse(finalState.readiness.canWriteAuthenticatedApi)
        XCTAssertTrue(finalState.readiness.canReadAuthenticatedApi)
    }

    @MainActor
    func testAuthoritativePlatformCookieApplySkipsPartialBrowserBatch() async throws {
        let currentState = makeSessionState(csrfToken: "csrf-token")
        let store = MockLoginSessionStore(
            finalizationResult: makeSessionState(csrfToken: nil),
            bootstrapResult: currentState,
            currentSnapshot: currentState
        )
        let coordinator = FireWebViewLoginCoordinator(loginSessionStore: store)

        let state = try await coordinator.applyPlatformCookiesIfAuthoritative([
            PlatformCookieState(
                name: "cf_clearance",
                value: "clearance",
                domain: "linux.do",
                path: "/",
                expiresAtUnixMs: nil,
                sameSite: nil
            )
        ])
        let calls = await store.callsSnapshot()
        let appliedCookies = await store.appliedPlatformCookiesSnapshot()

        XCTAssertEqual(calls, [MockLoginSessionStore.Call.currentSessionSnapshot])
        XCTAssertEqual(state, currentState)
        XCTAssertTrue(appliedCookies.isEmpty)
    }

    @MainActor
    func testCloudflareCompletionUsesChallengeMergePathForPartialBrowserBatch() async throws {
        let finalState = makeSessionState(csrfToken: "csrf-token")
        let store = MockLoginSessionStore(
            finalizationResult: finalState,
            bootstrapResult: finalState
        )
        let coordinator = FireWebViewLoginCoordinator(loginSessionStore: store)
        let cookies = [
            PlatformCookieState(
                name: "cf_clearance",
                value: "fresh-clearance",
                domain: "linux.do",
                path: "/",
                expiresAtUnixMs: nil,
                sameSite: nil
            )
        ]

        let state = try await coordinator.completeCloudflareChallenge(
            cookies: cookies,
            freshCfClearance: "fresh-clearance",
            browserUserAgent: "FireTests/1.0"
        )
        let calls = await store.callsSnapshot()
        let appliedCookies = await store.appliedPlatformCookiesSnapshot()
        let challengeCookies = await store.completedCloudflareChallengeCookiesSnapshot()

        XCTAssertEqual(calls, [.completeCloudflareChallenge])
        XCTAssertEqual(state, finalState)
        XCTAssertTrue(appliedCookies.isEmpty)
        XCTAssertEqual(challengeCookies, cookies)
    }

    @MainActor
    func testCompleteLoginRollsBackPartialSessionWhenBootstrapRefreshChallenges() async throws {
        let captured = FireCapturedLoginState(
            currentURL: "https://linux.do/",
            username: "alice",
            csrfToken: nil,
            homeHTML: "<html></html>",
            browserUserAgent: "FireTests/1.0",
            cookies: []
        )
        let partialState = SessionState(
            cookies: CookieState(
                tToken: "token",
                forumSession: "forum",
                cfClearance: "clearance",
                csrfToken: nil,
                platformCookies: [],
                canonicalCookies: []
            ),
            bootstrap: BootstrapState(
                baseUrl: "https://linux.do",
                discourseBaseUri: "/",
                sharedSessionKey: nil,
                currentUsername: "alice",
                currentUserId: 1,
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
                enabledReactionIds: [],
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
                hasPreloadedData: false,
                hasSharedSessionKey: false,
                canReadAuthenticatedApi: true,
                canWriteAuthenticatedApi: false,
                canOpenMessageBus: false
            ),
            loginPhase: .bootstrapCaptured,
            hasLoginSession: true,
            browserUserAgent: "FireTests/1.0",
            profileDisplayName: "alice",
            loginPhaseLabel: "账号信息同步中"
        )
        let store = MockLoginSessionStore(
            finalizationResult: partialState,
            bootstrapResult: partialState,
            bootstrapError: FireUniFfiError.CloudflareChallenge
        )
        let coordinator = FireWebViewLoginCoordinator(loginSessionStore: store)

        do {
            _ = try await coordinator.completeLogin(captured)
            XCTFail("Expected CloudflareChallenge during bootstrap refresh")
        } catch {
            XCTAssertTrue(error is FireUniFfiError)
        }
        let calls = await store.callsSnapshot()

        XCTAssertEqual(
            calls,
            [
                .finalizeLoginFromWebView,
                .refreshBootstrapIfNeeded,
            ]
        )
    }

    func testReplyContextRowsAppendMissingNestedRepliesWithDepth() {
        let root = makePost(postNumber: 2, replyToPostNumber: 1, username: "root")
        let sibling = makePost(postNumber: 5, replyToPostNumber: 1, username: "sibling")
        let existingRows = [
            TopicTreeRowState(
                postId: root.id,
                postNumber: root.postNumber,
                rootPostNumber: 1,
                parentPostNumber: 1,
                depth: 1,
                preorderIndex: 1,
                hasChildren: false,
                descendantCount: 0,
                siblingIndex: 0,
                isLastSibling: false
            ),
            TopicTreeRowState(
                postId: sibling.id,
                postNumber: sibling.postNumber,
                rootPostNumber: 1,
                parentPostNumber: 1,
                depth: 1,
                preorderIndex: 2,
                hasChildren: false,
                descendantCount: 0,
                siblingIndex: 1,
                isLastSibling: true
            ),
        ]
        let child = makePost(postNumber: 3, replyToPostNumber: 2, username: "child")
        let grandchild = makePost(postNumber: 4, replyToPostNumber: 3, username: "grandchild")

        let merged = FireTopicDetailStore.mergeReplyContextTreeRows(
            existingRows: existingRows,
            bodyPostNumber: 1,
            rootPost: root,
            contextPosts: [grandchild, child]
        )

        XCTAssertEqual(merged.map(\.postNumber), [2, 5, 3, 4])
        XCTAssertEqual(merged.map { $0.depth }, [1, 1, 2, 3] as [UInt16])
        XCTAssertEqual(merged.suffix(2).map { $0.parentPostNumber }, [2, 3] as [UInt32?])
        XCTAssertEqual(merged.suffix(2).map { $0.rootPostNumber }, [1, 1] as [UInt32])
    }

    private func makeTreeRow(
        postNumber: UInt32,
        parentPostNumber: UInt32?,
        depth: UInt16,
        username: String
    ) -> TopicTreeRowState {
        let post = makePost(
            postNumber: postNumber,
            replyToPostNumber: parentPostNumber,
            username: username
        )
        return TopicTreeRowState(
            postId: post.id,
            postNumber: post.postNumber,
            rootPostNumber: 1,
            parentPostNumber: parentPostNumber,
            depth: depth,
            preorderIndex: postNumber - 1,
            hasChildren: false,
            descendantCount: 0,
            siblingIndex: 0,
            isLastSibling: true
        )
    }

    private func makePost(
        postNumber: UInt32,
        replyToPostNumber: UInt32?,
        username: String
    ) -> TopicPostState {
        let cooked = "<p>\(username)</p>"
        return TopicPostState(
            id: UInt64(postNumber),
            username: username,
            name: nil,
            avatarTemplate: nil,
            authorMetadata: fireEmptyPostAuthorMetadataState(),
            cooked: cooked,
            renderDocument: renderCookedHtml(rawHtml: cooked, baseUrl: "https://linux.do"),
            raw: nil,
            postNumber: postNumber,
            postType: 1,
            createdAt: "2026-03-28T10:00:00Z",
            updatedAt: "2026-03-28T10:00:00Z",
            likeCount: 0,
            replyCount: 0,
            replyToPostNumber: replyToPostNumber,
            replyToUser: nil,
            bookmarked: false,
            bookmarkId: nil,
            bookmarkName: nil,
            bookmarkReminderAt: nil,
            reactions: [],
            currentUserReaction: nil,
            boosts: [],
            canBoost: false,
            polls: [],
            acceptedAnswer: false,
            canAcceptAnswer: false,
            canUnacceptAnswer: false,
            canEdit: false,
            canDelete: false,
            canRecover: false,
            hidden: false
        )
    }

    private func makeTopicDetail(
        posts: [TopicPostState],
        stream: [UInt64]
    ) -> TopicDetailState {
        TopicDetailState(
            id: 42,
            messageBusLastId: nil,
            title: "Fire Native",
            slug: "fire-native",
            postsCount: UInt32(max(stream.count, posts.count)),
            replyCount: UInt32(max(max(stream.count, posts.count) - 1, 0)),
            categoryId: 7,
            tags: [],
            views: 128,
            likeCount: 9,
            createdAt: "2026-03-28T10:00:00Z",
            highestPostNumber: UInt32(max(stream.count, posts.count)),
            lastReadPostNumber: nil,
            bookmarks: [],
            bookmarked: false,
            bookmarkId: nil,
            bookmarkName: nil,
            bookmarkReminderAt: nil,
            acceptedAnswer: false,
            hasAcceptedAnswer: false,
            canVote: false,
            voteCount: 0,
            userVoted: false,
            summarizable: false,
            hasCachedSummary: false,
            hasSummary: false,
            archetype: "regular",
            postStream: TopicPostStreamState(posts: posts, stream: stream),
            details: TopicDetailMetaState(
                notificationLevel: nil,
                canEdit: false,
                createdBy: nil,
                participants: []
            )
        )
    }

    private func makeSessionState(csrfToken: String?) -> SessionState {
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
                turnstileSitekey: nil,
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

private actor RequestedBatchRecorder {
    private var batches: [[UInt64]] = []

    func append(_ batch: [UInt64]) {
        batches.append(batch)
    }

    func snapshot() -> [[UInt64]] {
        batches
    }
}

private actor MockLoginSessionStore: FireLoginSessionStoring {
    enum Call: Equatable {
        case currentSessionSnapshot
        case finalizeLoginFromWebView
        case applyPlatformCookies
        case completeCloudflareChallenge
        case syncLoginContext
        case refreshBootstrapIfNeeded
        case refreshCsrfTokenIfNeeded
        case logoutLocal
        case webViewPrimingPayload
        case cookieSweepPlan
        case cookieNuclearResetPlan
        case commitCookieSweepResult
    }

    private let finalizationResult: SessionState
    private let bootstrapResult: SessionState
    private let csrfResult: SessionState
    private let currentSnapshot: SessionState
    private let bootstrapError: Error?
    private let csrfError: Error?
    private var calls: [Call] = []
    private var appliedPlatformCookies: [PlatformCookieState] = []
    private var completedCloudflareChallengeCookies: [PlatformCookieState] = []
    private var finalizedCapture: FireCapturedLoginState?

    init(
        finalizationResult: SessionState,
        bootstrapResult: SessionState,
        csrfResult: SessionState? = nil,
        currentSnapshot: SessionState? = nil,
        bootstrapError: Error? = nil,
        csrfError: Error? = nil
    ) {
        self.finalizationResult = finalizationResult
        self.bootstrapResult = bootstrapResult
        self.csrfResult = csrfResult ?? bootstrapResult
        self.currentSnapshot = currentSnapshot ?? finalizationResult
        self.bootstrapError = bootstrapError
        self.csrfError = csrfError
    }

    func currentSessionSnapshot() async throws -> SessionState {
        calls.append(.currentSessionSnapshot)
        return currentSnapshot
    }

    func restorePersistedSessionIfAvailable() async throws -> SessionState? {
        nil
    }

    func finalizeLoginFromWebView(
        _ captured: FireCapturedLoginState,
        allowLowConfidenceSessionCookies: Bool
    ) async throws -> LoginFinalizationResultState {
        calls.append(.finalizeLoginFromWebView)
        finalizedCapture = captured
        return LoginFinalizationResultState(
            success: true,
            session: finalizationResult,
            tTokenVerified: true,
            fingerprintWaitNeeded: true
        )
    }

    func syncLoginContext(_ captured: FireCapturedLoginState) async throws -> SessionState {
        calls.append(.syncLoginContext)
        return finalizationResult
    }

    func refreshBootstrapIfNeeded() async throws -> SessionState {
        calls.append(.refreshBootstrapIfNeeded)
        if let bootstrapError {
            throw bootstrapError
        }
        return bootstrapResult
    }

    func refreshCsrfTokenIfNeeded() async throws -> SessionState {
        calls.append(.refreshCsrfTokenIfNeeded)
        if let csrfError {
            throw csrfError
        }
        return csrfResult
    }

    func logout() async throws -> SessionState {
        bootstrapResult
    }

    func logoutLocal(preserveCfClearance: Bool) async throws -> SessionState {
        calls.append(.logoutLocal)
        return bootstrapResult
    }

    func applyPlatformCookies(_ cookies: [PlatformCookieState]) async throws -> SessionState {
        calls.append(.applyPlatformCookies)
        appliedPlatformCookies = cookies
        return finalizationResult
    }

    func completeCloudflareChallenge(
        cookies: [PlatformCookieState],
        freshCfClearance: String,
        browserUserAgent: String?
    ) async throws -> SessionState {
        calls.append(.completeCloudflareChallenge)
        completedCloudflareChallengeCookies = cookies
        return finalizationResult
    }

    func webViewPrimingPayload(targetURL: String?) async throws -> [WebViewCookieActionState] {
        calls.append(.webViewPrimingPayload)
        return []
    }

    func cookieSweepPlan(
        targetURL: String?,
        name: String,
        webViewCookies: [WebViewCookieInfoState]
    ) async throws -> CookieSweepPlanState {
        calls.append(.cookieSweepPlan)
        return CookieSweepPlanState(
            name: name,
            intent: .ensureUnique,
            actions: [],
            selectedWinner: nil
        )
    }

    func cookieNuclearResetPlan(
        targetURL: String?,
        webViewCookies: [WebViewCookieInfoState]
    ) async throws -> NuclearResetPlanState {
        calls.append(.cookieNuclearResetPlan)
        return NuclearResetPlanState(actions: [])
    }

    func commitCookieSweepResult(
        targetURL: String?,
        name: String,
        intent: CookieSweepIntentState,
        webViewCookies: [WebViewCookieInfoState]
    ) async throws -> SessionState {
        calls.append(.commitCookieSweepResult)
        return finalizationResult
    }

    func callsSnapshot() -> [Call] {
        calls
    }

    func appliedPlatformCookiesSnapshot() -> [PlatformCookieState] {
        appliedPlatformCookies
    }

    func completedCloudflareChallengeCookiesSnapshot() -> [PlatformCookieState] {
        completedCloudflareChallengeCookies
    }

    func finalizedCaptureSnapshot() -> FireCapturedLoginState? {
        finalizedCapture
    }
}
