package com.fire.app.data.paging

import androidx.paging.PagingSource
import androidx.paging.PagingState
import com.fire.app.session.FireSessionStore
import uniffi.fire_uniffi_types.TopicRowState

class ReadHistoryPagingSource(
    private val sessionStore: FireSessionStore,
) : PagingSource<UInt, TopicRowState>() {

    override fun getRefreshKey(state: PagingState<UInt, TopicRowState>): UInt? {
        return null
    }

    override suspend fun load(params: LoadParams<UInt>): LoadResult<UInt, TopicRowState> {
        val page = params.key ?: 0u
        return try {
            val response = sessionStore.fetchReadHistory(page.takeIf { it > 0u })
            LoadResult.Page(
                data = response.rows,
                prevKey = if (page == 0u) null else page - 1u,
                nextKey = response.nextPage,
            )
        } catch (error: Exception) {
            LoadResult.Error(error)
        }
    }
}
