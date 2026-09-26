package com.fire.app.session

import uniffi.fire_uniffi_session.SessionRecoveryState

object FireSessionRecoveryPolicy {
    fun suppressesHostLoginRecovery(recovery: SessionRecoveryState): Boolean {
        return recovery == SessionRecoveryState.CLOUDFLARE
    }
}
