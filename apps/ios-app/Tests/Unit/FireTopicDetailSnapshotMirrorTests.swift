import XCTest
@testable import Fire

final class FireTopicDetailSnapshotMirrorTests: XCTestCase {
    func testFirstChangePullsFullSnapshot() {
        let mirror = FireTopicDetailSnapshotMirror()
        let full = makeSnapshot(generation: 1, rows: [makeRow(postId: 1, likeCount: 0)])
        let applied = mirror.apply(
            makeChange(generation: 1, baseGeneration: nil),
            source: StubSource(full)
        )

        XCTAssertEqual(applied?.generation, 1)
        XCTAssertEqual(applied?.rows.map(\.postId), [1])
        XCTAssertEqual(applied?.rowsByPostID[1]?.likeCount, 0)
    }

    func testLikeChangeUpsertsOneRow() {
        let mirror = FireTopicDetailSnapshotMirror()
        let first = makeSnapshot(generation: 1, rows: [
            makeRow(postId: 1, likeCount: 0),
            makeRow(postId: 2, likeCount: 0, isOriginalPost: false),
        ])
        _ = mirror.apply(makeChange(generation: 1, baseGeneration: nil), source: StubSource(first))

        let liked = makeRow(postId: 2, likeCount: 4, isOriginalPost: false, interactionChecksum: 99)
        let applied = mirror.apply(
            makeChange(
                generation: 2,
                baseGeneration: 1,
                upsertedRows: [liked]
            ),
            source: StubSource(first)
        )

        XCTAssertEqual(applied?.generation, 2)
        XCTAssertEqual(applied?.rows.count, 2)
        XCTAssertEqual(applied?.rowsByPostID[1]?.likeCount, 0)
        XCTAssertEqual(applied?.rowsByPostID[2]?.likeCount, 4)
        XCTAssertEqual(applied?.interactionRevision, 2)
    }

    func testComposerOnlyChangeKeepsRows() {
        let mirror = FireTopicDetailSnapshotMirror()
        let first = makeSnapshot(generation: 1, rows: [makeRow(postId: 1, likeCount: 0)])
        _ = mirror.apply(makeChange(generation: 1, baseGeneration: nil), source: StubSource(first))

        var composer = first.composer
        composer = TopicDetailComposerModelState(typingUsers: [], isSubmitting: true)
        let applied = mirror.apply(
            makeChange(
                generation: 2,
                baseGeneration: 1,
                composer: composer,
                revisions: TopicDetailRevisionsState(
                    collection: 1,
                    chrome: 1,
                    sidecar: 1,
                    interaction: 1,
                    composer: 2
                )
            ),
            source: StubSource(first)
        )

        XCTAssertEqual(applied?.composer.isSubmitting, true)
        XCTAssertEqual(applied?.rows.count, 1)
        XCTAssertEqual(applied?.composerRevision, 2)
    }

    func testStaleGenerationIsDropped() {
        let mirror = FireTopicDetailSnapshotMirror()
        let first = makeSnapshot(generation: 2, rows: [makeRow(postId: 1, likeCount: 0)])
        _ = mirror.apply(makeChange(generation: 2, baseGeneration: nil), source: StubSource(first))

        let applied = mirror.apply(
            makeChange(generation: 2, baseGeneration: 1),
            source: StubSource(first)
        )
        XCTAssertNil(applied)
    }

    func testMismatchedBaselinePullsFullSnapshot() {
        let mirror = FireTopicDetailSnapshotMirror()
        let first = makeSnapshot(generation: 1, rows: [makeRow(postId: 1, likeCount: 0)])
        _ = mirror.apply(makeChange(generation: 1, baseGeneration: nil), source: StubSource(first))

        let resync = makeSnapshot(generation: 4, rows: [
            makeRow(postId: 1, likeCount: 1),
            makeRow(postId: 3, likeCount: 0, isOriginalPost: false),
        ])
        let applied = mirror.apply(
            makeChange(generation: 4, baseGeneration: 2),
            source: StubSource(resync)
        )

        XCTAssertEqual(applied?.generation, 4)
        XCTAssertEqual(applied?.rows.map(\.postId), [1, 3])
    }

    func testMissingRowInOrderResyncs() {
        let mirror = FireTopicDetailSnapshotMirror()
        let first = makeSnapshot(generation: 1, rows: [makeRow(postId: 1, likeCount: 0)])
        _ = mirror.apply(makeChange(generation: 1, baseGeneration: nil), source: StubSource(first))

        let resync = makeSnapshot(generation: 3, rows: [
            makeRow(postId: 1, likeCount: 0),
            makeRow(postId: 2, likeCount: 0, isOriginalPost: false),
        ])
        let applied = mirror.apply(
            makeChange(
                generation: 3,
                baseGeneration: 1,
                rowOrder: [1, 2]
            ),
            source: StubSource(resync)
        )

        XCTAssertEqual(applied?.rows.map(\.postId), [1, 2])
    }
}

private struct StubSource: FireTopicDetailFullSnapshotSource {
    let snapshot: TopicDetailUiSnapshotState

    init(_ snapshot: TopicDetailUiSnapshotState) {
        self.snapshot = snapshot
    }

    func full() -> TopicDetailUiSnapshotState {
        snapshot
    }
}

private func makeChange(
    generation: UInt64,
    baseGeneration: UInt64?,
    composer: TopicDetailComposerModelState? = nil,
    upsertedRows: [TopicDetailUiRowState] = [],
    rowOrder: [UInt64]? = nil,
    revisions: TopicDetailRevisionsState = TopicDetailRevisionsState(
        collection: 1,
        chrome: 1,
        sidecar: 1,
        interaction: generation,
        composer: 1
    )
) -> TopicDetailSnapshotChangeState {
    TopicDetailSnapshotChangeState(
        topicId: 42,
        generation: generation,
        baseGeneration: baseGeneration,
        revisions: revisions,
        status: nil,
        chrome: nil,
        composer: composer,
        sidecar: nil,
        replyContext: .unchanged,
        flagTypes: nil,
        rowOrder: rowOrder,
        upsertedRows: upsertedRows,
        homeRowPatch: nil
    )
}

private func makeSnapshot(
    generation: UInt64,
    rows: [TopicDetailUiRowState]
) -> TopicDetailUiSnapshotState {
    TopicDetailUiSnapshotState(
        topicId: 42,
        generation: generation,
        phase: .ready,
        loadError: nil,
        notice: nil,
        hasMore: false,
        isLoadingMore: false,
        loadMoreError: nil,
        scrollTargetPostNumber: nil,
        collectionRevision: 1,
        chromeRevision: 1,
        sidecarRevision: 1,
        interactionRevision: 1,
        composerRevision: 1,
        chrome: TopicDetailChromeState(
            title: "topic",
            slug: "topic",
            archetype: nil,
            bookmarked: false,
            bookmarkId: nil,
            bookmarkName: nil,
            bookmarkReminderAt: nil,
            notificationLevel: nil,
            canEdit: false,
            categoryId: nil,
            tags: [],
            views: 0,
            postsCount: UInt32(rows.count),
            replyCount: UInt32(max(rows.count, 1) - 1),
            likeCount: 0,
            voteCount: 0,
            userVoted: false,
            canVote: false,
            hasAcceptedAnswer: false,
            createdAt: nil,
            highestPostNumber: rows.last?.postNumber ?? 1,
            lastReadPostNumber: nil,
            participants: [],
            summarizable: false
        ),
        composer: TopicDetailComposerModelState(typingUsers: [], isSubmitting: false),
        sidecar: TopicDetailSidecarModelState(
            summarizedText: nil,
            algorithm: nil,
            outdated: false,
            canRegenerate: false,
            newPostsSinceSummary: 0,
            updatedAt: nil,
            isLoading: false,
            error: nil
        ),
        rows: rows,
        focusedReplyContext: nil,
        flagTypes: [],
        homeRowPatch: nil
    )
}

private func makeRow(
    postId: UInt64,
    likeCount: UInt32,
    isOriginalPost: Bool = true,
    interactionChecksum: UInt64 = 1
) -> TopicDetailUiRowState {
    TopicDetailUiRowState(
        postId: postId,
        postNumber: UInt32(postId),
        rootPostNumber: 1,
        parentPostNumber: isOriginalPost ? nil : 1,
        depth: isOriginalPost ? 0 : 1,
        hasChildren: false,
        isLastSibling: true,
        descendantCount: 0,
        author: TopicDetailAuthorDisplayState(
            username: "user-\(postId)",
            name: nil,
            avatarTemplate: nil,
            userId: nil,
            userTitle: nil,
            primaryGroupName: nil,
            flairUrl: nil,
            flairName: nil,
            flairBgColor: nil,
            flairColor: nil,
            flairGroupId: nil,
            moderator: false,
            admin: false,
            groupModerator: false,
            userStatusEmoji: nil,
            userStatusDescription: nil
        ),
        presentation: nil,
        layoutChecksum: 1,
        interactionChecksum: interactionChecksum,
        authorBandChecksum: 1,
        textBandChecksum: 1,
        actionsBandChecksum: 1,
        reactionsBandChecksum: 1,
        createdAt: nil,
        updatedAt: nil,
        postType: 1,
        replyCount: 0,
        replyToUsername: nil,
        replyToUser: nil,
        likeCount: likeCount,
        reactions: [],
        currentReactionId: nil,
        polls: [],
        boosts: [],
        acceptedAnswer: false,
        canAcceptAnswer: false,
        canUnacceptAnswer: false,
        canEdit: false,
        canDelete: false,
        canRecover: false,
        canBoost: false,
        bookmarked: false,
        bookmarkId: nil,
        bookmarkName: nil,
        bookmarkReminderAt: nil,
        hidden: false,
        isMutating: false,
        isLoadingReplyContext: false,
        isOriginalPost: isOriginalPost
    )
}
