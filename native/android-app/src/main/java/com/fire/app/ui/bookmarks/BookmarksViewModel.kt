package com.fire.app.ui.bookmarks

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.paging.Pager
import androidx.paging.PagingConfig
import androidx.paging.PagingData
import androidx.paging.cachedIn
import com.fire.app.data.paging.BookmarksPagingSource
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.flow.Flow
import uniffi.fire_uniffi_types.TopicRowState

class BookmarksViewModel(
    private val sessionStore: FireSessionStore,
    private val username: String,
) : ViewModel() {

    fun bookmarksPagingFlow(): Flow<PagingData<TopicRowState>> {
        return Pager(
            config = PagingConfig(
                pageSize = 30,
                prefetchDistance = 10,
                enablePlaceholders = false,
            ),
            pagingSourceFactory = { BookmarksPagingSource(sessionStore, username) },
        ).flow.cachedIn(viewModelScope)
    }

    companion object {
        fun create(sessionStore: FireSessionStore, username: String): BookmarksViewModel {
            return BookmarksViewModel(sessionStore, username)
        }
    }
}
