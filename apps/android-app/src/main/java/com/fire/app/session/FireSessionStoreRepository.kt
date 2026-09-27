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
    @Volatile
    private var sessionCandidateHandler: FireSessionCandidateRuntimeHandler? = null
    @Volatile
    private var userApiKeyCryptoHandler: FireUserApiKeyCryptoRuntimeHandler? = null

    suspend fun get(context: Context): FireSessionStore = withContext(Dispatchers.IO) {
        getOrCreateBlocking(context.applicationContext)
    }

    fun getIfInitialized(): FireSessionStore? = shared

    suspend fun startUserApiKeyLogin(context: Context) {
        val store = get(context)
        val crypto = userApiKeyCrypto(context)
        store.registerUserApiKeyCryptoHandler(crypto)
        val authorize = store.buildUserApiKeyAuthorizeUrl(
            publicKeyPem = crypto.publicKeyPem(),
            clientId = crypto.clientId(),
        )
        val intent = android.content.Intent(
            android.content.Intent.ACTION_VIEW,
            android.net.Uri.parse(authorize.url),
        ).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    fun userApiKeyCrypto(context: Context): FireUserApiKeyCryptoRuntimeHandler {
        getOrCreateBlocking(context.applicationContext)
        return userApiKeyCryptoHandler ?: FireUserApiKeyCryptoRuntimeHandler(context.applicationContext).also {
            userApiKeyCryptoHandler = it
        }
    }

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
                store.registerBrowserHttpHandler(FireBrowserHttpHandler(context.applicationContext))
                store.registerCloudflareClearanceResolvedHandler(FireClearanceResolvedRepository)
                if (cookieSelfHealingHandler == null) {
                    cookieSelfHealingHandler = FireCookieSelfHealingRuntimeHandler(store)
                }
                cookieSelfHealingHandler?.let(store::registerCookieSelfHealingHandler)
                if (sessionCandidateHandler == null) {
                    sessionCandidateHandler = FireSessionCandidateRuntimeHandler(store)
                }
                sessionCandidateHandler?.let(store::registerSessionCandidateHandler)
                if (userApiKeyCryptoHandler == null) {
                    userApiKeyCryptoHandler = FireUserApiKeyCryptoRuntimeHandler(context.applicationContext)
                }
                userApiKeyCryptoHandler?.let(store::registerUserApiKeyCryptoHandler)
                val refresh = FireCfClearanceRefreshService.get(context.applicationContext)
                refresh.bind(store)
                // snapshot() is suspend; callers (e.g. MainActivity / login) update
                // the refresh service after awaiting get() on a coroutine path.
                shared = store
                Log.d(TAG, "session store get cold_create=true session_store_get_ms=${SystemClock.elapsedRealtime() - startedAt}")
            }
        }
    }
}
