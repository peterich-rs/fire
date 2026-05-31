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

    func testLoadedResponsePageAppliesOnlyToCurrentCursor() {
        let cursor = TopicResponseCursorState(
            topicId: 42,
            sessionId: 7,
            nextRootOffset: 10,
            nextBranchOffset: 0,
            pageSize: 10,
            rowPageSize: 40
        )

        XCTAssertTrue(
            FireTopicDetailStore.shouldApplyLoadedResponsePage(
                expectedCursor: cursor,
                currentCursor: cursor
            )
        )
        XCTAssertFalse(
            FireTopicDetailStore.shouldApplyLoadedResponsePage(
                expectedCursor: cursor,
                currentCursor: nil
            )
        )
        XCTAssertFalse(
            FireTopicDetailStore.shouldApplyLoadedResponsePage(
                expectedCursor: cursor,
                currentCursor: TopicResponseCursorState(
                    topicId: 42,
                    sessionId: 8,
                    nextRootOffset: 0,
                    nextBranchOffset: 0,
                    pageSize: 10,
                    rowPageSize: 40
                )
            )
        )
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

    func testResponsePagePrefetchUsesRenderedResponseTailInsteadOfMaxPostNumber() {
        let loadedPostNumbers: [UInt32] = [1, 100] + Array(UInt32(2)...UInt32(20))

        XCTAssertTrue(
            FireTopicDetailStore.shouldPrefetchNextTopicResponsePage(
                visiblePostNumbers: [20],
                loadedResponsePostNumbers: loadedPostNumbers
            )
        )
        XCTAssertFalse(
            FireTopicDetailStore.shouldPrefetchNextTopicResponsePage(
                visiblePostNumbers: [100],
                loadedResponsePostNumbers: loadedPostNumbers
            )
        )
    }

    func testAppendableTopicResponseRowsFiltersPureOverlap() {
        let existingRows = [
            makeResponseRow(postNumber: 2, parentPostNumber: 1, depth: 1, username: "reply-a"),
            makeResponseRow(postNumber: 3, parentPostNumber: 2, depth: 2, username: "reply-b")
        ]
        let incomingRows = [
            existingRows[1],
            makeResponseRow(postNumber: 4, parentPostNumber: 1, depth: 1, username: "reply-c")
        ]
        let existingPosts = FireTopicPresentation.topicPostsByID(existingRows.map(\.post))

        let appendableRows = FireTopicDetailStore.appendableTopicResponseRows(
            existingRows: existingRows,
            incomingRows: incomingRows,
            existingPostsByID: existingPosts
        )

        XCTAssertEqual(appendableRows?.map { $0.post.postNumber }, [4])
    }

    func testAppendableTopicResponseRowsRejectsChangedOverlap() {
        let existingRows = [
            makeResponseRow(postNumber: 2, parentPostNumber: 1, depth: 1, username: "reply-a")
        ]
        let incomingRows = [
            makeResponseRow(postNumber: 2, parentPostNumber: 1, depth: 1, username: "reply-updated"),
            makeResponseRow(postNumber: 3, parentPostNumber: 1, depth: 1, username: "reply-b")
        ]
        let existingPosts = FireTopicPresentation.topicPostsByID(existingRows.map(\.post))

        let appendableRows = FireTopicDetailStore.appendableTopicResponseRows(
            existingRows: existingRows,
            incomingRows: incomingRows,
            existingPostsByID: existingPosts
        )

        XCTAssertNil(appendableRows)
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
        var requestedBatches: [[UInt64]] = []

        let hydrated = try await FireTopicDetailStore.hydrateRequestedRange(
            detail: initialDetail,
            window: window
        ) { postIDs in
            requestedBatches.append(postIDs)
            return [
                self.makePost(postNumber: 2, replyToPostNumber: 1, username: "reply-root"),
                self.makePost(postNumber: 5, replyToPostNumber: 4, username: "reply-c"),
            ]
        }

        XCTAssertEqual(requestedBatches, [[2, 5]])
        XCTAssertEqual(
            hydrated.detail.postStream.posts.map(\.postNumber),
            [2, 3, 4, 5]
        )
        XCTAssertTrue(hydrated.exhaustedPostIDs.isEmpty)
    }

    @MainActor
    func testCompleteLoginSyncsCookiesAndBootstrapWithoutEagerCsrfRefresh() async throws {
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
                    expiresAtUnixMs: nil
                )
            ]
        )
        let store = MockLoginSessionStore(
            syncResult: makeSessionState(csrfToken: nil),
            bootstrapResult: makeSessionState(csrfToken: nil),
            csrfResult: makeSessionState(csrfToken: "csrf-token")
        )
        let coordinator = FireWebViewLoginCoordinator(loginSessionStore: store)

        let finalState = try await coordinator.completeLogin(captured)
        let calls = await store.callsSnapshot()
        let appliedCookies = await store.appliedPlatformCookiesSnapshot()

        XCTAssertEqual(
            calls,
            [.applyPlatformCookies, .syncLoginContext, .refreshBootstrapIfNeeded]
        )
        XCTAssertEqual(appliedCookies, captured.cookies)
        XCTAssertNil(finalState.cookies.csrfToken)
        XCTAssertFalse(finalState.readiness.hasCsrfToken)
        XCTAssertFalse(finalState.readiness.canWriteAuthenticatedApi)
        XCTAssertTrue(finalState.readiness.canReadAuthenticatedApi)
    }

    @MainActor
    func testCompleteLoginSkipsCsrfRefreshChallengeAfterBootstrapSucceeds() async throws {
        let captured = FireCapturedLoginState(
            currentURL: "https://linux.do/",
            username: "alice",
            csrfToken: nil,
            homeHTML: "<html></html>",
            browserUserAgent: "FireTests/1.0",
            cookies: []
        )
        let store = MockLoginSessionStore(
            syncResult: makeSessionState(csrfToken: nil),
            bootstrapResult: makeSessionState(csrfToken: nil),
            csrfError: FireUniFfiError.CloudflareChallenge
        )
        let coordinator = FireWebViewLoginCoordinator(loginSessionStore: store)

        let finalState = try await coordinator.completeLogin(captured)
        let calls = await store.callsSnapshot()

        XCTAssertEqual(
            calls,
            [
                .applyPlatformCookies,
                .syncLoginContext,
                .refreshBootstrapIfNeeded,
            ]
        )
        XCTAssertNil(finalState.cookies.csrfToken)
    }

    func testReplyContextRowsAppendMissingNestedRepliesWithDepth() {
        let root = makePost(postNumber: 2, replyToPostNumber: 1, username: "root")
        let sibling = makePost(postNumber: 5, replyToPostNumber: 1, username: "sibling")
        let existingRows = [
            TopicResponseRowState(
                post: root,
                rootPostNumber: 1,
                parentPostNumber: 1,
                depth: 1,
                preorderIndex: 1,
                hasChildren: false,
                descendantCount: 0,
                siblingIndex: 0,
                isLastSibling: false
            ),
            TopicResponseRowState(
                post: sibling,
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

        let merged = FireTopicDetailStore.mergeReplyContextResponseRows(
            existingRows: existingRows,
            bodyPostNumber: 1,
            rootPost: root,
            contextPosts: [grandchild, child]
        )

        XCTAssertEqual(merged.map { $0.post.postNumber }, [2, 5, 3, 4])
        XCTAssertEqual(merged.map(\.depth), [1, 1, 2, 3] as [UInt16])
        XCTAssertEqual(merged.suffix(2).map(\.parentPostNumber), [2, 3] as [UInt32?])
        XCTAssertEqual(merged.suffix(2).map(\.rootPostNumber), [1, 1] as [UInt32])
    }

    private func makeResponseRow(
        postNumber: UInt32,
        parentPostNumber: UInt32?,
        depth: UInt16,
        username: String
    ) -> TopicResponseRowState {
        TopicResponseRowState(
            post: makePost(
                postNumber: postNumber,
                replyToPostNumber: parentPostNumber,
                username: username
            ),
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
        TopicPostState(
            id: UInt64(postNumber),
            username: username,
            name: nil,
            avatarTemplate: nil,
            cooked: "<p>\(username)</p>",
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
            categoryId: 7,
            tags: [],
            views: 128,
            likeCount: 9,
            createdAt: "2026-03-28T10:00:00Z",
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
                platformCookies: []
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

private actor MockLoginSessionStore: FireLoginSessionStoring {
    enum Call: Equatable {
        case applyPlatformCookies
        case syncLoginContext
        case refreshBootstrapIfNeeded
        case refreshCsrfTokenIfNeeded
        case logoutLocal
    }

    private let syncResult: SessionState
    private let bootstrapResult: SessionState
    private let csrfResult: SessionState
    private let csrfError: Error?
    private var calls: [Call] = []
    private var appliedPlatformCookies: [PlatformCookieState] = []

    init(
        syncResult: SessionState,
        bootstrapResult: SessionState,
        csrfResult: SessionState? = nil,
        csrfError: Error? = nil
    ) {
        self.syncResult = syncResult
        self.bootstrapResult = bootstrapResult
        self.csrfResult = csrfResult ?? bootstrapResult
        self.csrfError = csrfError
    }

    func restorePersistedSessionIfAvailable() async throws -> SessionState? {
        nil
    }

    func syncLoginContext(_ captured: FireCapturedLoginState) async throws -> SessionState {
        calls.append(.syncLoginContext)
        return syncResult
    }

    func refreshBootstrapIfNeeded() async throws -> SessionState {
        calls.append(.refreshBootstrapIfNeeded)
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
        return syncResult
    }

    func callsSnapshot() -> [Call] {
        calls
    }

    func appliedPlatformCookiesSnapshot() -> [PlatformCookieState] {
        appliedPlatformCookies
    }
}
