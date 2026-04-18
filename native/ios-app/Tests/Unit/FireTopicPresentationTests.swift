import XCTest
import UIKit
import SwiftUI
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

    func testPrivateMessageArchetypeRequiresPrivateMessageValue() {
        XCTAssertTrue(FireTopicPresentation.isPrivateMessageArchetype("private_message"))
        XCTAssertTrue(FireTopicPresentation.isPrivateMessageArchetype(" Private_Message "))
        XCTAssertFalse(FireTopicPresentation.isPrivateMessageArchetype("regular"))
        XCTAssertFalse(FireTopicPresentation.isPrivateMessageArchetype(nil))
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
                participants: [],
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

    func testTopicDetailSubscriptionTaskIDChangesWhenDetailLoads() {
        let beforeLoad = FireTopicDetailView.topicDetailSubscriptionTaskID(
            topicId: 42,
            canOpenMessageBus: true,
            hasLoadedDetail: false
        )
        let afterLoad = FireTopicDetailView.topicDetailSubscriptionTaskID(
            topicId: 42,
            canOpenMessageBus: true,
            hasLoadedDetail: true
        )

        XCTAssertNotEqual(beforeLoad, afterLoad)
    }

    @MainActor
    func testHomeFeedVisibleTopicSanitizerDropsUnloadedTopicIDs() {
        let sanitized = FireHomeFeedStore.sanitizedVisibleTopicIDs(
            currentTopicIDs: [11, 12, 13],
            candidateVisibleTopicIDs: Set<UInt64>([10, 12, 14])
        )

        XCTAssertEqual(sanitized, Set<UInt64>([12]))
    }

    func testTimelineRowsBuildStableLookupForReplyRows() {
        let detail = FireTopicPresentation.recomposedDetail(
            makeTopicDetail(
                posts: [
                    makePost(postNumber: 1, replyToPostNumber: nil, username: "author"),
                    makePost(postNumber: 2, replyToPostNumber: 1, username: "reply-a"),
                    makePost(postNumber: 3, replyToPostNumber: 2, username: "reply-b"),
                ],
                stream: [1, 2, 3]
            )
        )
        let replyRows = FireTopicPresentation.timelineRows(
            entries: detail.timelineEntries,
            posts: detail.postStream.posts
        ).filter { !$0.entry.isOriginalPost }

        let lookup = Dictionary(uniqueKeysWithValues: replyRows.enumerated().map { ($1.entry.postNumber, $0) })

        XCTAssertEqual(lookup[2], 0)
        XCTAssertEqual(lookup[3], 1)
        XCTAssertEqual(lookup.count, 2)
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
        let topicDetailStore = FireTopicDetailStore(appViewModel: viewModel)
        viewModel.bindTopicDetailStore(topicDetailStore)
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

    func testPrivateMessageDraftRestoreRequiresMatchingExplicitRecipients() {
        XCTAssertTrue(
            shouldRestorePrivateMessageDraft(
                explicitRecipients: [],
                draftRecipients: ["alice"]
            )
        )
        XCTAssertTrue(
            shouldRestorePrivateMessageDraft(
                explicitRecipients: ["Bob", "alice"],
                draftRecipients: ["alice", "bob", "bob"]
            )
        )
        XCTAssertFalse(
            shouldRestorePrivateMessageDraft(
                explicitRecipients: ["bob"],
                draftRecipients: ["alice"]
            )
        )
        XCTAssertFalse(
            shouldRestorePrivateMessageDraft(
                explicitRecipients: ["bob"],
                draftRecipients: []
            )
        )
    }

    @MainActor
    func testPrivateMessagesViewModelIgnoresStaleMailboxResponses() async throws {
        let loader = PrivateMessageMailboxLoader(
            steps: [
                .deferred,
                .success(makePrivateMessageMailboxResponse(topicID: 202, username: "bob"))
            ]
        )
        let viewModel = FirePrivateMessagesViewModel { kind, page in
            try await loader.fetch(kind: kind, page: page)
        }

        let inboxTask = Task {
            await viewModel.refresh()
        }
        while await loader.callCount() < 1 {
            await Task.yield()
        }

        let sentTask = Task {
            await viewModel.selectKind(.privateMessagesSent)
        }
        while await loader.callCount() < 2 {
            await Task.yield()
        }

        await sentTask.value
        XCTAssertEqual(viewModel.selectedKind, .privateMessagesSent)
        XCTAssertEqual(viewModel.rows.map(\.topic.id), [202])

        await loader.resumeDeferredResponse(
            makePrivateMessageMailboxResponse(topicID: 101, username: "alice")
        )
        await inboxTask.value

        XCTAssertEqual(viewModel.selectedKind, .privateMessagesSent)
        XCTAssertEqual(viewModel.rows.map(\.topic.id), [202])
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testPrivateMessagesViewModelClearsRowsWhenMailboxReloadFails() async {
        let loader = PrivateMessageMailboxLoader(
            steps: [
                .success(makePrivateMessageMailboxResponse(topicID: 101, username: "alice")),
                .failure("offline")
            ]
        )
        let viewModel = FirePrivateMessagesViewModel { kind, page in
            try await loader.fetch(kind: kind, page: page)
        }

        await viewModel.refresh()
        XCTAssertEqual(viewModel.rows.map(\.topic.id), [101])

        await viewModel.selectKind(.privateMessagesSent)

        XCTAssertEqual(viewModel.selectedKind, .privateMessagesSent)
        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertTrue(viewModel.users.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "offline")
    }

    @MainActor
    func testPrivateMessagesViewModelStopsWhenNextPageCannotBeResolved() async {
        let loader = PrivateMessageMailboxLoader(
            steps: [
                .success(
                    makePrivateMessageMailboxResponse(
                        topicID: 101,
                        username: "alice",
                        moreTopicsUrl: "/topics/private-messages/alice",
                        nextPage: nil
                    )
                )
            ]
        )
        let viewModel = FirePrivateMessagesViewModel { kind, page in
            try await loader.fetch(kind: kind, page: page)
        }

        await viewModel.refresh()
        await viewModel.loadMoreIfNeeded(currentTopicID: 101)

        let callCount = await loader.callCount()
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(viewModel.rows.map(\.topic.id), [101])
    }

    @MainActor
    func testPrivateMessagesViewModelStopsAfterAppendReturnsNoFreshRows() async {
        let loader = PrivateMessageMailboxLoader(
            steps: [
                .success(
                    makePrivateMessageMailboxResponse(
                        topicID: 101,
                        username: "alice",
                        moreTopicsUrl: "/topics/private-messages/alice?page=2",
                        nextPage: 2
                    )
                ),
                .success(
                    makePrivateMessageMailboxResponse(
                        topicID: 101,
                        username: "alice",
                        moreTopicsUrl: "/topics/private-messages/alice?page=3",
                        nextPage: 3
                    )
                )
            ]
        )
        let viewModel = FirePrivateMessagesViewModel { kind, page in
            try await loader.fetch(kind: kind, page: page)
        }

        await viewModel.refresh()
        await viewModel.loadMoreIfNeeded(currentTopicID: 101)
        await viewModel.loadMoreIfNeeded(currentTopicID: 101)

        let callCount = await loader.callCount()
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(viewModel.rows.map(\.topic.id), [101])
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
            minPersonalMessageTitleLength: 2,
            minPersonalMessagePostLength: 10,
            defaultComposerCategory: nil
        )
    }

    // MARK: - Timeline Entries

    func testRebuildTimelineEntriesFloorOrderWithFullPostSet() {
        let posts = [
            makePost(postNumber: 1, replyToPostNumber: nil, username: "author"),
            makePost(postNumber: 2, replyToPostNumber: 1, username: "reply-a"),
            makePost(postNumber: 3, replyToPostNumber: 2, username: "reply-b"),
            makePost(postNumber: 4, replyToPostNumber: 1, username: "reply-c"),
        ]

        let entries = FireTopicPresentation.rebuildTimelineEntries(from: posts)

        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0].postNumber, 1)
        XCTAssertEqual(entries[0].depth, 0)
        XCTAssertTrue(entries[0].isOriginalPost)
        XCTAssertEqual(entries[1].postNumber, 2)
        XCTAssertEqual(entries[1].depth, 1)
        XCTAssertEqual(entries[2].postNumber, 3)
        XCTAssertEqual(entries[2].depth, 2)
        XCTAssertEqual(entries[3].postNumber, 4)
        XCTAssertEqual(entries[3].depth, 1)
    }

    func testRebuildTimelineEntriesPartialSetFallsBackDepth() {
        // Simulate an anchored load where parent #3 is not loaded.
        let posts = [
            makePost(postNumber: 5, replyToPostNumber: 3, username: "reply-d"),
            makePost(postNumber: 6, replyToPostNumber: 5, username: "reply-e"),
            makePost(postNumber: 7, replyToPostNumber: nil, username: "standalone"),
        ]

        let entries = FireTopicPresentation.rebuildTimelineEntries(from: posts)

        XCTAssertEqual(entries.count, 3)
        // Post 5 replies to 3 (not loaded) — depth falls back to 1.
        XCTAssertEqual(entries[0].depth, 1)
        XCTAssertEqual(entries[0].parentPostNumber, 3)
        // Post 6 replies to 5 (loaded) — depth is 2.
        XCTAssertEqual(entries[1].depth, 2)
        // Post 7 has no parent — depth is 0.
        XCTAssertEqual(entries[2].depth, 0)
    }

    func testTimelineRowsJoinsEntriesWithPosts() {
        let posts = [
            makePost(postNumber: 1, replyToPostNumber: nil, username: "author"),
            makePost(postNumber: 2, replyToPostNumber: 1, username: "reply"),
        ]
        let entries = [
            TopicTimelineEntryState(
                postId: 1, postNumber: 1, parentPostNumber: nil, depth: 0, isOriginalPost: true
            ),
            TopicTimelineEntryState(
                postId: 2, postNumber: 2, parentPostNumber: 1, depth: 1, isOriginalPost: false
            ),
            TopicTimelineEntryState(
                postId: 3, postNumber: 3, parentPostNumber: 2, depth: 2, isOriginalPost: false
            ),
        ]

        let rows = FireTopicPresentation.timelineRows(entries: entries, posts: posts)

        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows[0].isLoaded)
        XCTAssertTrue(rows[1].isLoaded)
        XCTAssertFalse(rows[2].isLoaded) // Post 3 not loaded yet.
        XCTAssertNil(rows[2].post)
    }

    func testRangeBasedMissingPostIDs() {
        let orderedPostIDs: [UInt64] = [10, 20, 30, 40, 50]
        let loadedPostIDs: Set<UInt64> = [10, 30, 50]

        let missing = FireTopicPresentation.missingPostIDs(
            orderedPostIDs: orderedPostIDs,
            in: 1..<4,
            loadedPostIDs: loadedPostIDs,
            excluding: []
        )

        XCTAssertEqual(missing, [20, 40])
    }

    func testRangeBasedMissingPostIDsExcludesExhausted() {
        let orderedPostIDs: [UInt64] = [10, 20, 30, 40, 50]
        let loadedPostIDs: Set<UInt64> = [10, 30, 50]

        let missing = FireTopicPresentation.missingPostIDs(
            orderedPostIDs: orderedPostIDs,
            in: 1..<4,
            loadedPostIDs: loadedPostIDs,
            excluding: [20]
        )

        XCTAssertEqual(missing, [40])
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
            raw: nil,
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
            polls: [],
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
            timelineEntries: [],
            details: TopicDetailMetaState(
                notificationLevel: nil,
                canEdit: false,
                createdBy: nil,
                participants: []
            )
        )
    }

    private func makePrivateMessageMailboxResponse(
        topicID: UInt64,
        username: String,
        moreTopicsUrl: String? = nil,
        nextPage: UInt32? = nil
    ) -> TopicListState {
        let user = TopicUserState(id: topicID, username: username, avatarTemplate: nil)
        let participant = TopicParticipantState(
            userId: topicID,
            username: username,
            name: username.capitalized,
            avatarTemplate: nil
        )
        let topic = TopicSummaryState(
            id: topicID,
            title: "PM \(topicID)",
            slug: "pm-\(topicID)",
            postsCount: 2,
            replyCount: 1,
            views: 10,
            likeCount: 0,
            excerpt: "hello",
            createdAt: "2026-03-28T10:00:00Z",
            lastPostedAt: "2026-03-28T10:05:00Z",
            lastPosterUsername: username,
            categoryId: nil,
            pinned: false,
            visible: true,
            closed: false,
            archived: false,
            tags: [],
            posters: [],
            participants: [participant],
            unseen: false,
            unreadPosts: 0,
            newPosts: 0,
            lastReadPostNumber: nil,
            highestPostNumber: 2,
            bookmarkedPostNumber: nil,
            bookmarkId: nil,
            bookmarkName: nil,
            bookmarkReminderAt: nil,
            bookmarkableType: nil,
            hasAcceptedAnswer: false,
            canHaveAnswer: false
        )
        let row = TopicRowState(
            topic: topic,
            excerptText: "hello",
            originalPosterUsername: username,
            originalPosterAvatarTemplate: nil,
            tagNames: [],
            statusLabels: [],
            isPinned: false,
            isClosed: false,
            isArchived: false,
            hasAcceptedAnswer: false,
            hasUnreadPosts: false,
            createdTimestampUnixMs: 1_711_624_600_000,
            activityTimestampUnixMs: 1_711_624_900_000,
            lastPosterUsername: username
        )

        return TopicListState(
            topics: [topic],
            users: [user],
            rows: [row],
            moreTopicsUrl: moreTopicsUrl,
            nextPage: nextPage
        )
    }
}

final class FireAvatarImagePipelineTests: XCTestCase {
    func testAvatarURLReplacesTemplateSizeAndResolvesRelativePath() {
        let url = fireAvatarURL(
            avatarTemplate: "/user_avatar/linux.do/alice/{size}/1_2.png",
            size: 34,
            scale: 3,
            baseURLString: "https://linux.do"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://linux.do/user_avatar/linux.do/alice/102/1_2.png"
        )
    }

    func testAvatarURLSupportsProtocolRelativePath() {
        let url = fireAvatarURL(
            avatarTemplate: "//cdn.linux.do/user_avatar/linux.do/alice/{size}/1_2.png",
            size: 32,
            scale: 2,
            baseURLString: "https://linux.do"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://cdn.linux.do/user_avatar/linux.do/alice/64/1_2.png"
        )
    }

    func testAvatarPipelineCachesSuccessfulLoadForSynchronousReuse() async throws {
        let counter = FireAvatarImageLoadCounter()
        let cache = FireAvatarImageMemoryCache(countLimit: 8, totalCostLimit: 1_024 * 1_024)
        let pipeline = FireAvatarImagePipeline(memoryCache: cache) { _ in
            counter.increment()
            return try XCTUnwrap(Self.makeTestImageData())
        }
        let request = FireAvatarImageRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/avatar.png"))
        )

        XCTAssertNil(pipeline.cachedImage(for: request))

        _ = try await pipeline.loadImage(for: request)

        XCTAssertEqual(counter.value, 1)
        XCTAssertNotNil(pipeline.cachedImage(for: request))

        _ = try await pipeline.loadImage(for: request)

        XCTAssertEqual(counter.value, 1)
    }

    func testAvatarPipelineCoalescesConcurrentLoadsForSameURL() async throws {
        let counter = FireAvatarImageLoadCounter()
        let cache = FireAvatarImageMemoryCache(countLimit: 8, totalCostLimit: 1_024 * 1_024)
        let pipeline = FireAvatarImagePipeline(memoryCache: cache) { _ in
            counter.increment()
            try await Task.sleep(nanoseconds: 20_000_000)
            return try XCTUnwrap(Self.makeTestImageData())
        }
        let request = FireAvatarImageRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/avatar.png"))
        )

        async let firstImage = pipeline.loadImage(for: request)
        async let secondImage = pipeline.loadImage(for: request)

        _ = try await (firstImage, secondImage)

        XCTAssertEqual(counter.value, 1)
    }

    @MainActor
    func testAvatarViewRendersWarmCachedImageOnInitialRender() throws {
        let size: CGFloat = 40
        let avatarTemplate = "/user_avatar/linux.do/alice/{size}/1_2.png"
        let request = FireAvatarImageRequest(
            url: try XCTUnwrap(
                fireAvatarURL(
                    avatarTemplate: avatarTemplate,
                    size: size,
                    scale: UIScreen.main.scale,
                    baseURLString: "https://linux.do"
                )
            )
        )
        let expectedColor = UIColor(red: 0.04, green: 0.82, blue: 0.99, alpha: 1)

        FireAvatarImageMemoryCache.shared.removeAllObjects()
        addTeardownBlock {
            FireAvatarImageMemoryCache.shared.removeAllObjects()
        }

        let cachedImage = Self.makeSolidTestImage(color: expectedColor, size: CGSize(width: size, height: size))
        FireAvatarImageMemoryCache.shared.insert(cachedImage, for: request.cacheKey)

        let renderedImage = try XCTUnwrap(
            Self.renderAvatarView(
                FireAvatarView(avatarTemplate: avatarTemplate, username: "alice", size: size),
                size: CGSize(width: size, height: size)
            )
        )
        let centerColor = try XCTUnwrap(renderedImage.fireColor(at: CGPoint(x: size / 2, y: size / 2)))

        XCTAssertTrue(centerColor.fireIsApproximatelyEqual(to: expectedColor, tolerance: 0.08))
    }

    private static func makeTestImageData() -> Data? {
        makeSolidTestImage(color: .systemOrange, size: CGSize(width: 4, height: 4)).pngData()
    }

    private static func makeSolidTestImage(color: UIColor, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image
    }

    @MainActor
    private static func renderAvatarView(_ view: FireAvatarView, size: CGSize) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}

private final class FireAvatarImageLoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        storage += 1
    }
}

private extension UIImage {
    func fireColor(at point: CGPoint) -> UIColor? {
        guard let cgImage else {
            return nil
        }

        let pixelX = min(max(Int(point.x * scale), 0), cgImage.width - 1)
        let pixelY = min(max(Int(point.y * scale), 0), cgImage.height - 1)
        guard let pixelImage = cgImage.cropping(to: CGRect(x: pixelX, y: pixelY, width: 1, height: 1)) else {
            return nil
        }

        var pixelData = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixelData,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(pixelImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        return UIColor(
            red: CGFloat(pixelData[0]) / 255,
            green: CGFloat(pixelData[1]) / 255,
            blue: CGFloat(pixelData[2]) / 255,
            alpha: CGFloat(pixelData[3]) / 255
        )
    }
}

private extension UIColor {
    func fireIsApproximatelyEqual(to other: UIColor, tolerance: CGFloat) -> Bool {
        guard let lhs = fireRGBA, let rhs = other.fireRGBA else {
            return false
        }

        return abs(lhs.red - rhs.red) <= tolerance
            && abs(lhs.green - rhs.green) <= tolerance
            && abs(lhs.blue - rhs.blue) <= tolerance
            && abs(lhs.alpha - rhs.alpha) <= tolerance
    }

    private var fireRGBA: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return (red, green, blue, alpha)
    }
}

private actor PrivateMessageMailboxLoader {
    enum Step {
        case deferred
        case success(TopicListState)
        case failure(String)
    }

    private let steps: [Step]
    private var callCountValue = 0
    private var deferredResponses: [CheckedContinuation<TopicListState, Error>] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func fetch(
        kind: TopicListKindState,
        page: UInt32?
    ) async throws -> TopicListState {
        let stepIndex = callCountValue
        callCountValue += 1

        switch steps[stepIndex] {
        case .deferred:
            return try await withCheckedThrowingContinuation { continuation in
                deferredResponses.append(continuation)
            }
        case .success(let response):
            return response
        case .failure(let message):
            throw NSError(
                domain: "FireTests.PrivateMessageMailboxLoader",
                code: stepIndex,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    func callCount() -> Int {
        callCountValue
    }

    func resumeDeferredResponse(_ response: TopicListState) {
        guard !deferredResponses.isEmpty else { return }
        let continuation = deferredResponses.removeFirst()
        continuation.resume(returning: response)
    }
}
