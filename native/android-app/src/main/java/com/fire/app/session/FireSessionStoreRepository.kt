package com.fire.app.session

import android.content.Context

object FireSessionStoreRepository {
    @Volatile
    private var shared: FireSessionStore? = null
    @Volatile
    private var challengeHandler: FireCloudflareChallengeRuntimeHandler? = null

    fun get(context: Context): FireSessionStore {
        return shared ?: synchronized(this) {
            shared ?: FireSessionStore(context.applicationContext).also { store ->
                if (challengeHandler == null) {
                    challengeHandler = FireCloudflareChallengeRuntimeHandler(
                        context.applicationContext,
                    )
                }
                challengeHandler?.let(store::registerCloudflareChallengeHandler)
                shared = store
            }
        }
    }
}
