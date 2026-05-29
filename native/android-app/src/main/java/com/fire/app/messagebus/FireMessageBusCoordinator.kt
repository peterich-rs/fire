package com.fire.app.messagebus

import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_messagebus.MessageBusEventHandler
import uniffi.fire_uniffi_messagebus.MessageBusEventKindState
import uniffi.fire_uniffi_messagebus.MessageBusEventState
import uniffi.fire_uniffi_notifications.NotificationCenterState

class FireMessageBusCoordinator(private val sessionStore: FireSessionStore) {
    fun notificationStateFlow(): Flow<NotificationCenterState> = flow {
        while (true) {
            val state = sessionStore.notificationState()
            emit(state)
            kotlinx.coroutines.delay(30_000)
        }
    }.flowOn(Dispatchers.IO)

    fun topicListEvents(): Flow<MessageBusEventState> = callbackFlow {
        val handler = object : MessageBusEventHandler {
            override fun onMessageBusEvent(event: MessageBusEventState) {
                if (event.kind == MessageBusEventKindState.TOPIC_LIST) {
                    trySend(event)
                }
            }
        }

        val startJob = launch(Dispatchers.IO) {
            try {
                sessionStore.startMessageBus(handler)
            } catch (error: Exception) {
                close(error)
            }
        }

        awaitClose {
            startJob.cancel()
            runCatching { sessionStore.stopMessageBus(clearSubscriptions = false) }
        }
    }.flowOn(Dispatchers.IO)
}
