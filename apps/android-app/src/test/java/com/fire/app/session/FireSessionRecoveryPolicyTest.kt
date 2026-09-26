package com.fire.app.session

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.fire_uniffi_session.SessionRecoveryState

class FireSessionRecoveryPolicyTest {
    @Test
    fun cloudflareRecoverySuppressesPassiveLogoutAndBrowserPrompt() {
        assertTrue(
            FireSessionRecoveryPolicy.suppressesHostLoginRecovery(SessionRecoveryState.CLOUDFLARE),
        )
        assertFalse(
            FireSessionRecoveryPolicy.suppressesHostLoginRecovery(SessionRecoveryState.IDLE),
        )
    }
}
