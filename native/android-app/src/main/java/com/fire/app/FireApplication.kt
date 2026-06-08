package com.fire.app

import android.app.Application
import com.fire.app.core.image.FireImageLoader
import com.fire.app.push.FirePushNotificationDispatcher
import com.fire.app.ui.topicdetail.BookmarkReminderScheduler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

class FireApplication : Application() {
    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onCreate() {
        super.onCreate()
        instance = this
        FireImageLoader.initialize(this)
        BookmarkReminderScheduler.createNotificationChannel(this)
        FirePushNotificationDispatcher.createNotificationChannel(this)
    }

    override fun onTerminate() {
        applicationScope.cancel()
        super.onTerminate()
    }

    companion object {
        @Volatile
        private var instance: FireApplication? = null

        fun getInstance(): Application =
            instance ?: throw IllegalStateException("FireApplication not initialized")

        fun applicationScope(): CoroutineScope =
            (getInstance() as FireApplication).applicationScope
    }
}
