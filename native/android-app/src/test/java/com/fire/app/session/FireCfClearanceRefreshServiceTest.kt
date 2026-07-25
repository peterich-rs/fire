package com.fire.app.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.fire_uniffi_session.PlatformCookieState

class FireCfClearanceRefreshServiceTest {
    @Test
    fun cloudflareClearanceValue_prefersChangedValue() {
        val cookies = listOf(
            PlatformCookieState(
                name = "cf_clearance",
                value = "old",
                domain = ".linux.do",
                path = "/",
                expiresAtUnixMs = null,
                sameSite = null,
            ),
            PlatformCookieState(
                name = "cf_clearance",
                value = "new",
                domain = ".linux.do",
                path = "/",
                expiresAtUnixMs = null,
                sameSite = null,
            ),
        )
        assertEquals(
            "new",
            FireCfClearanceRefreshService.cloudflareClearanceValue(cookies, "old"),
        )
    }

    @Test
    fun turnstileHtml_includesSitekeyAndRuntimeToken() {
        val html = FireCfClearanceRefreshService.turnstileHtml(
            sitekey = "site-key-123",
            runtimeToken = "runtime-token-456",
        )
        assertTrue(html.contains("site-key-123"))
        assertTrue(html.contains("runtime-token-456"))
        assertTrue(html.contains("turnstile.render"))
    }
}
