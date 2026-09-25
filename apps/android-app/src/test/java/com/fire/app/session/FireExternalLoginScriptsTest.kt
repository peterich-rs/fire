package com.fire.app.session

import com.fire.app.ui.auth.FireExternalLoginMethod
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FireExternalLoginScriptsTest {

    @Test
    fun autoStart_google_targetsSocialButton() {
        val script = FireExternalLoginScripts.autoStart(FireExternalLoginMethod.Google)
        assertTrue(script.contains("google_oauth2"))
        assertTrue(script.contains("btn-social"))
        assertTrue(script.contains("login-buttons"))
    }

    @Test
    fun autoStart_passkey_targetsPasskeyButton() {
        val script = FireExternalLoginScripts.autoStart(FireExternalLoginMethod.Passkey)
        assertTrue(script.contains("passkey-login-button"))
        assertTrue(script.contains("login-buttons"))
    }

    @Test
    fun autoStart_x_usesTwitterProviderName() {
        val script = FireExternalLoginScripts.autoStart(FireExternalLoginMethod.X)
        assertTrue(script.contains("twitter"))
    }

    @Test
    fun isLinuxDoLoginPage_acceptsLoginPaths() {
        assertTrue(FireExternalLoginScripts.isLinuxDoLoginPage("https://linux.do/login"))
        assertTrue(FireExternalLoginScripts.isLinuxDoLoginPage("https://linux.do/login/"))
        assertTrue(FireExternalLoginScripts.isLinuxDoLoginPage("https://www.linux.do/login?foo=1"))
    }

    @Test
    fun isLinuxDoLoginPage_rejectsOtherPaths() {
        assertFalse(FireExternalLoginScripts.isLinuxDoLoginPage(null))
        assertFalse(FireExternalLoginScripts.isLinuxDoLoginPage(""))
        assertFalse(FireExternalLoginScripts.isLinuxDoLoginPage("https://linux.do/"))
        assertFalse(FireExternalLoginScripts.isLinuxDoLoginPage("https://linux.do/t/topic/1"))
        assertFalse(FireExternalLoginScripts.isLinuxDoLoginPage("https://example.com/login"))
    }
}
