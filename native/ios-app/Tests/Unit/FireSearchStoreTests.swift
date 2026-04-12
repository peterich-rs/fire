import XCTest
@testable import Fire

final class FireSearchStoreTests: XCTestCase {
    func testMergePreservesExistingOrderAndAppendsNewIDs() {
        let existing = SearchResultState(
            posts: [makePost(id: 1), makePost(id: 2)],
            topics: [makeTopic(id: 11, views: 10)],
            users: [makeUser(id: 21, username: "alice")],
            groupedResult: makeGroupedResult()
        )
        let incoming = SearchResultState(
            posts: [makePost(id: 2), makePost(id: 3)],
            topics: [makeTopic(id: 12, views: 30)],
            users: [makeUser(id: 22, username: "bob")],
            groupedResult: makeGroupedResult(moreUsers: true)
        )

        let merged = FireSearchStore.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.posts.map(\.id), [1, 2, 3])
        XCTAssertEqual(merged.topics.map(\.id), [11, 12])
        XCTAssertEqual(merged.users.map(\.id), [21, 22])
        XCTAssertTrue(merged.groupedResult.moreUsers)
    }

    func testMergeReplacesExistingItemsWithIncomingPayload() {
        let existing = SearchResultState(
            posts: [],
            topics: [makeTopic(id: 11, views: 10)],
            users: [],
            groupedResult: makeGroupedResult()
        )
        let incoming = SearchResultState(
            posts: [],
            topics: [makeTopic(id: 11, views: 99)],
            users: [],
            groupedResult: makeGroupedResult()
        )

        let merged = FireSearchStore.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.topics.map(\.id), [11])
        XCTAssertEqual(merged.topics.first?.views, 99)
    }

    @MainActor
    func testResetClearsTransientSearchState() {
        let store = FireSearchStore(appViewModel: FireAppViewModel())
        store.query = "rust"
        store.setScope(.user)
        store.reset()

        XCTAssertEqual(store.query, "")
        XCTAssertEqual(store.scope, .all)
        XCTAssertNil(store.result)
        XCTAssertEqual(store.currentPage, 1)
        XCTAssertFalse(store.isSearching)
        XCTAssertFalse(store.isAppending)
        XCTAssertNil(store.errorMessage)
    }

    private func makeGroupedResult(
        morePosts: Bool = false,
        moreUsers: Bool = false
    ) -> GroupedSearchResultState {
        GroupedSearchResultState(
            term: "rust",
            morePosts: morePosts,
            moreUsers: moreUsers,
            moreCategories: false,
            moreFullPageResults: false,
            searchLogId: nil
        )
    }

    private func makePost(id: UInt64) -> SearchPostState {
        SearchPostState(
            id: id,
            topicId: 100 + id,
            username: "user\(id)",
            avatarTemplate: nil,
            createdAt: nil,
            createdTimestampUnixMs: nil,
            likeCount: 0,
            blurb: "Post \(id)",
            postNumber: 1,
            topicTitleHeadline: "Topic \(id)"
        )
    }

    private func makeTopic(id: UInt64, views: UInt64) -> SearchTopicState {
        SearchTopicState(
            id: id,
            title: "Topic \(id)",
            slug: "topic-\(id)",
            categoryId: nil,
            tags: [],
            postsCount: 1,
            views: UInt32(views),
            closed: false,
            archived: false
        )
    }

    private func makeUser(id: UInt64, username: String) -> SearchUserState {
        SearchUserState(
            id: id,
            username: username,
            name: nil,
            avatarTemplate: nil
        )
    }
}
