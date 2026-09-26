package com.fire.app.session

import uniffi.fire_uniffi_session.AuthRuntimeSignalKindState
import uniffi.fire_uniffi_session.SessionState

object FireBrowserTransportPrompt {
    fun shouldPresent(kind: AuthRuntimeSignalKindState?, alreadyLatched: Boolean): Boolean {
        return kind == AuthRuntimeSignalKindState.ASK_ENABLE_BROWSER_TRANSPORT && !alreadyLatched
    }

    fun nextLatch(kind: AuthRuntimeSignalKindState?): Boolean {
        return kind == AuthRuntimeSignalKindState.ASK_ENABLE_BROWSER_TRANSPORT
    }

    fun signalKind(snapshot: SessionState): AuthRuntimeSignalKindState? {
        return snapshot.lastAuthRuntimeSignal?.kind
    }
}
