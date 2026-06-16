package com.fire.app.session

import android.content.Context
import android.os.SystemClock
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object FireSessionStoreRepository {
    private const val TAG = "FireSessionStoreRepo"

    @Volatile
    private var shared: FireSessionStore? = null
    @Volatile
    private var challengeHandler: FireCloudflareChallengeRuntimeHandler? = null
    @Volatile
    private var cookieSelfHealingHandler: FireCookieSelfHealingRuntimeHandler? = null

    suspend fun get(context: Context): FireSessionStore = withContext(Dispatchers.IO) {
        getOrCreateBlocking(context.applicationContext)
    }

    fun getIfInitialized(): FireSessionStore? = shared

    private fun getOrCreateBlocking(context: Context): FireSessionStore {
        val startedAt = SystemClock.elapsedRealtime()
        shared?.let { store ->
            Log.d(TAG, "session store get cached session_store_get_ms=${SystemClock.elapsedRealtime() - startedAt}")
            return store
        }
        return shared ?: synchronized(this) {
            shared?.also {
                Log.d(TAG, "session store get cached session_store_get_ms=${SystemClock.elapsedRealtime() - startedAt}")
            } ?: FireSessionStore(context.applicationContext).also { store ->
                if (challengeHandler == null) {
                    challengeHandler = FireCloudflareChallengeRuntimeHandler(
                        context.applicationContext,
                    )
                }
                challengeHandler?.let(store::registerCloudflareChallengeHandler)
                if (cookieSelfHealingHandler == null) {
                    cookieSelfHealingHandler = FireCookieSelfHealingRuntimeHandler(store)
                }
                cookieSelfHealingHandler?.let(store::registerCookieSelfHealingHandler)
                shared = store
                Log.d(TAG, "session store get cold_create=true session_store_get_ms=${SystemClock.elapsedRealtime() - startedAt}")
            }
        }
    }
}
