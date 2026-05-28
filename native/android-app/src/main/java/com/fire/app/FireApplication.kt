package com.fire.app

import android.app.Application
import com.fire.app.session.FireSessionStoreRepository

class FireApplication : Application() {
    val sessionStore: FireSessionStoreRepository by lazy {
        FireSessionStoreRepository.get(applicationContext)
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    companion object {
        @Volatile
        private var instance: FireApplication? = null

        fun getInstance(): FireApplication =
            instance ?: throw IllegalStateException("FireApplication not initialized")
    }
}
