package com.fire.app.ui.privatemessages

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.paging.Pager
import androidx.paging.PagingConfig
import androidx.paging.PagingData
import androidx.paging.cachedIn
import com.fire.app.data.paging.TopicListPagingSource
import com.fire.app.data.repository.TopicRepository
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.flow.Flow
import uniffi.fire_uniffi_types.TopicListKindState
import uniffi.fire_uniffi_types.TopicRowState

class PrivateMessagesViewModel(
    private val topicRepository: TopicRepository,
) : ViewModel() {

    fun pmPagingFlow(): Flow<PagingData<TopicRowState>> {
        return Pager(
            config = PagingConfig(
                pageSize = 30,
                prefetchDistance = 10,
                enablePlaceholders = false,
            ),
            pagingSourceFactory = {
                TopicListPagingSource(topicRepository, TopicListKindState.PRIVATE_MESSAGES_INBOX)
            },
        ).flow.cachedIn(viewModelScope)
    }

    companion object {
        fun create(sessionStore: FireSessionStore): PrivateMessagesViewModel {
            val repo = TopicRepository(sessionStore)
            return PrivateMessagesViewModel(repo)
        }
    }
}
