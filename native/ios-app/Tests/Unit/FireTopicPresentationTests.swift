import XCTest
@testable import Fire

final class FireTopicPresentationTests: XCTestCase {
    func testPlainTextNormalizesHTMLContent() {
        let plainText = plainTextFromHtml(rawHtml: "<p>Hello<br>Fire</p><ul><li>Rust</li><li>CI</li></ul>")

        XCTAssertEqual(plainText, "Hello\nFire\n\n Rust\n CI")
    }

    func testSharedTextHelpersProvidePreviewAndMonogram() {
        XCTAssertEqual(
            previewTextFromHtml(rawHtml: "<p>Hello&nbsp;<strong>Fire</strong></p>"),
            "Hello Fire"
        )
        XCTAssertEqual(monogramForUsername(username: "fire native"), "FN")
    }

    func testImageAttachmentsResolveRelativeUploadsAndSkipEmoji() {
        let attachments = FireTopicPresentation.imageAttachments(
            from: """
            <p>Hello</p>
            <img class="emoji" src="/images/emoji/twitter/smile.png">
            <img src="/uploads/default/original/1X/fire.png" alt="fire" width="1200" height="800">
            <img src="https://cdn.example.com/second.jpg">
            """,
            baseURLString: "https://linux.do"
        )

        XCTAssertEqual(attachments.count, 2)
        XCTAssertEqual(
            attachments.map(\.url.absoluteString),
            [
                "https://linux.do/uploads/default/original/1X/fire.png",
                "https://cdn.example.com/second.jpg",
            ]
        )
        XCTAssertEqual(attachments.first?.altText, "fire")
        XCTAssertEqual(Double(attachments.first?.aspectRatio ?? 0), 1.5, accuracy: 0.001)
    }

    func testEnabledReactionOptionsPreserveOrderAndDeduplicateIDs() {
        let options = FireTopicPresentation.enabledReactionOptions(
            from: ["heart", "laughing", "thumbsup", "heart"]
        )

        XCTAssertEqual(options.map(\.id), ["heart", "laughing", "thumbsup"])
        XCTAssertEqual(options[1].symbol, "😆")
        XCTAssertEqual(options[2].label, "赞同")
    }

    func testMinimumReplyLengthFallsBackToOne() {
        XCTAssertEqual(FireTopicPresentation.minimumReplyLength(from: 15), 15)
        XCTAssertEqual(FireTopicPresentation.minimumReplyLength(from: 0), 1)
    }

    func testTopicRowStateCarriesRustStatusLabels() {
        let row = TopicRowState(
            topic: TopicSummaryState(
                id: 42,
                title: "Fire Native",
                slug: "fire-native",
                postsCount: 18,
                replyCount: 17,
                views: 2048,
                likeCount: 32,
                excerpt: "<p>Hello&nbsp;<strong>Fire</strong></p>",
                createdAt: "2026-03-28T10:00:00Z",
                lastPostedAt: "2026-03-28T11:30:00Z",
                lastPosterUsername: nil,
                categoryId: 7,
                pinned: true,
                visible: true,
                closed: false,
                archived: false,
                tags: [TopicTagState(id: nil, name: "rust", slug: nil)],
                posters: [TopicPosterState(userId: 9, description: nil, extras: nil)],
                unseen: false,
                unreadPosts: 3,
                newPosts: 1,
                lastReadPostNumber: nil,
                highestPostNumber: 18,
                bookmarkedPostNumber: nil,
                bookmarkId: nil,
                bookmarkName: nil,
                bookmarkReminderAt: nil,
                bookmarkableType: nil,
                hasAcceptedAnswer: false,
                canHaveAnswer: true
            ),
            excerptText: "Hello Fire",
            originalPosterUsername: "alice",
            originalPosterAvatarTemplate: nil,
            tagNames: ["rust"],
            statusLabels: ["Pinned", "Unread 3", "New 1"],
            isPinned: true,
            isClosed: false,
            isArchived: false,
            hasAcceptedAnswer: false,
            hasUnreadPosts: true,
            createdTimestampUnixMs: 1_711_624_600_000,
            activityTimestampUnixMs: 1_711_630_000_000,
            lastPosterUsername: "alice"
        )

        XCTAssertEqual(row.statusLabels, ["Pinned", "Unread 3", "New 1"])
        XCTAssertTrue(row.isPinned)
        XCTAssertTrue(row.hasUnreadPosts)
        XCTAssertEqual(row.tagNames, ["rust"])
    }

    func testCompactTimestampFormatsUnixMilliseconds() {
        let timestamp = FireTopicPresentation.compactTimestamp(unixMs: 1_711_624_600_000)
        XCTAssertNotNil(timestamp)
    }

    func testTopicThreadFlatPostStateCarriesRustDisplayMetadata() {
        let flatPosts = [
            TopicThreadFlatPostState(
                post: makePost(postNumber: 1, replyToPostNumber: nil, username: "author"),
                depth: 0,
                parentPostNumber: nil,
                showsThreadLine: true,
                isOriginalPost: true
            ),
            TopicThreadFlatPostState(
                post: makePost(postNumber: 2, replyToPostNumber: 1, username: "floor-a"),
                depth: 0,
                parentPostNumber: nil,
                showsThreadLine: true,
                isOriginalPost: false
            ),
            TopicThreadFlatPostState(
                post: makePost(postNumber: 3, replyToPostNumber: 2, username: "nested-a1"),
                depth: 1,
                parentPostNumber: 2,
                showsThreadLine: true,
                isOriginalPost: false
            ),
            TopicThreadFlatPostState(
                post: makePost(postNumber: 4, replyToPostNumber: 3, username: "nested-a2"),
                depth: 2,
                parentPostNumber: 3,
                showsThreadLine: false,
                isOriginalPost: false
            ),
        ]

        XCTAssertEqual(flatPosts.map(\.post.postNumber), [1, 2, 3, 4])
        XCTAssertEqual(flatPosts.map(\.depth), [0, 0, 1, 2])
        XCTAssertEqual(flatPosts[2].parentPostNumber, 2)
        XCTAssertEqual(flatPosts[3].parentPostNumber, 3)
        XCTAssertTrue(flatPosts[0].showsThreadLine)
        XCTAssertFalse(flatPosts[3].showsThreadLine)
        XCTAssertTrue(flatPosts[0].isOriginalPost)
    }

    func testMergeTopicPostsRespectsStreamOrderAndPrefersIncomingValues() {
        let merged = FireTopicPresentation.mergeTopicPosts(
            existing: [
                makePost(postNumber: 3, replyToPostNumber: 2, username: "old-nested"),
                makePost(postNumber: 1, replyToPostNumber: nil, username: "author"),
            ],
            incoming: [
                makePost(postNumber: 2, replyToPostNumber: 1, username: "reply"),
                makePost(postNumber: 3, replyToPostNumber: 2, username: "new-nested"),
            ],
            orderedPostIDs: [1, 2, 3]
        )

        XCTAssertEqual(merged.map(\.postNumber), [1, 2, 3])
        XCTAssertEqual(merged[2].username, "new-nested")
    }

    func testRecomposedDetailRebuildsThreadFromLoadedPosts() {
        let detail = makeTopicDetail(
            posts: [
                makePost(postNumber: 3, replyToPostNumber: 2, username: "nested"),
                makePost(postNumber: 1, replyToPostNumber: nil, username: "author"),
                makePost(postNumber: 2, replyToPostNumber: 1, username: "reply"),
            ],
            stream: [1, 2, 3]
        )

        let recomposed = FireTopicPresentation.recomposedDetail(detail)

        XCTAssertEqual(recomposed.postStream.posts.map(\.postNumber), [1, 2, 3])
        XCTAssertEqual(recomposed.flatPosts.map(\.post.postNumber), [1, 2, 3])
        XCTAssertEqual(recomposed.flatPosts.map(\.depth), [0, 0, 1])
        XCTAssertEqual(recomposed.flatPosts[2].parentPostNumber, 2)
    }

    func testRecomposedDetailRecomputesInteractionCountFromNonHeartReactions() {
        let detail = makeTopicDetail(
            posts: [
                makePost(
                    postNumber: 1,
                    replyToPostNumber: nil,
                    username: "author",
                    reactions: [
                        TopicReactionState(id: "heart", kind: "emoji", count: 4, canUndo: nil),
                        TopicReactionState(id: "clap", kind: "emoji", count: 2, canUndo: nil),
                    ]
                ),
                makePost(
                    postNumber: 2,
                    replyToPostNumber: 1,
                    username: "reply",
                    reactions: [
                        TopicReactionState(id: "TADA", kind: "emoji", count: 1, canUndo: nil),
                    ]
                ),
            ],
            stream: [1, 2]
        )

        let recomposed = FireTopicPresentation.recomposedDetail(detail)

        XCTAssertEqual(recomposed.interactionCount, 12)
    }

    func testLoadedWindowCountStopsAtFirstGap() {
        let loadedWindowCount = FireTopicPresentation.loadedWindowCount(
            orderedPostIDs: [1, 2, 3, 4, 5],
            loadedPosts: [
                makePost(postNumber: 1, replyToPostNumber: nil, username: "author"),
                makePost(postNumber: 5, replyToPostNumber: 4, username: "late-reply"),
            ]
        )

        XCTAssertEqual(loadedWindowCount, 1)
    }

    func testMissingPostIDsSkipsLoadedAndExhaustedHoles() {
        let missingPostIDs = FireTopicPresentation.missingPostIDs(
            orderedPostIDs: [1, 2, 3, 4, 5],
            loadedPostIDs: [1, 5],
            upTo: 5,
            excluding: [2]
        )

        XCTAssertEqual(missingPostIDs, [3, 4])
    }

    func testProfileDisplayNameAvoidsAnonymousCopyWhenAuthenticatedIdentityIsMissing() {
        let session = SessionState(
            cookies: CookieState(
                tToken: "token",
                forumSession: "forum",
                cfClearance: "clearance",
                csrfToken: "csrf",
                platformCookies: []
            ),
            bootstrap: makeBootstrap(
                currentUsername: nil,
                preloadedJson: "{\"site\":{}}",
                hasPreloadedData: true
            ),
            readiness: SessionReadinessState(
                hasLoginCookie: true,
                hasForumSession: true,
                hasCloudflareClearance: true,
                hasCsrfToken: true,
                hasCurrentUser: false,
                hasPreloadedData: true,
                hasSharedSessionKey: true,
                canReadAuthenticatedApi: true,
                canWriteAuthenticatedApi: true,
                canOpenMessageBus: true
            ),
            loginPhase: .cookiesCaptured,
            hasLoginSession: true,
            profileDisplayName: "会话已连接",
            loginPhaseLabel: "账号信息同步中"
        )

        XCTAssertEqual(session.profileDisplayName, "会话已连接")
        XCTAssertEqual(session.profileStatusTitle, "账号信息同步中")
    }

    func testProfileDisplayNamePrefersResolvedUsername() {
        let session = SessionState(
            cookies: CookieState(
                tToken: nil,
                forumSession: nil,
                cfClearance: nil,
                csrfToken: nil,
                platformCookies: []
            ),
            bootstrap: makeBootstrap(
                currentUsername: "alice",
                preloadedJson: nil,
                hasPreloadedData: false
            ),
            readiness: SessionReadinessState(
                hasLoginCookie: false,
                hasForumSession: false,
                hasCloudflareClearance: false,
                hasCsrfToken: false,
                hasCurrentUser: true,
                hasPreloadedData: false,
                hasSharedSessionKey: false,
                canReadAuthenticatedApi: false,
                canWriteAuthenticatedApi: false,
                canOpenMessageBus: false
            ),
            loginPhase: .ready,
            hasLoginSession: true,
            profileDisplayName: "alice",
            loginPhaseLabel: "已就绪"
        )

        XCTAssertEqual(session.profileDisplayName, "alice")
        XCTAssertEqual(session.profileStatusTitle, "已就绪")
    }

    @MainActor
    func testActiveTopicDetailOwnersRetainTopicIDsUntilLastOwnerLeaves() {
        let viewModel = FireAppViewModel()
        let visibleTopicIDs: Set<UInt64> = [1, 2]

        viewModel.beginTopicDetailLifecycle(topicId: 42, ownerToken: "owner-a")
        viewModel.beginTopicDetailLifecycle(topicId: 42, ownerToken: "owner-b")

        XCTAssertEqual(
            viewModel.retainedTopicDetailIDs(visibleTopicIDs: visibleTopicIDs),
            Set<UInt64>([1, 2, 42])
        )

        viewModel.endTopicDetailLifecycle(topicId: 42, ownerToken: "owner-a")
        XCTAssertEqual(
            viewModel.retainedTopicDetailIDs(visibleTopicIDs: visibleTopicIDs),
            Set<UInt64>([1, 2, 42])
        )

        viewModel.endTopicDetailLifecycle(topicId: 42, ownerToken: "owner-b")
        XCTAssertEqual(viewModel.retainedTopicDetailIDs(visibleTopicIDs: visibleTopicIDs), visibleTopicIDs)
    }

    private func makeBootstrap(
        currentUsername: String?,
        preloadedJson: String?,
        hasPreloadedData: Bool
    ) -> BootstrapState {
        BootstrapState(
            baseUrl: "https://linux.do",
            discourseBaseUri: "/",
            sharedSessionKey: "shared-session",
            currentUsername: currentUsername,
            currentUserId: nil,
            notificationChannelPosition: nil,
            longPollingBaseUrl: "https://linux.do",
            turnstileSitekey: nil,
            topicTrackingStateMeta: "{\"message_bus_last_id\":42}",
            preloadedJson: preloadedJson,
            hasPreloadedData: hasPreloadedData,
            hasSiteMetadata: hasPreloadedData,
            topTags: [],
            canTagTopics: false,
            categories: [],
            hasSiteSettings: hasPreloadedData,
            enabledReactionIds: ["heart"],
            minPostLength: 1,
            minTopicTitleLength: 15,
            minFirstPostLength: 20,
            defaultComposerCategory: nil
        )
    }

    private func makePost(
        postNumber: UInt32,
        replyToPostNumber: UInt32?,
        username: String,
        likeCount: UInt32 = 0,
        reactions: [TopicReactionState] = []
    ) -> TopicPostState {
        TopicPostState(
            id: UInt64(postNumber),
            username: username,
            name: nil,
            avatarTemplate: nil,
            cooked: "<p>\(username)</p>",
            postNumber: postNumber,
            postType: 1,
            createdAt: "2026-03-28T10:00:00Z",
            updatedAt: "2026-03-28T10:00:00Z",
            likeCount: likeCount,
            replyCount: 0,
            replyToPostNumber: replyToPostNumber,
            bookmarked: false,
            bookmarkId: nil,
            bookmarkName: nil,
            bookmarkReminderAt: nil,
            reactions: reactions,
            currentUserReaction: nil,
            acceptedAnswer: false,
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
            title: "Fire Native",
            slug: "fire-native",
            postsCount: UInt32(max(stream.count, posts.count)),
            categoryId: 7,
            tags: [],
            views: 128,
            likeCount: 9,
            interactionCount: 9,
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
            thread: TopicThreadState(originalPostNumber: nil, replySections: []),
            flatPosts: [],
            details: TopicDetailMetaState(notificationLevel: nil, canEdit: false, createdBy: nil)
        )
    }
}
