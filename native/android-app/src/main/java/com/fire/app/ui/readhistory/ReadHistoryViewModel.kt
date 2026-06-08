package com.fire.app.ui.readhistory

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.paging.Pager
import androidx.paging.PagingConfig
import androidx.paging.PagingData
import androidx.paging.cachedIn
import com.fire.app.data.paging.ReadHistoryPagingSource
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.flow.Flow
import uniffi.fire_uniffi_types.TopicRowState

class ReadHistoryViewModel(
    private val sessionStore: FireSessionStore,
) : ViewModel() {

    val readHistoryPagingFlow: Flow<PagingData<TopicRowState>> = Pager(
        config = PagingConfig(
            pageSize = 30,
            prefetchDistance = 10,
            enablePlaceholders = false,
        ),
        pagingSourceFactory = { ReadHistoryPagingSource(sessionStore) },
    ).flow.cachedIn(viewModelScope)

    companion object {
        fun create(sessionStore: FireSessionStore): ReadHistoryViewModel {
            return ReadHistoryViewModel(sessionStore)
        }
    }
}
