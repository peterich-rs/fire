package com.fire.app.session

import android.os.Looper
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import uniffi.fire_uniffi_session.CookieSelfHealingHandler
import uniffi.fire_uniffi_session.CookieSelfHealingPhaseState
import uniffi.fire_uniffi_session.CookieSelfHealingRequestState
import uniffi.fire_uniffi_session.CookieSelfHealingResultState

class FireCookieSelfHealingRuntimeHandler(
    private val sessionStore: FireSessionStore,
) : CookieSelfHealingHandler {
    override fun healCookies(
        request: CookieSelfHealingRequestState,
    ): CookieSelfHealingResultState {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return CookieSelfHealingResultState(
                completed = false,
                sessionEpoch = request.sessionEpoch,
            )
        }

        return runBlocking {
            val coordinator = FireWebViewLoginCoordinator(sessionStore)
            val completed = withTimeoutOrNull(15_000L) {
                runCatching {
                    when (request.phase) {
                        CookieSelfHealingPhaseState.SWEEP -> {
                            coordinator.sweepCookies(
                                names = request.cookieNames,
                                targetUrl = request.targetUrl,
                            )
                        }
                        CookieSelfHealingPhaseState.NUCLEAR_RESET -> {
                            coordinator.nuclearResetCookies(
                                targetUrl = request.targetUrl,
                            )
                        }
                    }
                }.isSuccess
            } ?: false
            CookieSelfHealingResultState(
                completed = completed,
                sessionEpoch = request.sessionEpoch,
            )
        }
    }
}
