package com.fire.app.push

import android.util.Log
import com.fire.app.FireApplication
import com.fire.app.session.FireSessionStoreRepository
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.fire_uniffi_diagnostics.HostLogLevelState

class FireFirebaseMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "fcm token refreshed")
        FireApplication.applicationScope().launch(Dispatchers.IO) {
            runCatching {
                val store = FireSessionStoreRepository.get(applicationContext)
                store.logHost(
                    level = HostLogLevelState.INFO,
                    target = "android.push",
                    message = "fcm token refreshed; registration API not yet available",
                )
                store.flushLogs(sync = false)
            }
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val notification = FirePushPayloadParser.parse(
            data = message.data,
            notificationTitle = message.notification?.title,
            notificationBody = message.notification?.body,
        ) ?: return

        FirePushNotificationDispatcher.show(applicationContext, notification)
        FireApplication.applicationScope().launch {
            refreshNotificationState()
        }
    }

    private suspend fun refreshNotificationState() {
        runCatching {
            val store = withContext(Dispatchers.IO) {
                FireSessionStoreRepository.get(applicationContext)
            }
            withContext(Dispatchers.IO) {
                store.notificationState()
            }
        }.onFailure { error ->
            Log.w(TAG, "notification state refresh after push failed", error)
        }
    }

    companion object {
        private const val TAG = "FireFCM"
    }
}
