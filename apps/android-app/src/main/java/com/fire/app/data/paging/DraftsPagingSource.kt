package com.fire.app.data.paging

import androidx.paging.PagingSource
import androidx.paging.PagingState
import com.fire.app.session.FireSessionStore
import uniffi.fire_uniffi_types.DraftState

class DraftsPagingSource(
    private val sessionStore: FireSessionStore,
) : PagingSource<UInt, DraftState>() {

    override fun getRefreshKey(state: PagingState<UInt, DraftState>): UInt? {
        return null
    }

    override suspend fun load(params: LoadParams<UInt>): LoadResult<UInt, DraftState> {
        val offset = when (params) {
            is LoadParams.Refresh -> params.key ?: 0u
            is LoadParams.Append -> params.key
            is LoadParams.Prepend -> return LoadResult.Page(emptyList(), null, null)
        }

        return try {
            val pageSize = minOf(params.loadSize, API_PAGE_SIZE)
            val response = sessionStore.fetchDrafts(
                offset = offset.takeIf { it > 0u },
                limit = pageSize.toUInt(),
            )
            val nextOffset = if (response.hasMore && response.drafts.isNotEmpty()) {
                offset + response.drafts.size.toUInt()
            } else {
                null
            }
            LoadResult.Page(
                data = response.drafts,
                prevKey = null,
                nextKey = nextOffset,
            )
        } catch (error: Exception) {
            LoadResult.Error(error)
        }
    }

    private companion object {
        const val API_PAGE_SIZE = 30
    }
}
