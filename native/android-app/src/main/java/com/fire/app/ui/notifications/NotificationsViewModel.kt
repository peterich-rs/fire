package com.fire.app.ui.notifications

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.paging.Pager
import androidx.paging.PagingConfig
import androidx.paging.PagingData
import androidx.paging.cachedIn
import com.fire.app.cloudflare.CloudflareChallengeDetector
import com.fire.app.data.paging.NotificationPagingSource
import com.fire.app.data.repository.NotificationRepository
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_notifications.NotificationCenterState
import uniffi.fire_uniffi_notifications.NotificationItemState

class NotificationsViewModel(
    private val repository: NotificationRepository,
) : ViewModel() {

    private val _notificationCenter = MutableStateFlow<NotificationCenterState?>(null)
    val notificationCenter = _notificationCenter.asStateFlow()

    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing = _isRefreshing.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    private val _cloudflareChallenge = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val cloudflareChallenge = _cloudflareChallenge.asSharedFlow()

    private val pagingFlow: Flow<PagingData<NotificationItemState>> = Pager(
        config = PagingConfig(
            pageSize = 20,
            prefetchDistance = 5,
            initialLoadSize = 20,
            enablePlaceholders = false,
        ),
        pagingSourceFactory = { NotificationPagingSource(repository) },
    ).flow.cachedIn(viewModelScope)

    fun notificationPagingFlow(): Flow<PagingData<NotificationItemState>> {
        return pagingFlow
    }

    fun markAllRead() {
        viewModelScope.launch {
            try {
                val state = repository.markNotificationsRead()
                _notificationCenter.value = state
                _error.value = null
            } catch (e: Exception) {
                handleError(e)
            }
        }
    }

    fun markRead(id: ULong) {
        viewModelScope.launch {
            try {
                val state = repository.markNotificationRead(id)
                _notificationCenter.value = state
                _error.value = null
            } catch (e: Exception) {
                handleError(e)
            }
        }
    }

    fun refreshNotificationCenter() {
        viewModelScope.launch {
            try {
                val state = repository.fetchNotificationState()
                _notificationCenter.value = state
                _error.value = null
            } catch (e: Exception) {
                handleError(e)
            }
        }
    }

    fun refreshRecentNotifications() {
        viewModelScope.launch {
            _isRefreshing.value = true
            try {
                repository.fetchRecentNotifications()
                _notificationCenter.value = repository.fetchNotificationState()
                _error.value = null
            } catch (e: Exception) {
                handleError(e)
            } finally {
                _isRefreshing.value = false
            }
        }
    }

    private fun handleError(error: Exception) {
        if (CloudflareChallengeDetector.isChallenge(error)) {
            _cloudflareChallenge.tryEmit(Unit)
            _error.value = null
        } else {
            _error.value = error.localizedMessage
        }
    }

    companion object {
        fun create(sessionStore: FireSessionStore): NotificationsViewModel {
            val repo = NotificationRepository(sessionStore)
            return NotificationsViewModel(repo)
        }
    }
}
