package com.fire.app.session

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.fire_uniffi_session.AuthRuntimeSignalKindState

class FireBrowserTransportPromptTest {
    @Test
    fun presentsAskEnableOnceUntilSignalLeaves() {
        assertTrue(
            FireBrowserTransportPrompt.shouldPresent(
                AuthRuntimeSignalKindState.ASK_ENABLE_BROWSER_TRANSPORT,
                alreadyLatched = false,
            ),
        )
        assertFalse(
            FireBrowserTransportPrompt.shouldPresent(
                AuthRuntimeSignalKindState.ASK_ENABLE_BROWSER_TRANSPORT,
                alreadyLatched = true,
            ),
        )
        assertTrue(
            FireBrowserTransportPrompt.nextLatch(
                AuthRuntimeSignalKindState.ASK_ENABLE_BROWSER_TRANSPORT,
            ),
        )
        assertFalse(
            FireBrowserTransportPrompt.nextLatch(
                AuthRuntimeSignalKindState.CLOUDFLARE_CHALLENGE,
            ),
        )
        assertFalse(FireBrowserTransportPrompt.shouldPresent(null, alreadyLatched = false))
    }
}
