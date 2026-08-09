package com.fire.app.ui.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_chat.ChatChannelState
import uniffi.fire_uniffi_chat.CreateDirectMessageChannelRequestState
import uniffi.fire_uniffi_chat.MyChatChannelsState

enum class ChatSegment {
    DirectMessages,
    PublicChannels,
}

data class ChatChannelsUiState(
    val publicChannels: List<ChatChannelState> = emptyList(),
    val directMessageChannels: List<ChatChannelState> = emptyList(),
    val tracking: Map<ULong, Pair<UInt, UInt>> = emptyMap(),
    val totalUnreadBadge: UInt = 0u,
    val segment: ChatSegment = ChatSegment.DirectMessages,
    val isLoading: Boolean = false,
    val hasLoadedOnce: Boolean = false,
    val errorMessage: String? = null,
) {
    val displayedChannels: List<ChatChannelState>
        get() = when (segment) {
            ChatSegment.DirectMessages -> sortChannels(directMessageChannels)
            ChatSegment.PublicChannels -> sortChannels(publicChannels)
        }

    fun badgeFor(channel: ChatChannelState): UInt {
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

    fun loadIfNeeded() {
        if (_state.value.hasLoadedOnce || _state.value.isLoading) return
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, errorMessage = null)
            runCatching { sessionStore.fetchMyChatChannels() }
                .onSuccess { response -> apply(response) }
                .onFailure { error ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        hasLoadedOnce = true,
                        errorMessage = error.message ?: "加载聊天失败",
                    )
                }
        }
    }

    fun selectSegment(segment: ChatSegment) {
        _state.value = _state.value.copy(segment = segment)
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

    private fun apply(response: MyChatChannelsState) {
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
            errorMessage = null,
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
}

class ChatChannelsViewModelFactory(
    private val sessionStore: FireSessionStore,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return ChatChannelsViewModel(sessionStore) as T
    }
}
