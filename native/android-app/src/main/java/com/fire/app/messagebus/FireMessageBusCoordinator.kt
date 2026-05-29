package com.fire.app.messagebus

import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import uniffi.fire_uniffi_notifications.NotificationCenterState

class FireMessageBusCoordinator(private val sessionStore: FireSessionStore) {

    fun notificationStateFlow(): Flow<NotificationCenterState> = flow {
        while (true) {
            val state = sessionStore.notificationState()
            emit(state)
            kotlinx.coroutines.delay(30_000)
        }
    }.flowOn(Dispatchers.IO)
}