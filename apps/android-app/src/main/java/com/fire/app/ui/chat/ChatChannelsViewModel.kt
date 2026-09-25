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
import uniffi.fire_uniffi_chat.ChatBusEventState
import uniffi.fire_uniffi_chat.ChatChannelState
import uniffi.fire_uniffi_chat.ChatMessageState
import uniffi.fire_uniffi_chat.CreateDirectMessageChannelRequestState
import uniffi.fire_uniffi_chat.MyChatChannelsState
import uniffi.fire_uniffi_messagebus.MessageBusEventState

data class ChatChannelsUiState(
    val publicChannels: List<ChatChannelState> = emptyList(),
    val directMessageChannels: List<ChatChannelState> = emptyList(),
    val tracking: Map<ULong, Pair<UInt, UInt>> = emptyMap(),
    val totalUnreadBadge: UInt = 0u,
    val isLoading: Boolean = false,
    val hasLoadedOnce: Boolean = false,
    val errorMessage: String? = null,
) {
    val displayedChannels: List<ChatChannelState>
        get() = sortChannels(directMessageChannels + publicChannels)

    fun badgeFor(channel: ChatChannelState): UInt {
        if (channel.currentUserMembership?.muted == true) return 0u
        val (unread, mention) = tracking[channel.id] ?: (0u to 0u)
        return if (channel.isDirectMessage) unread + mention else mention
    }
}

private fun sortChannels(channels: List<ChatChannelState>): List<ChatChannelState> {
    return channels.sortedWith(
        compareByDescending<ChatChannelState> { it.currentUserMembership?.starred == true }
            .thenByDescending { it.lastMessage?.createdAt.orEmpty() }
            .thenByDescending { it.id },
    )
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
    private var baseUrl: String = "https://linux.do"
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
                baseUrl = bootstrap.baseUrl.ifBlank { "https://linux.do" }
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
        val next = _state.value.tracking.toMutableMap()
        next[channelId] = 0u to 0u
        _state.value = _state.value.copy(
            tracking = next,
            totalUnreadBadge = recomputeBadge(
                publicChannels = _state.value.publicChannels,
                directMessageChannels = _state.value.directMessageChannels,
                tracking = next,
            ),
        )
    }

    fun upsert(channel: ChatChannelState) {
        val current = _state.value
        _state.value = if (channel.isDirectMessage) {
            current.copy(
                directMessageChannels = listOf(channel) +
                    current.directMessageChannels.filterNot { it.id == channel.id },
            )
        } else {
            current.copy(
                publicChannels = listOf(channel) +
                    current.publicChannels.filterNot { it.id == channel.id },
            )
        }
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
        when {
            event.channel == "/chat/new-channel" -> handleNewChannel(event)
            event.channel.startsWith("/chat/user-tracking-state/") -> handleTracking(event)
            event.channel.endsWith("/new-messages") -> handleNewMessages(event)
        }
    }

    private fun handleNewChannel(event: MessageBusEventState) {
        val channel = FireChatBusPayload.channel(event, baseUrl) ?: return
        if (channel.isDirectMessage) {
            upsert(channel)
        }
    }

    private fun handleTracking(event: MessageBusEventState) {
        val parsed = FireChatBusPayload.event(event, event.topicId, baseUrl)
        val tracking = parsed as? ChatBusEventState.Tracking ?: return
        if (tracking.threadId != null || tracking.channelId == 0uL) return
        val next = _state.value.tracking.toMutableMap()
        next[tracking.channelId] = tracking.unread to tracking.mention
        _state.value = _state.value.copy(
            tracking = next,
            totalUnreadBadge = recomputeBadge(
                _state.value.publicChannels,
                _state.value.directMessageChannels,
                next,
            ),
        )
    }

    private fun handleNewMessages(event: MessageBusEventState) {
        when (val parsed = FireChatBusPayload.event(event, event.topicId, baseUrl)) {
            is ChatBusEventState.NewMessages -> {
                if (!parsed.isChannelLevel || parsed.channelId == 0uL) return
                val message = parsed.message ?: return
                applyIncomingLastMessage(message, isSelf = message.user?.id == currentUserId)
            }
            is ChatBusEventState.MessageUpsert -> {
                applyIncomingLastMessage(
                    parsed.message,
                    isSelf = parsed.message.user?.id == currentUserId,
                )
            }
            else -> Unit
        }
    }

    private fun applyIncomingLastMessage(message: ChatMessageState, isSelf: Boolean) {
        val channelId = message.channelId
        val current = _state.value
        val nextTracking = current.tracking.toMutableMap()
        if (!isSelf) {
            val old = nextTracking[channelId] ?: (0u to 0u)
            nextTracking[channelId] = (old.first + 1u) to old.second
        }
        fun withLastMessage(channel: ChatChannelState): ChatChannelState {
            return if (channel.id == channelId) channel.copy(lastMessage = message) else channel
        }
        _state.value = current.copy(
            publicChannels = sortChannels(current.publicChannels.map(::withLastMessage)),
            directMessageChannels = sortChannels(current.directMessageChannels.map(::withLastMessage)),
            tracking = nextTracking,
            totalUnreadBadge = recomputeBadge(
                current.publicChannels,
                current.directMessageChannels,
                nextTracking,
            ),
        )
    }

    private fun recomputeBadge(
        publicChannels: List<ChatChannelState>,
        directMessageChannels: List<ChatChannelState>,
        tracking: Map<ULong, Pair<UInt, UInt>>,
    ): UInt {
        var sum = 0u
        for (channel in directMessageChannels) {
            if (channel.currentUserMembership?.muted == true) continue
            val (unread, mention) = tracking[channel.id] ?: (0u to 0u)
            sum += unread + mention
        }
        for (channel in publicChannels) {
            if (channel.currentUserMembership?.muted == true) continue
            sum += tracking[channel.id]?.second ?: 0u
        }
        return sum
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
