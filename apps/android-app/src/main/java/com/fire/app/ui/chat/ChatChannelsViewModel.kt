package com.fire.app.ui.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fire.app.messagebus.FireMessageBusCoordinator
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_chat.ChatChannelState
import uniffi.fire_uniffi_chat.CreateDirectMessageChannelRequestState
import uniffi.fire_uniffi_chat.MyChatChannelsState
import uniffi.fire_uniffi_messagebus.MessageBusEventState

data class ChatChannelsUiState(
    val publicChannels: List<ChatChannelState> = emptyList(),
    val directMessageChannels: List<ChatChannelState> = emptyList(),
    val displayedChannels: List<ChatChannelState> = emptyList(),
    val tracking: Map<ULong, Pair<UInt, UInt>> = emptyMap(),
    val totalUnreadBadge: UInt = 0u,
    val isLoading: Boolean = false,
    val hasLoadedOnce: Boolean = false,
    val errorMessage: String? = null,
) {
    fun badgeFor(channel: ChatChannelState): UInt = channel.unreadBadge
}

class ChatChannelsViewModel(
    private val sessionStore: FireSessionStore,
) : ViewModel() {
    private val _state = MutableStateFlow(ChatChannelsUiState())
    val state: StateFlow<ChatChannelsUiState> = _state.asStateFlow()

    private val ownerToken = "chat-channels-list"
    private val subscribedNewMessageChannels = mutableSetOf<ULong>()
    private var busJob: Job? = null
    private var currentUserId: ULong? = null
    private var didRefreshFromNetwork = false

    init {
        busJob = viewModelScope.launch {
            FireMessageBusCoordinator(sessionStore).chatEvents().collect { event ->
                handleBusEvent(event)
            }
        }
    }

    fun loadIfNeeded() {
        viewModelScope.launch {
            if (!_state.value.hasLoadedOnce) {
                runCatching { sessionStore.cachedMyChatChannels() }
                    .getOrNull()
                    ?.let { apply(it, fromCache = true) }
            }
            if (didRefreshFromNetwork || _state.value.isLoading) return@launch
            refresh()
        }
    }

    fun refresh() {
        viewModelScope.launch {
            didRefreshFromNetwork = true
            _state.value = _state.value.copy(isLoading = true, errorMessage = null)
            runCatching {
                val bootstrap = sessionStore.snapshot().bootstrap
                currentUserId = bootstrap.currentUserId
                sessionStore.fetchMyChatChannels()
            }
                .onSuccess { response ->
                    apply(response)
                    resubscribe(response)
                }
                .onFailure { error ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        hasLoadedOnce = true,
                        errorMessage = error.message ?: "加载聊天失败",
                    )
                }
        }
    }

    fun clearTracking(channelId: ULong) {
        apply(
            sessionStore.applyChatListTracking(
                channelId = channelId,
                unread = 0u,
                mention = 0u,
                explicitMarkRead = true,
            ),
        )
    }

    fun upsert(channel: ChatChannelState) {
        sessionStore.chatListSnapshot()?.let { apply(it) }
        subscribeNewMessages(channel)
    }

    suspend fun createDirectMessage(usernames: List<String>): ChatChannelState {
        val channel = sessionStore.createDirectMessageChannel(
            CreateDirectMessageChannelRequestState(
                targetUsernames = usernames,
                name = null,
                upsert = usernames.size == 1,
            ),
        )
        upsert(channel)
        return channel
    }

    suspend fun markRead(channelId: ULong) {
        sessionStore.markChatChannelRead(channelId)
        clearTracking(channelId)
    }

    suspend fun leave(channelId: ULong) {
        sessionStore.leaveChatChannel(channelId)
        refresh()
    }

    private fun apply(response: MyChatChannelsState, fromCache: Boolean = false) {
        val tracking = response.channelTracking.associate {
            it.channelId to (it.unreadCount to it.mentionCount)
        }
        _state.value = _state.value.copy(
            publicChannels = response.publicChannels,
            directMessageChannels = response.directMessageChannels,
            displayedChannels = response.inboxChannels,
            tracking = tracking,
            totalUnreadBadge = response.totalUnreadBadge,
            isLoading = false,
            hasLoadedOnce = true,
            errorMessage = if (fromCache) _state.value.errorMessage else null,
        )
    }

    private fun resubscribe(response: MyChatChannelsState) {
        teardownSubscriptions()
        val globalLast = response.globalBusLastIds.associate { it.channel to it.lastId }
        sessionStore.subscribeMessageBusChannel(
            channel = "/chat/new-channel",
            ownerToken = ownerToken,
            lastMessageId = globalLast["new_channel"],
        )
        sessionStore.subscribeMessageBusChannel(
            channel = "/chat/channel-edits",
            ownerToken = ownerToken,
            lastMessageId = globalLast["channel_edits"],
        )
        currentUserId?.let { userId ->
            sessionStore.subscribeMessageBusChannel(
                channel = "/chat/user-tracking-state/$userId",
                ownerToken = ownerToken,
                lastMessageId = globalLast["user_tracking_state"],
            )
        }
        (response.directMessageChannels + response.publicChannels).forEach { subscribeNewMessages(it) }
    }

    private fun subscribeNewMessages(channel: ChatChannelState) {
        if (!subscribedNewMessageChannels.add(channel.id)) return
        sessionStore.subscribeMessageBusChannel(
            channel = "/chat/${channel.id}/new-messages",
            ownerToken = ownerToken,
            lastMessageId = channel.busLastIds.newMessages,
        )
    }

    private fun teardownSubscriptions() {
        subscribedNewMessageChannels.forEach { id ->
            sessionStore.unsubscribeMessageBusChannel("/chat/$id/new-messages", ownerToken)
        }
        subscribedNewMessageChannels.clear()
        sessionStore.unsubscribeMessageBusChannel("/chat/new-channel", ownerToken)
        sessionStore.unsubscribeMessageBusChannel("/chat/channel-edits", ownerToken)
        currentUserId?.let { userId ->
            sessionStore.unsubscribeMessageBusChannel("/chat/user-tracking-state/$userId", ownerToken)
        }
    }

    private fun handleBusEvent(event: MessageBusEventState) {
        val channel = event.channel
        if (channel != "/chat/new-channel" &&
            channel != "/chat/channel-edits" &&
            !channel.startsWith("/chat/user-tracking-state/") &&
            !channel.endsWith("/new-messages")
        ) {
            return
        }
        val payload = event.payloadJson ?: return
        val knownIds = (_state.value.directMessageChannels + _state.value.publicChannels)
            .map { it.id }
            .toSet()
        apply(
            sessionStore.applyChatListBusEvent(
                payloadJson = payload,
                eventType = event.detailEventType ?: event.messageType,
                fallbackChannelId = event.topicId,
            ),
        )
        (_state.value.directMessageChannels + _state.value.publicChannels)
            .filter { it.id !in knownIds }
            .forEach { subscribeNewMessages(it) }
    }

    override fun onCleared() {
        busJob?.cancel()
        teardownSubscriptions()
        super.onCleared()
    }
}

class ChatChannelsViewModelFactory(
    private val sessionStore: FireSessionStore,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return ChatChannelsViewModel(sessionStore) as T
    }
}
