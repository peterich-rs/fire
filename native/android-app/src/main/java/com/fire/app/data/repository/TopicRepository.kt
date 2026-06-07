package com.fire.app.data.repository

import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.fire_uniffi_topics.LoadMoreTopicPostsQueryState
import uniffi.fire_uniffi_topics.TopicListQueryState
import uniffi.fire_uniffi_topics.TopicDetailPageState
import uniffi.fire_uniffi_topics.TopicDetailSourceQueryState
import uniffi.fire_uniffi_topics.TopicDetailSourceSnapshotState
import uniffi.fire_uniffi_topics.TopicLoadMoreOutcomeState
import uniffi.fire_uniffi_topics.TopicAiSummaryState
import uniffi.fire_uniffi_topics.TopicSourceCursorState
import uniffi.fire_uniffi_types.TopicListKindState
import uniffi.fire_uniffi_types.TopicListState
import uniffi.fire_uniffi_types.TopicRowState

class TopicRepository(private val sessionStore: FireSessionStore) {

    suspend fun fetchTopicList(
        kind: TopicListKindState = TopicListKindState.LATEST,
        page: UInt? = null,
        categorySlug: String? = null,
        categoryId: ULong? = null,
        parentCategorySlug: String? = null,
        tag: String? = null,
        additionalTags: List<String> = emptyList(),
        matchAllTags: Boolean = false,
        topicIds: List<ULong> = emptyList(),
    ): TopicListState = withContext(Dispatchers.Default) {
        sessionStore.fetchTopicList(
            TopicListQueryState(
                kind = kind,
                page = page,
                topicIds = topicIds,
                order = null,
                ascending = null,
                categorySlug = categorySlug,
                categoryId = categoryId,
                parentCategorySlug = parentCategorySlug,
                tag = tag,
                additionalTags = additionalTags,
                matchAllTags = matchAllTags,
            ),
        )
    }

    suspend fun fetchTopicDetailSourceSnapshot(
        topicId: ULong,
        targetPostNumber: UInt? = null,
        forceLoad: Boolean = true,
        trackVisit: Boolean = true,
        initialBatchSize: UShort = 40u,
        loadMoreBatchSize: UShort = 40u,
        maxAutoBatchesPerGesture: UByte = 3u,
        maxAutoPostsPerGesture: UShort = 120u,
    ): TopicDetailSourceSnapshotState = withContext(Dispatchers.Default) {
        sessionStore.fetchTopicDetailSourceSnapshot(
            TopicDetailSourceQueryState(
                topicId = topicId,
                targetPostNumber = targetPostNumber,
                trackVisit = trackVisit,
                forceLoad = forceLoad,
                initialBatchSize = initialBatchSize,
                loadMoreBatchSize = loadMoreBatchSize,
                maxAutoBatchesPerGesture = maxAutoBatchesPerGesture,
                maxAutoPostsPerGesture = maxAutoPostsPerGesture,
            ),
        )
    }

    suspend fun fetchTopicDetailPage(
        topicId: ULong,
        targetPostNumber: UInt? = null,
        forceLoad: Boolean = true,
        trackVisit: Boolean = true,
        initialBatchSize: UShort = 40u,
        loadMoreBatchSize: UShort = 40u,
        maxAutoBatchesPerGesture: UByte = 3u,
        maxAutoPostsPerGesture: UShort = 120u,
    ): TopicDetailPageState = withContext(Dispatchers.Default) {
        sessionStore.fetchTopicDetailPage(
            TopicDetailSourceQueryState(
                topicId = topicId,
                targetPostNumber = targetPostNumber,
                trackVisit = trackVisit,
                forceLoad = forceLoad,
                initialBatchSize = initialBatchSize,
                loadMoreBatchSize = loadMoreBatchSize,
                maxAutoBatchesPerGesture = maxAutoBatchesPerGesture,
                maxAutoPostsPerGesture = maxAutoPostsPerGesture,
            ),
        )
    }

    suspend fun loadMoreTopicPosts(
        cursor: TopicSourceCursorState,
    ): TopicLoadMoreOutcomeState = withContext(Dispatchers.Default) {
        sessionStore.loadMoreTopicPosts(
            LoadMoreTopicPostsQueryState(cursor = cursor),
        )
    }

    suspend fun fetchTopicAiSummary(
        topicId: ULong,
        skipAgeCheck: Boolean = false,
    ): TopicAiSummaryState? = withContext(Dispatchers.Default) {
        sessionStore.fetchTopicAiSummary(topicId, skipAgeCheck)
    }

    suspend fun fetchBookmarks(username: String, page: UInt? = null): TopicListState =
        withContext(Dispatchers.Default) {
            sessionStore.fetchBookmarks(username, page)
        }

    suspend fun fetchReadHistory(page: UInt? = null): TopicListState =
        withContext(Dispatchers.Default) {
            sessionStore.fetchReadHistory(page)
        }
}
