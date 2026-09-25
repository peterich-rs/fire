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
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import uniffi.fire_uniffi_types.TopicListKindState
import uniffi.fire_uniffi_types.TopicRowState

class PrivateMessagesViewModel(
    private val topicRepository: TopicRepository,
) : ViewModel() {

    private val _selectedKind = MutableStateFlow(TopicListKindState.PRIVATE_MESSAGES_INBOX)
    val selectedKind = _selectedKind.asStateFlow()

    @OptIn(ExperimentalCoroutinesApi::class)
    val pmPagingFlow: Flow<PagingData<TopicRowState>> = _selectedKind
        .flatMapLatest { kind ->
            Pager(
                config = PagingConfig(
                    pageSize = 30,
                    prefetchDistance = 10,
                    enablePlaceholders = false,
                ),
                pagingSourceFactory = {
                    TopicListPagingSource(topicRepository, kind)
                },
            ).flow
        }
        .cachedIn(viewModelScope)

    fun selectKind(kind: TopicListKindState) {
        if (_selectedKind.value == kind) return
        _selectedKind.value = kind
    }

    companion object {
        fun create(sessionStore: FireSessionStore): PrivateMessagesViewModel {
            val repo = TopicRepository(sessionStore)
            return PrivateMessagesViewModel(repo)
        }
    }
}
