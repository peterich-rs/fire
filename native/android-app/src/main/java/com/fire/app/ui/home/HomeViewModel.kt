package com.fire.app.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.paging.Pager
import androidx.paging.PagingConfig
import androidx.paging.PagingData
import androidx.paging.cachedIn
import com.fire.app.data.paging.TopicListPagingSource
import com.fire.app.data.repository.SessionRepository
import com.fire.app.data.repository.TopicRepository
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_session.SessionState
import uniffi.fire_uniffi_types.TopicListKindState
import uniffi.fire_uniffi_types.TopicRowState

class HomeViewModel(
    private val sessionRepository: SessionRepository,
    private val topicRepository: TopicRepository,
) : ViewModel() {

    private val _session = MutableStateFlow<SessionState?>(null)
    val session = _session.asStateFlow()

    private val _selectedKind = MutableStateFlow(TopicListKindState.LATEST)
    val selectedKind = _selectedKind.asStateFlow()

    private var currentPagingFlow: Flow<PagingData<TopicRowState>>? = null

    val topicListKinds = listOf(
        TopicListKindState.LATEST,
        TopicListKindState.NEW,
        TopicListKindState.UNREAD,
        TopicListKindState.UNSEEN,
        TopicListKindState.HOT,
        TopicListKindState.TOP,
    )

    fun topicPagingFlow(): Flow<PagingData<TopicRowState>> {
        val kind = _selectedKind.value
        return currentPagingFlow ?: createPagingFlow(kind).also { currentPagingFlow = it }
    }

    fun selectKind(kind: TopicListKindState) {
        if (_selectedKind.value == kind) return
        _selectedKind.value = kind
        currentPagingFlow = createPagingFlow(kind)
    }

    private fun createPagingFlow(kind: TopicListKindState): Flow<PagingData<TopicRowState>> {
        return Pager(
            config = PagingConfig(
                pageSize = 30,
                prefetchDistance = 10,
                enablePlaceholders = false,
            ),
            pagingSourceFactory = { TopicListPagingSource(topicRepository, kind) },
        ).flow.cachedIn(viewModelScope)
    }

    fun restoreSession() {
        viewModelScope.launch {
            val restored = sessionRepository.restoreSession()
            _session.value = restored
        }
    }

    fun refreshSession() {
        viewModelScope.launch {
            val snap = sessionRepository.snapshot()
            _session.value = snap
        }
    }

    fun kindDisplayName(kind: TopicListKindState): String = when (kind) {
        TopicListKindState.LATEST -> "最新"
        TopicListKindState.NEW -> "最新发布"
        TopicListKindState.UNREAD -> "未读"
        TopicListKindState.UNSEEN -> "未看"
        TopicListKindState.HOT -> "热门"
        TopicListKindState.TOP -> "精华"
        TopicListKindState.PRIVATE_MESSAGES_INBOX -> "私信"
        TopicListKindState.PRIVATE_MESSAGES_SENT -> "已发"
    }

    companion object {
        fun create(sessionStore: FireSessionStore): HomeViewModel {
            val sessionRepo = SessionRepository(sessionStore)
            val topicRepo = TopicRepository(sessionStore)
            return HomeViewModel(sessionRepo, topicRepo)
        }
    }
}
