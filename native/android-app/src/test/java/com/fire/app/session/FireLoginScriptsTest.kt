package com.fire.app.session

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FireLoginScriptsTest {
    @Test
    fun minimalLoginDocumentUsesWebViewOwnedLoginEndpoints() {
        val html = FireLoginScripts.minimalLoginDocument("site-key")

        assertTrue(html.contains("https://js.hcaptcha.com/1/api.js"))
        assertTrue(FireLoginScripts.linuxDoHcaptchaSiteKey.matches(Regex("[0-9a-f-]{36}")))
        assertTrue(html.contains("hcaptcha.render('hcaptcha'"))
        assertTrue(html.contains("window.__fireLogin = async function"))
        assertTrue(html.contains("fetch('/session/csrf'"))
        assertTrue(html.contains("\"/captcha/hcaptcha/create.json\""))
        assertTrue(html.contains("\"/hcaptcha/create.json\""))
        assertTrue(html.contains("fetch('/session.json'"))
        assertTrue(html.contains("'X-Requested-With': 'XMLHttpRequest'"))
        assertTrue(html.contains("credentials: 'include'"))
        assertTrue(html.contains("loginResult"))
        assertFalse(html.contains("loadUrl(\"https://linux.do/login\")"))
    }

    @Test
    fun fireLoginInvocationJsonEscapesAllArguments() {
        val script = FireLoginScripts.fireLoginInvocation(
            identifier = "alice@example.com",
            password = "p\"ass\\word",
            hcaptchaToken = "hc-token",
            secondFactorToken = null,
        )

        assertTrue(script.startsWith("window.__fireLogin("))
        assertTrue(script.contains("\"alice@example.com\""))
        assertTrue(script.contains("\"p\\\"ass\\\\word\""))
        assertTrue(script.contains("\"hc-token\""))
        assertTrue(script.endsWith(",null);"))
    }

    @Test
    fun minimalLoginDocumentAllowsConfiguredHcaptchaEndpointFirst() {
        val html = FireLoginScripts.minimalLoginDocument(
            hcaptchaSiteKey = "site-key",
            hcaptchaCreateEndpoint = "/custom/hcaptcha/create.json",
        )

        assertTrue(
            html.indexOf("\"/custom/hcaptcha/create.json\"") <
                html.indexOf("\"/captcha/hcaptcha/create.json\""),
        )
    }
}
