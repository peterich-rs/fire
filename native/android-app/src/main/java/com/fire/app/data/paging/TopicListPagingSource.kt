package com.fire.app.data.paging

import androidx.paging.PagingSource
import androidx.paging.PagingState
import com.fire.app.data.repository.TopicRepository
import uniffi.fire_uniffi_types.TopicListKindState
import uniffi.fire_uniffi_types.TopicRowState

class TopicListPagingSource(
    private val repository: TopicRepository,
    private val kind: TopicListKindState,
    private val categorySlug: String? = null,
    private val categoryId: ULong? = null,
    private val parentCategorySlug: String? = null,
    private val tag: String? = null,
    private val additionalTags: List<String> = emptyList(),
    private val matchAllTags: Boolean = false,
    private val onPageLoaded: (page: UInt, isCached: Boolean, rows: List<TopicRowState>) -> Unit = { _, _, _ -> },
) : PagingSource<UInt, TopicRowState>() {

    override fun getRefreshKey(state: PagingState<UInt, TopicRowState>): UInt? {
        // Home only supports forward pagination. Refreshing from an anchor page
        // strands the list on that single page after an automatic invalidation.
        return null
    }

    override suspend fun load(params: LoadParams<UInt>): LoadResult<UInt, TopicRowState> {
        val page = params.key ?: 0u
        return try {
            val response = repository.fetchTopicList(
                kind = kind,
                page = params.key,
                categorySlug = categorySlug,
                categoryId = categoryId,
                parentCategorySlug = parentCategorySlug,
                tag = tag,
                additionalTags = additionalTags,
                matchAllTags = matchAllTags,
            )
            val rows = response.rows
            onPageLoaded(page, response.isCached, rows)
            LoadResult.Page(
                data = rows,
                prevKey = if (page == 0u) null else page - 1u,
                nextKey = response.nextPage,
            )
        } catch (e: Exception) {
            LoadResult.Error(e)
        }
    }
}
