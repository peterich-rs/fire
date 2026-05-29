package com.fire.app.data.paging

import androidx.paging.PagingSource
import androidx.paging.PagingState
import com.fire.app.data.repository.NotificationRepository
import uniffi.fire_uniffi_notifications.NotificationItemState

class NotificationPagingSource(
    private val repository: NotificationRepository,
) : PagingSource<UInt, NotificationItemState>() {

    override fun getRefreshKey(state: PagingState<UInt, NotificationItemState>): UInt? {
        return null
    }

    override suspend fun load(params: LoadParams<UInt>): LoadResult<UInt, NotificationItemState> {
        val offset = when (params) {
            is LoadParams.Refresh -> params.key ?: 0u
            is LoadParams.Append -> params.key
            is LoadParams.Prepend -> return LoadResult.Page(emptyList(), null, null)
        }

        return try {
            val result = repository.fetchNotifications(
                limit = minOf(params.loadSize, API_PAGE_SIZE).toUInt(),
                offset = offset.takeIf { it > 0u },
            )
            LoadResult.Page(
                data = result.notifications,
                prevKey = null,
                nextKey = result.nextOffset,
            )
        } catch (e: Exception) {
            LoadResult.Error(e)
        }
    }

    private companion object {
        const val API_PAGE_SIZE = 60
    }
}
