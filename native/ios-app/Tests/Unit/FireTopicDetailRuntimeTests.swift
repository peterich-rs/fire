import XCTest
@testable import Fire

final class FireTopicDetailRuntimeTests: XCTestCase {
    func testSnapshotKeepsStableReplyItemsAndScrollLookup() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let firstReply = makePost(id: 200, postNumber: 2, username: "bob", replyToPostNumber: 1)
        let secondReply = makePost(id: 300, postNumber: 3, username: "carol", replyToPostNumber: 2)
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [
                makeTimelineRow(post: firstReply, parentPostNumber: 1, depth: 1),
                makeTimelineRow(post: secondReply, parentPostNumber: 2, depth: 2),
            ],
            contentByPostID: [
                original.id: makeRenderContent("Original"),
                firstReply.id: makeRenderContent("First reply"),
                secondReply.id: makeRenderContent("Second reply"),
            ]
        )
        let detail = makeTopicDetail(posts: [original, firstReply, secondReply])
        let configuration = makeConfiguration(
            detail: detail,
            renderState: renderState,
            postLookup: [original.id: original, firstReply.id: firstReply, secondReply.id: secondReply]
        )

        let snapshot = configuration.makeSnapshot()

        XCTAssertEqual(snapshot.items.map(\.id), [
            "header:42",
            "original:42",
            "stats:42",
            "replies-header:42",
            "reply:200:2",
            "reply:300:3",
        ])
        XCTAssertEqual(snapshot.replyIndexByPostID, [firstReply.id: 0, secondReply.id: 1])
        XCTAssertEqual(configuration.scrollItem(for: 3)?.id, "reply:300:3")
        XCTAssertNil(configuration.scrollItem(for: 404))
    }

    func testSnapshotShowsEmptyFooterForLoadedTopicWithoutReplies() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [],
            contentByPostID: [original.id: makeRenderContent("Original")]
        )
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: [original]),
            renderState: renderState,
            postLookup: [original.id: original]
        )

        let snapshot = configuration.makeSnapshot()

        XCTAssertEqual(snapshot.items.last?.kind, .replyFooter)
        XCTAssertEqual(snapshot.items.last?.id, "reply-footer:42")
    }

    func testImageRequestBuilderUsesSharedAvatarResolution() {
        let request = FireTopicImageRequestBuilder.avatarRequest(
            avatarTemplate: "/user_avatar/linux.do/alice/{size}/1_2.png",
            username: "alice",
            depth: 0,
            baseURLString: "https://linux.do"
        )
        let expectedPixelSize = Int(FirePostCellLayoutCalculator.avatarSizeRoot * UIScreen.main.scale)

        XCTAssertEqual(
            request?.url.absoluteString,
            "https://linux.do/user_avatar/linux.do/alice/\(expectedPixelSize)/1_2.png"
        )
    }

    func testFeedSnapshotBridgeSynthesizesTopicScreen() throws {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let reply = makePost(id: 200, postNumber: 2, username: "bob", replyToPostNumber: 1)
        let row = TopicResponseRowState(
            post: reply,
            rootPostNumber: 1,
            parentPostNumber: 1,
            depth: 1,
            preorderIndex: 1,
            hasChildren: false,
            descendantCount: 0,
            siblingIndex: 0,
            isLastSibling: true
        )
        let cursor = TopicDetailCursorState(nextResponseCursor: nil, loadedRanges: [], hasMore: false)
        let snapshot = TopicDetailFeedSnapshotState(
            topicId: 42,
            revision: 7,
            items: [
                TopicDetailFeedItemState(
                    itemId: "topic-header:42",
                    kind: .header,
                    ordinal: 0,
                    postId: nil,
                    contentRevision: "header",
                    header: makeHeader(replyCount: 1),
                    post: nil,
                    responseRow: nil,
                    title: nil,
                    message: nil,
                    retryable: false
                ),
                TopicDetailFeedItemState(
                    itemId: "post:100:original",
                    kind: .originalPost,
                    ordinal: 1,
                    postId: original.id,
                    contentRevision: "original",
                    header: nil,
                    post: original,
                    responseRow: nil,
                    title: nil,
                    message: nil,
                    retryable: false
                ),
                TopicDetailFeedItemState(
                    itemId: "post:200:reply",
                    kind: .reply,
                    ordinal: 2,
                    postId: reply.id,
                    contentRevision: "reply",
                    header: nil,
                    post: reply,
                    responseRow: row,
                    title: nil,
                    message: nil,
                    retryable: false
                ),
            ],
            cursor: cursor,
            source: .network,
            loadState: .ready,
            staleErrorMessage: nil,
            updatedAtMs: 1
        )

        let screen = try FireTopicDetailStore.topicScreen(from: snapshot)

        XCTAssertEqual(screen.header.topicId, 42)
        XCTAssertEqual(screen.body.post.id, original.id)
        XCTAssertEqual(screen.response.rows.map(\.post.id), [reply.id])
        XCTAssertNil(screen.response.nextCursor)
    }

    private func makeConfiguration(
        detail: TopicDetailState?,
        renderState: FireTopicDetailRenderState?,
        postLookup: [UInt64: TopicPostState],
        hasMoreTopicPosts: Bool = false,
        isLoadingMoreTopicPosts: Bool = false
    ) -> FireTopicDetailRuntimeConfiguration {
        FireTopicDetailRuntimeConfiguration(
            row: makeTopicRow(),
            baseURLString: "https://linux.do",
            detail: detail,
            renderState: renderState,
            pendingScrollTarget: nil,
            detailError: nil,
            hasMoreTopicPosts: hasMoreTopicPosts,
            isLoadingTopic: false,
            isLoadingMoreTopicPosts: isLoadingMoreTopicPosts,
            topicAiSummary: nil,
            isLoadingTopicAiSummary: false,
            topicAiSummaryError: nil,
            topicCollectionRevision: 1,
            canWriteInteractions: true,
            postLookup: postLookup,
            isMutatingPost: { _ in false },
            onVisiblePostNumbersChanged: { _ in },
            onRefresh: {},
            onLoadTopicDetail: {},
            onScrollTargetHandled: { _ in },
            onPreloadTopicPosts: { _ in },
            onLoadMoreTopicPosts: {},
            onReloadTopicAiSummary: {},
            onOpenComposer: { _ in },
            onOpenPostNumber: { _ in },
            onOpenPostReplies: { _ in },
            onLinkTapped: { _ in },
            onOpenImage: { _ in },
            onToggleLike: { _ in },
            onSelectReaction: { _, _ in },
            onEditPost: { _ in },
            onBookmarkPost: { _ in },
            onDeletePost: { _ in },
            onRecoverPost: { _ in },
            onFlagPost: { _ in },
            onVotePoll: { _, _, _ in },
            onUnvotePoll: { _, _ in },
            onToggleTopicVote: {},
            onShowTopicVoters: {}
        )
    }

    private func makeTopicRow() -> TopicRowState {
        TopicRowState(
            topic: TopicSummaryState(
                id: 42,
                title: "Fire Native",
                slug: "fire-native",
                postsCount: 3,
                replyCount: 2,
                views: 128,
                likeCount: 9,
                excerpt: nil,
                createdAt: "2026-03-28T10:00:00Z",
                lastPostedAt: "2026-03-28T10:10:00Z",
                lastPosterUsername: nil,
                categoryId: 7,
                pinned: false,
                visible: true,
                closed: false,
                archived: false,
                tags: [],
                posters: [],
                participants: [],
                unseen: false,
                unreadPosts: 0,
                newPosts: 0,
                lastReadPostNumber: nil,
                highestPostNumber: 3,
                bookmarkedPostNumber: nil,
                bookmarkId: nil,
                bookmarkName: nil,
                bookmarkReminderAt: nil,
                bookmarkableType: nil,
                hasAcceptedAnswer: false,
                canHaveAnswer: false
            ),
            excerptText: nil,
            originalPosterUsername: "alice",
            originalPosterAvatarTemplate: nil,
            tagNames: [],
            statusLabels: [],
            isPinned: false,
            isClosed: false,
            isArchived: false,
            hasAcceptedAnswer: false,
            hasUnreadPosts: false,
            createdTimestampUnixMs: nil,
            activityTimestampUnixMs: nil,
            lastPosterUsername: nil
        )
    }

    private func makeTopicDetail(posts: [TopicPostState]) -> TopicDetailState {
        TopicDetailState(
            id: 42,
            messageBusLastId: nil,
            title: "Fire Native",
            slug: "fire-native",
            postsCount: UInt32(posts.count),
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
            postStream: TopicPostStreamState(posts: posts, stream: posts.map(\.id)),
            details: TopicDetailMetaState(notificationLevel: nil, canEdit: false, createdBy: nil, participants: [])
        )
    }

    private func makeHeader(replyCount: UInt32) -> TopicHeaderState {
        TopicHeaderState(
            topicId: 42,
            messageBusLastId: nil,
            title: "Fire Native",
            slug: "fire-native",
            postsCount: replyCount + 1,
            replyCount: replyCount,
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
            details: TopicDetailMetaState(notificationLevel: nil, canEdit: false, createdBy: nil, participants: [])
        )
    }

    private func makePost(
        id: UInt64,
        postNumber: UInt32,
        username: String,
        replyToPostNumber: UInt32? = nil
    ) -> TopicPostState {
        TopicPostState(
            id: id,
            username: username,
            name: nil,
            avatarTemplate: nil,
            cooked: "<p>\(username)</p>",
            raw: username,
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

    private func makeTimelineRow(
        post: TopicPostState,
        parentPostNumber: UInt32? = nil,
        depth: UInt32,
        isOriginalPost: Bool = false
    ) -> FirePreparedTopicTimelineRow {
        FirePreparedTopicTimelineRow(
            entry: FireTopicTimelineEntry(
                postId: post.id,
                postNumber: post.postNumber,
                parentPostNumber: parentPostNumber,
                depth: depth,
                isOriginalPost: isOriginalPost
            )
        )
    }

    private func makeRenderContent(_ plainText: String) -> FireTopicPostRenderContent {
        FireTopicPostRenderContent(plainText: plainText, attributedText: nil, imageAttachments: [])
    }
}
