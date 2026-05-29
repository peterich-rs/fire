package com.fire.app.session

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn

class FireCfClearanceService(private val sessionStore: FireSessionStore) {

    private var lastRecoveryTimeMs: Long = 0
    private val cooldownMs: Long = 10_000 // 10 seconds

    fun isInCooldown(): Boolean {
        return System.currentTimeMillis() - lastRecoveryTimeMs < cooldownMs
    }

    fun markRecoveryCompleted() {
        lastRecoveryTimeMs = System.currentTimeMillis()
    }

    fun pollClearanceStatus(intervalMs: Long = 5000): Flow<Boolean> = flow {
        while (true) {
            val state = sessionStore.snapshot()
            val canRead = state.readiness.canReadAuthenticatedApi
            emit(canRead)
            if (canRead) break
            delay(intervalMs)
        }
    }.flowOn(Dispatchers.IO)
}
