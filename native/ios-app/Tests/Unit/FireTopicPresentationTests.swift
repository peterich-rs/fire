import XCTest
@testable import Fire

final class FireTopicPresentationTests: XCTestCase {
    func testPlainTextNormalizesHTMLContent() {
        let plainText = plainTextFromHtml(rawHtml: "<p>Hello<br>Fire</p><ul><li>Rust</li><li>CI</li></ul>")

        XCTAssertEqual(plainText, "Hello\nFire\n\nRust\nCI")
    }

    func testSharedTextHelpersProvidePreviewAndMonogram() {
        XCTAssertEqual(
            previewTextFromHtml(rawHtml: "<p>Hello&nbsp;<strong>Fire</strong></p>"),
            "Hello Fire"
        )
        XCTAssertEqual(monogramForUsername(username: "fire native"), "FN")
    }

    func testImageAttachmentsResolveRelativeUploadsAndSkipEmoji() {
        let attachments = fireImageAttachmentFixture("""
            <p>Hello</p>
            <img class="emoji" src="/images/emoji/twitter/smile.png">
            <img src="/uploads/default/original/1X/fire.png" alt="fire" width="1200" height="800">
            <img src="https://cdn.example.com/second.jpg">
            """)

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

    func testReactionOptionsIncludeCurrentReactionWhenMissingFromBootstrap() {
        let options = FireTopicPresentation.reactionOptions(
            from: ["heart", "laughing"],
            currentReactionID: "tada"
        )

        XCTAssertEqual(options.map(\.id), ["heart", "laughing", "tada"])
        XCTAssertEqual(options[2].symbol, "🎉")
    }

    func testReactionOptionFilteringMatchesIdLabelOrSymbol() {
        let options = FireTopicPresentation.reactionOptions(
            from: ["heart", "laughing", "thumbsup"],
            currentReactionID: nil
        )

        XCTAssertEqual(FireTopicPresentation.filterReactionOptions(options, query: "laugh").map(\.id), ["laughing"])
        XCTAssertEqual(FireTopicPresentation.filterReactionOptions(options, query: "赞同").map(\.id), ["thumbsup"])
        XCTAssertEqual(FireTopicPresentation.filterReactionOptions(options, query: "❤️").map(\.id), ["heart"])
        XCTAssertEqual(FireTopicPresentation.filterReactionOptions(options, query: " ").map(\.id), options.map(\.id))
    }

    func testTopicSearchMatchesLoadedRenderPlainTextInPostOrder() {
        let first = makePost(
            postNumber: 3,
            replyToPostNumber: nil,
            username: "first",
            cooked: "<p>Needle in a later post</p>"
        )
        let earlier = makePost(
            postNumber: 2,
            replyToPostNumber: nil,
            username: "earlier",
            cooked: "<p>accent NEEDLE match</p>"
        )
        let duplicate = makePost(
            postNumber: 2,
            replyToPostNumber: nil,
            username: "duplicate",
            cooked: "<p>needle duplicate</p>"
        )
        let cookedOnly = makePost(
            postNumber: 4,
            replyToPostNumber: nil,
            username: "cooked-only",
            cooked: "<p>needle in cooked only</p>",
            includeRenderDocument: false
        )

        let matches = FireTopicPresentation.topicSearchMatches(
            query: " needle ",
            posts: [first, earlier, duplicate, cookedOnly]
        )

        XCTAssertEqual(matches, [
            FireTopicSearchMatch(postID: earlier.id, postNumber: 2),
            FireTopicSearchMatch(postID: first.id, postNumber: 3),
        ])
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

    func testTimelineRowsBuildStableLookupForReplyRows() {
        let renderState = FireTopicPresentation.detailRenderState(
            from: makeTopicDetail(
                posts: [
                    makePost(postNumber: 1, replyToPostNumber: nil, username: "author"),
                    makePost(postNumber: 2, replyToPostNumber: 1, username: "reply-a"),
                    makePost(postNumber: 3, replyToPostNumber: 2, username: "reply-b"),
                ],
                stream: [1, 2, 3]
            ),
            baseURLString: "https://linux.do"
        )

        let lookup = Dictionary(uniqueKeysWithValues: renderState.replyRows.enumerated().map { ($1.entry.postNumber, $0) })

        XCTAssertEqual(lookup[2], 0)
        XCTAssertEqual(lookup[3], 1)
        XCTAssertEqual(lookup.count, 2)
    }

    func testDetailRenderStateCachesPlainTextAndImages() {
        let detail = makeTopicDetail(
            posts: [
                makePost(
                    postNumber: 1,
                    replyToPostNumber: nil,
                    username: "author",
                    cooked: "<p>Hello&nbsp;Fire</p><img src=\"/uploads/default/original/1X/fire.png\" alt=\"fire\">"
                )
            ],
            stream: [1]
        )

        let renderState = FireTopicPresentation.detailRenderState(
            from: detail,
            baseURLString: "https://linux.do"
        )
        let content = renderState.contentByPostID[1]

        XCTAssertEqual(content?.plainText, "Hello Fire\n\nfire")
        XCTAssertEqual(
            content?.imageAttachments.first?.url.absoluteString,
            "https://linux.do/uploads/default/original/1X/fire.png"
        )
    }

    func testDetailRenderCacheReusesRenderedContentForUnchangedPostsAcrossHydration() throws {
        let initial = FireTopicPresentation.detailRenderCache(
            from: makeTopicDetail(
                posts: [
                    makePost(
                        postNumber: 1,
                        replyToPostNumber: nil,
                        username: "author",
                        cooked: #"<p>Hello <a class="mention" href="/u/alice">@alice</a></p>"#
                    ),
                    makePost(postNumber: 2, replyToPostNumber: 1, username: "reply-a"),
                ],
                stream: [1, 2]
            ),
            baseURLString: "https://linux.do"
        )

        let hydrated = FireTopicPresentation.detailRenderCache(
            from: makeTopicDetail(
                posts: [
                    makePost(
                        postNumber: 1,
                        replyToPostNumber: nil,
                        username: "author",
                        likeCount: 5,
                        reactions: [TopicReactionState(id: "heart", kind: nil, count: 5, canUndo: nil)],
                        cooked: #"<p>Hello <a class="mention" href="/u/alice">@alice</a></p>"#
                    ),
                    makePost(postNumber: 2, replyToPostNumber: 1, username: "reply-a"),
                    makePost(postNumber: 3, replyToPostNumber: 2, username: "reply-b"),
                ],
                stream: [1, 2, 3]
            ),
            baseURLString: "https://linux.do",
            previous: initial
        )

        let initialText = try XCTUnwrap(initial.renderState.contentByPostID[1]?.attributedText)
        let hydratedText = try XCTUnwrap(hydrated.renderState.contentByPostID[1]?.attributedText)

        XCTAssertTrue(initialText === hydratedText)
        XCTAssertEqual(hydrated.renderState.replyRows.map { $0.entry.postNumber }, [2, 3])
    }

    func testDetailRenderCacheRebuildsTimelineWhenMissingParentArrives() {
        let partial = FireTopicPresentation.detailRenderCache(
            from: makeTopicDetail(
                posts: [
                    makePost(postNumber: 1, replyToPostNumber: nil, username: "author"),
                    makePost(postNumber: 3, replyToPostNumber: 2, username: "reply-b"),
                ],
                stream: [1, 2, 3]
            ),
            baseURLString: "https://linux.do"
        )

        XCTAssertEqual(partial.renderState.replyRows.map { $0.entry.postNumber }, [3])
        XCTAssertEqual(partial.renderState.replyRows.map { $0.entry.depth }, [1])

        let full = FireTopicPresentation.detailRenderCache(
            from: makeTopicDetail(
                posts: [
                    makePost(postNumber: 1, replyToPostNumber: nil, username: "author"),
                    makePost(postNumber: 2, replyToPostNumber: 1, username: "reply-a"),
                    makePost(postNumber: 3, replyToPostNumber: 2, username: "reply-b"),
                ],
                stream: [1, 2, 3]
            ),
            baseURLString: "https://linux.do",
            previous: partial
        )

        XCTAssertEqual(full.renderState.replyRows.map { $0.entry.postNumber }, [2, 3])
        XCTAssertEqual(full.renderState.replyRows.map { $0.entry.depth }, [1, 2])
    }

    func testSourceDetailRenderCacheAppendsReplyRowsIncrementally() throws {
        let originalPost = makePost(
            postNumber: 1,
            replyToPostNumber: nil,
            username: "author",
            cooked: #"<p>Hello <a class="mention" href="/u/alice">@alice</a></p>"#
        )
        let initialRows = [
            makeTreeRow(postNumber: 2, parentPostNumber: 1, depth: 1, username: "reply-a")
        ]
        let sourceSnapshot = makeSourceSnapshot(originalPost: originalPost, replyRows: initialRows)
        let treePresentation = makeTreePresentation(originalPost: originalPost, replyRows: initialRows)

        let initial = FireTopicPresentation.detailRenderCache(
            sourceSnapshot: sourceSnapshot,
            treePresentation: treePresentation,
            baseURLString: "https://linux.do"
        )

        let appended = try XCTUnwrap(
            FireTopicPresentation.detailRenderCache(
                sourceSnapshot: makeSourceSnapshot(
                    originalPost: originalPost,
                    replyRows: [
                        makeTreeRow(postNumber: 2, parentPostNumber: 1, depth: 1, username: "reply-a"),
                        makeTreeRow(postNumber: 3, parentPostNumber: 2, depth: 2, username: "reply-b"),
                        makeTreeRow(postNumber: 4, parentPostNumber: 1, depth: 1, username: "reply-c")
                    ]
                ),
                appending: [
                    makeTreeRow(postNumber: 3, parentPostNumber: 2, depth: 2, username: "reply-b"),
                    makeTreeRow(postNumber: 4, parentPostNumber: 1, depth: 1, username: "reply-c")
                ],
                baseURLString: "https://linux.do",
                previous: initial
            )
        )

        let initialOriginal = try XCTUnwrap(initial.renderState.contentByPostID[1]?.attributedText)
        let appendedOriginal = try XCTUnwrap(appended.renderState.contentByPostID[1]?.attributedText)

        XCTAssertTrue(initialOriginal === appendedOriginal)
        XCTAssertEqual(appended.renderState.replyRows.map { $0.entry.postNumber }, [2, 3, 4])
        XCTAssertEqual(appended.rowInputs.map(\.postNumber), [1, 2, 3, 4])
    }

    func testSourceDetailRenderCacheRebuildsRowsWhenReplyShapeChanges() {
        let originalPost = makePost(postNumber: 1, replyToPostNumber: nil, username: "author")
        let initialRows = [
            makeTreeRow(postNumber: 2, parentPostNumber: 1, depth: 1, username: "reply-a")
        ]
        let changedRows = [
            makeTreeRow(postNumber: 2, parentPostNumber: 1, depth: 2, username: "reply-a")
        ]
        let initial = FireTopicPresentation.detailRenderCache(
            sourceSnapshot: makeSourceSnapshot(originalPost: originalPost, replyRows: initialRows),
            treePresentation: makeTreePresentation(originalPost: originalPost, replyRows: initialRows),
            baseURLString: "https://linux.do"
        )

        let refreshed = FireTopicPresentation.detailRenderCache(
            sourceSnapshot: makeSourceSnapshot(originalPost: originalPost, replyRows: changedRows),
            treePresentation: makeTreePresentation(originalPost: originalPost, replyRows: changedRows),
            baseURLString: "https://linux.do",
            previous: initial
        )

        XCTAssertNotEqual(initial.rowInputs, refreshed.rowInputs)
        XCTAssertEqual(refreshed.renderState.replyRows.map { $0.entry.depth }, [2])
    }

    func testSourceDetailRenderCacheAppendFallsBackForDuplicateRows() {
        let originalPost = makePost(postNumber: 1, replyToPostNumber: nil, username: "author")
        let initialRows = [
            makeTreeRow(postNumber: 2, parentPostNumber: 1, depth: 1, username: "reply-a")
        ]
        let initial = FireTopicPresentation.detailRenderCache(
            sourceSnapshot: makeSourceSnapshot(originalPost: originalPost, replyRows: initialRows),
            treePresentation: makeTreePresentation(originalPost: originalPost, replyRows: initialRows),
            baseURLString: "https://linux.do"
        )

        let duplicateAppend = FireTopicPresentation.detailRenderCache(
            sourceSnapshot: makeSourceSnapshot(originalPost: originalPost, replyRows: initialRows),
            appending: [
                makeTreeRow(postNumber: 2, parentPostNumber: 1, depth: 1, username: "reply-a")
            ],
            baseURLString: "https://linux.do",
            previous: initial
        )

        XCTAssertNil(duplicateAppend)
    }

    func testSourceDetailRenderCacheAppendFallsBackWhenPreviousOriginalContentIsMissing() {
        let originalPost = makePost(postNumber: 1, replyToPostNumber: nil, username: "author")
        let initialRows = [
            makeTreeRow(postNumber: 2, parentPostNumber: 1, depth: 1, username: "reply-a")
        ]
        let initial = FireTopicPresentation.detailRenderCache(
            sourceSnapshot: makeSourceSnapshot(originalPost: originalPost, replyRows: initialRows),
            treePresentation: makeTreePresentation(originalPost: originalPost, replyRows: initialRows),
            baseURLString: "https://linux.do"
        )
        let brokenPrevious = FireTopicDetailRenderCache(
            baseURLString: initial.baseURLString,
            rowInputs: initial.rowInputs,
            contentInputsByPostID: initial.contentInputsByPostID,
            renderState: FireTopicDetailRenderState(
                originalRow: initial.renderState.originalRow,
                replyRows: initial.renderState.replyRows,
                contentByPostID: initial.renderState.contentByPostID.filter { $0.key != originalPost.id }
            )
        )

        let appended = FireTopicPresentation.detailRenderCache(
            sourceSnapshot: makeSourceSnapshot(originalPost: originalPost, replyRows: initialRows),
            appending: [
                makeTreeRow(postNumber: 3, parentPostNumber: 1, depth: 1, username: "reply-b")
            ],
            baseURLString: "https://linux.do",
            previous: brokenPrevious
        )

        XCTAssertNil(appended)
    }

    func testSourceDetailRenderCacheDeduplicatesOverlappingRows() {
        let originalPost = makePost(postNumber: 1, replyToPostNumber: nil, username: "author")
        let rows = [
            makeTreeRow(postNumber: 2, parentPostNumber: 1, depth: 1, username: "reply-old"),
            makeTreeRow(postNumber: 2, parentPostNumber: 1, depth: 1, username: "reply-new")
        ]

        let renderCache = FireTopicPresentation.detailRenderCache(
            sourceSnapshot: makeSourceSnapshot(
                originalPost: originalPost,
                replyRows: rows,
                replyPosts: [
                    makePost(postNumber: 2, replyToPostNumber: 1, username: "reply-old"),
                    makePost(postNumber: 2, replyToPostNumber: 1, username: "reply-new")
                ]
            ),
            treePresentation: makeTreePresentation(originalPost: originalPost, replyRows: rows),
            baseURLString: "https://linux.do"
        )

        XCTAssertEqual(renderCache.renderState.replyRows.map { $0.entry.postNumber }, [2])
        XCTAssertEqual(renderCache.renderState.contentByPostID[2]?.plainText, "reply-new")
    }

    func testDetailRenderCacheDeduplicatesDuplicatePostsAndStreamIDs() {
        let detail = makeTopicDetail(
            posts: [
                makePost(postNumber: 1, replyToPostNumber: nil, username: "author"),
                makePost(postNumber: 2, replyToPostNumber: 1, username: "reply-old"),
                makePost(postNumber: 2, replyToPostNumber: 1, username: "reply-new")
            ],
            stream: [1, 2, 2]
        )

        let renderCache = FireTopicPresentation.detailRenderCache(
            from: detail,
            baseURLString: "https://linux.do"
        )

        XCTAssertEqual(renderCache.renderState.replyRows.map { $0.entry.postNumber }, [2])
        XCTAssertEqual(renderCache.renderState.contentByPostID[2]?.plainText, "reply-new")
    }

    func testRenderContentPlainTextIncludesImageAttachmentAltTextFromSharedRenderer() {
        let content = fireRenderContentFixture(#"<p>Hello&nbsp;Fire</p><img src="/uploads/default/original/1X/fire.png" alt="fire">"#)

        XCTAssertEqual(content.plainText, "Hello Fire\n\nfire")
        XCTAssertEqual(content.imageAttachments.first?.altText, "fire")
    }

    func testRenderContentMakesMentionsTappableAsInAppProfiles() throws {
        let content = fireRenderContentFixture(#"<p>Hello <a class="mention" href="/u/alice">@alice</a></p>"#)

        let attributedText = try XCTUnwrap(content.attributedText)
        let range = (attributedText.string as NSString).range(of: "@alice")

        XCTAssertNotEqual(range.location, NSNotFound)
        XCTAssertEqual(
            attributedText.attribute(.link, at: range.location, effectiveRange: nil) as? URL,
            URL(string: "fire://profile/alice")
        )
    }

    func testImageAttachmentsPreferLightboxOriginalURL() {
        let content = fireRenderContentFixture(#"<p><a class="lightbox" href="/uploads/default/original/1X/fire-full.png"><img src="/uploads/default/optimized/1X/fire_690x388.png" width="690" height="388"></a></p>"#)

        XCTAssertEqual(content.attributedText?.length ?? 0, 0)
        XCTAssertEqual(
            content.imageAttachments.map(\.url.absoluteString),
            ["https://linux.do/uploads/default/original/1X/fire-full.png"]
        )
        XCTAssertEqual(Double(content.imageAttachments.first?.aspectRatio ?? 0), 690.0 / 388.0, accuracy: 0.001)
    }

    func testRenderContentKeepsImagesInInlineSegmentOrder() {
        let content = fireRenderContentFixture(#"<p>Before</p><p><a class="lightbox" href="/uploads/default/original/1X/fire-full.png"><img src="/uploads/default/optimized/1X/fire_690x388.png" width="690" height="388" alt="fire"></a></p><p>After</p>"#)

        XCTAssertEqual(content.segments.count, 3)
        if case .text(let beforeText) = content.segments[0] {
            XCTAssertEqual(beforeText.string, "Before")
        } else {
            XCTFail("Expected leading text segment")
        }
        if case .image(let image) = content.segments[1] {
            XCTAssertEqual(image.url.absoluteString, "https://linux.do/uploads/default/original/1X/fire-full.png")
            XCTAssertEqual(image.altText, "fire")
        } else {
            XCTFail("Expected middle image segment")
        }
        if case .text(let afterText) = content.segments[2] {
            XCTAssertEqual(afterText.string, "After")
        } else {
            XCTFail("Expected trailing text segment")
        }
    }

    func testRenderContentAppendsImageAttachmentsMissingFromRenderTree() {
        let document = RenderDocumentState(
            blocks: [
                RenderBlockState(id: 1, parentId: nil, depth: 0, kind: .document),
                RenderBlockState(id: 2, parentId: 1, depth: 1, kind: .paragraph),
                RenderBlockState(id: 3, parentId: 2, depth: 2, kind: .text(content: "Before")),
            ],
            plainText: "Before\nfire",
            imageAttachments: [
                RenderImageAttachmentState(
                    url: "https://linux.do/uploads/default/original/1X/fire.png",
                    altText: "fire",
                    width: 690,
                    height: 388
                ),
            ]
        )

        let content = FireTopicPresentation.renderContent(from: document, sourceToken: "missing-image-node")

        XCTAssertEqual(content.segments.count, 2)
        if case .text(let text) = content.segments[0] {
            XCTAssertEqual(text.string, "Before")
        } else {
            XCTFail("Expected leading text segment")
        }
        if case .image(let image) = content.segments[1] {
            XCTAssertEqual(image.url.absoluteString, "https://linux.do/uploads/default/original/1X/fire.png")
            XCTAssertEqual(image.altText, "fire")
        } else {
            XCTFail("Expected appended image segment")
        }
    }

    func testRenderContentSuppressesInlineImageMetadataText() {
        let content = fireRenderContentFixture(#"<p><a class="lightbox" href="/uploads/default/original/1X/fire-full.png"><img src="/uploads/default/optimized/1X/fire_690x388.png" width="690" height="388" alt="fire"></a> screen-shot 1080x1920 34kb</p>"#)
        let segmentText = content.segments.compactMap { segment -> String? in
            if case .text(let text) = segment {
                return text.string
            }
            return nil
        }.joined(separator: "\n")

        XCTAssertEqual(content.imageAttachments.count, 1)
        XCTAssertFalse(content.plainText.contains("1080x1920"))
        XCTAssertFalse(content.plainText.contains("screen-shot"))
        XCTAssertFalse(content.plainText.contains("34kb"))
        XCTAssertFalse(segmentText.contains("1080x1920"))
        XCTAssertFalse(segmentText.contains("screen-shot"))
        XCTAssertFalse(segmentText.contains("34kb"))
    }

    func testRenderContentPreservesTextBeforeInlineImageMetadataSuffix() {
        let content = fireRenderContentFixture(#"<p><a class="lightbox" href="/uploads/default/original/1X/fire-full.png"><img src="/uploads/default/optimized/1X/fire_690x388.png" width="690" height="388"></a> body text screen-shot 1080x1920 34kb</p>"#)
        let segmentText = content.segments.compactMap { segment -> String? in
            if case .text(let text) = segment {
                return text.string
            }
            return nil
        }.joined(separator: "\n")

        XCTAssertEqual(content.imageAttachments.count, 1)
        XCTAssertEqual(content.plainText, "body text")
        XCTAssertEqual(segmentText, "body text")
        XCTAssertFalse(segmentText.contains("screen-shot"))
        XCTAssertFalse(segmentText.contains("1080x1920"))
        XCTAssertFalse(segmentText.contains("34kb"))
    }

    func testHeadingAttributedTextCarriesExpandedParagraphLineHeight() throws {
        let content = fireRenderContentFixture("<h1>Big heading wraps onto another line</h1>")
        let attributedText = try XCTUnwrap(content.attributedText)
        let paragraph = try XCTUnwrap(
            attributedText.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )
        let font = try XCTUnwrap(attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)

        XCTAssertGreaterThanOrEqual(paragraph.minimumLineHeight, ceil(font.lineHeight))
        XCTAssertGreaterThan(paragraph.lineSpacing, 0)
    }

    func testImageAttachmentsPreferGenericLinkedImageURL() {
        let content = fireRenderContentFixture(#"<p><a href="/uploads/default/original/1X/fire-full.png"><img src="/uploads/default/optimized/1X/fire_690x388.png" width="690" height="388"></a></p>"#)

        XCTAssertEqual(content.attributedText?.length ?? 0, 0)
        XCTAssertEqual(
            content.imageAttachments.map(\.url.absoluteString),
            ["https://linux.do/uploads/default/original/1X/fire-full.png"]
        )
    }

    func testRenderContentEmbedsEmojiAttachments() throws {
        let content = fireRenderContentFixture(#"<p><img class="emoji" title="smile" src="/images/emoji/twitter/smile.png?v=12"></p>"#)

        let attributedText = try XCTUnwrap(content.attributedText)
        let attachment = try XCTUnwrap(
            attributedText.attribute(.attachment, at: 0, effectiveRange: nil) as? FireRichTextEmojiAttachment
        )

        XCTAssertEqual(attachment.remoteURL.absoluteString, "https://linux.do/images/emoji/twitter/smile.png?v=12")
        XCTAssertEqual(attachment.fallbackText, ":smile:")
        XCTAssertTrue(content.imageAttachments.isEmpty)
    }

    func testRenderContentDerivesEmojiShortcodeFromToneVariantPath() throws {
        let content = fireRenderContentFixture(#"<p><img class="emoji" src="/images/emoji/twitter/wave/t3.png?v=12"></p>"#)

        let attributedText = try XCTUnwrap(content.attributedText)
        let attachment = try XCTUnwrap(
            attributedText.attribute(.attachment, at: 0, effectiveRange: nil) as? FireRichTextEmojiAttachment
        )

        XCTAssertEqual(attachment.fallbackText, ":wave:t3:")
    }

    func testRenderContentBuildsQuotedReplyHeaderWithInternalLinks() throws {
        let content = fireRenderContentFixture(#"<aside class="quote" data-username="alice" data-post="12" data-topic="987"><blockquote><p>Hello <a href="https://linux.do/t/fire/987/12">Fire link</a></p></blockquote></aside>"#)

        let attributedText = try XCTUnwrap(content.attributedText)
        let text = attributedText.string as NSString
        let authorRange = text.range(of: "@alice")
        let postRange = text.range(of: "#12")
        let bodyLinkRange = text.range(of: "Fire link")

        XCTAssertNotEqual(authorRange.location, NSNotFound)
        XCTAssertNotEqual(postRange.location, NSNotFound)
        XCTAssertEqual(
            attributedText.attribute(.fireQuotePreviewBlock, at: authorRange.location, effectiveRange: nil) as? Bool,
            true
        )
        XCTAssertEqual(
            attributedText.attribute(.link, at: authorRange.location, effectiveRange: nil) as? URL,
            URL(string: "fire://profile/alice")
        )
        XCTAssertEqual(
            attributedText.attribute(.link, at: postRange.location, effectiveRange: nil) as? URL,
            URL(string: "fire://topic/987/12")
        )
        XCTAssertNotEqual(bodyLinkRange.location, NSNotFound)
        XCTAssertEqual(
            attributedText.attribute(.link, at: bodyLinkRange.location, effectiveRange: nil) as? URL,
            URL(string: "https://linux.do/t/fire/987/12")
        )
    }

    func testRenderContentCompactsQuotedReplyPreview() throws {
        let content = fireRenderContentFixture(#"""
            <aside class="quote" data-username="alice" data-post="12" data-topic="987">
              <blockquote>
                <p>First quoted line</p>
                <p>Second quoted line</p>
                <p>Third quoted line should be hidden</p>
              </blockquote>
            </aside>
            """#)

        let attributedText = try XCTUnwrap(content.attributedText)
        let text = attributedText.string

        XCTAssertTrue(text.contains("First quoted line"))
        XCTAssertTrue(text.contains("Second quoted line"))
        XCTAssertFalse(text.contains("Third quoted line should be hidden"))
        XCTAssertTrue(text.contains("引用"))
        XCTAssertEqual(
            attributedText.attribute(.fireQuotePreviewBlock, at: 0, effectiveRange: nil) as? Bool,
            true
        )
    }

    func testRenderContentDoesNotPromoteQuoteAvatarToPostAttachment() throws {
        let content = fireRenderContentFixture(#"""
            <aside class="quote" data-username="alice" data-post="12" data-topic="987">
              <div class="title">
                <img class="avatar" src="/user_avatar/linux.do/alice/48/1_2.png" width="24" height="24">
                <a href="/u/alice">alice</a>:
              </div>
              <blockquote><p>Hello Fire</p></blockquote>
            </aside>
            """#)

        let attributedText = try XCTUnwrap(content.attributedText)

        XCTAssertTrue(content.imageAttachments.isEmpty)
        XCTAssertTrue(attributedText.string.contains("引用"))
        XCTAssertTrue(attributedText.string.contains("Hello Fire"))
        XCTAssertFalse(attributedText.string.contains("alice:"))
        XCTAssertEqual(attributedText.string.components(separatedBy: "alice").count - 1, 1)
    }

    func testRenderContentMakesMentionGroupsAndHashtagsTappable() throws {
        let content = fireRenderContentFixture(#"<p><a class="mention-group" href="/groups/moderators">@moderators</a> <a class="hashtag-cooked" data-type="tag" href="/tag/rust">#rust</a></p>"#)

        let attributedText = try XCTUnwrap(content.attributedText)
        let text = attributedText.string as NSString
        let groupRange = text.range(of: "@moderators")
        let hashtagRange = text.range(of: "#rust")

        XCTAssertNotEqual(groupRange.location, NSNotFound)
        XCTAssertNotEqual(hashtagRange.location, NSNotFound)
        XCTAssertEqual(
            attributedText.attribute(.link, at: groupRange.location, effectiveRange: nil) as? URL,
            URL(string: "https://linux.do/groups/moderators")
        )
        XCTAssertEqual(
            attributedText.attribute(.link, at: hashtagRange.location, effectiveRange: nil) as? URL,
            URL(string: "https://linux.do/tag/rust")
        )
    }

    func testRenderContentPreservesDetailsAndSpoilerText() throws {
        let content = fireRenderContentFixture(#"<details><summary>展开说明</summary><p>可见 <span class="spoiler">隐藏内容</span></p></details>"#)

        let attributedText = try XCTUnwrap(content.attributedText)
        let text = attributedText.string as NSString
        let spoilerRange = text.range(of: "隐藏内容")

        XCTAssertTrue(attributedText.string.contains("展开说明"))
        XCTAssertNotEqual(spoilerRange.location, NSNotFound)
        XCTAssertNotNil(attributedText.attribute(.backgroundColor, at: spoilerRange.location, effectiveRange: nil))
    }

    func testRenderContentSupportsOrderedListsTablesAndOneboxes() throws {
        let content = fireRenderContentFixture(#"""
            <ol><li>第一项</li><li><strong>第二项</strong></li></ol>
            <table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>
            <aside class="onebox"><header><a href="https://example.com/post">example.com</a></header><div class="onebox-body"><h3><a href="https://example.com/post">Example title</a></h3><p>Example description</p></div></aside>
            """#)

        let attributedText = try XCTUnwrap(content.attributedText)
        XCTAssertTrue(attributedText.string.contains("1. 第一项"))
        XCTAssertTrue(attributedText.string.contains("2. 第二项"))
        XCTAssertTrue(attributedText.string.contains("A | B\n1 | 2"))
        XCTAssertTrue(attributedText.string.contains("链接预览"))
        XCTAssertTrue(attributedText.string.contains("Example title"))
        XCTAssertTrue(attributedText.string.contains("Example description"))
        XCTAssertFalse(attributedText.string.contains("example.com Example title Example description"))
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

    func testRebuildTimelineEntriesUsesFloorOrderForLoadedPosts() {
        let detail = makeTopicDetail(
            posts: [
                makePost(postNumber: 3, replyToPostNumber: 2, username: "nested"),
                makePost(postNumber: 1, replyToPostNumber: nil, username: "author"),
                makePost(postNumber: 2, replyToPostNumber: 1, username: "reply"),
            ],
            stream: [1, 2, 3]
        )

        let entries = FireTopicPresentation.rebuildTimelineEntries(from: detail.postStream.posts)

        XCTAssertEqual(entries.map(\.postNumber), [1, 2, 3])
        XCTAssertEqual(entries.map(\.depth), [0, 1, 2])
        XCTAssertEqual(entries[2].parentPostNumber, 2)
    }

    func testInteractionCountIncludesNonHeartReactions() {
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

        XCTAssertEqual(FireTopicPresentation.interactionCount(for: detail), 12)
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
            browserUserAgent: nil,
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
            browserUserAgent: nil,
            profileDisplayName: "alice",
            loginPhaseLabel: "已就绪"
        )

        XCTAssertEqual(session.profileDisplayName, "alice")
        XCTAssertEqual(session.profileStatusTitle, "已就绪")
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
            FireTopicTimelineEntry(
                postId: 1, postNumber: 1, parentPostNumber: nil, depth: 0, isOriginalPost: true
            ),
            FireTopicTimelineEntry(
                postId: 2, postNumber: 2, parentPostNumber: 1, depth: 1, isOriginalPost: false
            ),
            FireTopicTimelineEntry(
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

    func testReplyContextPrefersResolvedTreeParentWhenItDiffers() {
        let post = makePost(postNumber: 5, replyToPostNumber: 3, username: "reply")

        XCTAssertEqual(
            FireTopicPresentation.replyTargetPostNumber(
                for: post,
                preferredPostNumber: 2
            ),
            2
        )
        XCTAssertEqual(
            FireTopicPresentation.replyContextLabel(
                for: post,
                preferredPostNumber: 2
            ),
            "回复 #2"
        )
    }

    func testReplyContextKeepsReplyUserWhenTreeParentMatchesDeclaredParent() {
        var post = makePost(postNumber: 5, replyToPostNumber: 3, username: "reply")
        post.replyToUser = TopicReplyToUserState(
            username: "alice",
            name: nil,
            avatarTemplate: nil
        )

        XCTAssertEqual(
            FireTopicPresentation.replyContextLabel(
                for: post,
                preferredPostNumber: 3
            ),
            "回复 @alice"
        )
    }

    func testRenderContentRequiresRenderDocumentEvenWhenCookedExists() {
        let post = makePost(
            postNumber: 1,
            replyToPostNumber: nil,
            username: "author",
            cooked: "<p>Cooked only</p>",
            includeRenderDocument: false
        )
        let detail = makeTopicDetail(posts: [post], stream: [post.id])
        let renderState = FireTopicPresentation.detailRenderState(
            from: detail,
            baseURLString: "https://linux.do"
        )

        XCTAssertNil(FireTopicPresentation.renderContent(from: post))
        XCTAssertNil(renderState.contentByPostID[post.id])
    }

    private func makePost(
        postNumber: UInt32,
        replyToPostNumber: UInt32?,
        username: String,
        likeCount: UInt32 = 0,
        reactions: [TopicReactionState] = [],
        cooked: String? = nil,
        includeRenderDocument: Bool = true
    ) -> TopicPostState {
        let cooked = cooked ?? "<p>\(username)</p>"
        let renderDocument = includeRenderDocument
            ? renderCookedHtml(rawHtml: cooked, baseUrl: "https://linux.do")
            : nil
        return TopicPostState(
            id: UInt64(postNumber),
            username: username,
            name: nil,
            avatarTemplate: nil,
            authorMetadata: fireEmptyPostAuthorMetadataState(),
            cooked: cooked,
            renderDocument: renderDocument,
            raw: nil,
            postNumber: postNumber,
            postType: 1,
            createdAt: "2026-03-28T10:00:00Z",
            updatedAt: "2026-03-28T10:00:00Z",
            likeCount: likeCount,
            replyCount: 0,
            replyToPostNumber: replyToPostNumber,
            replyToUser: nil,
            bookmarked: false,
            bookmarkId: nil,
            bookmarkName: nil,
            bookmarkReminderAt: nil,
            reactions: reactions,
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

    private func makeSourceSnapshot(
        originalPost: TopicPostState,
        replyRows: [TopicTreeRowState],
        replyPosts: [TopicPostState]? = nil
    ) -> TopicDetailSourceSnapshotState {
        let loadedReplyPosts = replyPosts ?? replyRows.map { row in
            makePost(
                postNumber: row.postNumber,
                replyToPostNumber: row.parentPostNumber,
                username: "reply-\(row.postNumber)"
            )
        }
        return TopicDetailSourceSnapshotState(
            header: TopicHeaderState(
                topicId: 42,
                messageBusLastId: nil,
                title: "Fire Native",
                slug: "fire-native",
                postsCount: UInt32(replyRows.count + 1),
                replyCount: UInt32(replyRows.count),
                categoryId: 7,
                tags: [],
                views: 128,
                likeCount: 9,
                createdAt: "2026-03-28T10:00:00Z",
                highestPostNumber: UInt32(replyRows.count + 1),
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
                details: TopicDetailMetaState(
                    notificationLevel: nil,
                    canEdit: false,
                    createdBy: nil,
                    participants: []
                )
            ),
            body: TopicBodyState(post: originalPost),
            rawStreamIds: [originalPost.id] + replyRows.map(\.postId),
            loadedPosts: loadedReplyPosts,
            loadedRanges: [],
            sourceCursor: TopicSourceCursorState(
                topicId: 42,
                sessionId: 7,
                nextStreamOffset: UInt32(replyRows.count + 1),
                lastLoadedPostId: replyRows.last?.postId ?? originalPost.id,
                batchSize: 10
            ),
            sourceExhausted: false,
            focusedPostNumber: nil
        )
    }

    private func makeTreePresentation(
        originalPost: TopicPostState,
        replyRows: [TopicTreeRowState]
    ) -> TopicTreePresentationState {
        TopicTreePresentationState(
            originalPostId: originalPost.id,
            originalPostNumber: originalPost.postNumber,
            replyRows: replyRows,
            totalLoadedPostCount: UInt32(replyRows.count + 1),
            visibleRootPostNumbers: Array(Set(replyRows.map(\.rootPostNumber))).sorted(),
            firstUnreadRootPostNumber: nil,
            gainedNewRootProgress: !replyRows.isEmpty
        )
    }

}
