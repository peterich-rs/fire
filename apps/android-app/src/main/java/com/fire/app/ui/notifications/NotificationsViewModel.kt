package com.fire.app.ui.notifications

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.paging.Pager
import androidx.paging.PagingConfig
import androidx.paging.PagingData
import androidx.paging.cachedIn
import com.fire.app.FireApplication
import com.fire.app.core.error.FireErrorReporter
import com.fire.app.data.paging.NotificationPagingSource
import com.fire.app.data.repository.NotificationRepository
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireStateObserverRepository
import com.fire.app.widget.FireWidgetData
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_notifications.NotificationCenterState
import uniffi.fire_uniffi_notifications.NotificationItemState

class NotificationsViewModel(
    private val repository: NotificationRepository,
    private val sessionStore: FireSessionStore,
) : ViewModel() {

    private val _notificationCenter = MutableStateFlow<NotificationCenterState?>(null)
    val notificationCenter = _notificationCenter.asStateFlow()

    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing = _isRefreshing.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    private val _isRecentOffline = MutableStateFlow(false)
    val isRecentOffline = _isRecentOffline.asStateFlow()

    private val _isFullOffline = MutableStateFlow(false)
    val isFullOffline = _isFullOffline.asStateFlow()

    val isOffline = combine(_isRecentOffline, _isFullOffline) { recent, full ->
        recent || full
    }.stateIn(viewModelScope, SharingStarted.Eagerly, false)

    private var initialRefreshStarted = false

    private val pagingFlow: Flow<PagingData<NotificationItemState>> = Pager(
        config = PagingConfig(
            pageSize = 20,
            prefetchDistance = 5,
            initialLoadSize = 20,
            enablePlaceholders = false,
        ),
        pagingSourceFactory = {
            NotificationPagingSource(
                repository = repository,
                onPageLoaded = ::handleNotificationPageLoaded,
            )
        },
    ).flow.cachedIn(viewModelScope)

    init {
        viewModelScope.launch {
            FireStateObserverRepository.notificationCenterSnapshots.collect { snapshot ->
                applyNotificationCenter(snapshot)
            }
        }
    }

    fun notificationPagingFlow(): Flow<PagingData<NotificationItemState>> {
        return pagingFlow
    }

    fun markAllRead() {
        viewModelScope.launch {
            try {
                val state = repository.markNotificationsRead()
                applyNotificationCenter(state)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                handleError(e)
            }
        }
    }

    fun markRead(id: ULong) {
        viewModelScope.launch {
            try {
                val state = repository.markNotificationRead(id)
                applyNotificationCenter(state)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                handleError(e)
            }
        }
    }

    fun refreshNotificationCenter() {
        viewModelScope.launch {
            try {
                val state = repository.fetchNotificationState()
                applyNotificationCenter(state)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                handleError(e)
            }
        }
    }

    fun refreshRecentNotifications(force: Boolean = false) {
        if (!force && initialRefreshStarted) return
        if (!force) {
            initialRefreshStarted = true
        }
        viewModelScope.launch {
            _isRefreshing.value = true
            try {
                val recent = repository.fetchRecentNotifications()
                _isRecentOffline.value = recent.isCached
                applyNotificationCenter(repository.fetchNotificationState())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!force) {
                    initialRefreshStarted = false
                }
                handleError(e)
            } finally {
                _isRefreshing.value = false
            }
        }
    }

    fun prepareNotificationRefresh() {
        _isRecentOffline.value = false
        _isFullOffline.value = false
    }

    fun prepareFullNotificationRefresh() {
        _isFullOffline.value = false
    }

    private fun applyNotificationCenter(state: NotificationCenterState) {
        _notificationCenter.value = state
        _isRecentOffline.value = state.recentIsCached
        _isFullOffline.value = state.fullIsCached
        _error.value = null
        viewModelScope.launch {
            val session = runCatching { sessionStore.snapshot() }.getOrNull()
            FireWidgetData.updateNotificationState(
                context = FireApplication.getInstance(),
                state = state,
                session = session,
            )
        }
    }

    private fun handleNotificationPageLoaded(offset: UInt, isCached: Boolean) {
        if (offset == 0u) {
            _isFullOffline.value = isCached
        } else if (isCached) {
            _isFullOffline.value = true
        }
    }

    private fun handleError(error: Exception) {
        val reported = FireErrorReporter.report(
            operation = "notifications.action",
            error = error,
            sessionStore = sessionStore,
        )
        _error.value = reported.displayMessage
    }

    companion object {
        fun create(sessionStore: FireSessionStore): NotificationsViewModel {
            val repo = NotificationRepository(sessionStore)
            return NotificationsViewModel(repo, sessionStore)
        }
    }
}
