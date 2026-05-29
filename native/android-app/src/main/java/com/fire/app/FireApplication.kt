package com.fire.app

import android.app.Application
import com.fire.app.core.image.FireImageLoader
import com.fire.app.session.FireSessionStoreRepository

class FireApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        instance = this
        FireImageLoader.initialize(this)
    }

    companion object {
        @Volatile
        private var instance: FireApplication? = null

        fun getInstance(): Application =
            instance ?: throw IllegalStateException("FireApplication not initialized")
    }
}