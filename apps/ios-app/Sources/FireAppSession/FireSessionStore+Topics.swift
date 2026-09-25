import Foundation

extension FireSessionStore {
    public nonisolated func cancelTopicDetailHttp() {
        try? core.topics().cancelTopicDetailHttp()
    }

    public nonisolated func closeAllTopicDetailSessions() {
        try? core.topics().closeAllTopicDetailSessions()
    }

    public nonisolated func openTopicDetail(
        request: TopicDetailOpenRequestState,
        observer: TopicDetailObserver
    ) throws -> TopicDetailSessionHandle {
        try core.topics().openTopicDetail(request: request, observer: observer)
    }

    public func fetchReadHistory(page: UInt32? = nil) async throws -> TopicListState {
        try await runPersistingSessionChanges {
            try await core.notifications().fetchReadHistory(page: page)
        }
    }

    public func fetchTopicList(query: TopicListQueryState) async throws -> TopicListState {
        try await runPersistingSessionChanges {
            try await core.topics().fetchTopicList(query: query)
        }
    }

    public func fetchTopicList(kind: TopicListKindState) async throws -> TopicListState {
        try await fetchTopicList(
            query: TopicListQueryState(
                kind: kind,
                page: nil,
                topicIds: [],
                order: nil,
                ascending: nil,
                categorySlug: nil,
                categoryId: nil,
                parentCategorySlug: nil,
                tag: nil,
                additionalTags: [],
                matchAllTags: false
            )
        )
    }

    public func fetchTopicPosts(topicID: UInt64, postIDs: [UInt64]) async throws -> [TopicPostState] {
        try await runPersistingSessionChanges {
            try await core.topics().fetchTopicPosts(topicId: topicID, postIds: postIDs)
        }
    }

    public func fetchTopicAiSummary(
        topicID: UInt64,
        skipAgeCheck: Bool = false
    ) async throws -> TopicAiSummaryState? {
        try await runPersistingSessionChanges {
            try await core.topics().fetchTopicAiSummary(
                topicId: topicID,
                skipAgeCheck: skipAgeCheck
            )
        }
    }

    public func fetchPost(postID: UInt64) async throws -> TopicPostState {
        try await runPersistingSessionChanges {
            try await core.topics().fetchPost(postId: postID)
        }
    }

    public func fetchPostReplyIds(postID: UInt64) async throws -> [UInt64] {
        try await runPersistingSessionChanges {
            try await core.topics().fetchPostReplyIds(postId: postID)
        }
    }

    public func fetchPostReplyHistory(postID: UInt64) async throws -> [TopicPostState] {
        try await runPersistingSessionChanges {
            try await core.topics().fetchPostReplyHistory(postId: postID)
        }
    }
}
