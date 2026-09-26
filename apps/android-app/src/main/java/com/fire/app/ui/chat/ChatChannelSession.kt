package com.fire.app.ui.chat

import com.fire.app.session.FireSessionStore
import uniffi.fire_uniffi_chat.ChatChannelRuntimeState
import uniffi.fire_uniffi_chat.ChatMessageState
import uniffi.fire_uniffi_chat.ChatMessagesQueryState
import uniffi.fire_uniffi_chat.SendChatMessageRequestState
import uniffi.fire_uniffi_messagebus.MessageBusEventState
import java.util.UUID

class ChatChannelSession(
    private val store: FireSessionStore,
    private val channelId: ULong,
    private val threadId: ULong?,
    initialTitle: String,
    initialThreadingEnabled: Boolean,
) {
    data class Snapshot(
        val title: String,
        val threadingEnabled: Boolean,
        val messages: List<ChatMessageState>,
        val pins: List<ChatMessageState>,
        val canLoadMorePast: Boolean,
        val isLoading: Boolean,
        val chatBaseUrl: String,
    )

    enum class Change {
        Cached,
        Initial,
        Older,
        Latest,
        MessageInserted,
        MessageUpdated,
        MessageDeleted,
        Pins,
        Loading,
    }

    sealed class Command {
        data object LoadMorePast : Command()
        data class Send(
            val message: String,
            val uploadIds: List<ULong> = emptyList(),
        ) : Command()
        data class ToggleReaction(
            val messageId: ULong,
            val emoji: String,
        ) : Command()
        data class SetPinned(
            val messageId: ULong,
            val pinned: Boolean,
        ) : Command()
        data class ResolveThread(
            val messageId: ULong,
        ) : Command()
    }

    sealed class CommandResult {
        data object None : CommandResult()
        data class ThreadId(val id: ULong) : CommandResult()
    }

    var onChange: ((Snapshot, Change) -> Unit)? = null
    var onError: ((Exception) -> Unit)? = null

    private val ownerToken = "chat-channel-activity"
    private val busChannelName = threadId?.let { "/chat/$channelId/thread/$it" } ?: "/chat/$channelId"

    private var title: String = initialTitle
    private var threadingEnabled: Boolean = initialThreadingEnabled
    private var messages: List<ChatMessageState> = emptyList()
    private var pins: List<ChatMessageState> = emptyList()
    private var canLoadMorePast = false
    private var isLoading = false
    private var isSending = false
    private var isOpen = false
    private var chatBaseUrl: String = "https://linux.do"

    fun snapshot(): Snapshot {
        return Snapshot(
            title = title,
            threadingEnabled = threadingEnabled,
            messages = messages,
            pins = pins,
            canLoadMorePast = canLoadMorePast,
            isLoading = isLoading,
            chatBaseUrl = chatBaseUrl,
        )
    }

    suspend fun open() {
        if (isOpen || channelId == 0uL) return
        isOpen = true
        isLoading = true
        try {
            val bootstrap = store.snapshot().bootstrap
            chatBaseUrl = bootstrap.baseUrl.ifBlank { "https://linux.do" }
            store.cachedChatMessages(channelId, threadId)?.messages?.takeIf { it.isNotEmpty() }?.let {
                adoptRuntime(Change.Cached)
            } ?: emit(Change.Loading)
            if (threadId == null) {
                val channel = store.fetchChatChannel(channelId)
                threadingEnabled = channel.threadingEnabled
                title = channel.displayTitle
                pins = store.fetchChatChannelPins(channelId)
                emit(Change.Pins)
                if (pins.isNotEmpty()) {
                    runCatching { store.markChatChannelPinsRead(channelId) }
                }
            }
            fetchMessages(fetchFromLastRead = true)
            adoptRuntime(Change.Initial)
            if (threadId != null) {
                runCatching { store.markChatThreadRead(channelId, threadId!!) }
            } else {
                messages.lastOrNull()?.id?.let { latest ->
                    runCatching { store.markChatChannelRead(channelId, latest) }
                }
            }
            store.subscribeMessageBusChannel(
                channel = busChannelName,
                ownerToken = ownerToken,
                lastMessageId = null,
            )
        } catch (error: Exception) {
            if (isOpen) onError?.invoke(error)
        } finally {
            isLoading = false
            emit(Change.Loading)
        }
    }

    suspend fun close() {
        isOpen = false
        store.unsubscribeMessageBusChannel(busChannelName, ownerToken)
        store.closeChatChannelRuntime(channelId, threadId)
    }

    suspend fun command(command: Command): CommandResult {
        return when (command) {
            Command.LoadMorePast -> {
                loadMorePast()
                CommandResult.None
            }
            is Command.Send -> {
                send(command.message, command.uploadIds)
                CommandResult.None
            }
            is Command.ToggleReaction -> {
                toggleReaction(command.messageId, command.emoji)
                CommandResult.None
            }
            is Command.SetPinned -> {
                if (command.pinned) {
                    store.pinChatMessage(channelId, command.messageId)
                } else {
                    store.unpinChatMessage(channelId, command.messageId)
                }
                CommandResult.None
            }
            is Command.ResolveThread -> {
                val message = messages.firstOrNull { it.id == command.messageId }
                    ?: error("消息已不存在")
                val id = message.threadId
                    ?: message.thread?.id
                    ?: store.createChatThread(channelId, message.id)
                CommandResult.ThreadId(id)
            }
        }
    }

    fun handleBusEvent(event: MessageBusEventState) {
        if (!isOpen || event.channel != busChannelName) return
        val payload = event.payloadJson ?: return
        val type = event.detailEventType ?: event.messageType
        val previousCount = messages.size
        applyRuntime(
            store.applyChatChannelBusEvent(
                channelId = channelId,
                threadId = threadId,
                payloadJson = payload,
                eventType = type,
            ),
        )
        emit(
            when (type) {
                "pin", "unpin" -> Change.Pins
                "delete" -> Change.MessageDeleted
                "sent" -> if (messages.size > previousCount) Change.MessageInserted else Change.MessageUpdated
                else -> Change.MessageUpdated
            },
        )
    }

    private suspend fun loadMorePast() {
        if (!canLoadMorePast || isLoading) return
        val oldest = messages.firstOrNull() ?: return
        isLoading = true
        try {
            val query = ChatMessagesQueryState(
                channelId = channelId,
                direction = "past",
                targetMessageId = oldest.id,
                fetchFromLastRead = false,
                pageSize = 50u,
            )
            fetchMessages(query)
            adoptRuntime(Change.Older)
        } finally {
            isLoading = false
        }
    }

    private suspend fun send(text: String, uploadIds: List<ULong>) {
        if (isSending) return
        if (text.isEmpty() && uploadIds.isEmpty()) return
        isSending = true
        try {
            store.sendChatMessage(
                SendChatMessageRequestState(
                    channelId = channelId,
                    message = text,
                    stagedId = UUID.randomUUID().toString(),
                    inReplyToId = null,
                    threadId = threadId,
                    uploadIds = uploadIds,
                ),
            )
        } catch (error: Exception) {
            refreshLatest()
            throw error
        } finally {
            isSending = false
        }
    }

    private suspend fun toggleReaction(messageId: ULong, emoji: String) {
        val message = messages.firstOrNull { it.id == messageId } ?: return
        val reacted = message.reactions.any { it.emoji == emoji && it.reacted }
        store.reactChatMessage(
            channelId = channelId,
            messageId = message.id,
            emoji = emoji,
            reactAction = if (reacted) "remove" else "add",
        )
    }

    private suspend fun refreshLatest() {
        fetchMessages(fetchFromLastRead = false)
        adoptRuntime(Change.Latest)
        if (threadId == null) {
            messages.lastOrNull()?.id?.let { latest ->
                runCatching { store.markChatChannelRead(channelId, latest) }
            }
        }
    }

    private suspend fun fetchMessages(fetchFromLastRead: Boolean) = fetchMessages(
        ChatMessagesQueryState(
            channelId = channelId,
            direction = null,
            targetMessageId = null,
            fetchFromLastRead = fetchFromLastRead,
            pageSize = 50u,
        ),
    )

    private suspend fun fetchMessages(query: ChatMessagesQueryState) =
        if (threadId != null) {
            store.fetchChatThreadMessages(channelId, threadId, query)
        } else {
            store.fetchChatMessages(query)
        }

    private fun adoptRuntime(change: Change) {
        val runtime = store.chatChannelRuntimeSnapshot(channelId, threadId) ?: return
        applyRuntime(runtime)
        emit(change)
    }

    private fun applyRuntime(runtime: ChatChannelRuntimeState) {
        messages = runtime.messages
        if (threadId == null) {
            pins = runtime.pins
        }
        canLoadMorePast = runtime.canLoadMorePast
    }

    private fun emit(change: Change) {
        onChange?.invoke(snapshot(), change)
    }
}
