package com.fire.app.ui.chat

import uniffi.fire_uniffi_chat.ChatBusEventState
import uniffi.fire_uniffi_chat.ChatChannelState
import uniffi.fire_uniffi_chat.ChatMessageState
import uniffi.fire_uniffi_chat.chatBusEventFromPayload
import uniffi.fire_uniffi_chat.chatChannelFromBusPayload
import uniffi.fire_uniffi_chat.chatMessageFromBusPayload
import uniffi.fire_uniffi_messagebus.MessageBusEventState

object FireChatBusPayload {
    fun event(
        busEvent: MessageBusEventState,
        fallbackChannelId: ULong?,
        baseUrl: String,
    ): ChatBusEventState {
        val payload = busEvent.payloadJson ?: return ChatBusEventState.Ignored
        return chatBusEventFromPayload(
            payloadJson = payload,
            eventType = busEvent.detailEventType ?: busEvent.messageType,
            fallbackChannelId = fallbackChannelId ?: busEvent.topicId,
            baseUrl = baseUrl,
        )
    }

    fun chatMessage(
        busEvent: MessageBusEventState,
        fallbackChannelId: ULong?,
        baseUrl: String,
    ): ChatMessageState? {
        return when (val parsed = event(busEvent, fallbackChannelId, baseUrl)) {
            is ChatBusEventState.MessageUpsert -> parsed.message
            else -> busEvent.payloadJson?.let { payload ->
                chatMessageFromBusPayload(
                    payloadJson = payload,
                    fallbackChannelId = fallbackChannelId ?: busEvent.topicId,
                    baseUrl = baseUrl,
                )
            }
        }
    }

    fun channel(
        busEvent: MessageBusEventState,
        baseUrl: String,
    ): ChatChannelState? {
        return when (val parsed = event(busEvent, busEvent.topicId, baseUrl)) {
            is ChatBusEventState.ChannelUpsert -> parsed.channel
            else -> busEvent.payloadJson?.let { payload ->
                chatChannelFromBusPayload(payloadJson = payload, baseUrl = baseUrl)
            }
        }
    }
}
