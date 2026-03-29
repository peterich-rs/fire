import XCTest
@testable import Fire

final class FireTopicPresentationTests: XCTestCase {
    func testParseCategoriesReadsSiteCategories() {
        let categories = FireTopicPresentation.parseCategories(
            from: """
            {
              "site": {
                "categories": [
                  {
                    "id": 7,
                    "name": "Rust",
                    "slug": "rust",
                    "parent_category_id": 2,
                    "color": "FFFFFF",
                    "text_color": "000000"
                  }
                ]
              }
            }
            """
        )

        XCTAssertEqual(categories[7]?.name, "Rust")
        XCTAssertEqual(categories[7]?.slug, "rust")
        XCTAssertEqual(categories[7]?.parentCategoryID, 2)
        XCTAssertEqual(categories[7]?.colorHex, "FFFFFF")
        XCTAssertEqual(categories[7]?.textColorHex, "000000")
    }

    func testNextPageReadsRelativeAndAbsoluteMoreTopicsURLs() {
        XCTAssertEqual(FireTopicPresentation.nextPage(from: "/latest?page=3"), 3)
        XCTAssertEqual(FireTopicPresentation.nextPage(from: "https://linux.do/latest?page=9"), 9)
        XCTAssertNil(FireTopicPresentation.nextPage(from: "/latest"))
        XCTAssertNil(FireTopicPresentation.nextPage(from: nil))
    }

    func testPlainTextNormalizesHTMLContent() {
        let plainText = FireTopicPresentation.plainText(
            from: "<p>Hello<br>Fire</p><ul><li>Rust</li><li>CI</li></ul>"
        )

        XCTAssertEqual(plainText, "Hello\nFire\n\n Rust\n CI")
    }

    func testBuildRowPresentationsPrecomputesListRenderingFields() throws {
        let topic = TopicSummaryState(
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
            hasAcceptedAnswer: false,
            canHaveAnswer: true
        )

        let row = try XCTUnwrap(FireTopicPresentation.buildRowPresentations(from: [topic]).first)

        XCTAssertEqual(row.excerptText, "Hello Fire")
        XCTAssertEqual(row.lastPosterUsername, "User 9")
        XCTAssertEqual(row.statusLabels, ["Pinned", "Unread 3", "New 1"])
        XCTAssertEqual(row.tagSummaryText, "#rust")
        XCTAssertNotNil(row.activityTimestampText)
    }

    func testBuildThreadPresentationGroupsNestedRepliesUnderTopLevelFloors() {
        let thread = FireTopicPresentation.buildThreadPresentation(
            from: [
                makePost(postNumber: 1, replyToPostNumber: nil, username: "author"),
                makePost(postNumber: 2, replyToPostNumber: 1, username: "floor-a"),
                makePost(postNumber: 3, replyToPostNumber: 2, username: "nested-a1"),
                makePost(postNumber: 4, replyToPostNumber: 3, username: "nested-a2"),
                makePost(postNumber: 5, replyToPostNumber: 1, username: "floor-b"),
                makePost(postNumber: 6, replyToPostNumber: 99, username: "orphan"),
            ]
        )

        XCTAssertEqual(thread.originalPost?.postNumber, 1)
        XCTAssertEqual(thread.replySections.map(\.anchorPost.postNumber), [2, 5, 6])
        XCTAssertEqual(thread.replySections[0].replies.map(\.post.postNumber), [3, 4])
        XCTAssertEqual(thread.replySections[0].replies.map(\.depth), [1, 2])
        XCTAssertEqual(thread.replySections[1].replies.count, 0)
        XCTAssertEqual(thread.replySections[2].replies.count, 0)
    }

    func testProfileDisplayNameAvoidsAnonymousCopyWhenAuthenticatedIdentityIsMissing() {
        let session = SessionState(
            cookies: CookieState(
                tToken: "token",
                forumSession: "forum",
                cfClearance: "clearance",
                csrfToken: "csrf"
            ),
            bootstrap: BootstrapState(
                baseUrl: "https://linux.do",
                discourseBaseUri: "/",
                sharedSessionKey: "shared-session",
                currentUsername: nil,
                longPollingBaseUrl: "https://linux.do",
                turnstileSitekey: nil,
                topicTrackingStateMeta: "{\"message_bus_last_id\":42}",
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
            hasLoginSession: true
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
                csrfToken: nil
            ),
            bootstrap: BootstrapState(
                baseUrl: "https://linux.do",
                discourseBaseUri: nil,
                sharedSessionKey: nil,
                currentUsername: "alice",
                longPollingBaseUrl: nil,
                turnstileSitekey: nil,
                topicTrackingStateMeta: nil,
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
            hasLoginSession: true
        )

        XCTAssertEqual(session.profileDisplayName, "alice")
        XCTAssertEqual(session.profileStatusTitle, "已就绪")
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
            postNumber: postNumber,
            postType: 1,
            createdAt: "2026-03-28T10:00:00Z",
            updatedAt: "2026-03-28T10:00:00Z",
            likeCount: 0,
            replyCount: 0,
            replyToPostNumber: replyToPostNumber,
            bookmarked: false,
            bookmarkId: nil,
            reactions: [],
            currentUserReaction: nil,
            acceptedAnswer: false,
            canEdit: false,
            canDelete: false,
            canRecover: false,
            hidden: false
        )
    }
}
