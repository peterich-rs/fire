package com.fire.app.data.paging

import androidx.paging.PagingSource
import androidx.paging.PagingState
import com.fire.app.session.FireSessionStore
import uniffi.fire_uniffi_types.TopicRowState

class BookmarksPagingSource(
    private val sessionStore: FireSessionStore,
    private val username: String,
) : PagingSource<UInt, TopicRowState>() {

    override fun getRefreshKey(state: PagingState<UInt, TopicRowState>): UInt? {
        return state.anchorPosition?.let { position ->
            state.closestPageToPosition(position)?.prevKey?.plus(1u)
                ?: state.closestPageToPosition(position)?.nextKey?.minus(1u)
        }
    }

    override suspend fun load(params: LoadParams<UInt>): LoadResult<UInt, TopicRowState> {
        val page = params.key ?: 0u
        return try {
            val response = sessionStore.fetchBookmarks(username, page)
            LoadResult.Page(
                data = response.rows,
                prevKey = if (page == 0u) null else page,
                nextKey = response.nextPage,
            )
        } catch (e: Exception) {
            LoadResult.Error(e)
        }
    }
}
