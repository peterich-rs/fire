package com.fire.app.data.repository

import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.fire_uniffi_topics.TopicListQueryState
import uniffi.fire_uniffi_types.TopicListKindState
import uniffi.fire_uniffi_types.TopicListState
import uniffi.fire_uniffi_types.TopicRowState

class TopicRepository(private val sessionStore: FireSessionStore) {

    suspend fun fetchTopicList(
        kind: TopicListKindState = TopicListKindState.LATEST,
        page: UInt? = null,
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
                tag = null,
                additionalTags = emptyList(),
                matchAllTags = false,
            ),
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
