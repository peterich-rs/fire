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

    func testEnabledReactionOptionsReadsConfiguredReactionOrder() {
        let options = FireTopicPresentation.enabledReactionOptions(
            from: """
            {
              "siteSettings": {
                "discourse_reactions_enabled_reactions": "heart|laughing|thumbsup"
              }
            }
            """
        )

        XCTAssertEqual(options.map(\.id), ["heart", "laughing", "thumbsup"])
        XCTAssertEqual(options[1].symbol, "😆")
    }

    func testMinimumReplyLengthReadsSiteSettings() {
        XCTAssertEqual(
            FireTopicPresentation.minimumReplyLength(
                from: """
                {
                  "siteSettings": {
                    "min_post_length": 15
                  }
                }
                """
            ),
            15
        )
        XCTAssertEqual(FireTopicPresentation.minimumReplyLength(from: nil), 1)
    }

    func testImageAttachmentsExtractsNonEmojiImagesAndNormalizesRelativeURLs() {
        let images = FireTopicPresentation.imageAttachments(
            from: """
            <p>Hello</p>
            <img src="/uploads/default/original/1X/fire.png" alt="fire" width="1280" height="720">
            <img src="https://cdn.example.com/remote.jpg" width="400" height="300">
            <img src="/images/emoji/twitter/fire.png" class="emoji" alt=":fire:">
            """,
            baseURLString: "https://linux.do"
        )

        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(images.first?.url.absoluteString, "https://linux.do/uploads/default/original/1X/fire.png")
        XCTAssertEqual(images.first?.altText, "fire")
        XCTAssertEqual(images.first?.aspectRatio ?? 0, 1280.0 / 720.0, accuracy: 0.001)
        XCTAssertEqual(images.last?.url.absoluteString, "https://cdn.example.com/remote.jpg")
    }

    func testEnabledReactionOptionsReadsBootstrapSettings() {
        let reactions = FireTopicPresentation.enabledReactionOptions(
            from: """
            {
              "siteSettings": {
                "discourse_reactions_enabled_reactions": "heart|laughing|open_mouth"
              }
            }
            """
        )

        XCTAssertEqual(reactions.map(\.id), ["heart", "laughing", "open_mouth"])
        XCTAssertEqual(reactions[1].symbol, "😆")
        XCTAssertEqual(reactions[2].label, "惊讶")
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

        let row = try XCTUnwrap(
            FireTopicPresentation.buildRowPresentations(from: [topic], users: []).first
        )

        XCTAssertEqual(row.excerptText, "Hello Fire")
        XCTAssertEqual(row.lastPosterUsername, "User 9")
        XCTAssertEqual(row.tagNames, ["rust"])
        XCTAssertEqual(row.statusLabels, ["Pinned", "Unread 3", "New 1"])
        XCTAssertEqual(row.tagSummaryText, "#rust")
        XCTAssertNotNil(row.createdTimestampText)
        XCTAssertNotNil(row.activityTimestampText)
    }

    func testBuildRowPresentationsMapsOriginalPosterProfileFromTopicUsers() throws {
        let topic = TopicSummaryState(
            id: 7,
            title: "Avatar Mapping",
            slug: "avatar-mapping",
            postsCount: 2400,
            replyCount: 2399,
            views: 92000,
            likeCount: 18,
            excerpt: nil,
            createdAt: "2026-03-28T10:00:00Z",
            lastPostedAt: "2026-03-28T11:30:00Z",
            lastPosterUsername: "bob",
            categoryId: 9,
            pinned: false,
            visible: true,
            closed: false,
            archived: false,
            tags: [],
            posters: [
                TopicPosterState(userId: 11, description: "Most Recent Poster", extras: nil),
                TopicPosterState(userId: 9, description: "Original Poster", extras: nil),
            ],
            unseen: false,
            unreadPosts: 0,
            newPosts: 0,
            lastReadPostNumber: nil,
            highestPostNumber: 2400,
            hasAcceptedAnswer: false,
            canHaveAnswer: true
        )
        let users = [
            TopicUserState(
                id: 9,
                username: "alice",
                avatarTemplate: "/user_avatar/linux.do/alice/{size}/1.png"
            ),
            TopicUserState(
                id: 11,
                username: "bob",
                avatarTemplate: "/user_avatar/linux.do/bob/{size}/2.png"
            ),
        ]

        let row = try XCTUnwrap(
            FireTopicPresentation.buildRowPresentations(from: [topic], users: users).first
        )

        XCTAssertEqual(row.originalPosterUsername, "alice")
        XCTAssertEqual(
            row.originalPosterAvatarTemplate,
            "/user_avatar/linux.do/alice/{size}/1.png"
        )
        XCTAssertEqual(row.lastPosterUsername, "bob")
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
