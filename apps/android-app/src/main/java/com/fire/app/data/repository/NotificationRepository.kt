package com.fire.app.data.repository

import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.fire_uniffi_notifications.NotificationCenterState
import uniffi.fire_uniffi_notifications.NotificationListState

class NotificationRepository(private val sessionStore: FireSessionStore) {

    suspend fun fetchRecentNotifications(limit: UInt? = null): NotificationListState =
        withContext(Dispatchers.Default) {
            sessionStore.fetchRecentNotifications(limit)
        }

    suspend fun fetchNotifications(
        limit: UInt? = null,
        offset: UInt? = null,
    ): NotificationListState = withContext(Dispatchers.Default) {
        sessionStore.fetchNotifications(limit, offset)
    }

    suspend fun markNotificationRead(id: ULong): NotificationCenterState =
        withContext(Dispatchers.Default) {
            sessionStore.markNotificationRead(id)
        }

    suspend fun markNotificationsRead(): NotificationCenterState =
        withContext(Dispatchers.Default) {
            sessionStore.markAllNotificationsRead()
        }

    suspend fun fetchNotificationState(): NotificationCenterState =
        withContext(Dispatchers.Default) {
            sessionStore.notificationState()
        }
}
