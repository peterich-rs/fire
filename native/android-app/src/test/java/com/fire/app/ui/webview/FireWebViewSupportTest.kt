package com.fire.app.ui.webview

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FireWebViewSupportTest {
    @Test
    fun browserCompatibleUserAgentRemovesEmbeddedWebViewMarkers() {
        val embedded = "Mozilla/5.0 (Linux; Android 15; Pixel 9; wv) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 " +
            "Chrome/125.0.0.0 Mobile Safari/537.36"

        val sanitized = FireWebViewSupport.browserCompatibleUserAgent(embedded)

        assertFalse(sanitized.contains("; wv"))
        assertFalse(sanitized.contains("Version/4.0"))
        assertTrue(sanitized.contains("Chrome/125.0.0.0"))
        assertTrue(sanitized.endsWith("Mobile Safari/537.36"))
    }
}
