package com.fire.app.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.paging.Pager
import androidx.paging.PagingConfig
import androidx.paging.PagingData
import androidx.paging.cachedIn
import com.fire.app.FireApplication
import com.fire.app.core.error.FireErrorReporter
import com.fire.app.core.error.FireReportedError
import com.fire.app.core.error.launchWithFireErrorHandling
import com.fire.app.data.paging.TopicListPagingSource
import com.fire.app.data.repository.TopicRepository
import com.fire.app.messagebus.FireMessageBusCoordinator
import com.fire.app.session.FireAppStateRefreshRepository
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireStateObserverRepository
import com.fire.app.widget.FireWidgetData
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_session.HomeTopicListScopeState
import uniffi.fire_uniffi_session.RefreshBatchState
import uniffi.fire_uniffi_messagebus.MessageBusEventKindState
import uniffi.fire_uniffi_messagebus.MessageBusEventState
import uniffi.fire_uniffi_session.SessionState
import uniffi.fire_uniffi_types.TopicListKindState
import uniffi.fire_uniffi_types.TopicRowState

private data class HomeTopicFilter(
    val kind: TopicListKindState,
    val categoryId: ULong?,
    val categorySlug: String?,
    val parentCategorySlug: String?,
    val tags: List<String>,
)

internal data class HomeTopicListRefreshScope(
    val kind: TopicListKindState,
    val categoryId: ULong?,
    val tags: List<String>,
) {
    val supportsTopicScopedMessageBusRefresh: Boolean
        get() = kind == TopicListKindState.LATEST && categoryId == null && tags.isEmpty()
}

internal class HomeTopicListMessageBusRefreshController(
    private val debounceDelayMs: Long = 1_500L,
    private val minimumIntervalMs: Long = 30_000L,
) {
    private var scope: HomeTopicListRefreshScope? = null
    private var lastRefreshAtMs: Long? = null
    private val pendingTopicIds = mutableSetOf<ULong>()
    private var requiresFullRefresh = false

    fun register(
        event: MessageBusEventState,
        scope: HomeTopicListRefreshScope,
        nowMs: Long,
        allowTopicScopedRefresh: Boolean,
    ): Long? {
        prepare(scope)
        if (event.kind != MessageBusEventKindState.TOPIC_LIST || event.topicListKind != scope.kind) {
            return null
        }

        if (allowTopicScopedRefresh &&
            scope.supportsTopicScopedMessageBusRefresh &&
            event.topicId != null &&
            event.messageType?.equals("latest", ignoreCase = true) == true
        ) {
            event.topicId?.let { pendingTopicIds += it }
        } else {
            requiresFullRefresh = true
        }

        return scheduledDelay(nowMs)
    }

    fun takePendingRefresh(scope: HomeTopicListRefreshScope): Boolean {
        prepare(scope)
        if (requiresFullRefresh) {
            requiresFullRefresh = false
            pendingTopicIds.clear()
            return true
        }
        if (pendingTopicIds.isEmpty()) {
            return false
        }
        pendingTopicIds.clear()
        return true
    }

    fun markRefreshCompleted(scope: HomeTopicListRefreshScope, nowMs: Long) {
        prepare(scope)
        lastRefreshAtMs = nowMs
    }

    fun clearPending(scope: HomeTopicListRefreshScope) {
        prepare(scope)
        pendingTopicIds.clear()
        requiresFullRefresh = false
    }

    private fun prepare(nextScope: HomeTopicListRefreshScope) {
        if (scope == nextScope) return
        scope = nextScope
        lastRefreshAtMs = null
        pendingTopicIds.clear()
        requiresFullRefresh = false
    }

    private fun scheduledDelay(nowMs: Long): Long {
        val last = lastRefreshAtMs ?: return debounceDelayMs
        val elapsed = nowMs - last
        return maxOf(debounceDelayMs, minimumIntervalMs - elapsed)
    }
}

class HomeViewModel(
    private val topicRepository: TopicRepository,
    private val messageBusCoordinator: FireMessageBusCoordinator,
    private val sessionStore: FireSessionStore,
) : ViewModel() {

    private val _session = MutableStateFlow<SessionState?>(null)
    val session = _session.asStateFlow()

    private val _selectedKind = MutableStateFlow(TopicListKindState.LATEST)
    val selectedKind = _selectedKind.asStateFlow()

    private val _selectedCategoryId = MutableStateFlow<ULong?>(null)
    val selectedCategoryId = _selectedCategoryId.asStateFlow()

    private val _selectedTags = MutableStateFlow<List<String>>(emptyList())
    val selectedTags = _selectedTags.asStateFlow()

    private val _topicListRefreshEvents = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val topicListRefreshEvents = _topicListRefreshEvents.asSharedFlow()

    private val _error = MutableSharedFlow<String>(extraBufferCapacity = 1)
    val error = _error.asSharedFlow()

    private val _isOffline = MutableStateFlow(false)
    val isOffline = _isOffline.asStateFlow()

    val topicListKinds = listOf(
        TopicListKindState.LATEST,
        TopicListKindState.NEW,
        TopicListKindState.UNREAD,
        TopicListKindState.UNSEEN,
        TopicListKindState.HOT,
        TopicListKindState.TOP,
    )

    @OptIn(ExperimentalCoroutinesApi::class)
    val topicPagingFlow: Flow<PagingData<TopicRowState>> =
        combine(_selectedKind, _selectedCategoryId, _selectedTags, _session) { kind, categoryId, tags, session ->
            val categories = session?.bootstrap?.categories.orEmpty()
            val category = categories.firstOrNull { it.id == categoryId }
            val parentCategory = category?.parentCategoryId?.let { parentId ->
                categories.firstOrNull { it.id == parentId }
            }
            HomeTopicFilter(
                kind = kind,
                categoryId = category?.id,
                categorySlug = category?.slug?.takeIf { it.isNotBlank() },
                parentCategorySlug = parentCategory?.slug?.takeIf { it.isNotBlank() },
                tags = tags,
            )
        }
            .distinctUntilChanged()
            .flatMapLatest { filter -> createPagingFlow(filter) }
            .cachedIn(viewModelScope)

    private val topicListMessageBusRefreshController = HomeTopicListMessageBusRefreshController()
    private var messageBusJob: Job? = null
    private var pendingMessageBusRefreshJob: Job? = null

    init {
        runCatching { sessionStore.currentHomeTopicListScope() }
            .onSuccess(::applyCurrentHomeTopicListScope)
            .onFailure(::reportHomeScopeSyncError)

        viewModelScope.launchWithFireErrorHandling(
            operation = "home.attach_authoritative_session",
            sessionStore = sessionStore,
            fallbackMessage = "刷新会话失败",
            onError = ::handleReportedError,
        ) {
            val snapshot = sessionStore.snapshot()
            _session.value = snapshot
            if (snapshot.readiness.canOpenMessageBus) {
                startRealtimeRefresh()
            }
        }

        viewModelScope.launch {
            FireStateObserverRepository.sessionSnapshots.collectLatest { snapshot ->
                _session.value = snapshot
            }
        }

        viewModelScope.launch {
            FireAppStateRefreshRepository.events.collectLatest { event ->
                try {
                    handleAppStateRefreshEvent(event.batch)
                } catch (error: Exception) {
                    val reported = FireErrorReporter.report(
                        operation = "home.app_state_refresh",
                        error = error,
                        sessionStore = sessionStore,
                    )
                    handleReportedError(reported)
                }
            }
        }
    }

    fun selectKind(kind: TopicListKindState) {
        if (_selectedKind.value == kind) return
        _selectedKind.value = kind
        _isOffline.value = false
        clearPendingMessageBusRefresh()
        syncCurrentHomeTopicListScope()
    }

    fun selectCategory(categoryId: ULong?) {
        if (_selectedCategoryId.value == categoryId) return
        _selectedCategoryId.value = categoryId
        _selectedTags.value = emptyList()
        _isOffline.value = false
        clearPendingMessageBusRefresh()
        syncCurrentHomeTopicListScope()
    }

    fun selectTag(tag: String) {
        val normalizedTag = tag.trim().removePrefix("#").takeIf { it.isNotBlank() } ?: return
        if (_selectedTags.value.contains(normalizedTag)) return
        _selectedTags.value = _selectedTags.value + normalizedTag
        _isOffline.value = false
        clearPendingMessageBusRefresh()
        syncCurrentHomeTopicListScope()
    }

    fun removeTag(tag: String) {
        if (!_selectedTags.value.contains(tag)) return
        _selectedTags.value = _selectedTags.value.filterNot { it == tag }
        _isOffline.value = false
        clearPendingMessageBusRefresh()
        syncCurrentHomeTopicListScope()
    }

    fun clearTags() {
        if (_selectedTags.value.isEmpty()) return
        _selectedTags.value = emptyList()
        _isOffline.value = false
        clearPendingMessageBusRefresh()
        syncCurrentHomeTopicListScope()
    }

    fun prepareTopicRefresh() {
        _isOffline.value = false
    }

    private fun createPagingFlow(filter: HomeTopicFilter): Flow<PagingData<TopicRowState>> {
        val primaryTag = filter.tags.firstOrNull()
        val additionalTags = filter.tags.drop(1)
        return Pager(
            config = PagingConfig(
                pageSize = 30,
                prefetchDistance = 10,
                enablePlaceholders = false,
            ),
            pagingSourceFactory = {
                TopicListPagingSource(
                    repository = topicRepository,
                    kind = filter.kind,
                    categorySlug = filter.categorySlug,
                    categoryId = filter.categoryId,
                    parentCategorySlug = filter.parentCategorySlug,
                    tag = primaryTag,
                    additionalTags = additionalTags,
                    matchAllTags = additionalTags.isNotEmpty(),
                    onPageLoaded = ::handleTopicPageLoaded,
                )
            },
        ).flow
    }

    private fun updateOfflineState(page: UInt, isCached: Boolean) {
        if (page == 0u) {
            _isOffline.value = isCached
        } else if (isCached) {
            _isOffline.value = true
        }
    }

    private fun handleTopicPageLoaded(page: UInt, isCached: Boolean, rows: List<TopicRowState>) {
        updateOfflineState(page, isCached)
        if (page == 0u) {
            FireWidgetData.updateTopicRows(
                context = FireApplication.getInstance(),
                rows = rows,
                session = _session.value,
            )
        }
    }

    fun startRealtimeRefresh() {
        if (messageBusJob != null) return
        messageBusJob = viewModelScope.launch {
            try {
                messageBusCoordinator.topicListEvents().collect { event ->
                    handleTopicListMessageBusEvent(event)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                messageBusJob = null
                val reported = FireErrorReporter.report(
                    operation = "home.messagebus.topic_list",
                    error = error,
                    sessionStore = sessionStore,
                )
                _error.tryEmit(reported.displayMessage)
            }
        }
    }

    private fun stopRealtimeRefresh() {
        pendingMessageBusRefreshJob?.cancel()
        pendingMessageBusRefreshJob = null
        messageBusJob?.cancel()
        messageBusJob = null
        topicListMessageBusRefreshController.clearPending(currentRefreshScope())
    }

    private fun currentHomeTopicListScopeState(): HomeTopicListScopeState {
        return HomeTopicListScopeState(
            kind = _selectedKind.value,
            categoryId = _selectedCategoryId.value,
            tags = _selectedTags.value,
        )
    }

    private fun applyCurrentHomeTopicListScope(scope: HomeTopicListScopeState) {
        _selectedKind.value = scope.kind
        _selectedCategoryId.value = scope.categoryId
        _selectedTags.value = scope.tags
    }

    private fun syncCurrentHomeTopicListScope() {
        runCatching {
            sessionStore.setCurrentHomeTopicListScope(currentHomeTopicListScopeState())
        }.onSuccess(::applyCurrentHomeTopicListScope)
            .onFailure(::reportHomeScopeSyncError)
    }

    private fun reportHomeScopeSyncError(error: Throwable) {
        handleReportedError(
            FireErrorReporter.report(
                operation = "home.sync_topic_list_scope",
                error = error,
                sessionStore = sessionStore,
            ),
        )
    }

    private fun handleReportedError(error: FireReportedError) {
        _error.tryEmit(error.displayMessage)
    }

    private suspend fun handleAppStateRefreshEvent(batch: RefreshBatchState) {
        applyCurrentHomeTopicListScope(sessionStore.currentHomeTopicListScope())
        val snapshot = sessionStore.snapshot()
        _session.value = snapshot
        if (snapshot.readiness.canOpenMessageBus) {
            startRealtimeRefresh()
        } else {
            stopRealtimeRefresh()
        }

        // Rust core refresh already fetched the current home scope. Triggering
        // Paging.refresh() here reissues the same request and can invalidate a
        // deep scroll position at the wrong anchor page.
        if (batch == RefreshBatchState.CORE) return
    }

    private fun handleTopicListMessageBusEvent(event: MessageBusEventState) {
        val scope = currentRefreshScope()
        val allowTopicScopedRefresh = scope.supportsTopicScopedMessageBusRefresh
        val delayMs = topicListMessageBusRefreshController.register(
            event = event,
            scope = scope,
            nowMs = System.currentTimeMillis(),
            allowTopicScopedRefresh = allowTopicScopedRefresh,
        ) ?: return

        pendingMessageBusRefreshJob?.cancel()
        pendingMessageBusRefreshJob = viewModelScope.launch {
            delay(delayMs)
            val currentScope = currentRefreshScope()
            if (topicListMessageBusRefreshController.takePendingRefresh(currentScope)) {
                _topicListRefreshEvents.tryEmit(Unit)
                topicListMessageBusRefreshController.markRefreshCompleted(
                    currentScope,
                    System.currentTimeMillis(),
                )
            }
        }
    }

    private fun currentRefreshScope(): HomeTopicListRefreshScope {
        return HomeTopicListRefreshScope(
            kind = _selectedKind.value,
            categoryId = _selectedCategoryId.value,
            tags = _selectedTags.value,
        )
    }

    private fun clearPendingMessageBusRefresh() {
        pendingMessageBusRefreshJob?.cancel()
        pendingMessageBusRefreshJob = null
        topicListMessageBusRefreshController.clearPending(currentRefreshScope())
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
            val topicRepo = TopicRepository(sessionStore)
            val messageBus = FireMessageBusCoordinator(sessionStore)
            return HomeViewModel(topicRepo, messageBus, sessionStore)
        }
    }

    override fun onCleared() {
        pendingMessageBusRefreshJob?.cancel()
        messageBusJob?.cancel()
        super.onCleared()
    }
}
