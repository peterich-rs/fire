package com.fire.app.data.repository

import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.fire_uniffi_topics.TopicListQueryState
import uniffi.fire_uniffi_topics.TopicScreenQueryState
import uniffi.fire_uniffi_topics.TopicResponsePageQueryState
import uniffi.fire_uniffi_topics.TopicResponseCursorState
import uniffi.fire_uniffi_types.TopicListKindState
import uniffi.fire_uniffi_types.TopicListState
import uniffi.fire_uniffi_types.TopicRowState
import uniffi.fire_uniffi_topics.TopicScreenState
import uniffi.fire_uniffi_topics.TopicResponsePageState

class TopicRepository(private val sessionStore: FireSessionStore) {

    suspend fun fetchTopicList(
        kind: TopicListKindState = TopicListKindState.LATEST,
        page: UInt? = null,
        tag: String? = null,
    ): TopicListState = withContext(Dispatchers.Default) {
        sessionStore.fetchTopicList(
            TopicListQueryState(
                kind = kind,
                page = page,
                topicIds = emptyList(),
                order = null,
                ascending = null,
                categorySlug = null,
                categoryId = null,
                parentCategorySlug = null,
                tag = tag,
                additionalTags = emptyList(),
                matchAllTags = false,
            ),
        )
    }

    suspend fun fetchTopicScreen(
        topicId: ULong,
        targetPostNumber: UInt? = null,
    ): TopicScreenState = withContext(Dispatchers.Default) {
        sessionStore.fetchTopicScreen(
            TopicScreenQueryState(
                topicId = topicId,
                targetPostNumber = targetPostNumber,
                rootPageSize = 10.toUShort(),
                trackVisit = true,
            ),
        )
    }

    suspend fun fetchTopicResponsePage(
        cursor: TopicResponseCursorState,
    ): TopicResponsePageState = withContext(Dispatchers.Default) {
        sessionStore.fetchTopicResponsePage(
            TopicResponsePageQueryState(cursor = cursor),
        )
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
