import AsyncDisplayKit
import XCTest
@testable import Fire

final class FireTopicDetailRuntimeTests: XCTestCase {
    @MainActor
    func testQuickReplyBarMeasuresToCompactVisibleHeight() {
        let node = FireTopicQuickReplyBarNode()
        node.apply(state: FireTopicDetailQuickReplyState(
            isVisible: true,
            typingSummary: "alice 正在输入",
            targetSummary: "#12 · bob",
            placeholder: "快速回复…",
            draft: "hello world",
            isSubmitting: false,
            validationMessage: nil
        ))
        node.updateLayoutWidth(393)

        let layout = node.layoutThatFits(ASSizeRange(
            min: CGSize(width: 393, height: 0),
            max: CGSize(width: 393, height: 852)
        ))

        XCTAssertEqual(layout.size.width, 393, accuracy: 0.5)
        XCTAssertLessThan(layout.size.height, 220)
    }

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
            postLookup: [original.id: original, firstReply.id: firstReply, secondReply.id: secondReply],
            expandedReplyRootPostIDs: [firstReply.id]
        )

        let snapshot = configuration.makeSnapshot()

        XCTAssertEqual(snapshot.items.map(\.id), [
            "header:42",
            "original:42",
            "stats:42",
            "replies-header:42",
            "reply:200:2",
            "reply:300:3",
            "reply-footer:42:endReached",
        ])
        XCTAssertEqual(snapshot.replyIndexByPostID, [firstReply.id: 0, secondReply.id: 1])
        XCTAssertEqual(snapshot.items.first(where: { $0.id == "reply:300:3" })?.replyIndex, 1)
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

        XCTAssertEqual(configuration.replyFooterState, .emptyPrompt)
        XCTAssertEqual(snapshot.items.last?.kind, .replyFooter)
        XCTAssertEqual(snapshot.items.last?.id, "reply-footer:42:emptyPrompt")
    }

    func testSnapshotDoesNotShowEmptyFooterWhenDetailHasRepliesButRenderStateIsPending() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let reply = makePost(id: 200, postNumber: 2, username: "bob", replyToPostNumber: 1)
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: [original, reply]),
            renderState: nil,
            postLookup: [original.id: original, reply.id: reply]
        )

        let snapshot = configuration.makeSnapshot()

        XCTAssertEqual(configuration.replyFooterState, .none)
        XCTAssertFalse(snapshot.items.contains { item in
            item.kind == .replyFooter
                && (item.contentToken.base as? String) == FireTopicDetailRuntimeReplyFooterState.emptyPrompt.contentToken
        })
    }

    func testSnapshotDoesNotShowEmptyFooterWhenReplyRowsTemporarilyMissing() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let reply = makePost(id: 200, postNumber: 2, username: "bob", replyToPostNumber: 1)
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [],
            contentByPostID: [
                original.id: makeRenderContent("Original"),
                reply.id: makeRenderContent("Reply"),
            ]
        )
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: [original, reply]),
            renderState: renderState,
            postLookup: [original.id: original, reply.id: reply]
        )

        let snapshot = configuration.makeSnapshot()

        XCTAssertEqual(configuration.replyFooterState, .none)
        XCTAssertFalse(snapshot.items.contains { $0.kind == .replyFooter })
    }

    func testSnapshotIncludesTopicVoteWhenTopicCanVote() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [],
            contentByPostID: [original.id: makeRenderContent("Original")]
        )
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: [original], canVote: true, voteCount: 3, userVoted: true),
            renderState: renderState,
            postLookup: [original.id: original]
        )

        let snapshot = configuration.makeSnapshot()

        XCTAssertTrue(snapshot.items.contains(where: { $0.kind == .topicVote && $0.id == "topic-vote:42" }))
        XCTAssertLessThan(
            snapshot.items.firstIndex(where: { $0.kind == .stats }) ?? .max,
            snapshot.items.firstIndex(where: { $0.kind == .topicVote }) ?? .min
        )
    }

    func testThreadLineStopsWhenNextReplyIsShallower() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let nestedReply = makePost(id: 200, postNumber: 2, username: "bob", replyToPostNumber: 1)
        let shallowReply = makePost(id: 300, postNumber: 3, username: "carol", replyToPostNumber: 1)
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [
                makeTimelineRow(post: nestedReply, parentPostNumber: 1, depth: 2),
                makeTimelineRow(post: shallowReply, parentPostNumber: 1, depth: 1),
            ],
            contentByPostID: [
                original.id: makeRenderContent("Original"),
                nestedReply.id: makeRenderContent("Nested"),
                shallowReply.id: makeRenderContent("Shallow"),
            ]
        )
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: [original, nestedReply, shallowReply]),
            renderState: renderState,
            postLookup: [original.id: original, nestedReply.id: nestedReply, shallowReply.id: shallowReply]
        )

        let snapshot = configuration.makeSnapshot()
        let nestedItem = snapshot.items.first { $0.id == "reply:200:2" }

        XCTAssertEqual(nestedItem.flatMap(configuration.postContext(for:))?.showsThreadLine, false)
    }

    func testSnapshotHidesSecondaryRepliesBehindRootShortcutByDefault() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let rootReply = makePost(
            id: 200,
            postNumber: 2,
            username: "bob",
            replyCount: 5,
            replyToPostNumber: 1
        )
        let lowQuality = makePost(id: 300, postNumber: 3, username: "c1", replyToPostNumber: 2)
        let liked = makePost(id: 400, postNumber: 4, username: "c2", likeCount: 10, replyToPostNumber: 2)
        let reacted = makePost(
            id: 500,
            postNumber: 5,
            username: "c3",
            reactions: [TopicReactionState(id: "clap", kind: nil, count: 4, canUndo: nil)],
            replyToPostNumber: 2
        )
        let discussed = makePost(id: 600, postNumber: 6, username: "c4", replyCount: 6, replyToPostNumber: 2)
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [
                makeTimelineRow(post: rootReply, parentPostNumber: 1, depth: 1),
                makeTimelineRow(post: lowQuality, parentPostNumber: 2, depth: 2),
                makeTimelineRow(post: liked, parentPostNumber: 2, depth: 2),
                makeTimelineRow(post: reacted, parentPostNumber: 2, depth: 2),
                makeTimelineRow(post: discussed, parentPostNumber: 2, depth: 2),
            ],
            contentByPostID: [
                original.id: makeRenderContent("Original"),
                rootReply.id: makeRenderContent("Root"),
                lowQuality.id: makeRenderContent("Low"),
                liked.id: makeRenderContent("Liked"),
                reacted.id: makeRenderContent("Reacted"),
                discussed.id: makeRenderContent("Discussed"),
            ]
        )
        let posts = [original, rootReply, lowQuality, liked, reacted, discussed]
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: posts),
            renderState: renderState,
            postLookup: Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
        )

        let snapshot = configuration.makeSnapshot()
        let replyItems = snapshot.items.filter { $0.kind == .reply }

        XCTAssertEqual(replyItems.map(\.postNumber), [2])
        XCTAssertNil(configuration.scrollItem(for: 3))
        XCTAssertEqual(configuration.postContext(for: replyItems[0])?.depth, 1)
        XCTAssertEqual(configuration.postContext(for: replyItems[0])?.replyShortcutCount, 5)
    }

    func testExpandedReplyThreadShowsAllLoadedSecondaryReplies() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let rootReply = makePost(
            id: 200,
            postNumber: 2,
            username: "bob",
            replyCount: 3,
            replyToPostNumber: 1
        )
        let child = makePost(id: 300, postNumber: 3, username: "c1", replyToPostNumber: 2)
        let grandchild = makePost(id: 400, postNumber: 4, username: "c2", replyToPostNumber: 3)
        let sibling = makePost(id: 500, postNumber: 5, username: "c3", replyToPostNumber: 2)
        let posts = [original, rootReply, child, grandchild, sibling]
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [
                makeTimelineRow(post: rootReply, parentPostNumber: 1, depth: 1),
                makeTimelineRow(post: child, parentPostNumber: 2, depth: 2),
                makeTimelineRow(post: grandchild, parentPostNumber: 3, depth: 3),
                makeTimelineRow(post: sibling, parentPostNumber: 2, depth: 2),
            ],
            contentByPostID: Dictionary(uniqueKeysWithValues: posts.map { ($0.id, makeRenderContent($0.username)) })
        )
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: posts),
            renderState: renderState,
            postLookup: Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) }),
            expandedReplyRootPostIDs: [rootReply.id]
        )

        let snapshot = configuration.makeSnapshot()
        let replyItems = snapshot.items.filter { $0.kind == .reply }

        XCTAssertEqual(replyItems.map(\.postNumber), [2, 3, 4, 5])
        XCTAssertEqual(configuration.postContext(for: replyItems[0])?.depth, 1)
        XCTAssertEqual(configuration.postContext(for: replyItems[1])?.depth, 2)
        XCTAssertEqual(configuration.postContext(for: replyItems[2])?.depth, 3)
        XCTAssertNil(configuration.postContext(for: replyItems[0])?.replyShortcutCount)
        XCTAssertEqual(configuration.postContext(for: replyItems[0])?.showsThreadLine, true)
        XCTAssertEqual(configuration.postContext(for: replyItems[1])?.showsThreadLine, true)
        XCTAssertEqual(configuration.postContext(for: replyItems[2])?.showsThreadLine, false)
        XCTAssertEqual(configuration.scrollItem(for: 3)?.id, "reply:300:3")
    }

    func testPendingSecondaryScrollTargetShowsAncestryWithoutFlatteningDepth() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let rootReply = makePost(id: 200, postNumber: 2, username: "bob", replyCount: 2, replyToPostNumber: 1)
        let child = makePost(id: 300, postNumber: 3, username: "c1", replyToPostNumber: 2)
        let grandchild = makePost(id: 400, postNumber: 4, username: "c2", replyToPostNumber: 3)
        let posts = [original, rootReply, child, grandchild]
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [
                makeTimelineRow(post: rootReply, parentPostNumber: 1, depth: 1),
                makeTimelineRow(post: child, parentPostNumber: 2, depth: 2),
                makeTimelineRow(post: grandchild, parentPostNumber: 3, depth: 3),
            ],
            contentByPostID: Dictionary(uniqueKeysWithValues: posts.map { ($0.id, makeRenderContent($0.username)) })
        )
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: posts),
            renderState: renderState,
            postLookup: Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) }),
            pendingScrollTarget: grandchild.postNumber
        )

        let replyItems = configuration.makeSnapshot().items.filter { $0.kind == .reply }

        XCTAssertEqual(replyItems.map(\.postNumber), [2, 3, 4])
        XCTAssertEqual(configuration.postContext(for: replyItems[1])?.depth, 2)
        XCTAssertEqual(configuration.postContext(for: replyItems[2])?.depth, 3)
    }

    func testLoadedSecondaryRepliesStayHiddenWithoutExpansionState() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let rootReply = makePost(id: 200, postNumber: 2, username: "bob", replyCount: 4, replyToPostNumber: 1)
        let secondaryReplies = [
            makePost(id: 300, postNumber: 3, username: "c1", replyToPostNumber: 2),
            makePost(id: 400, postNumber: 4, username: "c2", replyToPostNumber: 2),
            makePost(id: 500, postNumber: 5, username: "c3", replyToPostNumber: 2),
            makePost(id: 600, postNumber: 6, username: "c4", replyToPostNumber: 2),
        ]
        let posts = [original, rootReply] + secondaryReplies
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: posts.dropFirst().map { post in
                makeTimelineRow(
                    post: post,
                    parentPostNumber: post.id == rootReply.id ? 1 : 2,
                    depth: post.id == rootReply.id ? 1 : 2
                )
            },
            contentByPostID: Dictionary(uniqueKeysWithValues: posts.map { ($0.id, makeRenderContent($0.username)) })
        )
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: posts),
            renderState: renderState,
            postLookup: Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
        )

        let replyItems = configuration.makeSnapshot().items.filter { $0.kind == .reply }

        XCTAssertEqual(replyItems.map(\.postNumber), [2])
        XCTAssertEqual(configuration.postContext(for: replyItems[0])?.replyShortcutCount, 4)
    }

    func testSnapshotShowsLoadMoreFooterForNonEmptyRepliesWhenMoreAvailable() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let reply = makePost(id: 200, postNumber: 2, username: "bob", replyToPostNumber: 1)
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [makeTimelineRow(post: reply, parentPostNumber: 1, depth: 1)],
            contentByPostID: [
                original.id: makeRenderContent("Original"),
                reply.id: makeRenderContent("Reply"),
            ]
        )
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: [original, reply]),
            renderState: renderState,
            postLookup: [original.id: original, reply.id: reply],
            hasMoreTopicPosts: true
        )

        let snapshot = configuration.makeSnapshot()

        XCTAssertEqual(configuration.replyFooterState, .loadMoreAvailable)
        XCTAssertEqual(snapshot.items.last?.kind, .replyFooter)
        XCTAssertEqual(
            snapshot.items.last?.contentToken.base as? String,
            FireTopicDetailRuntimeReplyFooterState.loadMoreAvailable.contentToken
        )
    }

    func testSnapshotShowsEndReachedFooterForNonEmptyRepliesWhenNoMoreAvailable() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let reply = makePost(id: 200, postNumber: 2, username: "bob", replyToPostNumber: 1)
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [makeTimelineRow(post: reply, parentPostNumber: 1, depth: 1)],
            contentByPostID: [
                original.id: makeRenderContent("Original"),
                reply.id: makeRenderContent("Reply"),
            ]
        )
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: [original, reply]),
            renderState: renderState,
            postLookup: [original.id: original, reply.id: reply]
        )

        let snapshot = configuration.makeSnapshot()

        XCTAssertEqual(configuration.replyFooterState, .endReached)
        XCTAssertEqual(snapshot.items.last?.kind, .replyFooter)
    }

    func testSnapshotShowsFailedFooterWhenLoadMoreFails() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let reply = makePost(id: 200, postNumber: 2, username: "bob", replyToPostNumber: 1)
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [makeTimelineRow(post: reply, parentPostNumber: 1, depth: 1)],
            contentByPostID: [
                original.id: makeRenderContent("Original"),
                reply.id: makeRenderContent("Reply"),
            ]
        )
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: [original, reply]),
            renderState: renderState,
            postLookup: [original.id: original, reply.id: reply],
            hasMoreTopicPosts: true,
            loadMoreTopicPostsError: "network failed"
        )

        let snapshot = configuration.makeSnapshot()

        XCTAssertEqual(configuration.replyFooterState, .loadFailed("network failed"))
        XCTAssertEqual(snapshot.items.last?.kind, .replyFooter)
    }

    func testSnapshotShowsLoadingFooterWhileLoadingMoreReplies() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let reply = makePost(id: 200, postNumber: 2, username: "bob", replyToPostNumber: 1)
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [makeTimelineRow(post: reply, parentPostNumber: 1, depth: 1)],
            contentByPostID: [
                original.id: makeRenderContent("Original"),
                reply.id: makeRenderContent("Reply"),
            ]
        )
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: [original, reply]),
            renderState: renderState,
            postLookup: [original.id: original, reply.id: reply],
            hasMoreTopicPosts: true,
            isLoadingMoreTopicPosts: true
        )

        XCTAssertEqual(configuration.replyFooterState, .loadingFooter)
        XCTAssertEqual(configuration.makeSnapshot().items.last?.kind, .replyFooter)
    }

    func testSnapshotSkipsReplyRowsMissingFromPostLookup() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let missingReply = makePost(id: 200, postNumber: 2, username: "bob", replyToPostNumber: 1)
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [makeTimelineRow(post: missingReply, parentPostNumber: 1, depth: 1)],
            contentByPostID: [
                original.id: makeRenderContent("Original"),
                missingReply.id: makeRenderContent("Reply"),
            ]
        )
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: [original, missingReply]),
            renderState: renderState,
            postLookup: [original.id: original]
        )

        let snapshot = configuration.makeSnapshot()

        XCTAssertEqual(snapshot.items.filter { $0.kind == .reply }.count, 0)
        XCTAssertNil(configuration.scrollItem(for: missingReply.postNumber))
    }

    func testOriginalPostContextUsesRenderPlainTextWhenAttributedTextIsMissing() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [],
            contentByPostID: [
                original.id: FireTopicPostRenderContent(
                    plainText: "Original plain text",
                    attributedText: nil,
                    imageAttachments: [],
                    segments: [],
                    signature: FireTopicPostRenderSignature.make(
                        source: "render-document-test-token",
                        imageAttachments: []
                    )
                )
            ]
        )
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: [original]),
            renderState: renderState,
            postLookup: [original.id: original]
        )
        let item = try? XCTUnwrap(
            configuration.makeSnapshot().items.first(where: { $0.kind == .originalPost })
        )
        let context = item.flatMap(configuration.postContext(for:))

        XCTAssertEqual(context?.renderContent.plainText, "Original plain text")
        XCTAssertNil(context?.renderContent.attributedText)
    }

    func testOriginalPostContextIsUnavailableWhileRenderStateIsPending() throws {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: [original]),
            renderState: nil,
            postLookup: [original.id: original]
        )

        let item = try XCTUnwrap(
            configuration.makeSnapshot().items.first(where: { $0.kind == .originalPost })
        )

        XCTAssertNil(configuration.postContext(for: item))
    }

    func testOriginalPostContextDoesNotShowInlineDivider() throws {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [],
            contentByPostID: [
                original.id: makeRenderContent("alice"),
            ]
        )
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: [original]),
            renderState: renderState,
            postLookup: [original.id: original]
        )

        let item = try XCTUnwrap(
            configuration.makeSnapshot().items.first(where: { $0.kind == .originalPost })
        )
        let context = try XCTUnwrap(configuration.postContext(for: item))

        XCTAssertFalse(context.showsDivider)
    }

    func testRenderSignatureIsStableAndContentSensitive() throws {
        let image = FireCookedImage(
            url: try XCTUnwrap(URL(string: "https://linux.do/uploads/default/original/1x/image.png")),
            altText: "sample",
            width: 120,
            height: 80
        )

        let first = FireTopicPostRenderSignature.make(source: "<p>Hello</p>", imageAttachments: [image])
        let second = FireTopicPostRenderSignature.make(source: "<p>Hello</p>", imageAttachments: [image])
        let changedText = FireTopicPostRenderSignature.make(source: "<p>Hello!</p>", imageAttachments: [image])
        let changedImages = FireTopicPostRenderSignature.make(source: "<p>Hello</p>", imageAttachments: [])

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.token, second.token)
        XCTAssertNotEqual(first, changedText)
        XCTAssertNotEqual(first, changedImages)
    }

    func testItemsHaveSameRenderedContentMatchesOnlyEquivalentSnapshots() {
        let item = makeRuntimeItem(contentToken: "render-a", replyIndex: 0)
        let same = makeRuntimeItem(contentToken: "render-a", replyIndex: 0)
        let changedToken = makeRuntimeItem(contentToken: "render-b", replyIndex: 0)
        let changedReplyIndex = makeRuntimeItem(contentToken: "render-a", replyIndex: 1)

        XCTAssertTrue(fireTopicDetailItemsHaveSameRenderedContent([item], [same]))
        XCTAssertFalse(fireTopicDetailItemsHaveSameRenderedContent([item], [changedToken]))
        XCTAssertFalse(fireTopicDetailItemsHaveSameRenderedContent([item], [changedReplyIndex]))
        XCTAssertFalse(fireTopicDetailItemsHaveSameRenderedContent([item], [item, same]))
    }

    func testSnapshotReuseRequiresCurrentItemsAndMatchingInvalidationToken() {
        XCTAssertTrue(fireTopicDetailCanReuseCurrentSnapshot(
            previousInvalidationToken: AnyHashable("a"),
            nextInvalidationToken: AnyHashable("a"),
            hasCurrentItems: true
        ))
        XCTAssertFalse(fireTopicDetailCanReuseCurrentSnapshot(
            previousInvalidationToken: AnyHashable("a"),
            nextInvalidationToken: AnyHashable("b"),
            hasCurrentItems: true
        ))
        XCTAssertFalse(fireTopicDetailCanReuseCurrentSnapshot(
            previousInvalidationToken: AnyHashable("a"),
            nextInvalidationToken: AnyHashable("a"),
            hasCurrentItems: false
        ))
        XCTAssertFalse(fireTopicDetailCanReuseCurrentSnapshot(
            previousInvalidationToken: AnyHashable("a"),
            nextInvalidationToken: AnyHashable("a"),
            hasCurrentItems: true,
            itemsHaveSameRenderedContent: false
        ))
    }

    func testComposerDraftChangeDoesNotChangeFeedInvalidationToken() {
        let feedToken = FireTopicDetailFeedInvalidationToken(
            topicID: 42,
            topicCollectionRevision: 7,
            pendingScrollTarget: nil,
            detailError: "",
            detailNotice: nil,
            hasDetail: true,
            isLoadingTopic: false,
            isLoadingMoreTopicPosts: false,
            loadMoreTopicPostsError: "",
            hasMoreTopicPosts: true,
            canWriteInteractions: true,
            currentUsername: "alice",
            baseURLString: "https://linux.do",
            activeSearchPostID: nil,
            expandedReplyRootPostIDs: []
        )
        let firstComposerToken = FireTopicDetailComposerInvalidationToken(
            canWriteInteractions: true,
            typingUsernames: [],
            composerContextID: nil,
            replyDraft: "",
            quickReplyError: nil,
            isSubmittingReply: false,
            minimumReplyLength: 5
        )
        let secondComposerToken = FireTopicDetailComposerInvalidationToken(
            canWriteInteractions: true,
            typingUsernames: [],
            composerContextID: nil,
            replyDraft: "typing",
            quickReplyError: nil,
            isSubmittingReply: false,
            minimumReplyLength: 5
        )

        XCTAssertEqual(feedToken, feedToken)
        XCTAssertNotEqual(firstComposerToken, secondComposerToken)
    }

    func testChromeAndSidecarTokensAreIndependentFromFeedToken() {
        let feedToken = FireTopicDetailFeedInvalidationToken(
            topicID: 42,
            topicCollectionRevision: 3,
            pendingScrollTarget: nil,
            detailError: "",
            detailNotice: nil,
            hasDetail: true,
            isLoadingTopic: false,
            isLoadingMoreTopicPosts: false,
            loadMoreTopicPostsError: "",
            hasMoreTopicPosts: false,
            canWriteInteractions: true,
            currentUsername: "alice",
            baseURLString: "https://linux.do",
            activeSearchPostID: nil,
            expandedReplyRootPostIDs: []
        )
        let changedChromeToken = FireTopicDetailChromeInvalidationToken(
            topicID: 42,
            title: "Fire Native",
            slug: "fire-native",
            bookmarked: true,
            canWriteInteractions: true,
            canEditTopic: true,
            archetype: nil,
            notificationLevel: 3,
            baseURLString: "https://linux.do"
        )
        let loadingSidecarToken = FireTopicDetailSidecarInvalidationToken(
            topicAiSummaryToken: "",
            isLoadingTopicAiSummary: true,
            topicAiSummaryError: ""
        )
        let interactionToken = FireTopicDetailInteractionInvalidationToken(
            mutatingPostIDs: [100],
            loadingPostReplyContextIDs: [],
            expandedPostTextIDs: [300],
            expandedReplyRootPostIDs: []
        )

        XCTAssertEqual(feedToken.topicCollectionRevision, 3)
        XCTAssertTrue(changedChromeToken.bookmarked)
        XCTAssertTrue(loadingSidecarToken.isLoadingTopicAiSummary)
        XCTAssertEqual(interactionToken.mutatingPostIDs, [100])
    }

    func testAnimatedUpdatePolicyAllowsOnlySmallIdleAttachedUpdates() {
        XCTAssertTrue(fireTopicDetailAllowsAnimatedUpdate(
            isViewAttached: true,
            isScrollInteractionActive: false,
            hasCurrentItems: true,
            itemDelta: 4
        ))
        XCTAssertFalse(fireTopicDetailAllowsAnimatedUpdate(
            isViewAttached: true,
            isScrollInteractionActive: false,
            hasCurrentItems: true,
            itemDelta: 5
        ))
        XCTAssertTrue(fireTopicDetailAllowsAnimatedUpdate(
            isViewAttached: true,
            isScrollInteractionActive: false,
            hasCurrentItems: true,
            itemDelta: -4
        ))
        XCTAssertFalse(fireTopicDetailAllowsAnimatedUpdate(
            isViewAttached: true,
            isScrollInteractionActive: true,
            hasCurrentItems: true,
            itemDelta: 1
        ))
        XCTAssertFalse(fireTopicDetailAllowsAnimatedUpdate(
            isViewAttached: false,
            isScrollInteractionActive: false,
            hasCurrentItems: true,
            itemDelta: 1
        ))
        XCTAssertFalse(fireTopicDetailAllowsAnimatedUpdate(
            isViewAttached: true,
            isScrollInteractionActive: false,
            hasCurrentItems: false,
            itemDelta: 1
        ))
    }

    func testColdReloadPolicyBypassesTextureCompletionUntilFeedIsEstablished() {
        XCTAssertTrue(fireTopicDetailShouldBypassTextureReloadCompletion(
            previousItemsIsEmpty: true,
            isViewAttached: true
        ))
        XCTAssertTrue(fireTopicDetailShouldBypassTextureReloadCompletion(
            previousItemsIsEmpty: false,
            isViewAttached: false
        ))
        XCTAssertFalse(fireTopicDetailShouldBypassTextureReloadCompletion(
            previousItemsIsEmpty: false,
            isViewAttached: true
        ))
    }

    func testImageRequestBuilderUsesSharedAvatarResolution() {
        let request = FireTopicImageRequestBuilder.avatarRequest(
            avatarTemplate: "/user_avatar/linux.do/alice/{size}/1_2.png",
            username: "alice",
            depth: 0,
            baseURLString: "https://linux.do"
        )
        XCTAssertEqual(
            request?.url.absoluteString,
            "https://linux.do/user_avatar/linux.do/alice/384/1_2.png"
        )
    }

    func testSnapshotIncludesDetailNoticeAheadOfReplies() {
        let original = makePost(id: 100, postNumber: 1, username: "alice")
        let reply = makePost(id: 200, postNumber: 2, username: "bob", replyToPostNumber: 1)
        let renderState = FireTopicDetailRenderState(
            originalRow: makeTimelineRow(post: original, depth: 0, isOriginalPost: true),
            replyRows: [makeTimelineRow(post: reply, parentPostNumber: 1, depth: 1)],
            contentByPostID: [
                original.id: makeRenderContent("Original"),
                reply.id: makeRenderContent("Reply"),
            ]
        )
        let notice = FireTopicDetailStatusMessage(
            title: nil,
            message: "刷新失败，正在显示缓存内容。",
            retryable: true,
            emphasizesError: false
        )
        let configuration = makeConfiguration(
            detail: makeTopicDetail(posts: [original, reply]),
            renderState: renderState,
            postLookup: [original.id: original, reply.id: reply],
            detailNotice: notice
        )

        let snapshot = configuration.makeSnapshot()
        let noticeIndex = snapshot.items.firstIndex { $0.kind == .notice }
        let replyIndex = snapshot.items.firstIndex { $0.kind == .reply }

        XCTAssertNotNil(noticeIndex)
        XCTAssertNotNil(replyIndex)
        XCTAssertLessThan(noticeIndex ?? .max, replyIndex ?? .min)
        XCTAssertEqual(snapshot.items[noticeIndex!].statusMessage, notice)
    }

    private func makeRuntimeItem(
        contentToken: String,
        replyIndex: Int?
    ) -> FireTopicDetailRuntimeItem {
        FireTopicDetailRuntimeItem(
            id: "reply:200:2",
            kind: .reply,
            postID: 200,
            postNumber: 2,
            replyIndex: replyIndex,
            contentToken: AnyHashable(contentToken)
        )
    }

    private func makeConfiguration(
        detail: TopicDetailState?,
        renderState: FireTopicDetailRenderState?,
        postLookup: [UInt64: TopicPostState],
        pendingScrollTarget: UInt32? = nil,
        detailNotice: FireTopicDetailStatusMessage? = nil,
        hasMoreTopicPosts: Bool = false,
        isLoadingMoreTopicPosts: Bool = false,
        loadMoreTopicPostsError: String? = nil,
        expandedReplyRootPostIDs: Set<UInt64> = []
    ) -> FireTopicDetailRuntimeConfiguration {
        let interactionState = FireTopicDetailInteractionState(
            mutatingPostIDs: [],
            loadingPostReplyContextIDs: [],
            expandedPostTextIDs: [],
            expandedReplyRootPostIDs: expandedReplyRootPostIDs
        )
        return FireTopicDetailRuntimeConfiguration(
            viewModel: nil,
            displayedCategory: nil,
            currentUsername: nil,
            row: makeTopicRow(),
            baseURLString: "https://linux.do",
            detail: detail,
            renderState: renderState,
            pendingScrollTarget: pendingScrollTarget,
            detailError: nil,
            detailNotice: detailNotice,
            hasMoreTopicPosts: hasMoreTopicPosts,
            isLoadingTopic: false,
            isLoadingMoreTopicPosts: isLoadingMoreTopicPosts,
            loadMoreTopicPostsError: loadMoreTopicPostsError,
            topicAiSummary: nil,
            isLoadingTopicAiSummary: false,
            topicAiSummaryError: nil,
            topicCollectionRevision: 1,
            canWriteInteractions: true,
            postLookup: postLookup,
            interactionState: interactionState,
            activeSearchPostID: nil,
            snapshotInvalidationToken: AnyHashable("test"),
            interactions: FireTopicDetailRuntimeInteractions(
                isMutatingPost: { _ in false },
                isPostTextExpanded: { _ in false },
                isReplyThreadExpanded: { expandedReplyRootPostIDs.contains($0) },
                isLoadingPostReplyContext: { _ in false },
                onVisiblePostNumbersChanged: { _ in },
                onRefresh: {},
                onLoadTopicDetail: {},
                onScrollTargetHandled: { _ in },
                onLoadMoreTopicPosts: { true },
                onReloadTopicAiSummary: {},
                onOpenComposer: { _ in },
                onOpenPostNumber: { _ in },
                onOpenPostReplies: { _ in },
                onLinkTapped: { _ in },
                onOpenProfile: { _ in },
                onOpenImage: { _ in },
                onToggleLike: { _ in },
                onSelectReaction: { _, _ in },
                onOpenReactionPicker: { _ in },
                onQuotePost: { _ in },
                onEditPost: { _ in },
                onBookmarkPost: { _ in },
                onDeletePost: { _ in },
                onRecoverPost: { _ in },
                onFlagPost: { _ in },
                onExpandPostText: { _ in },
                onVotePoll: { _, _, _ in },
                onUnvotePoll: { _, _ in },
                onToggleTopicVote: {},
                onShowTopicVoters: {},
                onOpenCategory: { _ in },
                onOpenTag: { _ in }
            )
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

    private func makeTopicDetail(
        posts: [TopicPostState],
        canVote: Bool = false,
        voteCount: Int32 = 0,
        userVoted: Bool = false
    ) -> TopicDetailState {
        TopicDetailState(
            id: 42,
            messageBusLastId: nil,
            title: "Fire Native",
            slug: "fire-native",
            postsCount: UInt32(posts.count),
            replyCount: UInt32(max(posts.count - 1, 0)),
            categoryId: 7,
            tags: [],
            views: 128,
            likeCount: 9,
            createdAt: "2026-03-28T10:00:00Z",
            highestPostNumber: UInt32(posts.map(\.postNumber).max() ?? UInt32(posts.count)),
            lastReadPostNumber: nil,
            bookmarks: [],
            bookmarked: false,
            bookmarkId: nil,
            bookmarkName: nil,
            bookmarkReminderAt: nil,
            acceptedAnswer: false,
            hasAcceptedAnswer: false,
            canVote: canVote,
            voteCount: voteCount,
            userVoted: userVoted,
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
            highestPostNumber: replyCount + 1,
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
        likeCount: UInt32 = 0,
        replyCount: UInt32 = 0,
        reactions: [TopicReactionState] = [],
        replyToPostNumber: UInt32? = nil
    ) -> TopicPostState {
        let cooked = "<p>\(username)</p>"
        return TopicPostState(
            id: id,
            username: username,
            name: nil,
            avatarTemplate: nil,
            authorMetadata: fireEmptyPostAuthorMetadataState(),
            cooked: cooked,
            renderDocument: renderCookedHtml(rawHtml: cooked, baseUrl: "https://linux.do"),
            raw: username,
            postNumber: postNumber,
            postType: 1,
            createdAt: "2026-03-28T10:00:00Z",
            updatedAt: "2026-03-28T10:00:00Z",
            likeCount: likeCount,
            replyCount: replyCount,
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
        FireTopicPostRenderContent(
            plainText: plainText,
            attributedText: nil,
            imageAttachments: [],
            segments: [],
            signature: FireTopicPostRenderSignature.make(source: plainText, imageAttachments: [])
        )
    }
}
