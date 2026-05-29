package com.fire.app.messagebus

import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.MutableSharedFlow
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
        val startJob = acquireMessageBusReference(sessionStore) { error -> close(error) }
        val collectJob = launch {
            sharedEvents
                .filter { it.kind == MessageBusEventKindState.TOPIC_LIST }
                .collect { event -> trySend(event) }
        }

        awaitClose {
            collectJob.cancel()
            startJob.cancel()
            releaseMessageBusReference(sessionStore)
        }
    }.flowOn(Dispatchers.IO)

    fun topicDetailEvents(topicId: ULong): Flow<MessageBusEventState> = callbackFlow {
        val startJob = acquireMessageBusReference(sessionStore) { error -> close(error) }
        val collectJob = launch {
            sharedEvents
                .filter { event ->
                    event.topicId == topicId &&
                        (
                            event.kind == MessageBusEventKindState.TOPIC_DETAIL ||
                                event.kind == MessageBusEventKindState.TOPIC_REACTION ||
                                event.kind == MessageBusEventKindState.PRESENCE
                        )
                }
                .collect { event -> trySend(event) }
        }

        awaitClose {
            collectJob.cancel()
            startJob.cancel()
            releaseMessageBusReference(sessionStore)
        }
    }.flowOn(Dispatchers.IO)

    companion object {
        private val lock = Any()
        private val sharedEvents = MutableSharedFlow<MessageBusEventState>(
            extraBufferCapacity = 128,
        )
        private var referenceCount = 0
        private var started = false

        private val sharedHandler = object : MessageBusEventHandler {
            override fun onMessageBusEvent(event: MessageBusEventState) {
                sharedEvents.tryEmit(event)
            }
        }

        private fun acquireMessageBusReference(
            sessionStore: FireSessionStore,
            onStartFailed: (Exception) -> Unit,
        ) = kotlinx.coroutines.CoroutineScope(Dispatchers.IO).launch {
            val shouldStart = synchronized(lock) {
                referenceCount += 1
                if (!started) {
                    started = true
                    true
                } else {
                    false
                }
            }
            if (!shouldStart) return@launch

            try {
                sessionStore.startMessageBus(sharedHandler)
            } catch (error: Exception) {
                synchronized(lock) {
                    started = false
                    referenceCount = 0
                }
                onStartFailed(error)
            }
        }

        private fun releaseMessageBusReference(sessionStore: FireSessionStore) {
            val shouldStop = synchronized(lock) {
                referenceCount = (referenceCount - 1).coerceAtLeast(0)
                if (referenceCount == 0 && started) {
                    started = false
                    true
                } else {
                    false
                }
            }
            if (shouldStop) {
                runCatching { sessionStore.stopMessageBus(clearSubscriptions = false) }
            }
        }
    }
}
