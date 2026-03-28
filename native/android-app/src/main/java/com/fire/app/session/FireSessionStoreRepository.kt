package com.fire.app.session

import android.content.Context

object FireSessionStoreRepository {
    @Volatile
    private var shared: FireSessionStore? = null

    fun get(context: Context): FireSessionStore {
        return shared ?: synchronized(this) {
            shared ?: FireSessionStore(context.applicationContext).also { shared = it }
        }
    }
}
